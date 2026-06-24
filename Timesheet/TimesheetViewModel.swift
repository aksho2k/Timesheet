import Foundation
import Combine

enum EntryType: String, CaseIterable, Identifiable {
    case task = "Task"
    case meeting = "Meeting"
    var id: String { rawValue }
}

enum AppState {
    case newEntry, recording, summary, saved
}

class TimesheetViewModel: ObservableObject {
    @Published var state: AppState = .newEntry
    @Published var entryTitle: String = ""
    @Published var entryType: EntryType = .task
    @Published var startTime: Date = Date()
    @Published var endTime: Date = Date()
    @Published var elapsedSeconds: Int = 0
    @Published var saveMessage: String? = nil
    @Published var statusBarTitle: String? = nil
    @Published var suggestions: [CalendarSuggestion] = []
    @Published var isFetchingSuggestions: Bool = false

    private var recordingTimer: Timer?
    let calendarManager = GoogleCalendarManager()

    var elapsedString: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    var duration: String {
        let diff = max(0, endTime.timeIntervalSince(startTime))
        let totalMinutes = Int(diff) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(totalMinutes)m"
    }

    // MARK: - Time rounding

    /// Rounds a date to the nearest minute.
    /// Seconds < 30 → floor to :00; seconds ≥ 30 → ceil to next :00.
    private func roundedToNearestMinute(_ date: Date) -> Date {
        let cal = Calendar.current
        let seconds = cal.component(.second, from: date)
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.second = 0
        let base = cal.date(from: comps) ?? date
        return seconds >= 30 ? base.addingTimeInterval(60) : base
    }

    func startRecording() {
        startTime = roundedToNearestMinute(Date())
        elapsedSeconds = 0
        state = .recording
        statusBarTitle = "⏱ 00:00"
        recordingTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(timerTick),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func timerTick() {
        elapsedSeconds += 1
        statusBarTitle = "⏱ \(elapsedString)"
    }

    func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        endTime = roundedToNearestMinute(Date())
        statusBarTitle = nil
        state = .summary
    }

    func reset() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        state = .newEntry
        entryTitle = ""
        entryType = .task
        elapsedSeconds = 0
        saveMessage = nil
        statusBarTitle = nil
        Task { await fetchSuggestions() }
    }

    func fetchSuggestions() async {
        guard !isFetchingSuggestions else { return }
        isFetchingSuggestions = true
        let titles = await calendarManager.fetchRecentTitles(count: 5)
        // Only replace if we got results, so stale suggestions stay on failure.
        if !titles.isEmpty {
            suggestions = titles
        }
        isFetchingSuggestions = false
    }

    func saveToCalendar() async {
        let message = await calendarManager.saveEvent(
            title: entryTitle,
            start: startTime,
            end: endTime,
            type: entryType
        )
        if message.hasPrefix("Saved") {
            state = .saved
        } else {
            saveMessage = message
        }
    }
}
