# Writing a rule / 编写规则

Hoardless only knows about the folders listed in `rules/apps/`. Each file describes one kind of data for one app
(an app can have several, e.g. its cache and its drafts). Files are plain JSON, checked by `rules/schema.json` and
`scripts/validate_rules.py`. Adding a rule usually needs no Swift code — only apps that let users move their data
also need a small resolver in code (see Known limits).

Hoardless 只认识 `rules/apps/` 里列出的文件夹。每个文件描述一个应用的一类数据（一个应用可以有好几个，比如缓存和草稿各一个）。
文件是普通 JSON，由 `rules/schema.json` 和 `scripts/validate_rules.py` 校验。新增规则通常不用写代码；只有允许用户改存放位置的应用，
才需要在代码里补一个小"解析器"（见"已知局限"）。

## Example / 示例

```json
{
  "id": "example-app-cache",
  "app": "Example App",
  "category": "package-cache",
  "title": { "en": "Example App download cache", "zh": "Example App 下载缓存" },
  "explain": {
    "en": "Downloaded installers. Example App downloads them again when needed.",
    "zh": "下载过的安装包。需要时 Example App 会重新下载。"
  },
  "paths": ["~/Library/Caches/example-app"],
  "env_overrides": [
    { "var": "EXAMPLE_CACHE_DIR" },
    { "var": "XDG_CACHE_HOME", "subpath": "example-app" }
  ],
  "safety": "review",
  "official_cleanup": { "command": "pip cache purge", "source": "https://pip.pypa.io/en/stable/topics/caching/" },
  "status": "verified",
  "evidence": [
    { "type": "official_doc", "url": "https://example.com/docs/cache", "checked": "2026-10-08" }
  ]
}
```

## Fields / 字段

| Field | Meaning | 说明 |
|---|---|---|
| `id` | kebab-case, same as the file name | 短横线命名，与文件名一致 |
| `app` | App name as users know it | 应用名称 |
| `category` | `ai-models`, `package-cache`, `video-editors`, `dev-tools` | 分类 |
| `title`, `explain` | Shown to users, English + Chinese. `explain` must say what is lost if removed | 给用户看的中英文；`explain` 必须写清删掉会失去什么 |
| `paths` | Exact folders or files, starting with `~/`. No `..`, `//` or wildcards | 精确路径，以 `~/` 开头，不能有 `..`、`//` 和通配符 |
| `env_overrides` | Variables that move the data, highest precedence first. `subpath` is added to the variable's value (e.g. `HF_HOME` + `hub`). The rule's own `paths` are still scanned when they exist | 能改变存放位置的环境变量，按优先级从高到低排；`subpath` 接在变量值后面。规则自己的 `paths` 只要存在也照样扫描 |
| `app_settings` | Settings files where the app records a folder the user chose: `file` (`~/…`), `format` (`ini` with key `Section.key`, `json` with a top-level key holding a path or a list, `sqlite` with `table.column`, or `pointer` for a file that is just a path), optional `subpath` | 应用记录"用户自选位置"的设置文件：`file`、`format`（ini 用 `段.键`，json 用顶层键，sqlite 用 `表.列`，pointer 表示整个文件就是一个路径）、可选 `subpath` |
| `safety` | see below | 见下 |
| `official_cleanup` | The app's own cleanup command: a known tool (conda, uv, pip, hf, ollama…) followed by plain words, flags or `<placeholders>`. A new tool is added to `KNOWN_TOOLS` in the validator during review | 应用自带的清理命令：以已知工具开头（conda、uv、pip、hf、ollama 等），后面只能是普通词、参数或 `<占位符>`；新工具在审核时加进校验脚本的 `KNOWN_TOOLS` |
| `command_only` | `true` = Hoardless never removes these files itself, it only shows `official_cleanup` | 设为 `true` 时 Hoardless 不自己动文件，只展示官方清理命令 |
| `status` | `verified` or `unverified` (hidden from normal users) | 未核实的规则默认不显示 |
| `evidence` | Where the path comes from, with the date you checked. Required; may be empty only while `unverified` | 路径出处和核对日期；必填，只有未核实时可以为空 |
| `notes` | Maintainer notes, not shown to users | 维护者备注，不给用户看 |

## Safety levels / 安全等级

Nothing is ever pre-selected, and every action needs the user's confirmation.
任何项目都不会被默认勾选，所有操作都要用户确认。

| Level | Meaning | Hoardless behaviour | 含义与行为 |
|---|---|---|---|
| `safe` | The app rebuilds it automatically; nothing large to fetch again | User can pick it and trash or move it | 应用会自动重建，不用重新下载大文件；用户可以选中后丢进废纸篓或挪走 |
| `review` | Nothing irreplaceable, but costs a re-download or rebuild | Same, with a clear warning about the cost | 不会丢无法找回的东西，但要重新下载或重建；同上，并明确提示代价 |
| `protected` | May contain user work, settings or hard-to-rebuild state | Size only; no action offered | 可能有你的作品、设置或难以重建的数据；只显示大小，不提供任何操作 |

If a rule has `official_cleanup`, Hoardless shows the command as read-only text with a warning that it deletes permanently. It never runs it.
规则带有 `official_cleanup` 时，Hoardless 只把命令当作文字展示，并提示它会永久删除；Hoardless 自己从不运行。

