# Playtest preparation — 28 October 2026

Prepared `builds/Slay-and-Reign-0.2.0-closed-02-windows-x64.zip` (47,085,397
bytes). This is a Windows x64 release export, including the current uncommitted
0.2.0 work, native Steam dependencies, START-HERE.txt, build identity and license
notices. A SHA-256 sidecar identifies the exact archive. Nothing has been posted.

## Verification

- Version metadata agrees: game 0.2.0, Windows 0.2.0.0.
- Release export completed without engine/script errors.
- Extracted archive and launched its executable independently of the editor.
- Captured the actual release rendering: loading reaches the initial Create your
  kingdom screen, with readable layout at the default 1280x820 resolution. Exit
  code was zero. Evidence: `artifacts/playtest-render/launch00000239.png`.
- Eight focused headless suites pass: startup (106), logistics (373), logistics
  tutorial (87), tutorial (390), menus (110), localization (32), results (71),
  replays (131). Total: 1,300 passing checks.
- Updated stale menu expectations for eight topics and hover descriptions;
  replay construction now exercises cities instead of removed houses.

## Open issues before sending

The broader `test_game.gd` suite completed with 114,077 checks passing and 15
failing. Failed expectations involve recruitment away from hubs, long-distance
merging, follow-on upgrades/purchases, removed house construction/income and UI
movement. These overlap the 0.2.0 rules changes, but have not all been reconciled
or independently classified as obsolete tests versus regressions. Full output is
in `artifacts/playtest-test_game.log`. The full regression runner was not run.

The release launch check does not verify interactive gameplay. Before sending,
complete the organizer's fresh-extraction checklist: create a profile, finish a
tutorial, play a match, pause/restart, save and reopen a replay, and launch on
another Windows PC. Steam was running on the verification PC; offline launching
and two-account online play remain unverified. Minimum-window layout and hardware
compatibility need manual checks. No minimum hardware specification is claimed.

The first sandboxed export failed during temporary-file/native-library access;
the final archive came from a successful export outside that sandbox. Only
`closed-02` is the prepared archive.
