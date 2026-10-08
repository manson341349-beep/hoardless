#!/usr/bin/env python3
"""Regression test for validate_rules.py: every known bypass must fail for its own reason, good rules must pass.

Usage: python3 scripts/test_validator.py
Builds each case in a temporary folder, runs the validator on it, and checks the exit code and the reason.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = ROOT / "scripts" / "validate_rules.py"

BASE = {"app": "Test", "category": "package-cache", "title": {"en": "t", "zh": "t"},
        "explain": {"en": "e", "zh": "e"}, "safety": "review", "status": "verified",
        "evidence": [{"type": "official_doc", "url": "https://example.com/doc", "checked": "2026-10-08"}]}


def rule(rid="a", **fields):
    return {"id": rid, **BASE, **fields}


def p(*paths, **fields):
    return [rule(paths=list(paths), **fields)]


def cmd(command, **fields):
    return [rule(paths=["~/.foo/cache"], official_cleanup={"command": command, "source": "https://example.com/doc"}, **fields)]


def env(*overrides):
    return [rule(paths=["~/.foo/cache"], env_overrides=list(overrides))]


# (name, rule files or raw text, expected exit code, text the output must contain)
CASES = [
    # placement
    ("absolute path", p("/Library/Caches/x"), 1, "does not match"),
    ("dot-dot", p("~/Library/../Movies"), 1, "should not be valid"),
    ("wildcard", p("~/.cache/*"), 1, "should not be valid"),
    ("double slash", p("~//Movies"), 1, "should not be valid"),
    ("home itself", p("~"), 1, "does not match"),
    ("case-folded standard folder", p("~/movies"), 1, "whole standard folder"),
    ("unicode long s", p("~/Movieſ"), 1, "whole standard folder"),
    ("kelvin sign", p("~/DesKtop"), 1, "not inside an app"),
    ("inside Desktop", p("~/Desktop/stuff"), 1, "not inside an app"),
    ("preferences", p("~/Library/Preferences/com.foo.plist"), 1, "not inside an app"),
    ("icloud drive", p("~/Library/Mobile Documents/com~apple~CloudDocs"), 1, "not inside an app"),
    ("whole top-level folder", p("~/ComfyUI-Shared"), 1, "whole top-level folder"),
    ("container link", p("~/Library/Containers/com.x/Data/Downloads"), 1, "sandbox link"),
    # personal data and credentials
    ("ssh keys", p("~/.ssh/id_ed25519"), 1, "personal data"),
    ("hugging face token", p("~/.cache/huggingface/token"), 1, "also holds credentials"),
    ("ollama key", p("~/.ollama/id_ed25519"), 1, "also holds credentials"),
    ("ollama root", p("~/.ollama"), 1, "also holds credentials"),
    ("ancestor of a browser profile", p("~/Library/Application Support/Google"), 1, "personal data"),
    ("dropbox", p("~/Dropbox/Work"), 1, "personal data"),
    ("onedrive org folder", p("~/OneDrive - Acme/Work"), 1, "personal data"),
    ("photos library", p("~/Pictures/Photos Library.photoslibrary"), 1, "personal data"),
    ("xcode archives", p("~/Library/Developer/Xcode/Archives"), 1, "personal data"),
    # overlap
    ("nested across rules", [rule("a", paths=["~/Movies/CapCut"]), rule("b", paths=["~/Movies/CapCut/User Data"])], 1, "overlaps"),
    ("same folder, other case", [rule("a", paths=["~/.foo/cache"]), rule("b", paths=["~/.FOO/Cache/"])], 1, "overlaps"),
    ("nested in one rule", p("~/.foo", "~/.foo/cache"), 1, "overlaps"),
    ("env overrides collide", [rule("a", paths=["~/.foo/a"], env_overrides=[{"var": "FOO_DIR"}]),
                               rule("b", paths=["~/.foo/b"], env_overrides=[{"var": "FOO_DIR"}])], 1, "overlaps"),
    # env overrides
    ("HOME override", env({"var": "HOME"}), 1, "general-purpose"),
    ("secret-looking variable", env({"var": "HF_TOKEN"}), 1, "looks like a secret"),
    ("parent variable without subpath", env({"var": "XDG_CACHE_HOME"}), 1, "add a subpath"),
    ("parent variable into credentials", env({"var": "XDG_CACHE_HOME", "subpath": "huggingface"}), 1, "also holds credentials"),
    ("subpath escapes", env({"var": "FOO_HOME", "subpath": "../.."}), 1, "should not be valid"),
    # cleanup commands
    ("rm -R", cmd("rm -R Documents"), 1, "known tool"),
    ("sh -c", cmd("sh -c 'rm -rf Documents'"), 1, "plain words"),
    ("redirect", cmd("conda clean --all > .zshrc"), 1, "plain words"),
    ("trailing newline", cmd("uv cache clean\n"), 1, "plain words"),
    ("path in flag", cmd("hf cache rm --cache-dir=/Users"), 1, "plain words"),
    ("quoted sudo", cmd("'sudo' conda clean --all"), 1, "plain words"),
    ("command_only without command", [rule(paths=["~/.foo/cache"], command_only=True)], 1, "official_cleanup"),
    # evidence and text
    ("verified without evidence", p("~/.foo/cache", evidence=[]), 1, "should be non-empty"),
    ("bare https", p("~/.foo/cache", evidence=[{"type": "official_doc", "url": "https://", "checked": "2026-10-08"}]), 1, "does not match"),
    ("impossible date", p("~/.foo/cache", evidence=[{"type": "official_doc", "url": "https://example.com/d", "checked": "2026-02-30"}]), 1, "not a real date"),
    ("future date", p("~/.foo/cache", evidence=[{"type": "official_doc", "url": "https://example.com/d", "checked": "2099-01-01"}]), 1, "in the future"),
    ("whitespace title", p("~/.foo/cache", title={"en": " ", "zh": " "}), 1, "does not match"),
    # file handling
    ("duplicate key", '{"id": "a", "paths": ["~/Movies"], "paths": ["~/.foo/cache"]}', 1, "duplicate key"),
    ("not an object", "[]", 1, "is not of type 'object'"),
    ("wrong-typed id", [rule(paths=["~/.foo/cache"]) | {"id": ["a"]}], 1, "is not of type 'string'"),
    # app settings files
    ("settings file in credentials", [rule(paths=["~/.foo/cache"], app_settings=[{"file": "~/.ssh/config", "format": "ini", "key": "Host.path"}])], 1, "personal data"),
    ("pointer with a key", [rule(paths=["~/.foo/cache"], app_settings=[{"file": "~/.foo/home", "format": "pointer", "key": "x"}])], 1, "should not be valid"),
    ("ini without a key", [rule(paths=["~/.foo/cache"], app_settings=[{"file": "~/.foo/conf", "format": "ini"}])], 1, "'key' is a required property"),
    ("sqlite key injection", [rule(paths=["~/.foo/cache"], app_settings=[{"file": "~/.foo/db.sqlite", "format": "sqlite", "key": "settings;drop"}])], 1, "does not match"),
    ("settings file escapes", [rule(paths=["~/.foo/cache"], app_settings=[{"file": "~/../etc/passwd", "format": "pointer"}])], 1, "should not be valid"),
    # must pass
    ("lm studio settings", [rule(paths=["~/.lmstudio/models"], app_settings=[{"file": "~/.lmstudio/settings.json", "format": "json", "key": "downloadsFolder"}])], 0, "0 problem(s)"),
    ("whisper cache", [rule(paths=["~/.cache/whisper"], env_overrides=[{"var": "XDG_CACHE_HOME", "subpath": "whisper"}])], 0, "0 problem(s)"),
    ("xcode derived data", p("~/Library/Developer/Xcode/DerivedData"), 0, "0 problem(s)"),
    ("sibling names", [rule("a", paths=["~/.cache/uv"]), rule("b", paths=["~/.cache/uvx"])], 0, "0 problem(s)"),
    ("container documents", p("~/Library/Containers/com.x/Data/Documents/Models"), 0, "0 problem(s)"),
    ("tool command", cmd("ollama rm <model>"), 0, "0 problem(s)"),
]


def run(folder):
    r = subprocess.run([sys.executable, str(VALIDATOR), str(folder)], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def main() -> int:
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, (name, content, want_rc, want_text) in enumerate(CASES):
            folder = Path(tmp) / f"case{i}"
            folder.mkdir()
            if isinstance(content, str):
                (folder / "a.json").write_text(content, encoding="utf-8")
            else:
                for r in content:
                    rid = r["id"] if isinstance(r["id"], str) else "a"
                    (folder / f"{rid}.json").write_text(json.dumps(r, ensure_ascii=False), encoding="utf-8")
            rc, out = run(folder)
            if rc != want_rc or want_text not in out or "Traceback" in out:
                failures.append(f"{name}: expected rc={want_rc} with '{want_text}', got rc={rc}: {out.strip()[:200]}")

        extra = Path(tmp) / "extras"
        (extra / "sub").mkdir(parents=True)
        (extra / "A.JSON").write_text("{}")
        rc, out = run(extra)
        if rc != 1 or "not a plain lowercase" not in out:
            failures.append(f"stray files: got rc={rc}: {out.strip()[:200]}")
        rc, out = run(Path(tmp) / "missing")
        if rc != 2 or "Traceback" in out:
            failures.append(f"missing folder: got rc={rc}: {out.strip()[:200]}")

    rc, out = run(ROOT / "rules" / "apps")
    if rc != 0:
        failures.append(f"real rules: got rc={rc}: {out.strip()[:300]}")

    total = len(CASES) + 3
    for line in failures:
        print("FAIL", line)
    print(f"{total - len(failures)}/{total} checks passed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
