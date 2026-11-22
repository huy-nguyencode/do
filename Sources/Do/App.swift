import AppKit
import SwiftUI
import UniformTypeIdentifiers

private typealias AppState<Value> = SwiftUI.State<Value>

@main
struct DoApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    private let database: Result<TaskStore, Error>
    @AppState private var index: WorkspaceIndex

    init() {
        do {
            let store = try TaskStore.applicationStore()
            _index = SwiftUI.State(initialValue: WorkspaceIndex(try store.load()))
            database = .success(store)
        } catch {
            _index = SwiftUI.State(initialValue: WorkspaceIndex([]))
            database = .failure(error)
        }
    }

    var body: some Scene {
        Window("Do", id: "tasks") {
            Group {
                switch database {
                case .success(let store):
                    WorkspaceView(store: store, index: $index, appearance: $appearance)
                case .failure(let error):
                    ContentUnavailableView("Couldn’t open your tasks", systemImage: "externaldrive.badge.exclamationmark",
                                           description: Text(error.localizedDescription))
                        .frame(minWidth: 540, minHeight: 320)
                }
            }
            .preferredColorScheme(appearance.colorScheme)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1160, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { NotificationCenter.default.post(name: .newTask, object: nil) }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .textEditing) {
                Button("Find Tasks") { NotificationCenter.default.post(name: .findTasks, object: nil) }
                    .keyboardShortcut("f")
                Button("Focus Task Search") { NotificationCenter.default.post(name: .findTasks, object: nil) }
                    .keyboardShortcut("k")
            }
            CommandMenu("Tasks") {
                ForEach(Array(TaskView.allCases.enumerated()), id: \.element.id) { index, view in
                    Button(view.title) { NotificationCenter.default.post(name: .switchTaskView, object: view) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { NotificationCenter.default.post(name: .showSettings, object: nil) }
                    .keyboardShortcut(",")
            }
        }
    }
}

extension Notification.Name {
    static let findTasks = Notification.Name("Do.findTasks")
    static let switchTaskView = Notification.Name("Do.switchTaskView")
    static let newTask = Notification.Name("Do.newTask")
    static let showSettings = Notification.Name("Do.showSettings")
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(tasks: [TaskDetails]) throws {
        data = try TaskStore.encode(tasks)
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
