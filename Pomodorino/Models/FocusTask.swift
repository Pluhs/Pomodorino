import Combine
import Foundation

struct FocusTask: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var plannedMinutes: Int
    var loggedFocusSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        title: String,
        plannedMinutes: Int,
        loggedFocusSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.plannedMinutes = plannedMinutes
        self.loggedFocusSeconds = loggedFocusSeconds
    }

    var loggedFocusMinutes: Int {
        Int((loggedFocusSeconds / 60).rounded(.down))
    }
}

/// Persists named focus tasks independently from the global Pomodoro
/// defaults. A task supplies the work-session duration when selected and
/// accumulates completed focus time over multiple sessions.
final class FocusTaskStore: ObservableObject {
    @Published private(set) var tasks: [FocusTask] {
        didSet { saveTasks() }
    }
    @Published var selectedTaskID: UUID? {
        didSet { saveSelectedTaskID() }
    }

    private let defaults: UserDefaults
    private let tasksKey = "focusTasks"
    private let selectedTaskIDKey = "selectedFocusTaskID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: tasksKey),
           let savedTasks = try? JSONDecoder().decode([FocusTask].self, from: data)
        {
            tasks = savedTasks
        } else {
            tasks = []
        }

        selectedTaskID = defaults.string(forKey: selectedTaskIDKey).flatMap(UUID.init(uuidString:))
        if let selectedTaskID, !tasks.contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = nil
        }
    }

    var selectedTask: FocusTask? {
        task(withID: selectedTaskID)
    }

    func task(withID id: UUID?) -> FocusTask? {
        guard let id else { return nil }
        return tasks.first(where: { $0.id == id })
    }

    @discardableResult
    func addTask(title: String, plannedMinutes: Int) -> FocusTask? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let task = FocusTask(
            title: trimmedTitle,
            plannedMinutes: Self.clampedMinutes(plannedMinutes)
        )
        tasks.insert(task, at: 0)
        selectedTaskID = task.id
        return task
    }

    func updateTask(id: UUID, title: String? = nil, plannedMinutes: Int? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }

        if let title {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return }
            tasks[index].title = trimmedTitle
        }
        if let plannedMinutes {
            tasks[index].plannedMinutes = Self.clampedMinutes(plannedMinutes)
        }
    }

    func selectTask(id: UUID?) {
        selectedTaskID = id
    }

    func deleteTask(id: UUID) {
        tasks.removeAll(where: { $0.id == id })
        if selectedTaskID == id {
            selectedTaskID = nil
        }
    }

    func recordCompletedFocus(taskID: UUID?, seconds: TimeInterval) {
        guard seconds > 0,
              let taskID,
              let index = tasks.firstIndex(where: { $0.id == taskID })
        else {
            return
        }

        tasks[index].loggedFocusSeconds += seconds
    }

    private static func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 1), 480)
    }

    private func saveTasks() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        defaults.set(data, forKey: tasksKey)
    }

    private func saveSelectedTaskID() {
        defaults.set(selectedTaskID?.uuidString, forKey: selectedTaskIDKey)
    }
}
