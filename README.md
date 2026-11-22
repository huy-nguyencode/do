# Do

Do is a single-user macOS task tracker built with SwiftUI and local JSON storage. The packaged build targets Apple silicon and macOS 14 or later.

## Use the app

Unzip the app, move `Do.app` to Applications if desired, and open it. Press ⌘N to add a task. A task needs only a title. Select a row and press Return or double-click it to edit its details. Use the circle beside a task to complete or reopen it. Completing sets progress to 100%. Reopening resets it to 0%. To delete a task, select it and press Delete, click the toolbar trash button, or use the row’s context menu. Drag a row’s handle up or down or Shift-click to select a range. Command-click to select individual rows. Deleting requires confirmation.

- **Overview** shows tasks with a due date or key date in the current week. The window runs from Sunday at 7 a.m. through the next Sunday at 7 a.m., in your Mac’s local time. **All tasks** includes every task.
- **Today & overdue** shows unfinished tasks due today or earlier.
- **Upcoming 7 days** shows unfinished tasks due tomorrow through the following seven-day window.
- **Completed** shows finished tasks. You can reopen tasks from this view.
- **Exams & milestones** shows key dates from today onward. Completing a task does not remove its upcoming key date from this view.

Press ⌘F or ⌘K to search, ⌘1–⌘6 to switch views, and ⌘S to save the open editor. Use **Sort** to add ordered rules and choose a direction for each. Use the up and down arrows to change priority. Lower rules break ties. Clicking a table column header makes that column the first rule. Each view keeps its own rules while Do is open. Project and status filters work together with search. Use **Project → New Project…** to name a project when editing a task. The project becomes available to other tasks after you save. Status and its editable percentage are directly below the schedule. Escape closes the editor or clears the focused search field. Open **Do → Settings** or press ⌘, to choose **System**, **Light**, or **Dark**. In Settings you can also change text size and page heading style, or remove projects. Removing a project leaves its tasks unassigned. Do remembers appearance and typography choices on this Mac. System follows macOS appearance.

Click the date field, then choose the **Due date** or **Key date** tab in the shared calendar. Choose a day directly or use **Today** or **Tomorrow**. Turn on **Include time** to enter a local clock time and click **Apply**, then save the task. Existing dates stay all-day until a time is added. Files containing times require Do 1.3 or later.

Open **Settings → Backups** to export or import a JSON backup. You can also drop a backup JSON file onto the window to import it. Individual backup imports support up to 64 MiB and 100,000 tasks. Import merges tasks by ID and skips IDs already present. Right-click a row and choose **Copy Task Title** to copy it as text. The app stores its task file under `~/Library/Application Support/DoTaskTracker`.

## Build from source

Install the macOS Command Line Tools or Xcode with a Swift 5.10 or later toolchain and a macOS 14 or later SDK.

```sh
./scripts/build-app.sh
open dist/Do.app
```

Run the checks with `./scripts/check.sh`. The build script creates an ad hoc signed app in `dist/Do.app`. It builds for the current Mac's architecture. A default SwiftPM build-system build can be selected if needed with `DO_BUILD_SYSTEM=swiftbuild ./scripts/build-app.sh` on Swift versions that support it.
