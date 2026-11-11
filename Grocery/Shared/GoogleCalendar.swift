import CryptoKit
import Foundation

/// Everything about talking to Google Calendar that doesn't need the screen: building the sign-in and token
/// requests, and reading the replies. The sign-in itself (GoogleCalendarAccount) lives in the app.
///
/// The app signs in as a public client with PKCE, so there is no client secret anywhere in it, and asks only
/// for read-only access to calendar events.
enum GoogleCalendarAPI {
    static let scope = "https://www.googleapis.com/auth/calendar.readonly"
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let apiBase = "https://www.googleapis.com/calendar/v3"

    /// The OAuth client for this app, made in Google Cloud Console (see docs/google-calendar-setup.md).
    struct Config: Equatable {
        var clientID: String

        var isConfigured: Bool { clientID.hasSuffix(".apps.googleusercontent.com") }

        /// Google's iOS clients use the client ID backwards as the sign-in return address.
        var redirectScheme: String {
            "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        }

        var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

        static var fromBundle: Config {
            Config(clientID: (Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String) ?? "")
        }
    }

    // MARK: Sign-in

    static func makeVerifier() -> String {
        base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func authorizationURL(config: Config, challenge: String, state: String) -> URL? {
        var parts = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return parts?.url
    }

    /// The code from Google's reply, only when it answers this sign-in (the state matches).
    static func authorizationCode(from callback: URL, expectedState: String) -> String? {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState else { return nil }
        return items.first(where: { $0.name == "code" })?.value
    }

    static func tokenRequest(config: Config, code: String, verifier: String) -> URLRequest {
        form(tokenEndpoint, [
            "client_id": config.clientID, "code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": config.redirectURI,
        ])
    }

    static func refreshRequest(config: Config, refreshToken: String) -> URLRequest {
        form(tokenEndpoint, ["client_id": config.clientID, "refresh_token": refreshToken, "grant_type": "refresh_token"])
    }

    static func revokeRequest(token: String) -> URLRequest {
        form(revokeEndpoint, ["token": token])
    }

    struct Token: Equatable {
        var accessToken: String
        var expiresIn: TimeInterval
        /// Only sent the first time you sign in.
        var refreshToken: String?
    }

    static func parseToken(_ data: Data) -> Token? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = json["access_token"] as? String else { return nil }
        return Token(accessToken: access, expiresIn: (json["expires_in"] as? Double) ?? 3600,
                     refreshToken: json["refresh_token"] as? String)
    }

    // MARK: Events

    static var calendarListURL: URL {
        URL(string: "\(apiBase)/users/me/calendarList?minAccessRole=reader&maxResults=20")!
    }

    static func eventsURL(calendarID: String, from start: Date, to end: Date) -> URL? {
        let encoded = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "/", with: "%2F") ?? calendarID
        var parts = URLComponents(string: "\(apiBase)/calendars/\(encoded)/events")
        let formatter = ISO8601DateFormatter()
        parts?.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        return parts?.url
    }

    /// The calendars you have ticked in Google Calendar (the ones it shows), as ids and names.
    static func parseCalendarList(_ data: Data) -> [(id: String, name: String)] {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"] as? String, (item["selected"] as? Bool) ?? false else { return nil }
            return (id, (item["summaryOverride"] as? String) ?? (item["summary"] as? String) ?? id)
        }
    }

    static func parseEvents(_ data: Data, calendarName: String? = nil) -> [CalendarEvent] {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard (item["status"] as? String) != "cancelled", let id = item["id"] as? String,
                  let start = item["start"] as? [String: Any], let when = date(from: start) else { return nil }
            return CalendarEvent(id: "google-\(id)-\(when.date.timeIntervalSince1970)",
                                 title: (item["summary"] as? String) ?? "",
                                 start: when.date, attendeeCount: (item["attendees"] as? [Any])?.count ?? 0,
                                 isAllDay: when.allDay, calendarName: calendarName)
        }
    }

    // MARK: Helpers

    private static func date(from start: [String: Any]) -> (date: Date, allDay: Bool)? {
        if let text = start["dateTime"] as? String {
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = plain.date(from: text) ?? fractional.date(from: text) { return (date, false) }
            return nil
        }
        if let text = start["date"] as? String {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: text) { return (date, true) }
        }
        return nil
    }

    private static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        return request
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

extension CompanyEvents {
    /// The phone's events and Google's together. An event on both (the Google account is also added in
    /// Settings › Calendar) is listed once.
    static func merged(_ phone: [CalendarEvent], _ google: [CalendarEvent]) -> [CalendarEvent] {
        func key(_ event: CalendarEvent) -> String {
            "\(event.title.trimmingCharacters(in: .whitespaces).lowercased())|\(Int(event.start.timeIntervalSince1970 / 60))"
        }
        var seen = Set<String>()
        return (phone + google).filter { seen.insert(key($0)).inserted }
    }
}
