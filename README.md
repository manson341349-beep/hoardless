# Hoardless

**See what your AI tools are hoarding on your Mac — then move it or trash it, safely.**
**看清 AI 工具在你的 Mac 上囤了什么，再安全地挪走或丢进废纸篓。**

Free and open source (GPL-3.0). No account, no ads, no telemetry.
免费开源（GPL-3.0）。不用注册，没有广告，不收集任何数据。

> **Status: early planning.** There is no app to download yet. This repository currently holds the safety rules and the
> app-rule database that the app will be built on.
>
> **当前状态：早期规划。** 还没有可下载的 App。仓库里目前是安全规则和应用规则库，App 会基于它们开发。

---

## Why / 为什么做

Local AI work fills a disk fast: model weights from Ollama, Hugging Face and LM Studio, Python package caches,
video-editor render caches. General Mac cleaners either skip these on purpose or treat them like junk.
Hoardless shows them clearly, explains what each one is, and lets you decide.

本地跑 AI 很快会把硬盘塞满：Ollama、Hugging Face、LM Studio 的模型，Python 包缓存，剪辑软件的渲染缓存。
通用清理工具要么故意跳过这些，要么当成垃圾一删了之。Hoardless 把它们列清楚、说明白，由你决定怎么处理。

## What it will do / 计划功能

- **Show** disk usage, with AI models, package caches and video caches recognised by name.
  **看清**磁盘占用，自动认出 AI 模型、包缓存、剪辑缓存。
- **Find duplicates** among large files across your home folder. A copy can be moved or trashed only if it sits in a folder Hoardless knows is safe to touch; anywhere else it is shown with its size only.
  **找重复**的大文件（整个用户目录范围内）。只有位于 Hoardless 确认可以动的文件夹里的副本才能挪走或丢进废纸篓，其他位置的只显示大小。
- **Move or trash** what you pick — to an external drive, an archive folder, or the Trash.
  **挪走或丢进废纸篓**：移到外置硬盘、归档文件夹，或废纸篓。

## Safety promises / 安全承诺

- Scanning only reads. Nothing is ever selected for you; every action asks first. / 扫描只读，从不替你勾选，每次操作都先问你。
- Hoardless itself never deletes permanently: files go to the Trash or a folder you choose (an external drive is fine). / Hoardless 自己从不永久删除：文件只进废纸篓，或挪到你指定的文件夹（外置硬盘也可以）。
- For a few apps, Hoardless only shows the app's own cleanup command instead of touching files. Those commands do delete permanently, so read what each one does before running it. / 少数应用 Hoardless 只给出它自带的清理命令，不直接动文件。这些命令会永久删除，运行前请先看清楚它做什么。
- Only looks at and cleans your home folder. No system folders, no admin password. / 只查看和清理你的用户目录，不碰系统目录，不要管理员密码。
- Anything that may hold your work is shown, never touched. / 可能有你作品的位置只显示大小，不做任何操作。

## Won't do / 不做的事

RAM "boosters", system-folder "junk", app uninstalling (for now), browser/privacy cleaning, startup-item managers, anything needing admin rights.
内存"加速"、系统目录"垃圾"清理、卸载应用（暂不做）、浏览器隐私清理、启动项管理、需要管理员权限的功能。

## Supported apps / 已收录的应用

| App / 应用 | What / 内容 | Level / 等级 |
|---|---|---|
| ComfyUI Desktop | ComfyUI model folders / ComfyUI 模型文件夹 | protected · 只看 |
| DiffusionBee | DiffusionBee data / DiffusionBee 数据 | protected · 只看 |
| Draw Things | Draw Things models / Draw Things 模型 | protected · 只看 |
| Hugging Face | Hugging Face model cache / Hugging Face 模型缓存 | review · 要重新下载 · command only / 只给命令 |
| Hugging Face | Hugging Face transfer working files / Hugging Face 传输工具的工作文件 | review · 要重新下载 |
| LM Studio | LM Studio models / LM Studio 模型 | protected · 只看 |
| Ollama | Ollama models / Ollama 本地模型 | protected · 只看 |
| PyTorch | PyTorch Hub cache / PyTorch Hub 缓存 | review · 要重新下载 |
| conda | conda package cache / conda 包缓存 | review · 要重新下载 · command only / 只给命令 |
| pip | pip cache / pip 缓存 | review · 要重新下载 |
| uv | uv cache / uv 缓存 | review · 要重新下载 · command only / 只给命令 |
| CapCut | CapCut downloaded effects and music / CapCut 下载的特效和音乐 | protected · 只看 |
| CapCut | CapCut thumbnails, waveforms and speech recognition / CapCut 缩略图、波形和语音识别缓存 | review · 要重新下载 |
| CapCut | CapCut drafts / CapCut 草稿 | protected · 只看 |
| 剪映专业版 (JianyingPro) | JianyingPro downloaded effects and music / 剪映专业版下载的特效和音乐 | protected · 只看 |
| 剪映专业版 (JianyingPro) | JianyingPro thumbnails, waveforms and speech recognition / 剪映专业版缩略图、波形和语音识别缓存 | review · 要重新下载 |
| 剪映专业版 (JianyingPro) | JianyingPro drafts / 剪映专业版草稿 | protected · 只看 |
| Docker Desktop | Docker Desktop disk / Docker Desktop 虚拟磁盘 | protected · 只看 |

Nothing is ever pre-selected. / 任何项目都不会默认勾选。

- **safe**: the app rebuilds it automatically. / 应用会自动重建。
- **review**: nothing of yours is lost, but it must be downloaded or rebuilt again. / 不会丢你的东西，但要重新下载或重建。
- **protected**: may hold your work; size only, no action. / 可能有你的作品，只显示大小，不做任何操作。
- **command only**: Hoardless shows the app's own cleanup command instead of touching files. / 只给出应用自带的清理命令，不直接动文件。

Rules live in [`rules/apps/`](rules/apps/). Missing an app? See [docs/RULES.md](docs/RULES.md) — one JSON file, no code.
规则在 [`rules/apps/`](rules/apps/)。缺了你用的应用？看 [docs/RULES.md](docs/RULES.md)，加一个 JSON 文件就行，不用写代码。

## Maintenance / 维护说明

Hoardless is maintained in spare time. Issues and pull requests are welcome, but replies are not guaranteed to be fast.
Rule fixes and new rules are the most helpful contributions.

这是业余维护的项目。欢迎提 Issue 和 PR，但回复不保证及时。最有帮助的贡献是修正或新增应用规则。

## License / 许可证

Source code: [GPL-3.0](LICENSE). The mascot and icons in `Sources/Hoardless/Resources/Art` are not GPL; all rights
reserved, see [their license](Sources/Hoardless/Resources/Art/LICENSE.md).

源代码：[GPL-3.0](LICENSE)。`Sources/Hoardless/Resources/Art` 里的吉祥物和图标不属于 GPL，版权保留，见[素材版权说明](Sources/Hoardless/Resources/Art/LICENSE.md)。

## About / 关于作者

The author also runs XinYu AI ([xinyuai.app](https://xinyuai.app)). Hoardless is free and open source and does not depend
on any XinYu service. No sign-up or purchase needed.

作者同时运营 XinYu AI（[xinyuai.app](https://xinyuai.app)）。Hoardless 免费开源，不依赖心宇的任何服务，无需注册或购买。
