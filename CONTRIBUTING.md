# Contributing / 参与贡献

Thanks for helping. Hoardless is maintained in spare time, so replies may be slow.
谢谢参与。Hoardless 是业余维护的项目，回复可能比较慢。

## The most helpful thing: rules / 最有帮助的：应用规则

Every location Hoardless knows is one JSON file in [`rules/apps/`](rules/apps/). Adding or fixing an app usually
needs no Swift code. The format, the safety levels and the evidence needed are in [docs/RULES.md](docs/RULES.md).

Hoardless 认识的每个位置都是 [`rules/apps/`](rules/apps/) 里的一个 JSON 文件。新增或修正一个应用通常不用写 Swift 代码。
格式、安全等级和需要的证据见 [docs/RULES.md](docs/RULES.md)。

Before opening a pull request / 提交 PR 之前：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install jsonschema
.venv/bin/python scripts/validate_rules.py
```

- Mark a rule `verified` only with evidence: an official doc or source link, or a dated note of what you saw on your
  own Mac. / 只有拿得出证据时才标 `verified`：官方文档或源码链接，或你在自己 Mac 上看到的、带日期的记录。
- When unsure whether something can be lost, use `protected` (shown, never touched). / 拿不准会不会丢东西时，用 `protected`（只显示，不操作）。
- Add a row to the supported-apps table in [README.md](README.md) in the same change. / 在同一个改动里，把它加到 [README.md](README.md) 的应用表里。

Not sure how to write it? Open a **New app rule** issue with the app name and where it keeps its data; someone can
turn it into a rule.
不会写？开一个 **New app rule** 的 Issue，写上应用名称和它把数据放在哪里，会有人帮你写成规则。

## Code changes / 改代码

- Read the safety rules in [CLAUDE.md](CLAUDE.md) first. They are not negotiable: trash or move only, never a
  permanent delete; user folder only; protected means shown only; nothing pre-selected. A change that loosens any of
  them needs the maintainer's agreement before work starts.
  先读 [CLAUDE.md](CLAUDE.md) 里的安全规则，这些没有商量余地：只进废纸篓或挪走，绝不永久删除；只碰用户目录；protected 只显示；
  从不替用户勾选。会放宽其中任何一条的改动，要先征得维护者同意再动手。
- Run `swift test`, and the two rule scripts above if you touched rules or the validator
  (`scripts/test_validator.py` for the validator).
  运行 `swift test`；动了规则或校验器的话，再跑上面两个脚本（改校验器要跑 `scripts/test_validator.py`）。
- A new check or guard counts only once you have shown it failing on a bad sample. Test anything that moves or trashes
  files inside a temporary folder, never your real home folder.
  新加的检查要先证明它在坏样本上会报错，才算数。任何会挪动或删除文件的测试，都只在临时文件夹里做，不要用真实的个人文件夹。
- Keep the app's text in both English and Chinese (`Sources/Hoardless/Strings.swift`).
  App 里的文字要中英文都有（`Sources/Hoardless/Strings.swift`）。

## Out of scope / 不做的事

RAM "boosters", system-folder "junk", app uninstalling (for now), browser/privacy cleaning, startup-item managers,
anything needing admin rights.
内存"加速"、系统目录"垃圾"、卸载应用（暂不做）、浏览器隐私清理、启动项管理、需要管理员权限的功能。

## License / 许可证

Code you contribute is under [GPL-3.0](LICENSE). The mascot, icons and app icon are not GPL and should not be changed
in pull requests. / 你贡献的代码采用 [GPL-3.0](LICENSE)。吉祥物、图标和 App 图标不属于 GPL，请不要在 PR 里修改。
