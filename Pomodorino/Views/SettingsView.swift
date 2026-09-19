import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var taskStore: FocusTaskStore
    @State private var editingColor: EditableColor?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Durations
                Text("Durations")
                    .font(.headline)

                DurationRow(
                    title: "Work",
                    minutes: $settings.workDuration,
                    range: 1...60
                )
                DurationRow(
                    title: "Short Break",
                    minutes: $settings.shortBreakDuration,
                    range: 1...30
                )
                DurationRow(
                    title: "Long Break",
                    minutes: $settings.longBreakDuration,
                    range: 1...60
                )
                Stepper(
                    "Sessions before long break: \(settings.pomodorosBeforeLongBreak)",
                    value: $settings.pomodorosBeforeLongBreak, in: 2...10
                )

                Divider()

                TaskSettingsSection(taskStore: taskStore)

                Divider()

                // Audio
                Text("Audio")
                    .font(.headline)

                Toggle("Completion sound", isOn: $settings.audioEnabled)
                Toggle("10-second countdown ticker", isOn: $settings.tickerEnabled)

                Divider()

                // Behavior
                Text("Behavior")
                    .font(.headline)

                Toggle("Auto-start next session", isOn: $settings.autoStartNextSession)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                Divider()

                // Appearance
                Text("Appearance")
                    .font(.headline)

                ColorSettingRow(
                    role: .accent,
                    isSelected: editingColor == .accent,
                    color: $settings.accentColor
                ) {
                    editingColor = editingColor == .accent ? nil : .accent
                }

                if editingColor == .accent {
                    InlineColorEditor(title: EditableColor.accent.title, color: $settings.accentColor) {
                        settings.accentColor = .accentDefault
                    }
                }

                Divider()

                Text("Timer colors")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ColorSettingRow(
                    role: .work,
                    isSelected: editingColor == .work,
                    color: $settings.workTimerColor
                ) {
                    editingColor = editingColor == .work ? nil : .work
                }
                if editingColor == .work {
                    InlineColorEditor(title: EditableColor.work.title, color: $settings.workTimerColor) {
                        settings.workTimerColor = .workDefault
                    }
                }

                ColorSettingRow(
                    role: .break,
                    isSelected: editingColor == .break,
                    color: $settings.breakTimerColor
                ) {
                    editingColor = editingColor == .break ? nil : .break
                }
                if editingColor == .break {
                    InlineColorEditor(title: EditableColor.break.title, color: $settings.breakTimerColor) {
                        settings.breakTimerColor = .breakDefault
                    }
                }

                ColorSettingRow(
                    role: .paused,
                    isSelected: editingColor == .paused,
                    color: $settings.pausedTimerColor
                ) {
                    editingColor = editingColor == .paused ? nil : .paused
                }
                if editingColor == .paused {
                    InlineColorEditor(title: EditableColor.paused.title, color: $settings.pausedTimerColor) {
                        settings.pausedTimerColor = .pausedDefault
                    }
                }

                Toggle("Menu bar color pill", isOn: $settings.menuBarPillEnabled)
                Text("Show the active timer color behind the menu-bar timer.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Use the color wheel to choose or fine-tune any color.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Reset all colors") {
                    settings.resetColors()
                }
                .controlSize(.small)

                Divider()

                // Global shortcut
                Text("Keyboard Shortcut")
                    .font(.headline)

                HStack {
                    Text("Start / Pause")
                        .foregroundColor(.secondary)
                    Spacer()
                    ShortcutRecorder(
                        keyCode: $settings.shortcutKeyCode,
                        modifiers: $settings.shortcutModifiers
                    )
                    .frame(width: 120, height: 28)
                    Button("Reset") {
                        settings.shortcutKeyCode = 35
                        settings.shortcutModifiers = 6144
                    }
                    .controlSize(.small)
                }

                Text("Click the shortcut, then press a key combination with at least one modifier.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                Button("Quit Pomodoro") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
        }
    }

}

private struct TaskSettingsSection: View {
    @ObservedObject var taskStore: FocusTaskStore
    @State private var newTaskTitle = ""
    @State private var newTaskMinutes = 25

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus tasks")
                .font(.headline)

            Text("Give each task its own target. Completed focus sessions are logged against that task.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("Task name", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)

                Stepper(value: $newTaskMinutes, in: 1...480) {
                    Text("\(newTaskMinutes) min")
                        .monospacedDigit()
                }
                .fixedSize()

                Button("Add", action: addTask)
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if taskStore.tasks.isEmpty {
                Text("No task selected — the default work duration will be used.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(taskStore.tasks) { task in
                    FocusTaskRow(task: task, taskStore: taskStore)
                }
            }
        }
    }

    private func addTask() {
        guard taskStore.addTask(title: newTaskTitle, plannedMinutes: newTaskMinutes) != nil else {
            return
        }
        newTaskTitle = ""
    }
}

private struct FocusTaskRow: View {
    let task: FocusTask
    @ObservedObject var taskStore: FocusTaskStore

    private var titleBinding: Binding<String> {
        Binding(
            get: { taskStore.task(withID: task.id)?.title ?? task.title },
            set: { taskStore.updateTask(id: task.id, title: $0) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { taskStore.task(withID: task.id)?.plannedMinutes ?? task.plannedMinutes },
            set: { taskStore.updateTask(id: task.id, plannedMinutes: $0) }
        )
    }

    private var currentTask: FocusTask {
        taskStore.task(withID: task.id) ?? task
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Task name", text: titleBinding)
                    .textFieldStyle(.roundedBorder)

                if taskStore.selectedTaskID == task.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .help("Selected for the next focus session")
                }
            }

            HStack(spacing: 8) {
                Stepper(value: minutesBinding, in: 1...480) {
                    Text("\(currentTask.plannedMinutes) min target")
                        .monospacedDigit()
                }
                .controlSize(.small)

                Spacer()

                Text("\(formattedLoggedTime) logged")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Use") {
                    taskStore.selectTask(id: task.id)
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    taskStore.deleteTask(id: task.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete \(currentTask.title)")
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedLoggedTime: String {
        let minutes = currentTask.loggedFocusMinutes
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct DurationRow: View {
    let title: String
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    @State private var text: String

    init(title: String, minutes: Binding<Int>, range: ClosedRange<Int>) {
        self.title = title
        _minutes = minutes
        self.range = range
        _text = State(initialValue: String(minutes.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)

            Spacer()

            TextField("\(title) minutes", text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .onChange(of: text) { newValue in
                    guard let value = Int(newValue), range.contains(value) else { return }
                    minutes = value
                }
                .onSubmit(commitText)
                .accessibilityLabel("\(title) minutes")

            Text("min")
                .foregroundColor(.secondary)

            Stepper("Adjust \(title) minutes", value: $minutes, in: range)
                .labelsHidden()
                .onChange(of: minutes) { newValue in
                    text = String(newValue)
                }
        }
    }

    private func commitText() {
        let value = Int(text) ?? minutes
        minutes = min(max(value, range.lowerBound), range.upperBound)
        text = String(minutes)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onShortcut = { keyCode, modifiers in
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.title = ShortcutManager.displayString(keyCode: keyCode, modifiers: modifiers)
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onShortcut: ((Int, Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }

        let modifiers = ShortcutManager.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }

        onShortcut?(Int(event.keyCode), modifiers)
        window?.makeFirstResponder(nil)
    }
}
