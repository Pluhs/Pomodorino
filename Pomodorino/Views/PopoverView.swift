import SwiftUI

enum PopoverTab: String, CaseIterable {
    case timer = "Timer"
    case stats = "Stats"
    case settings = "Settings"
}

struct PopoverView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var settings: AppSettings
    @ObservedObject var analyticsStore: AnalyticsStore
    @ObservedObject var taskStore: FocusTaskStore
    @State private var selectedTab: PopoverTab

    init(
        timer: PomodoroTimer,
        settings: AppSettings,
        analyticsStore: AnalyticsStore,
        taskStore: FocusTaskStore,
        initialTab: PopoverTab = .timer
    ) {
        self.timer = timer
        self.settings = settings
        self.analyticsStore = analyticsStore
        self.taskStore = taskStore
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(PopoverTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Divider()
                .padding(.top, 8)

            switch selectedTab {
            case .timer:
                TimerView(timer: timer, settings: settings, taskStore: taskStore)
            case .stats:
                StatsView(analyticsStore: analyticsStore)
            case .settings:
                SettingsView(settings: settings, taskStore: taskStore)
            }
        }
        .frame(width: 320, height: 420, alignment: .top)
        .tint(settings.accentColor.color)
    }
}
