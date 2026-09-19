import Foundation
import Combine

class PomodoroTimer: ObservableObject {
    @Published var timeRemaining: TimeInterval
    @Published var timerState: TimerState = .idle
    @Published var sessionType: SessionType = .work
    @Published var completedPomodoros: Int = 0
    @Published var currentSessionIndex: Int = 0

    let settings: AppSettings
    private let audioManager: AudioManager
    private let analyticsStore: AnalyticsStore
    private let taskStore: FocusTaskStore
    private var timer: Timer?
    private var endDate: Date?
    private var cancellables = Set<AnyCancellable>()
    private var activeWorkTaskID: UUID?
    private var activeWorkDurationMinutes: Int?
    private var currentTaskID: UUID?
    private struct SavedTimer {
        let remaining: TimeInterval
        let state: TimerState
        let session: SessionType
        let sessionIndex: Int
        let workMinutes: Int?
    }
    private var savedTimers: [UUID?: SavedTimer] = [:]
    @Published var quickTimerMinutes: Int = 25

    var onSessionComplete: ((SessionType) -> Void)?

    var totalDuration: TimeInterval {
        switch sessionType {
        case .work:
            return TimeInterval(workDurationMinutes * 60)
        case .shortBreak: return TimeInterval(settings.shortBreakDuration * 60)
        case .longBreak: return TimeInterval(settings.longBreakDuration * 60)
        }
    }

    /// The task currently driving the work timer. While a work session is
    /// active this remains a snapshot, even if the task list is edited.
    var activeFocusTask: FocusTask? {
        if let activeWorkTaskID {
            return taskStore.task(withID: activeWorkTaskID)
        }
        return taskStore.task(withID: currentTaskID)
    }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - (timeRemaining / totalDuration)
    }

    var formattedTime: String {
        let total = max(0, Int(ceil(timeRemaining)))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    init(
        settings: AppSettings,
        audioManager: AudioManager,
        analyticsStore: AnalyticsStore,
        taskStore: FocusTaskStore
    ) {
        self.settings = settings
        self.audioManager = audioManager
        self.analyticsStore = analyticsStore
        self.taskStore = taskStore
        self.currentTaskID = taskStore.selectedTaskID
        self.quickTimerMinutes = settings.workDuration
        self.timeRemaining = TimeInterval((taskStore.selectedTask?.plannedMinutes ?? settings.workDuration) * 60)

        // Update timeRemaining when settings change while idle
        Publishers.CombineLatest3(
            settings.$workDuration,
            settings.$shortBreakDuration,
            settings.$longBreakDuration
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            guard let self = self, self.timerState == .idle else { return }
            self.timeRemaining = self.totalDuration
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(taskStore.$tasks, taskStore.$selectedTaskID)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.selectTask(id: self.taskStore.selectedTaskID)
                if self.timerState == .idle { self.timeRemaining = self.totalDuration }
            }
            .store(in: &cancellables)
    }

    /// Only the selected timer runs. Switching parks the previous timer;
    /// returning restores it paused, ready for an explicit Resume.
    func selectTask(id: UUID?) {
        guard id != currentTaskID else { return }
        pause()
        savedTimers[currentTaskID] = SavedTimer(
            remaining: timeRemaining, state: timerState, session: sessionType,
            sessionIndex: currentSessionIndex, workMinutes: activeWorkDurationMinutes
        )
        currentTaskID = id
        taskStore.selectTask(id: id)
        clearActiveWorkTask()
        if let saved = savedTimers.removeValue(forKey: id) {
            sessionType = saved.session
            currentSessionIndex = saved.sessionIndex
            activeWorkDurationMinutes = saved.workMinutes
            activeWorkTaskID = id
            timerState = saved.state
            timeRemaining = saved.remaining
        } else {
            sessionType = .work
            currentSessionIndex = 0
            timerState = .idle
            timeRemaining = totalDuration
        }
    }

    func setQuickTimerMinutes(_ minutes: Int) {
        guard currentTaskID == nil, timerState == .idle, sessionType == .work else { return }
        quickTimerMinutes = min(max(minutes, 1), 480)
        timeRemaining = totalDuration
    }

    func start() {
        guard timerState != .running else { return }

        if timerState == .idle {
            captureCurrentWorkTaskIfNeeded()
            timeRemaining = totalDuration
        }

        endDate = Date().addingTimeInterval(timeRemaining)
        timerState = .running
        startTimer()
    }

    func pause() {
        guard timerState == .running else { return }
        if let endDate = endDate {
            timeRemaining = max(0, endDate.timeIntervalSinceNow)
        }
        timerState = .paused
        stopTimer()
        endDate = nil
    }

    func toggleStartPause() {
        if timerState == .running {
            pause()
        } else {
            start()
        }
    }

    func reset() {
        stopTimer()
        endDate = nil
        timerState = .idle
        clearActiveWorkTask()
        timeRemaining = totalDuration
    }

    func skip() {
        stopTimer()
        endDate = nil
        let completedType = sessionType
        if sessionType == .work {
            clearActiveWorkTask()
            transitionToBreak()
        } else {
            transitionToWork()
        }
        onSessionComplete?(completedType)
    }

    private func startTimer() {
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let endDate = endDate else { return }

        let remaining = endDate.timeIntervalSinceNow

        if remaining <= 0 {
            timeRemaining = 0
            sessionCompleted()
            return
        }

        let previousWholeSeconds = Int(ceil(timeRemaining))
        timeRemaining = remaining
        let currentWholeSeconds = Int(ceil(remaining))

        // Play tick in the last 10 seconds when crossing a second boundary
        if currentWholeSeconds <= 10 && currentWholeSeconds > 0
            && currentWholeSeconds != previousWholeSeconds
        {
            audioManager.playTick()
        }
    }

    private func sessionCompleted() {
        stopTimer()
        endDate = nil
        audioManager.playCompletionChime()

        let completedType = sessionType

        if sessionType == .work {
            let completedDuration = totalDuration
            let completedTaskID = activeWorkTaskID
            completedPomodoros += 1
            currentSessionIndex += 1
            analyticsStore.recordCompletedPomodoro(focusMinutes: Int(completedDuration / 60))
            taskStore.recordCompletedFocus(taskID: completedTaskID, seconds: completedDuration)
            clearActiveWorkTask()
            transitionToBreak()
        } else {
            transitionToWork()
        }

        onSessionComplete?(completedType)
    }

    private func transitionToBreak() {
        timerState = .idle
        if currentSessionIndex >= settings.pomodorosBeforeLongBreak {
            sessionType = .longBreak
            currentSessionIndex = 0
        } else {
            sessionType = .shortBreak
        }
        timeRemaining = totalDuration

        if settings.autoStartNextSession {
            start()
        } else {
            timerState = .idle
        }
    }

    private func transitionToWork() {
        timerState = .idle
        sessionType = .work
        clearActiveWorkTask()
        timeRemaining = totalDuration

        if settings.autoStartNextSession {
            start()
        } else {
            timerState = .idle
        }
    }

    private var workDurationMinutes: Int {
        activeWorkDurationMinutes ?? taskStore.task(withID: currentTaskID)?.plannedMinutes ?? quickTimerMinutes
    }

    private func captureCurrentWorkTaskIfNeeded() {
        guard sessionType == .work else { return }
        activeWorkTaskID = currentTaskID
        activeWorkDurationMinutes = taskStore.task(withID: currentTaskID)?.plannedMinutes ?? quickTimerMinutes
    }

    private func clearActiveWorkTask() {
        activeWorkTaskID = nil
        activeWorkDurationMinutes = nil
    }
}
