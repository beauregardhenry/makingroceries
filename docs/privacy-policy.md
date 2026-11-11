# Privacy Policy for Makin' Groceries

_Last updated: November 11, 2026_

Makin' Groceries is a grocery list app for iPhone and iPad. This policy says what the app does with your information. The short version: **your data stays on your devices and in your own iCloud account. I don't run any servers, I don't collect your data, and there is no advertising, tracking or analytics in the app.**

## What the app stores

Your lists, stores, saved meals, meal plans, prices, spending history, what's at home, photos you attach to items, and settings are saved in files on your device. I never see them.

## iCloud Sync (optional, off until you turn it on)

If you turn on iCloud Sync, the same files are copied to **your private iCloud database** (CloudKit) so your devices stay in step. That data belongs to your Apple ID. It is stored and protected by Apple under [Apple's privacy policy](https://www.apple.com/legal/privacy/). The developer has no access to it.

## Live Sync (optional)

Live Sync shares one list between phones in the same household over the local network (Apple's Multipeer Connectivity). Phones find each other using a household code, which is hashed before use. The list goes directly between the phones. It doesn't pass through a server.

## Things the app asks permission for

Each is optional, and the app works without them.

- **Camera**: to scan barcodes, receipts and recipe photos. Images are processed on your device.
- **Photos**: to attach a photo to an item or read a recipe from a picture you choose.
- **Microphone and speech recognition**: to add items by voice, using on-device recognition when your iPhone supports it.
- **Location**: to remember where a store is and remind you of your list when you arrive. Your location is kept on your device and is never sent anywhere.
- **Calendar**: Company Coming reads event titles, dates and guest counts from your calendar to suggest make-ahead meals before dinners and parties. This is read on your device. Nothing from your calendar is stored in the cloud or sent anywhere.
- **Google Calendar (optional)**: if you tap Connect Google Calendar in Company Coming, you sign in on Google's own page, in Apple's secure web sheet, and allow read-only access to your calendar events. The app never sees your Google password. It keeps a sign-in token in your iPhone's Keychain on that phone only, and fetches your events directly from Google to your phone, where they are used only to find dinners and parties. Nothing goes to the developer or any other server. Disconnect in Company Coming revokes the access with Google and deletes the token, and you can also remove it at <https://myaccount.google.com/permissions>. The app's use of information received from Google APIs follows the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements.
- **Notifications**: for arrival reminders and for things in your kitchen that should be used soon.
- **Local network**: for Live Sync.

## The only times the app contacts the internet

1. **Barcode lookup.** When you scan a product barcode, the barcode number is sent to [Open Food Facts](https://world.openfoodfacts.org) to get the product's name, size and allergens. Nothing else is sent, and nothing identifies you.
2. **Recipe import from a web address.** When you paste a recipe link, the app downloads that page to read its ingredients, like a browser would.
3. **iCloud Sync**, if you turn it on, as described above.

Suggestions such as "What can I cook?" and aisle guesses use Apple's on-device intelligence on supported iPhones. Nothing is sent to a server for them.

## What I don't do

I don't collect, sell, rent or share your personal information. The app has no accounts, no ads, no third-party analytics and no tracking across other apps or websites.

## Children

The app doesn't knowingly collect any information from anyone, including children.

## Deleting your data

Delete the app to remove everything stored on that device. To remove iCloud copies, turn off iCloud Sync and delete the app's data in **Settings › [your name] › iCloud › Manage Storage**.

## Changes

If this policy changes, the new version will be posted at this address with a new date.

## Contact

Questions about privacy: open an issue at <https://github.com/beauregardhenry/makingroceries/issues>.
