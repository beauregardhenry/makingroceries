import AuthenticationServices
import Observation
import Security
import UIKit

/// Signs in to Google Calendar from inside the app and reads upcoming events (read-only). The sign-in
/// happens in Apple's secure web sheet, so the app never sees your Google password. Only a refresh token is
/// kept, in the iOS Keychain on this phone, and events are fetched straight from Google to this phone.
@MainActor @Observable
final class GoogleCalendarAccount: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum State: Equatable { case notSetUp, signedOut, signedIn }

    private(set) var state: State
    private(set) var message: String?
    private(set) var isWorking = false

    @ObservationIgnored private let config: GoogleCalendarAPI.Config
    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessExpiry = Date.distantPast
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    private static let keychainAccount = "google-refresh-token"

    init(config: GoogleCalendarAPI.Config = .fromBundle) {
        self.config = config
        state = !config.isConfigured ? .notSetUp : (Keychain.read(Self.keychainAccount) == nil ? .signedOut : .signedIn)
        super.init()
    }

    // MARK: Sign in and out

    func signIn() async {
        guard config.isConfigured, !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        let verifier = GoogleCalendarAPI.makeVerifier()
        let sentState = UUID().uuidString
        guard let url = GoogleCalendarAPI.authorizationURL(config: config, challenge: GoogleCalendarAPI.challenge(for: verifier), state: sentState) else {
            message = "Couldn't start Google sign-in."
            return
        }
        do {
            let callback = try await authenticate(url)
            guard let code = GoogleCalendarAPI.authorizationCode(from: callback, expectedState: sentState) else {
                message = "Google sign-in didn't finish. Try again."
                return
            }
            let (data, _) = try await URLSession.shared.data(for: GoogleCalendarAPI.tokenRequest(config: config, code: code, verifier: verifier))
            guard let token = GoogleCalendarAPI.parseToken(data), let refresh = token.refreshToken else {
                message = "Google didn't allow calendar access."
                return
            }
            Keychain.save(refresh, for: Self.keychainAccount)
            accessToken = token.accessToken
            accessExpiry = Date().addingTimeInterval(token.expiresIn - 60)
            state = .signedIn
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closed the sheet: nothing to report.
        } catch {
            message = "Couldn't reach Google. Check your connection and try again."
        }
    }

    func signOut() async {
        if let refresh = Keychain.read(Self.keychainAccount) {
            // Ask Google to end the access too; signing out here works even when this fails.
            _ = try? await URLSession.shared.data(for: GoogleCalendarAPI.revokeRequest(token: refresh))
        }
        Keychain.remove(Self.keychainAccount)
        accessToken = nil
        accessExpiry = .distantPast
        state = .signedOut
        message = nil
    }

    // MARK: Events

    /// Events on the calendars you show in Google Calendar over the next `days`, or none when signed out or offline.
    func events(days: Int, now: Date = Date()) async -> [CalendarEvent] {
        guard state == .signedIn, let token = await validToken(),
              let end = Calendar.current.date(byAdding: .day, value: days, to: now) else { return [] }
        func fetch(_ url: URL) async -> Data? {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
            if status == 401 { await expire() }
            return status == 200 ? data : nil
        }
        guard let listData = await fetch(GoogleCalendarAPI.calendarListURL) else { return [] }
        var events: [CalendarEvent] = []
        for calendar in GoogleCalendarAPI.parseCalendarList(listData).prefix(10) {
            guard let url = GoogleCalendarAPI.eventsURL(calendarID: calendar.id, from: now, to: end),
                  let data = await fetch(url) else { continue }
            events += GoogleCalendarAPI.parseEvents(data, calendarName: calendar.name)
        }
        return events
    }

    private func validToken() async -> String? {
        if let accessToken, accessExpiry > Date() { return accessToken }
        guard let refresh = Keychain.read(Self.keychainAccount),
              let (data, response) = try? await URLSession.shared.data(for: GoogleCalendarAPI.refreshRequest(config: config, refreshToken: refresh)),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 400 || status == 401 {
            // Access was removed on Google's side (or the testing period ended): go back to signed out.
            Keychain.remove(Self.keychainAccount)
            await expire()
            state = .signedOut
            return nil
        }
        guard let token = GoogleCalendarAPI.parseToken(data) else { return nil }
        accessToken = token.accessToken
        accessExpiry = Date().addingTimeInterval(token.expiresIn - 60)
        return token.accessToken
    }

    private func expire() async {
        accessToken = nil
        accessExpiry = .distantPast
    }

    // MARK: Web sign-in sheet

    private func authenticate(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(config.redirectScheme)) { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? URLError(.cancelled)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

/// The few Keychain calls the refresh token needs.
private enum Keychain {
    private static let service = "com.beauregardhenry.makingroceries.google"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func save(_ value: String, for account: String) {
        remove(account)
        var item = query(account)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        var item = query(account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
