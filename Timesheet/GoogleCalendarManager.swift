import Foundation
import GoogleSignIn
import AppKit

class GoogleCalendarManager {
    private let baseURL = "https://www.googleapis.com/calendar/v3"

    /// Cached Timesheet calendar ID so both save and fetch flows resolve it once
    /// and always use the same value.
    private var cachedTimesheetCalendarID: String?

    func saveEvent(title: String, start: Date, end: Date, type: EntryType) async -> String {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.hasPrefix("YOUR_") else {
            return "Configure your Google Client ID in Info.plist first."
        }
        do {
            let user = try await ensureAuthenticated()
            try await user.refreshTokensIfNeeded()
            let token = user.accessToken.tokenString
            let calendarID = try await resolveTimesheetCalendar(token: token)
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

    /// Returns the Timesheet calendar ID, using a cached value after the first lookup.
    private func resolveTimesheetCalendar(token: String) async throws -> String {
        if let cached = cachedTimesheetCalendarID {
            return cached
        }
        var req = URLRequest(url: URL(string: "\(baseURL)/users/me/calendarList")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let list = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        guard let cal = list.items.first(where: { $0.summary == "Timesheet" }) else {
            throw GoogleCalendarError.noTimesheetCalendar
        }
        cachedTimesheetCalendarID = cal.id
        #if DEBUG
        print("[Timesheet] Resolved Timesheet calendar ID: \(cal.id)")
        #endif
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

    // MARK: - Recent event titles

    /// Returns the titles of the last `count` past events in the Timesheet calendar,
    /// most recent first. Silently returns an empty array on any error.
    func fetchRecentTitles(count: Int = 3) async -> [CalendarSuggestion] {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.hasPrefix("YOUR_") else { return [] }
        do {
            let user = try await ensureAuthenticated()
            try await user.refreshTokensIfNeeded()
            let token = user.accessToken.tokenString
            return try await fetchEventTitles(token: token, unique: count)
        } catch {
            #if DEBUG
            print("[Timesheet] fetchRecentTitles error: \(error)")
            #endif
            return []
        }
    }

    private func fetchEventTitles(token: String, unique: Int) async throws -> [CalendarSuggestion] {
        let calendarID = "c_573eb76400332bf720232e4715c7821e539b7fc3c4721e0b86e8096ab61b98bf@group.calendar.google.com"
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID

        // Format dates with IST offset (+05:30) so morning IST events are not excluded.
        let ist = TimeZone(secondsFromGMT: 5 * 3600 + 30 * 60)!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        fmt.timeZone = ist
        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        // timeMin = midnight IST on the day 7 days ago
        var comps = Calendar.current.dateComponents(in: ist, from: sevenDaysAgo)
        comps.hour = 0; comps.minute = 0; comps.second = 0
        let timeMinDate = Calendar.current.date(from: comps) ?? sevenDaysAgo
        let timeMin = fmt.string(from: timeMinDate)
        let timeMax = fmt.string(from: now)

        // URLComponents.queryItems leaves '+' unencoded (RFC 3986 allows it in queries),
        // but Google Calendar API treats bare '+' as a space, making "+05:30" invalid.
        // Pre-encode '+' to '%2B' and set via percentEncodedQuery to avoid double-encoding.
        let timeMinEncoded = timeMin.replacingOccurrences(of: "+", with: "%2B")
        let timeMaxEncoded = timeMax.replacingOccurrences(of: "+", with: "%2B")

        var components = URLComponents(string: "\(baseURL)/calendars/\(encodedID)/events")!
        components.queryItems = [
            URLQueryItem(name: "orderBy",      value: "startTime"),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "maxResults",   value: "50"),
        ]
        components.percentEncodedQuery = (components.percentEncodedQuery ?? "")
            + "&timeMin=\(timeMinEncoded)"
            + "&timeMax=\(timeMaxEncoded)"
        var req = URLRequest(url: components.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        #if DEBUG
        print("[Timesheet] fetchEventTitles URL: \(components.url?.absoluteString ?? "nil")")
        #endif

        let (data, _) = try await URLSession.shared.data(for: req)
        let response: EventListResponse
        do {
            response = try JSONDecoder().decode(EventListResponse.self, from: data)
        } catch {
            #if DEBUG
            print("[Timesheet] fetchEventTitles decode error: \(error)")
            print("[Timesheet] raw response: \(String(data: data, encoding: .utf8) ?? "nil")")
            #endif
            throw error
        }

        #if DEBUG
        let rawTitles = response.items.compactMap { $0.summary }
        print("[Timesheet] fetchEventTitles: \(rawTitles.count) raw events before dedup: \(rawTitles)")
        #endif

        // Reverse (API returns oldest-first) then deduplicate, keeping most recent occurrence.
        var seen = Set<String>()
        var result: [CalendarSuggestion] = []
        for item in response.items.reversed() {
            guard let title = item.summary else { continue }
            let key = title.lowercased()
            guard seen.insert(key).inserted else { continue }
            let entryType: EntryType = item.colorId == "5" ? .meeting : .task
            result.append(CalendarSuggestion(title: title, entryType: entryType))
            if result.count == unique { break }
        }
        return result
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

private struct EventListResponse: Decodable {
    let items: [EventItem]
}

private struct EventItem: Decodable {
    let summary: String?
    let colorId: String?
}

struct CalendarSuggestion {
    let title: String
    let entryType: EntryType
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
