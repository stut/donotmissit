# DoNotMissIt

A macOS menu bar app that makes meetings impossible to miss. Shortly before each meeting it covers every display with a card showing the meeting and a live countdown. Press enter to join the call, or esc to dismiss.

- Finds the join link in the event's URL, location or notes: Zoom, Google Meet, Microsoft Teams, Webex, Whereby, Amazon Chime, GoTo and Around.
- Shows your next meeting and the time until it starts in the menu bar. Click to view upcoming meetings, and select one to preview its alert.
- Skips all-day, cancelled and declined events, and only alerts once for a meeting that appears in two calendars.
- Alerts on wake if the meeting started within the last 5 minutes while your Mac was asleep.
- Settings: alert 1 to 10 minutes before, look ahead for upcoming meetings from 4 hours to a month, option to start at login.

It reads the calendars on your Mac, so iCloud, Google, Exchange and any other account added in System Settings all work. Requires macOS 26.

## Install

The app has been submitted to the App Store, and the URL will be added once it's accepted.

## Building

Needs Xcode 26. To build without an Apple developer account:

```sh
xcodebuild CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
open build/Release/DoNotMissIt.app
```

With your own team set in Xcode, `./build.sh` builds, runs the self-test and copies the app to the repo root.

## Privacy

Your calendar never leaves your Mac. See [PRIVACY.md](PRIVACY.md).

## License

[MIT](LICENSE)
