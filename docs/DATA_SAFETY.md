# Google Play - Data safety form answers

Answers for Play Console -> App content -> Data safety, based on what the code does
(`lib/services/`): the game has no backend and no analytics SDK; the only SDKs that touch user
data are Google Mobile Ads (with UMP consent) and Google Play Billing.

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** (because of the ads SDK) |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (Google SDKs use HTTPS) |
| Do you provide a way for users to request that their data is deleted? | **No account, no server-side data**; local data is removed by uninstalling. Answer "No" for an account-deletion mechanism, there are no accounts. |

## Data types (declared because of Google Mobile Ads)

| Data type | Collected | Shared | Optional | Purposes |
|---|---|---|---|---|
| Location -> Approximate location | Yes | Yes | No | Advertising or marketing; Analytics; Fraud prevention |
| App activity -> App interactions | Yes | Yes | No | Advertising or marketing; Analytics |
| App info and performance -> Diagnostics | Yes | Yes | No | Analytics; Fraud prevention |
| Device or other IDs | Yes | Yes | No | Advertising or marketing; Analytics; Fraud prevention |
| Financial info -> Purchase history | Yes | No | Yes | App functionality (Remove ads, via Google Play Billing) |

Not collected: name, e-mail, user IDs, contacts, photos, files, messages, health, precise
location, audio, calendar, web history.

This table follows Google's published guidance for the Mobile Ads SDK
(https://developers.google.com/admob/android/privacy/play-data-disclosure). Re-check that page
when filling the form: Google updates it.

## Other declarations

| Section | Answer |
|---|---|
| Ads | **Yes, contains ads** |
| Advertising ID | **Yes** (declared by the ads SDK via `com.google.android.gms.permission.AD_ID`) |
| Target audience | 13+ recommended (keeps the app out of the Families policy requirements) |
| Content rating questionnaire | No violence, no user interaction, no shared location, digital purchases: yes |
| Government app / financial features / health | No |
| News app | No |
