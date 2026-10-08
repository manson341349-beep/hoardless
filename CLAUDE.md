# Hoardless — instructions for Claude Code and contributors

Hoardless is a free, open-source (GPL-3.0) macOS app that shows AI creators what is filling their disk
(model weights, package caches, video-editor caches) and helps them move or trash it safely.
The maintainer does not write code; Claude does most of the work. These rules exist so that a mistake
never costs a user their files.

## Safety rules (non-negotiable)

1. **Show first, act second.** Scanning is read-only. Nothing is selected by default; every action needs an explicit user confirmation that names the paths and the total size.
2. **Trash or move, never hard-delete.** Use `FileManager.trashItem` or a move to a folder the user picks (an external drive is fine, a system folder never). No `removeItem`, no `rm -rf`, no "secure erase", no emptying the Trash. Hoardless never runs an `official_cleanup` command itself; it shows it and says plainly that the command deletes permanently.
3. **User space only.** Rules may only point inside the user's home folder (`~/...`). No `/Library`, `/System`, `/private`, no privileged helper, no admin prompt.
4. **`protected` means show only.** A rule with `safety: "protected"` must never offer an action. Nothing is ever pre-selected, whatever its level. A rule with `command_only: true` is never trashed or moved by Hoardless; show its `official_cleanup` command instead. Showing an `official_cleanup` command (on any rule, including `protected`) is read-only text with a "deletes permanently" warning, not an action.
5. **Never follow symlinks out of a rule's root**, and never act on a path that is not exactly a rule path or inside one.
6. **No telemetry, no network calls** except the update check the user can turn off. No accounts, no ads, no upsell.
7. **Respect overrides, within rules 3 and 5.** `env_overrides` is ordered: the first variable that is set wins, and the location is its value plus `subpath`. Use it only if the resolved real path (symlinks resolved) is inside the home folder and passes the same checks as a rule path in `scripts/validate_rules.py`; otherwise show the location and size read-only. Say in the UI when an override is in effect. The rule's own `paths` are always scanned too when they exist, so a legacy or stale folder is never hidden. Rules 3 and 5 always win.

If a change would loosen any rule above, stop and ask the maintainer first.

## Rules are data, not code

- Every location the scanner knows about is one JSON file in `rules/apps/` (an app can have several), validated by `rules/schema.json` and `scripts/validate_rules.py`. See `docs/RULES.md`.
- Adding or fixing a rule should not need Swift code. The exception is a per-app resolver for apps that store a user-chosen location in their own settings (listed in `docs/RULES.md`, Known limits). Anything else that seems to need code means the schema is missing a field — discuss before adding one.
- The supported-apps table in `README.md` is kept by hand, one row per rule (app, title, level, "command only"); update it in the same change whenever a rule is added, removed or changes level.
- The validator is a gate for contributions, not a safety net: string checks cannot prove a folder is safe, so the app must still enforce the rules above at run time.
- A rule with `status: "verified"` needs evidence: an official doc/source URL or a dated local observation. Unconfirmed paths stay `unverified` and are hidden from normal users.
- Run `scripts/validate_rules.py` after any change under `rules/`, and `scripts/test_validator.py` after any change to the validator or schema (setup in `docs/RULES.md`). Every bypass found so far is a case in `test_validator.py`; add a case for each new check and show it failing before the fix.

## Out of scope (say no politely)

RAM "boosters", "system junk" in system folders, app uninstalling (for now), privacy/browser cleaning,
startup-item managers, anything needing admin rights. Keep the list in `README.md` in sync.

## Working discipline

- Report what you actually ran and its output. "Builds" is not "works"; "tests pass" is not "safe".
- Any check you add must be shown to fail on a bad sample before it counts.
- Test destructive paths only against a throwaway folder (e.g. a temp directory), never the real home folder.
- Target: macOS 14+, Apple Silicon and Intel. Native SwiftUI, no Electron.
