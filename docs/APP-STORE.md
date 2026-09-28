# App Store submission

Everything App Store Connect asks for, in the order it asks. The app ships
**unlisted**: it passes the same App Review as any other app, but it is not
searchable or browsable, and only people with the direct link can install it.

Nothing secret belongs in this file. The repo is public, so the reviewer demo
code goes in App Store Connect's review notes and nowhere else.

## 1. Unlisted distribution

1. Create the app record in App Store Connect (bundle `com.strangeramblings.com.appleapp`) and fill in sections 2–5 below.
2. Submit a build for review as usual.
3. Send Apple's **Unlisted App Distribution request** (developer.apple.com → Distribute → Unlisted app distribution),
   naming the app and saying who it is for: "a private companion for one family and a handful of invited people;
   every account is invitation-only and approved by hand".
4. Once Apple approves the request, the app is released as unlisted and App Store Connect shows the direct link.
   Send that link to the family. TestFlight keeps working alongside it.

## 2. Listing

| Field | Value |
| --- | --- |
| Name (30) | `Strange Rambler` (the Home Screen name stays `SR Companion`, from `CFBundleDisplayName`) |
| Subtitle (30) | `Family, health and chat` |
| Primary category | Health & Fitness |
| Secondary category | Lifestyle |
| Support URL | `https://strangeramblings.com/welcome` |
| Marketing URL | leave blank |
| Privacy policy URL | `https://strangeramblings.com/privacy` |
| Copyright | `2026 John Kelly` |

**Promotional text (170)**

> Where everyone is, how many steps they've done today, and who has earned their game time. The companion to strangeramblings.com, for invited family and friends.

**Description**

> Strange Rambler (SR Companion on your Home Screen) is the phone half of strangeramblings.com, my personal site, and it's for my family and a few people I've invited. You can't sign up without an invitation, and every account is checked by hand before it opens.
>
> Family. Everyone who shares their location shows up on one map with their battery, where they are and what they've been up to today. When someone leaves home the app keeps a closer track until they get where they're going, and the journey can sit on the Lock Screen while it's happening.
>
> Steps. A daily leaderboard for the family, reset every morning, with a nudge at four o'clock about where you stand and another if someone takes the top spot off you.
>
> Tasks. Anyone can add a job, with a deadline and a reward if there is one — cash, a day out, game time, lunch out — and a parent confirms it's done before it comes off the list. Everyone can see what they've finished and what they're owed.
>
> Health. The Apple Health figures you choose go to your own private health dashboard on the site. Family steps appear on the leaderboard only after separate opt-in. The site owner may publish selected figures on their public Health page; server operators administer the stored data.
>
> Chat. Talk to jkai, the site's assistant, by text, photo or voice note.
>
> Also games to play against each other, the news desk, and widgets for the Home Screen and Lock Screen.
>
> Location sharing can be paused at any time, and you can delete your account from Settings.

**Keywords (100)**

> `family,location,steps,leaderboard,chores,tasks,rewards,health,chat,companion,journey,widgets`

**What's New** (first release): `First release.`

## 3. App Review information

- **Sign-in required:** yes. **Demo account:** leave username/password blank and put this in the notes instead.
- **Contact:** John Kelly, john@strangeramblings.com (phone: the owner's, entered in App Store Connect only).

**Notes** (replace `<CODE>` with the value of `APP_REVIEW_DEMO_CODE` on the VPS):

> Strange Rambler (shown as SR Companion under the icon) is a private companion app for one family and a small number of invited people. Accounts are invitation-only and approved by hand, and the app is being submitted for Unlisted App Distribution.
>
> Because real accounts show real family members' live locations, we have provided a full demo mode instead of a demo account. On the first screen, tap "I have a pairing code" and enter <CODE>. The app then runs on made-up demo data (a demo family, health figures, chat, steps leaderboard and task list) and makes no uploads. Settings → Leave demo returns to the first screen.
>
> Background location: family members choose to share their location with each other. The app uses background location so that the family map stays current, and records a journey more closely after the person leaves a place they have chosen. Motion data is read only to switch GPS off while the phone is still, to save battery. Sharing can be paused from Settings → Location & battery.
>
> HealthKit: the app reads only the Apple Health categories the person chooses, and uploads them to their own private dashboard. It does not write to Apple Health, and health data is not used for advertising. Optional family steps and the configured owner’s public Health projection are explained in Settings and the privacy policy.
>
> Sign in with Apple is offered on the first screen alongside Google. Accounts can be deleted from Settings → Delete account.

## 4. App Privacy ("nutrition label")

Tracking: **No** for every type. Nothing is used for third-party advertising or shared with data brokers.
Every type below is **linked to the user** and used for **App Functionality** only.

| Data type | Why |
| --- | --- |
| Contact Info → Name | From Sign in with Apple / Google, shown to family |
| Contact Info → Email Address | Account identity |
| Health & Fitness → Health | Apple Health categories the person chooses, for their private dashboard |
| Health & Fitness → Fitness | Steps, workouts; daily step total shown on the family leaderboard |
| Location → Precise Location | Family map, journeys |
| User Content → Photos or Videos | Photos sent in chat |
| User Content → Audio Data | Voice notes sent in chat |
| User Content → Other User Content | Chat messages, family tasks |
| Identifiers → User ID | Account id |
| Identifiers → Device ID | Push notification token |

Not collected: financial info (a task reward is a number typed by a parent, not a payment), contacts, browsing
history, search history, purchases, usage data, diagnostics, sensitive info.

`ios/SRAppleApp/PrivacyInfo.xcprivacy` declares the same list, so the label and the manifest agree.

## 5. Age rating

Answer the questionnaire honestly. The answers that matter: **no** unrestricted web access, **no**
user-generated content shared publicly (chat is with an assistant, tasks are private to the family), the
assistant is an AI chatbot (answer the AI/chatbot question **yes**), location is shared **only with approved
family members**. Expect a 13+ rating. The rating doesn't stop anyone installing from a direct link unless
Screen Time content restrictions are set on their phone.

## 6. Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in `Info.plist` (HTTPS only), so no questions per build.

## 7. Screenshots

App Store Connect needs the **6.9-inch** set (1320 × 2868; any 6.5-inch set is accepted instead). Run the
**App Store screenshots** workflow (Actions → App Store screenshots → Run workflow). It runs the showcase
UI tests on an iPhone Pro Max simulator in demo mode, in light and dark, and uploads them as the
`app-store-screenshots` artifact. Upload 6–8 of them: Today, Family map, Steps, Tasks, Health, Chat, Games, widgets.
