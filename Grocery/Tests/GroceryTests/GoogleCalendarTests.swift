import XCTest

final class GoogleCalendarTests: XCTestCase {
    private let config = GoogleCalendarAPI.Config(clientID: "123-abc.apps.googleusercontent.com")

    func testTheClientIDDecidesWhetherItIsSetUp() {
        XCTAssertTrue(config.isConfigured)
        XCTAssertFalse(GoogleCalendarAPI.Config(clientID: "").isConfigured)
        XCTAssertFalse(GoogleCalendarAPI.Config(clientID: "not-a-client").isConfigured)
        XCTAssertEqual(config.redirectScheme, "com.googleusercontent.apps.123-abc")
        XCTAssertEqual(config.redirectURI, "com.googleusercontent.apps.123-abc:/oauth2redirect")
    }

    func testPKCEChallengeMatchesTheKnownExample() {
        // The worked example from RFC 7636.
        XCTAssertEqual(GoogleCalendarAPI.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = GoogleCalendarAPI.makeVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertNotEqual(verifier, GoogleCalendarAPI.makeVerifier())
        XCTAssertFalse(verifier.contains("+") || verifier.contains("/") || verifier.contains("="))
    }

    func testTheSignInAddressAsksForReadOnlyCalendarAccess() throws {
        let url = try XCTUnwrap(GoogleCalendarAPI.authorizationURL(config: config, challenge: "chal", state: "st"))
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["client_id"], config.clientID)
        XCTAssertEqual(items["scope"], "https://www.googleapis.com/auth/calendar.readonly")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["access_type"], "offline")
        XCTAssertEqual(items["redirect_uri"], config.redirectURI)
    }

    func testOnlyTheReplyToThisSignInIsAccepted() throws {
        let good = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?state=st&code=4%2Fabc"))
        XCTAssertEqual(GoogleCalendarAPI.authorizationCode(from: good, expectedState: "st"), "4/abc")
        XCTAssertNil(GoogleCalendarAPI.authorizationCode(from: good, expectedState: "other"))
        let denied = try XCTUnwrap(URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?state=st&error=access_denied"))
        XCTAssertNil(GoogleCalendarAPI.authorizationCode(from: denied, expectedState: "st"))
    }

    func testTokenRequestsAreFormEncodedWithoutAClientSecret() throws {
        let request = GoogleCalendarAPI.tokenRequest(config: config, code: "4/abc", verifier: "ver")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, GoogleCalendarAPI.tokenEndpoint)
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("code=4%2Fabc"))
        XCTAssertTrue(body.contains("code_verifier=ver"))
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertFalse(body.contains("secret"))
        let refresh = String(data: try XCTUnwrap(GoogleCalendarAPI.refreshRequest(config: config, refreshToken: "r").httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(refresh.contains("grant_type=refresh_token") && refresh.contains("refresh_token=r"))
        XCTAssertEqual(GoogleCalendarAPI.revokeRequest(token: "t").url, GoogleCalendarAPI.revokeEndpoint)
    }

    func testReadingTheTokenReply() {
        let reply = Data(#"{"access_token":"at","expires_in":3599,"refresh_token":"rt","scope":"x","token_type":"Bearer"}"#.utf8)
        XCTAssertEqual(GoogleCalendarAPI.parseToken(reply), GoogleCalendarAPI.Token(accessToken: "at", expiresIn: 3599, refreshToken: "rt"))
        XCTAssertNil(GoogleCalendarAPI.parseToken(Data(#"{"error":"invalid_grant"}"#.utf8)))
        XCTAssertNil(GoogleCalendarAPI.parseToken(Data("nope".utf8)))
        XCTAssertNil(GoogleCalendarAPI.parseToken(Data(#"{"access_token":"at"}"#.utf8))?.refreshToken)
    }

    func testCalendarListKeepsOnlyTheCalendarsYouShow() {
        let data = Data(#"{"items":[{"id":"me@x.com","summary":"Me","selected":true},{"id":"holidays","summary":"Holidays","summaryOverride":"US Holidays","selected":true},{"id":"hidden","summary":"Hidden"}]}"#.utf8)
        let calendars = GoogleCalendarAPI.parseCalendarList(data)
        XCTAssertEqual(calendars.map(\.id), ["me@x.com", "holidays"])
        XCTAssertEqual(calendars.map(\.name), ["Me", "US Holidays"])
        XCTAssertTrue(GoogleCalendarAPI.parseCalendarList(Data("{}".utf8)).isEmpty)
    }

    func testEventsAreReadWithTimesAllDayAndGuestCounts() throws {
        let json = #"""
        {"items":[
          {"id":"a","status":"confirmed","summary":"Family dinner","start":{"dateTime":"2026-11-20T18:30:00-05:00"},"attendees":[{},{},{},{},{}]},
          {"id":"b","summary":"Thanksgiving","start":{"date":"2026-11-26"}},
          {"id":"c","status":"cancelled","summary":"Gone","start":{"dateTime":"2026-11-21T10:00:00Z"}},
          {"id":"d","summary":"No time","start":{}},
          {"id":"e","summary":"Fractional","start":{"dateTime":"2026-11-22T10:00:00.500Z"}}
        ]}
        """#
        let events = GoogleCalendarAPI.parseEvents(Data(json.utf8), calendarName: "Me")
        XCTAssertEqual(events.map(\.title), ["Family dinner", "Thanksgiving", "Fractional"])
        XCTAssertEqual(events[0].attendeeCount, 5)
        XCTAssertFalse(events[0].isAllDay)
        XCTAssertEqual(events[0].start, Date(timeIntervalSince1970: 1_795_217_400))
        XCTAssertTrue(events[1].isAllDay)
        XCTAssertEqual(events[1].calendarName, "Me")
        XCTAssertTrue(GoogleCalendarAPI.parseEvents(Data("nope".utf8)).isEmpty)
    }

    func testEventsURLEscapesTheCalendarID() throws {
        let url = try XCTUnwrap(GoogleCalendarAPI.eventsURL(calendarID: "me@x.com", from: Date(timeIntervalSince1970: 0),
                                                           to: Date(timeIntervalSince1970: 86_400)))
        XCTAssertTrue(url.absoluteString.contains("/calendars/me@x.com/events") || url.absoluteString.contains("/calendars/me%40x.com/events"))
        XCTAssertTrue(url.absoluteString.contains("singleEvents=true"))
        XCTAssertTrue(url.absoluteString.contains("timeMin=1970-01-01T00:00:00Z"))
    }

    func testAnEventOnBothCalendarsIsListedOnce() {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let phone = [CalendarEvent(id: "p", title: "Family Dinner", start: when)]
        let google = [CalendarEvent(id: "g", title: " family dinner ", start: when),
                      CalendarEvent(id: "g2", title: "Brunch", start: when.addingTimeInterval(86_400))]
        XCTAssertEqual(CompanyEvents.merged(phone, google).map(\.id), ["p", "g2"])
    }
}
