#!/usr/bin/env python3
"""Validate every rule in rules/apps/ against rules/schema.json plus safety checks the schema cannot express.

Usage: python3 scripts/validate_rules.py [rules_dir]
Needs: jsonschema (see docs/RULES.md: python3 -m venv .venv && .venv/bin/python -m pip install jsonschema)
Exit code 0 = all rules valid, 1 = at least one problem, 2 = nothing to check.

This is a gate for contributed rules, not the app's safety net: string checks cannot prove a folder is safe.
The app itself must still enforce the safety rules in CLAUDE.md at run time.
"""
import datetime
import json
import re
import sys
import unicodedata
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "rules" / "schema.json"


# Paths are compared the way macOS home volumes see them: case-insensitive, Unicode-folded, repeated "/" collapsed.
def norm(path):
    parts = unicodedata.normalize("NFD", path).casefold().split("/")
    assert parts[0] == "~"
    return tuple(p for p in parts[1:] if p)


def paths(*items):
    return [norm(p) for p in items]


# A rule path must sit strictly inside one of these parents, so the next segment names one app or one cache.
APP_PARENTS = paths(
    "~/Library/Caches", "~/Library/Application Support", "~/Library/Containers", "~/Library/Group Containers",
    "~/Library/Logs", "~/Library/Developer/Xcode", "~/Library/Developer/CoreSimulator", "~/Library/pnpm",
    "~/Library/Android", "~/.cache", "~/.config", "~/.local/share", "~/.local/state",
    # Some apps keep data in the user's own folders (e.g. ~/Movies/CapCut). The validator cannot tell such an
    # app folder from a folder of your own with the same shape, so rules here need extra care in review.
    "~/Documents", "~/Movies", "~/Music", "~/Pictures",
)
# Top-level folders that are never an app's own folder (anything below them not covered by APP_PARENTS is rejected).
STANDARD_TOP = {norm(p)[0] for p in (
    "~/Desktop", "~/Documents", "~/Downloads", "~/Movies", "~/Music", "~/Pictures", "~/Public", "~/Library",
    "~/Applications", "~/Sites", "~/.local", "~/.Trash",
)}
# Personal data, credentials and synced folders: a rule may not point at these, inside them, or above them.
# This list cannot be complete; it backs up, not replaces, review and the app's run-time checks.
DENY_INSIDE = paths(
    # credentials and shell state
    "~/.ssh", "~/.gnupg", "~/.aws", "~/.azure", "~/.kube", "~/.netrc", "~/.git-credentials", "~/.gitconfig",
    "~/.npmrc", "~/.pypirc", "~/.yarnrc", "~/.kaggle", "~/.huggingface", "~/.docker/config.json",
    "~/.config/gh", "~/.config/gcloud", "~/.config/rclone", "~/.zshrc", "~/.bashrc", "~/.profile",
    "~/.zsh_history", "~/.bash_history", "~/.claude", "~/.claude.json", "~/.codex",
    # Apple personal data
    "~/.Trash", "~/Library/Keychains", "~/Library/Mail", "~/Library/Messages", "~/Library/Safari",
    "~/Library/Cookies", "~/Library/Calendars", "~/Library/Mobile Documents", "~/Library/CloudStorage",
    "~/Library/Application Support/MobileSync", "~/Library/Application Support/AddressBook",
    "~/Library/Containers/com.apple.Safari", "~/Library/Containers/com.apple.mail",
    "~/Library/Containers/com.apple.Notes", "~/Library/Group Containers/group.com.apple.notes",
    "~/Library/Group Containers/group.com.apple.calendar", "~/Library/Developer/Xcode/Archives",
    "~/Library/Developer/Xcode/UserData", "~/Music/Music", "~/Movies/TV", "~/Pictures/Photo Booth Library",
    # browser profiles and password managers
    "~/Library/Application Support/Google/Chrome", "~/Library/Application Support/Firefox",
    "~/Library/Application Support/BraveSoftware", "~/Library/Application Support/Microsoft Edge",
    "~/Library/Application Support/Arc", "~/Library/Application Support/1Password",
    "~/Library/Group Containers/2BUA8C4S2C.com.1password",
    # synced folders outside ~/Library/CloudStorage
    "~/Dropbox", "~/Google Drive", "~/OneDrive", "~/Box", "~/iCloud Drive (Archive)", "~/Creative Cloud Files",
)
DENY_SUFFIXES = (".photoslibrary", ".fcpbundle", ".imovielibrary", ".logicx")
DENY_TOP_PREFIXES = ("onedrive",)  # "OneDrive - <Org>"
# Sandbox containers link these names to the user's real folders.
CONTAINER_USER_LINKS = {"desktop", "downloads", "movies", "music", "pictures"}
# Folders that also hold credentials or chats: only these subfolders may be targeted.
ONLY_INSIDE = {norm("~/.ollama"): {"models"}, norm("~/.cache/huggingface"): {"hub", "xet"},
               norm("~/.lmstudio"): {"models"}}

