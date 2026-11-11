# Setting up Google Calendar sign-in

Makin' Groceries can read your Google Calendar directly (read-only) so Company Coming can find dinners and parties without adding your Google account to the iPhone Calendar app. Google requires every app that does this to have its own OAuth client. The client ID is not a secret and is safe to keep in this public repository. There is no client secret.

## One-time setup (about 10 minutes)

1. Go to <https://console.cloud.google.com/> and create a project (for example "Makin Groceries").
2. **APIs & Services › Library**: search for **Google Calendar API** and click **Enable**.
3. **APIs & Services › OAuth consent screen** (Google may call this "Google Auth Platform"):
   - User type: **External**.
   - App name: Makin' Groceries. Support email: yours.
   - Add the scope `https://www.googleapis.com/auth/calendar.readonly` under Data access.
   - Add your own Google account (and each family member's) under **Test users**. While the app is in **Testing**, only test users can sign in (up to 100), and Google ends their access after 7 days, so they would have to reconnect weekly. To avoid that, publish the app (see below).
4. **APIs & Services › Credentials › Create credentials › OAuth client ID**:
   - Application type: **iOS**.
   - Bundle ID: `com.beauregardhenry.makingroceries`.
5. Copy the **Client ID** (it ends in `.apps.googleusercontent.com`).
6. Put it in `Grocery/project.yml` as `GOOGLE_CLIENT_ID`, run `./scripts/regenerate-xcode-project.sh`, and build.

Until a client ID is set, the Google option stays hidden and the app uses only the phone's calendars.

## Publishing, so sign-in doesn't expire

Calendar read access is a "sensitive" scope. In **Testing** status, sign-ins expire after 7 days. Setting the consent screen to **In production** removes that. For fewer than 100 users, Google shows an "unverified app" warning on the consent screen, which each person can click through, and does not require a review. A public App Store release would need Google's verification (a privacy policy link, which this repository has, and a short video of the sign-in).

## What the app does

- Signs in with Apple's secure web sheet (PKCE). The app never sees your Google password.
- Asks only for read-only access to calendar events.
- Keeps a refresh token in this phone's Keychain (not synced, not backed up to other devices).
- Fetches events directly from Google to this phone. Nothing goes through any other server.
- **Disconnect** in Company Coming revokes the access with Google and deletes the token.
