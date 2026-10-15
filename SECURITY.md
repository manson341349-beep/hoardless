# Safety and security reports / 安全问题报告

Hoardless moves and trashes files, so a bug can cost someone their work. Reports like these are the most important
ones we get.
Hoardless 会挪动和删除文件，一个 bug 就可能让别人丢掉作品。这类报告是我们最重视的。

## What to report privately / 哪些问题请私下报告

- Hoardless moved, trashed or offered to tick something that is not exactly the location it showed. / Hoardless 挪走、丢掉或允许勾选的东西，和它显示的位置不完全一致。
- Something marked **View only** (protected) could be acted on. / 标着"只看"的项目可以被操作。
- Anything was deleted permanently instead of going to the Trash or the folder you picked. / 有东西被永久删除，而不是进了废纸篓或你选的文件夹。
- A path outside your home folder, or inside Library, was touched; a symbolic link was followed out of a rule's folder. / 动到了个人文件夹以外或"资源库"里的路径；顺着链接跑出了规则的文件夹。
- **Undo** put back the wrong thing, or overwrote something. / "撤销"放回了错误的东西，或覆盖了别的文件。
- Hoardless contacted the network. / Hoardless 发起了网络连接。

## How / 怎么报告

Use GitHub's private report: on this repository open **Security → Report a vulnerability**. Only the maintainer sees it.
Please include the macOS version, the Hoardless version, what you clicked, what was listed in the confirmation, and
where the files ended up. Do not attach the files themselves.

用 GitHub 的私下报告：在本仓库打开 **Security → Report a vulnerability**，只有维护者能看到。
请写上 macOS 版本、Hoardless 版本、你点了什么、确认框里列出了什么，以及文件最后去了哪里。不要附上文件本身。

If you lost files: look in the Trash first (right-click → **Put Back**), and for moves, in the `Hoardless` folder
inside the folder you picked.
如果丢了文件：先看废纸篓（右键"放回原处"）；如果是挪走的，看你当时选的文件夹里的 `Hoardless` 文件夹。

## Supported versions / 支持的版本

Only the latest release gets fixes. / 只修复最新发布的版本。