GENERAL_ENV = {"HOME", "TMPDIR", "USER", "PATH", "PWD", "SHELL", "LOGNAME"}
SECRET_ENV = re.compile(r"TOKEN|KEY|SECRET|PASSWORD|CREDENTIAL")
# Variables whose default value is a known parent folder: they need a subpath, and the default must pass placement.
ENV_DEFAULTS = {"XDG_CACHE_HOME": "~/.cache", "XDG_CONFIG_HOME": "~/.config", "XDG_DATA_HOME": "~/.local/share",
                "XDG_STATE_HOME": "~/.local/state", "HF_HOME": "~/.cache/huggingface", "TORCH_HOME": "~/.cache/torch"}

# official_cleanup.command: one known tool, then plain words, flags or <placeholders>, single spaces only.
KNOWN_TOOLS = {"brew", "conda", "docker", "hf", "mamba", "micromamba", "npm", "ollama", "pip", "pip3", "pnpm",
               "uv", "xcrun", "yarn"}
COMMAND_TOKEN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._=-]*|--?[A-Za-z0-9][A-Za-z0-9-]*|<[a-z][a-z-]*>")


def inside(a, b):
    """True if path a equals b or sits inside it."""
    return a[:len(b)] == b


def path_problems(raw):
    if any(0xD800 <= ord(ch) <= 0xDFFF for ch in raw):
        return ["contains an invalid character"]
    c = norm(raw)
    if not c:
        return ["points at the whole home folder"]
    out = []
    parent = max((p for p in APP_PARENTS if inside(c, p)), key=len, default=None)
    if parent is not None:
        if len(c) == len(parent):
            out.append("is a whole standard folder; point at the app's own folder inside it")
    elif c[0] in STANDARD_TOP:
        out.append("is not inside an app's own folder")
    elif not c[0].startswith(".") and len(c) < 2:
        out.append("is a whole top-level folder; point at the data folder inside it")
    if any(inside(c, d) or inside(d, c) for d in DENY_INSIDE) or c[0].startswith(DENY_TOP_PREFIXES) \
            or any(s.endswith(DENY_SUFFIXES) for s in c):
        out.append("is or contains personal data, credentials or synced files")
    for root, allowed in ONLY_INSIDE.items():
        if inside(root, c) or (inside(c, root) and c[len(root)] not in allowed):
            out.append("is in a folder that also holds credentials or chats; only its model/cache folders are allowed")
    if len(c) >= 5 and c[:2] in paths("~/Library/Containers", "~/Library/Group Containers") \
            and c[3] == "data" and c[4] in CONTAINER_USER_LINKS:
        out.append("goes through a sandbox link to your own folders")
    return out


def command_problems(cmd):
    tokens = cmd.split(" ")
    if not all(COMMAND_TOKEN.fullmatch(t) for t in tokens):
        return ["must be plain words, flags or <placeholders> separated by single spaces (no quotes, paths, pipes)"]
    if tokens[0] not in KNOWN_TOOLS:
        return [f"must start with a known tool ({', '.join(sorted(KNOWN_TOOLS))})"]
    return []


