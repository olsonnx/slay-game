# Closed playtest build — 31 October 2026

- Branch: `codex/playtest-0.2.0p` (local; not pushed).
- Game version: `0.2.0P`; build label: `closed-07`.
- Source revision: `eaf10afbfbd3c1d8c909b76e879a44b6d621f8c2`.
- Archive: `builds/Slay-and-Reign-0.2.0P-closed-07-windows-x64.zip`.
- Size: 354,030,454 bytes.
- SHA-256: `A2A7EF10AE3073A576CC6178B0371EDBF5957DABA2E5E477A06AA14EDE1CABED`.

The branch snapshots the previously uncommitted game work, including authored
tutorials, artwork and their supporting resources. Temporary native-library
copies and tutorial recovery files stay ignored. The release was built with the
official Godot 4.6.3 Windows x64 template and includes native Steam dependencies,
START-HERE.txt, license notices and BUILD.txt. Nothing has been distributed.

The packager now captures source identity before its temporary template-preset
change, so BUILD.txt correctly records the branch and clean source state.
The earlier intermediate archive is retained under
`artifacts/playtest-closed-07-intermediate/`; distribute only the archive in builds.

## Checks already performed

Version consistency, localization catalogue and all 17 Python tests passed.
Release export completed successfully. The archive was extracted into a fresh
folder, and standalone headless and Direct3D 12 launches exited successfully.
The final extracted build visibly reached the kingdom-creation screen.

The Godot regression run stopped at `test_logistics_tutorial`: 60 checks passed
and four failed. The army harness assumes a single target, while the authored
expansion step now accepts multiple targets; that failure needs reconciliation.
The construction lesson builds a bridge at (1, 0), but its Shatter step targets
(-2, 2), which also needs correction or investigation. No tutorial fixes were
made during packaging. The complete regression run has not passed for this build.
Logs: `artifacts/playtest-closed-07-tests.log` and
`artifacts/playtest-closed-07-package-final.log`.

## Handoff

At the user's request, self-playtesting stopped. The isolated QA game was closed.
Tutorial completion, a full match, replay round-trip, another-PC launch and
two-account Steam play remain for testers. Use the existing organizer checklist
and Discord feedback instructions. Do not describe this build as fully validated.

Keep this branch stable for tester fixes, and use a separate development branch
for new features. Use a new build label whenever sharing an updated package.
