import SwiftUI

struct TimerView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var settings: AppSettings
    @ObservedObject var taskStore: FocusTaskStore

    private var stateColor: Color {
        switch timer.timerState {
        case .idle:
            return settings.accentColor.color
        case .running:
            return timer.sessionType == .work
                ? settings.workTimerColor.color
                : settings.breakTimerColor.color
        case .paused:
            return settings.pausedTimerColor.color
        }
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 10) {
            // Session type
            Text(timer.sessionType.displayName)
                .font(.headline)
                .foregroundColor(stateColor)

            TaskPicker(timer: timer, taskStore: taskStore)

            // Circular progress timer
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(stateColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                VStack(spacing: 4) {
                    Text(timer.formattedTime)
                        .font(.system(size: 36, weight: .medium, design: .monospaced))

                    if timer.timerState == .paused {
                        Text("PAUSED")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 140, height: 140)

            // Session count
            VStack(spacing: 4) {
            Text(
                "Session \(timer.currentSessionIndex + 1) of \(timer.settings.pomodorosBeforeLongBreak)"
            )
            .font(.subheadline)
            .foregroundColor(.secondary)

            // Completed count
            Text(
                "\(timer.completedPomodoros) pomodoro\(timer.completedPomodoros == 1 ? "" : "s") completed"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            }

            // Controls
            HStack(spacing: 20) {
                Button(action: timer.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(timer.timerState == .idle)
                .opacity(timer.timerState == .idle ? 0.4 : 1.0)

                Button(action: timer.toggleStartPause) {
                    Image(
                        systemName: timer.timerState == .running
                            ? "pause.circle.fill" : "play.circle.fill"
                    )
                    .font(.system(size: 44))
                    .foregroundColor(stateColor)
                }
                .buttonStyle(.plain)

                Button(action: timer.skip) {
                    Image(systemName: "forward.end")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }

        }
        .frame(maxWidth: .infinity)
        .padding(12)
        }
    }
}

private struct TaskPicker: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var taskStore: FocusTaskStore

    private var taskTitle: String {
        timer.activeFocusTask?.title ?? "Quick timer"
    }

    private var durationTitle: String {
        let minutes = Int(timer.totalDuration / 60)
        return "\(minutes) min target"
    }

    var body: some View {
        VStack(spacing: 4) {
        Menu {
            Button("Quick timer (no task)") {
                timer.selectTask(id: nil)
            }

            if !taskStore.tasks.isEmpty {
                Divider()
                ForEach(taskStore.tasks) { task in
                    Button {
                        timer.selectTask(id: task.id)
                    } label: {
                        if task.id == taskStore.selectedTaskID {
                            Label("\(task.title) · \(task.plannedMinutes) min", systemImage: "checkmark")
                        } else {
                            Text("\(task.title) · \(task.plannedMinutes) min")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                Text(taskTitle)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .help("Switch timers; the current timer is paused and kept until you return.")
        if timer.activeFocusTask == nil, timer.sessionType == .work, timer.timerState == .idle {
            HStack {
                Text("Minutes")
                TextField("Minutes", value: Binding(
                    get: { timer.quickTimerMinutes },
                    set: { timer.setQuickTimerMinutes($0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
            }
            .font(.caption)
        } else {
            Text(durationTitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        }
    }
}
