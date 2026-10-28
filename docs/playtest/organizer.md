# First closed playtest

Invite 5-8 people, including genre players who have not watched development.
Watch 2-3 first sessions with consent. Let players attempt things before helping;
note what they expected and what actually happened. Avoid explaining all the rules
up front: the tutorial and UI are part of this test.

## Discord post

Here's the first closed playtest of Slay & Reign. Extract the whole ZIP and open
Slay and Reign.exe. START-HERE.txt has the controls and where to find logs.

Try the armies, money and cities tutorials, then a Tiny / 2 kingdoms / Easy
Quick Play match. Around 30-45 minutes is enough; there's no need to finish.
There isn't mid-match saving yet.

I'd like to know where you got confused, which decision was most interesting,
and whether you'd play another match. Please include the build label with bugs,
plus what you were doing and a screenshot or log if possible.

Please keep the build and link in this group.

## Packaging

Run from the project root, supplying your Godot 4.6.3 console executable:

```powershell
./tools/package_playtest.ps1 -Godot "C:/path/to/Godot_console.exe" -Label closed-01
```

Godot's installed release export template is used by default. With a standalone
Windows x64 release template, add `-Template "C:/path/to/windows_release_x86_64.exe"`.
The script isolates export preferences, preserves the existing export preset,
checks native dependencies, adds the tester brief, licenses and build identity,
then creates a ZIP and SHA-256 file under `builds/`. Use a new label for each build.
The git revision identifies the base; existing uncommitted changes are included
and indicated in BUILD.txt. Keep the exact distributed archive for reproductions.

## Before sending

- Extract the ZIP into a fresh folder; launch without the editor or Steam.
- Check first-launch onboarding and readable UI at 1280x820 and 960x620.
- Complete one tutorial, then start Quick Play, move, recruit and end a turn.
- Check pause/resume, restart, return to menu, quit and relaunch.
- Complete a match; save and reopen its replay.
- Confirm the log path in START-HERE.txt on that PC.
- Repeat launch on another Windows PC. Hardware requirements remain unverified.
- Treat Steam online as a separate test with two real accounts.

Headless regression checks do not replace these exported-build checks. Record
results in the preparation report and leave unperformed checks explicitly open.