When unsure, pick the stricter level. / 不确定选哪个时，选更严格的那个。

## Where a rule may point / 规则能指向哪里

The validator only accepts paths in places where apps normally keep data, for example `~/Library/Caches/<app>`,
`~/Library/Application Support/<app>`, `~/Library/Containers/<app>`, `~/.cache/<app>`, `~/.<app>`, `~/Movies/<app>/...`.
It rejects whole standard folders, known credential, personal-data and synced locations (keychains, mail, browser profiles,
iCloud Drive, Dropbox, photo libraries…), anything in `~/.ollama`, `~/.cache/huggingface` or `~/.lmstudio` except their model
folders, and any two paths that overlap, in any spelling (macOS ignores letter case).

It cannot tell an app's folder from a folder of your own with the same shape (`~/Documents/<x>`, `~/<x>/<y>`), and its list
of personal-data locations can never be complete. Reviewers must check every new path, and the app re-checks at run time.

校验脚本只接受应用通常存数据的位置，例如上面这些。整个标准文件夹、已知的凭据/个人数据/同步文件夹（钥匙串、邮件、浏览器资料、
iCloud 云盘、Dropbox、照片图库等）、`~/.ollama` `~/.cache/huggingface` `~/.lmstudio` 里除模型文件夹以外的位置，以及任何两条互相重叠的路径（不分大小写）都会被拒绝。

但它分不清"应用的文件夹"和"形状一样的你自己的文件夹"（如 `~/Documents/<x>`），个人数据的名单也不可能列全。
所以每条新路径都要人工审核，App 运行时也会再检查一遍。

## Evidence / 证据

- `official_doc` / `official_source_code`: a link to the app's own docs or source code. / 应用官方文档或源码的链接。
- `local_observation`: you saw the folder on your Mac with that app installed. The `note` says what you saw, with the app version if known and the macOS version. / 你在装了该应用的 Mac 上亲眼看到这个文件夹；`note` 写清看到了什么，注明应用版本（如知道）和 macOS 版本。
- Third-party blog posts are not enough on their own. Rules without evidence stay `unverified`. / 只有第三方博客不够；没有证据的规则保持 `unverified`。

## Known limits / 已知局限

Locations the user moved are found through `app_settings` for Ollama, LM Studio, ComfyUI Desktop, 剪映, CapCut drafts
and pip. They are shown read-only: Hoardless only trashes or moves a rule's own default path. Still not followed:

用户改过的位置，Ollama、LM Studio、ComfyUI Desktop、剪映、CapCut 草稿和 pip 已经能通过 `app_settings` 找到，但只显示不操作
（Hoardless 只对规则自己的默认路径提供移动和删除）。仍然跟不到的：

- Draw Things (External Folder is stored inside its sandbox), Docker Desktop (disk image location is in a Group Container),
  ComfyUI manual git installs (`extra_model_paths.yaml` inside the repo), CapCut cache (its settings file has no cache key).
  Draw Things 的外部文件夹、Docker 的磁盘位置（都在沙盒里）、手动安装的 ComfyUI、CapCut 缓存（设置文件里没有这个键）。
- DaVinci Resolve has no fixed cache path at all (it follows each project's Working Folders setting), so it has no rule yet.
  DaVinci Resolve 的缓存位置跟着每个项目的设置走，没有固定路径，所以暂时没有规则。
- conda's main package cache usually sits outside the home folder (e.g. `/opt/anaconda3/pkgs`), which rules cannot point to.
  conda 的主包缓存通常在用户目录外（如 `/opt/anaconda3/pkgs`），规则目前不能指向那里。
- Shown sizes can be larger than the space actually freed: files hard-linked into environments (conda, uv) are counted
  twice, and Docker.raw's apparent size is larger than what it uses on disk.
  显示的大小可能比实际能腾出的空间大：conda、uv 的文件和环境共用，Docker.raw 显示的大小也比实际占用大。

## Wanted rules / 待收录

Candidates found during research, **not yet verified** — good first contributions:
调研中发现、**尚未核实**的候选，适合作为第一次贡献：

Adobe Premiere Pro media cache (`~/Library/Application Support/Adobe/Common/Media Cache Files` and `Media Cache`;
the location can be changed in Premiere's preferences, and Adobe's help pages could not be read to confirm it),
npx installs (`~/.npm/_npx`), pnpm metadata cache (`~/Library/Caches/pnpm`), Gradle (`~/.gradle/caches`),
Cargo registry (`~/.cargo/registry`), mamba/micromamba package cache.

Already covered elsewhere: llama.cpp's `-hf` downloads go to the Hugging Face cache (`~/.cache/huggingface/hub`,
see `common/hf-cache.cpp`), so the `huggingface-hub` rule shows them.
llama.cpp 用 `-hf` 下载的模型存在 Hugging Face 缓存里，已由 `huggingface-hub` 规则显示。

## Check your rule / 本地校验

```bash
python3 -m venv .venv
.venv/bin/python -m pip install jsonschema
.venv/bin/python scripts/validate_rules.py
```

If you change the validator or the schema, also run the regression test (every known bypass is a case there):
改了校验脚本或 schema，还要跑回归测试（已知的每种绕过手法都在里面）：

```bash
.venv/bin/python scripts/test_validator.py
```
