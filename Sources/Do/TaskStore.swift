import Darwin
import Foundation

private enum StorageError: LocalizedError {
    case regularFileRequired, importTooLarge, tooManyTasks, unsafeOwner

    var errorDescription: String? {
        switch self {
        case .regularFileRequired: "Choose a regular local JSON file."
        case .importTooLarge: "The backup exceeds the 64 MiB import limit."
        case .tooManyTasks: "A backup can import up to 100,000 tasks at once."
        case .unsafeOwner: "The task storage location is not owned by your account."
        }
    }
}

struct TaskStore {
    let url: URL

    private static func systemError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    static func applicationStore() throws -> TaskStore {
        #if DEBUG
        if let previewPath = ProcessInfo.processInfo.environment["DO_PREVIEW_TASK_FILE"] {
            return TaskStore(url: URL(fileURLWithPath: previewPath))
        }
        #endif
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("DoTaskTracker", isDirectory: true)
        guard mkdir(folder.path, 0o700) == 0 || errno == EEXIST else { throw systemError() }
        let fd = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw systemError() }
        defer { close(fd) }
        try restrictPermissions(fd, mode: 0o700)
        return TaskStore(url: folder.appendingPathComponent("Tasks.json"))
    }

    private static func restrictPermissions(_ fd: Int32, mode: mode_t) throws {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw systemError() }
        guard info.st_uid == geteuid() else { throw StorageError.unsafeOwner }
        if info.st_mode & 0o7777 != mode, fchmod(fd, mode) != 0 { throw systemError() }
    }

    // Inspect and read the same descriptor. Nonblocking open also lets us reject
    // special files before a read can wait for a writer.
    private static func read(_ url: URL, importLimit: Int?) throws -> Data {
        guard url.isFileURL else { throw StorageError.regularFileRequired }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw systemError() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw systemError() }
        guard info.st_mode & S_IFMT == S_IFREG else { throw StorageError.regularFileRequired }
        guard let importLimit else {
            try restrictPermissions(fd, mode: 0o600)
            return try handle.readToEnd() ?? Data()
        }
        guard info.st_size <= importLimit else { throw StorageError.importTooLarge }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(262144, importLimit - data.count + 1)), !chunk.isEmpty {
            guard chunk.count <= importLimit - data.count else { throw StorageError.importTooLarge }
            data.append(chunk)
        }
        return data
    }

    func load() throws -> [TaskDetails] {
        let data: Data
        do {
            data = try Self.read(url, importLimit: nil)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return []
        }
        return try JSONDecoder().decode(TaskBackup.self, from: data).newTasks(excluding: [])
    }

    static func importBackup(at url: URL) throws -> (tasks: [TaskDetails], total: Int) {
        let acquired = url.startAccessingSecurityScopedResource()
        defer { if acquired { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        let data = try read(url, importLimit: 64 * 1024 * 1024)
        let backup = try decoder.decode(ExternalBackup.self, from: data)
        return (try backup.value.newTasks(excluding: []), backup.value.tasks.count)
    }

    private struct ExternalBackup: Decodable {
        enum Keys: CodingKey { case version, tasks }
        let value: TaskBackup

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            let version = try container.decode(Int.self, forKey: .version)
            guard version == 1 || version == 2 else { throw TaskError.unsupportedBackup }
            var rows = try container.nestedUnkeyedContainer(forKey: .tasks)
            let limit = 100_000
            guard (rows.count ?? 0) <= limit else { throw StorageError.tooManyTasks }
            var tasks: [TaskDetails] = []
            while !rows.isAtEnd {
                guard tasks.count < limit else { throw StorageError.tooManyTasks }
                tasks.append(try rows.decode(TaskDetails.self))
            }
            value = TaskBackup(version: version, tasks: tasks)
        }
    }

    func save(_ tasks: [TaskDetails]) throws {
        let data = try Self.encode(tasks)
        var template = Array(url.deletingLastPathComponent().appendingPathComponent(".Do-XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw Self.systemError() }
        let path = String(cString: template)
        defer { unlink(path) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.close()
        guard rename(path, url.path) == 0 else { throw Self.systemError() }
    }

    static func encode(_ tasks: [TaskDetails]) throws -> Data {
        let hasScheduledTimes = tasks.contains { $0.dueTime != nil || $0.keyTime != nil }
        return try JSONEncoder().encode(TaskBackup(version: hasScheduledTimes ? 2 : 1, tasks: tasks))
    }
}
