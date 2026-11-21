# Homework

Isaac's iPhone homework app (Flutter).

- **Today**: everything due, grouped by when, with a bar showing how much time is left (a full bar = a week or more).
- **Calendar**: the app's own month calendar. Blue dots = homework due, orange squares = school activities.
- **Found**: deadlines Claude found in Teams messages. They're added automatically; ones with an unclear date are marked "Check the date".
- **Detail page**: reminders (nudge to start, day before, morning of) scheduled on the phone, the original message, and Open in Teams.

Data: your own items are stored on the device. Teams items come from a private feed whose address is set at build time (`FEED_URL`) and is never in this repository.

Build: `codemagic.yaml` makes the unsigned iPhone `.ipa`; `.github/workflows/build-windows.yml` makes a Windows test build on every push.

Install: sideload the `.ipa` with SideStore using a free Apple ID (refresh every 7 days).

Code: `lib/main.dart` (Today, Calendar, Found), `lib/detail.dart`, `lib/editor.dart`, `lib/ui.dart` (shared pieces), `lib/data.dart` (storage and sync), `lib/reminders.dart` (alerts), `lib/models.dart`.
