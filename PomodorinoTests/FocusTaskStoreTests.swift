import XCTest
@testable import Pomodorino

final class FocusTaskStoreTests: XCTestCase {
    func testSwitchingTasksAndQuickTimerPreservesPausedProgress() throws {
        let suiteName = "TimerSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FocusTaskStore(defaults: defaults)
        let first = try XCTUnwrap(store.addTask(title: "Reading", plannedMinutes: 40))
        let second = try XCTUnwrap(store.addTask(title: "Writing", plannedMinutes: 15))
        store.selectTask(id: first.id)
        let settings = AppSettings()
        let timer = PomodoroTimer(settings: settings,
                                  audioManager: AudioManager(settings: settings),
                                  analyticsStore: AnalyticsStore(), taskStore: store)
        XCTAssertEqual(timer.timeRemaining, 2400)
        timer.start()
        timer.pause()
        timer.timeRemaining = 1234
        timer.selectTask(id: second.id)
        XCTAssertEqual(timer.timeRemaining, 900)
        XCTAssertEqual(timer.timerState, .idle)
        timer.selectTask(id: nil)
        timer.setQuickTimerMinutes(7)
        XCTAssertEqual(timer.timeRemaining, 420)
        XCTAssertNil(timer.activeFocusTask)
        timer.start()
        timer.selectTask(id: first.id)
        XCTAssertEqual(timer.timeRemaining, 1234)
        XCTAssertEqual(timer.totalDuration, 2400)
        XCTAssertEqual(timer.timerState, .paused)
        timer.selectTask(id: nil)
        XCTAssertEqual(timer.timerState, .paused)
        XCTAssertEqual(timer.totalDuration, 420)
        XCTAssertLessThanOrEqual(timer.timeRemaining, 420)
        XCTAssertGreaterThan(timer.timeRemaining, 415)
        timer.reset()
    }

    func testTaskPersistsTargetAndCompletedFocusTime() {
        let suiteName = "FocusTaskStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated user defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = FocusTaskStore(defaults: defaults)
        let task = store.addTask(title: "Write proposal", plannedMinutes: 42)

        XCTAssertEqual(task?.title, "Write proposal")
        XCTAssertEqual(task?.plannedMinutes, 42)
        XCTAssertEqual(store.selectedTaskID, task?.id)

        store.recordCompletedFocus(taskID: task?.id, seconds: 42 * 60)

        let restoredStore = FocusTaskStore(defaults: defaults)
        XCTAssertEqual(restoredStore.selectedTask?.title, "Write proposal")
        XCTAssertEqual(restoredStore.selectedTask?.plannedMinutes, 42)
        XCTAssertEqual(restoredStore.selectedTask?.loggedFocusMinutes, 42)
    }
}
