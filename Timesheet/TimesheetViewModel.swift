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

    func startRecording() {
        startTime = Date()
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
        endTime = Date()
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
