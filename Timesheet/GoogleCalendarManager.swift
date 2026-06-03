import Foundation
import GoogleSignIn
import AppKit

class GoogleCalendarManager {
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    func saveEvent(title: String, start: Date, end: Date, type: EntryType) async -> String {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.hasPrefix("YOUR_") else {
            return "Configure your Google Client ID in Info.plist first."
        }
        do {
            let user = try await ensureAuthenticated()
            try await user.refreshTokensIfNeeded()
            let token = user.accessToken.tokenString
            let calendarID = try await findTimesheetCalendar(token: token)
            try await postEvent(title: title, start: start, end: end, type: type, to: calendarID, token: token)
            return "Saved to Google Calendar (Timesheet)."
        } catch GoogleCalendarError.noTimesheetCalendar {
            return "No 'Timesheet' calendar found. Create it in Google Calendar first."
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Auth

    private func ensureAuthenticated() async throws -> GIDGoogleUser {
        if let current = GIDSignIn.sharedInstance.currentUser {
            return current
        }
        if let restored = await silentRestore() {
            return restored
        }
        return try await interactiveSignIn()
    }

    private func silentRestore() async -> GIDGoogleUser? {
        await withCheckedContinuation { cont in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                cont.resume(returning: user)
            }
        }
    }

    private func interactiveSignIn() async throws -> GIDGoogleUser {
        let window = NSApp.keyWindow ?? makeHelperWindow()
        return try await withCheckedThrowingContinuation { cont in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: window,
                hint: nil,
                additionalScopes: ["https://www.googleapis.com/auth/calendar"]
            ) { result, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let user = result?.user {
                    cont.resume(returning: user)
                } else {
                    cont.resume(throwing: GoogleCalendarError.signInFailed)
                }
            }
        }
    }

    private func makeHelperWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        return w
    }

    // MARK: - Calendar API

    private func findTimesheetCalendar(token: String) async throws -> String {
        var req = URLRequest(url: URL(string: "\(baseURL)/users/me/calendarList")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        guard let cal = list.items.first(where: { $0.summary == "Timesheet" }) else {
            throw GoogleCalendarError.noTimesheetCalendar
        }
        return cal.id
    }

    private func postEvent(title: String, start: Date, end: Date, type: EntryType, to calendarID: String, token: String) async throws {
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID
        let url = URL(string: "\(baseURL)/calendars/\(encodedID)/events")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let adjustedEnd = max(end, start.addingTimeInterval(60))
        let tz = TimeZone.current.identifier

        let body: [String: Any] = [
            "summary": title,
            "description": type.rawValue,
            "colorId": type == .task ? "10" : "5",
            "start": ["dateTime": fmt.string(from: start), "timeZone": tz],
            "end": ["dateTime": fmt.string(from: adjustedEnd), "timeZone": tz]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        #if DEBUG
        if let bodyData = req.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            print("[Timesheet] POST body: \(bodyString)")
        }
        #endif
        let (data, response) = try await URLSession.shared.data(for: req)
        #if DEBUG
        if let responseString = String(data: data, encoding: .utf8) {
            print("[Timesheet] API response: \(responseString)")
        }
        #endif
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GoogleCalendarError.apiError
        }
    }
}

// MARK: - Models

private struct CalendarListResponse: Decodable {
    let items: [CalendarItem]
}

private struct CalendarItem: Decodable {
    let id: String
    let summary: String
}

// MARK: - Errors

enum GoogleCalendarError: LocalizedError {
    case noTimesheetCalendar, signInFailed, apiError

    var errorDescription: String? {
        switch self {
        case .noTimesheetCalendar: return "No 'Timesheet' calendar found in Google Calendar."
        case .signInFailed: return "Google Sign-In was cancelled or failed."
        case .apiError: return "Failed to create calendar event."
        }
    }
}
