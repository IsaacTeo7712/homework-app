# Homework

A small iPhone app that shows homework deadlines and school activities from a Google Calendar, as a list and a month calendar, with tick-off boxes.

- Data: the calendar's private iCal link, pasted into the app's Settings. The link is stored only on the phone and is never in this repository.
- Build: GitHub Actions compiles an unsigned `.ipa` on every push to `main` and attaches it to a release.
- Install: sideload the `.ipa` with SideStore or iloader using a free Apple ID (re-sign every 7 days).

Code: `lib/main.dart` (screens) and `lib/ics.dart` (calendar feed reader).