def no_duplicate_keys(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError(f"duplicate key '{key}'")
        obj[key] = value
    return obj


def as_list(value):
    return value if isinstance(value, list) else []


def main() -> int:
    rules_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "rules" / "apps"
    if not rules_dir.is_dir():
        print(f"Not a directory: {rules_dir}", file=sys.stderr)
        return 2
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)

    problems = []
    for e in sorted(rules_dir.iterdir()):
        if e.name == ".DS_Store":
            continue
        if e.is_symlink() or not e.is_file() or e.suffix != ".json":
            problems.append(f"{e.name}: not a plain lowercase .json rule file; the validator does not check it")
    files = sorted(f for f in rules_dir.glob("*.json") if f.is_file() and not f.is_symlink())
    if not files and not problems:
        print(f"No rule files found in {rules_dir}", file=sys.stderr)
        return 2

    # Latest calendar date anywhere on Earth, so a rule checked "today" in any time zone is never "in the future".
    latest_today = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=14)).date()
    seen_ids = {}
    claimed = []      # (normalized path, label, file name)
    env_claimed = []  # (var + normalized subpath, label, file name)
    for f in files:
        try:
            rule = json.loads(f.read_text(encoding="utf-8"), object_pairs_hook=no_duplicate_keys)
        except (ValueError, RecursionError, OSError) as e:  # JSONDecodeError and UnicodeDecodeError are ValueErrors
            problems.append(f"{f.name}: invalid JSON ({e})")
            continue

        for err in sorted(validator.iter_errors(rule), key=lambda e: [str(p) for p in e.path]):
            where = "/".join(str(p) for p in err.path) or "(root)"
            problems.append(f"{f.name}: {where}: {err.message}")
        if not isinstance(rule, dict):
            continue

        rid = rule.get("id")
        if isinstance(rid, str):
            if rid != f.stem:
                problems.append(f"{f.name}: id '{rid}' must equal the file name '{f.stem}'")
            if rid in seen_ids:
                problems.append(f"{f.name}: duplicate id '{rid}' (also in {seen_ids[rid]})")
            seen_ids[rid] = f.name

        for p in as_list(rule.get("paths")):
            if not isinstance(p, str) or not p.startswith("~/"):
                continue  # already reported by the schema
            for msg in path_problems(p):
                problems.append(f"{f.name}: path '{p}' {msg}")
            claimed.append((norm(p), f"'{p}'", f.name))

        for ov in as_list(rule.get("env_overrides")):
            var = ov.get("var") if isinstance(ov, dict) else None
            if not isinstance(var, str):
                continue
            sub = ov.get("subpath") if isinstance(ov.get("subpath"), str) else ""
            if var in GENERAL_ENV:
                problems.append(f"{f.name}: env override '{var}' is a general-purpose variable")
            if SECRET_ENV.search(var):
                problems.append(f"{f.name}: env override '{var}' looks like a secret, not a location")
            if var in ENV_DEFAULTS:
                if not sub:
                    problems.append(f"{f.name}: env override '{var}' names a parent folder; add a subpath")
                else:
                    for msg in path_problems(f"{ENV_DEFAULTS[var]}/{sub}"):
                        problems.append(f"{f.name}: env override '{var}' + '{sub}' (default {ENV_DEFAULTS[var]}/{sub}) {msg}")
            key = (var,) + (norm("~/" + sub) if sub else ())
            env_claimed.append((key, f"'{var}' + '{sub}'", f.name))

        for setting in as_list(rule.get("app_settings")):
            f_ = setting.get("file") if isinstance(setting, dict) else None
            if not isinstance(f_, str) or not f_.startswith("~/"):
                continue  # already reported by the schema
            c = norm(f_)
            if any(inside(c, d) for d in DENY_INSIDE) or any(s.endswith(DENY_SUFFIXES) for s in c):
                problems.append(f"{f.name}: app_settings file '{f_}' is personal data or credentials")

        cleanup = rule.get("official_cleanup")
        if isinstance(cleanup, dict) and isinstance(cleanup.get("command"), str) and cleanup["command"]:
            for msg in command_problems(cleanup["command"]):
                problems.append(f"{f.name}: official_cleanup command {msg}")

        for ev in as_list(rule.get("evidence")):
            checked = ev.get("checked") if isinstance(ev, dict) else None
            if not isinstance(checked, str):
                continue
            try:
                day = datetime.date.fromisoformat(checked)
            except ValueError:
                problems.append(f"{f.name}: evidence date '{checked}' is not a real date")
                continue
            if day > latest_today:
                problems.append(f"{f.name}: evidence date '{checked}' is in the future")

    # No folder may be covered twice, by paths or by env overrides, in any spelling or nesting.
    for group in (claimed, env_claimed):
        for i, (a, label_a, fa) in enumerate(group):
            for b, label_b, fb in group[i + 1:]:
                if inside(a, b) or inside(b, a):
                    problems.append(f"{fb}: {label_b} overlaps {label_a} in {fa}")

    for line in problems:
        print(line.encode("utf-8", "backslashreplace").decode("utf-8"))
    print(f"Checked {len(files)} rule file(s): {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
