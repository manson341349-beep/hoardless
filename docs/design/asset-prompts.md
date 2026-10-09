# Asset prompts / 素材提示词

Model: `gpt-image-2-5-flare` on XinYuAi, 1K, quality `high`, 1:1, transparent background.
Make the mascot first. Use the chosen mascot image as a reference image for every icon, so lighting and material match.

模型：XinYuAi 上的 `gpt-image-2-5-flare`，1K，`high`，1:1，透明背景。
先出吉祥物，选定后把它作为参考图喂给每个图标，让光线和材质保持一致。

## Check transparency / 检查透明通道

The model sometimes paints a fake checkerboard instead of real transparency (2026-10-08: 7 of 14 images, every
amber video icon). Check each PNG has an alpha channel before using it. If an icon keeps failing, render it on a flat
`#0a0a0a` background instead and cut it out with XinYuAi's background removal (Heavy model); the app background is
the same ink color, so no fringe shows.

这个模型有时会把灰白格子"画"进图里，而不是真透明（2026-10-08 实测 14 张里 7 张，橙色剪辑图标每次都中）。
用之前先确认 PNG 有透明通道。某个图标反复失败时，改成在纯色 `#0a0a0a` 底上渲染，再用 XinYuAi 去背景（Heavy 模型）抠出；
App 背景本来就是这个墨黑色，边缘看不出来。

## Chosen assets (2026-10-08) / 已选定素材

XinYuAi canvas "Hoardless 素材". All have a real alpha channel (checked).

| Asset | URL | Note |
|---|---|---|
| Mascot idle / 待机 | https://cdn.xinyuai.app/image/original/1e06c502-0743-41cb-8b8a-fa51140e4097-original.png | style reference for everything else |
| Mascot searching / 翻找中 | https://cdn.xinyuai.app/image/original/619e7fd6-841b-4531-aa11-fd6be7c2dc83-original.png | ink background + Heavy cutout; thin dark fur fringe, fine on ink |
| Mascot done / 完成 | https://cdn.xinyuai.app/image/original/2cba28bc-385b-4b5c-96bc-04aa3d7c505f-original.png | |
| Video editors / 剪辑软件 | https://cdn.xinyuai.app/image/original/5c005b2a-1ee2-4793-9ad4-b4fb061b0028-original.png | ink background + Heavy cutout |
| AI models / AI 模型 | https://cdn.xinyuai.app/image/original/e3ce0cb3-4e1a-401c-a512-03c033561d0d-original.png | cube version |
| Package caches / 软件包缓存 | https://cdn.xinyuai.app/image/original/ad15f052-56e1-440b-a391-baedb4a5ceb1-original.png | |
| Developer tools / 开发工具 | https://cdn.xinyuai.app/image/original/314c4c16-b020-41ef-bb15-a3717cb00f74-original.png | |
| Duplicates / 重复文件 | https://cdn.xinyuai.app/image/original/6c18d97e-9950-4f8e-98b7-a7455c17a9bf-original.png | 2026-10-09; ink background + Heavy cutout, cropped to 512 |

## Shared style / 统一风格

Append this block to every prompt below. / 每条提示词后面都接上这一段：

```
Style: premium macOS app icon object, 3D render. Glossy translucent glass mixed with soft frosted resin,
chunky rounded shapes, subtle inner glow, soft studio key light from the upper left, thin bright rim light,
gentle reflections. Three-quarter front view, centered, generous empty margin around the object.
Fully transparent background, no ground shadow, no text, no letters, no logo. Simple silhouette that
still reads at 64 px. Accent color lime green #a3d233 appears as a small glow or highlight.
```

## Mascot / 吉祥物

```
A cute chubby squirrel mascot, designer vinyl toy style, warm caramel fur with a cream belly and a big
fluffy curled tail, large friendly glossy eyes, small smile. It hugs an oversized glowing glass acorn
in lime green #a3d233 that lights its face from below. Full body, sitting upright.
```

Later poses (same character, use the chosen mascot as reference) / 后续姿态（同一角色，以选定的吉祥物为参考图）：
- Searching / 翻找中：`The same squirrel digging eagerly into a small pile of tiny glowing glass boxes, tail raised, focused expression.`
- Done / 完成：`The same squirrel standing proudly on top of a neat stack of tiny glass boxes, holding the glowing acorn up, happy closed-eye smile.`

## Category icons / 分类图标

| Category | Prompt |
|---|---|
| Video editors / 剪辑软件 | `A clapperboard fused with a film reel, warm amber-orange glass from #ffb347 to #c4501f.` |
| AI models / AI 模型 | `A cluster of connected glowing glass spheres forming a small neural network inside a faceted crystal cube, lime green glass #a3d233.` |
| Package caches / 软件包缓存 | `A neat stack of three rounded glass parcel boxes with soft ribbons, sky blue glass #5eb0ff.` |
| Developer tools / 开发工具 | `A rounded terminal window block with an embossed chevron prompt symbol, no letters, violet glass #8b7bd8.` |
| Duplicates / 重复文件 | `Two identical rounded glass file cards, one standing slightly behind the other and offset up and to the right, like a file and its exact copy. Each card has a softly folded top-right corner and two short embossed lines, no letters. Mint teal glass #4fd6c0, with a small lime green #a3d233 glow where the two cards overlap.` Rendered on flat `#0a0a0a` instead of transparent. |

## App icon / App 图标 (2026-10-09)

**Layered Liquid Glass icon (macOS 26).** `icon/AppIcon.icon` is an Icon Composer document: the ink-to-deep-green
gradient is the icon's fill, then a lime glow layer and the squirrel layer (glass on, specular on, neutral shadow). The
system draws the shape, margin and shadow and makes the dark, clear and tinted versions itself. Make the layers with
`python3 scripts/compose_app_icon.py <cutout.png> --layers icon/AppIcon.icon/Assets`; preview with
`"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" "$PWD/icon/AppIcon.icon"
--export-image --output-file out.png --platform macOS --rendition Default --width 512 --height 512 --scale 1`
(renditions: Default, Dark, ClearLight, ClearDark, TintedLight, TintedDark). `scripts/build_app.sh` compiles it with
`actool` (Xcode 26+; paths must be absolute) into `Assets.car`, which also holds flattened images for macOS 14 and 15.
Without that Xcode it falls back to the flat icon below.

**分层液态玻璃图标（macOS 26）。** `icon/AppIcon.icon` 是 Icon Composer 文档：墨黑到深绿的渐变是图标底色，上面是青柠光晕层和松鼠层
（松鼠开玻璃和高光，中性投影）。形状、留边、投影以及深色/透明/着色版本由系统生成。图层用上面的 `--layers` 命令生成，用 `ictool` 预览。
打包时 `scripts/build_app.sh` 用 Xcode 26 以上的 `actool` 编译成 `Assets.car`（路径必须是绝对路径），里面也带给 macOS 14、15 用的压平图；
没有这个版本的 Xcode 时退回到下面的平面图标。

**Flat icon (fallback) / 平面图标（备用）**

The plate is drawn in code, not by the model: `scripts/compose_app_icon.py` puts the cutout on an ink-to-deep-green
squircle (824 px body on a 1024 canvas, Apple's grid) with a lime glow behind the acorn, clips it to the plate and
adds the drop shadow. `scripts/build_app.sh` turns `Art/app-icon.png` into `AppIcon.icns` with `sips` and `iconutil`.
The ink plate was chosen over a light paper plate: the cutout keeps a thin dark fur fringe that shows on light colors.

底板用代码画，不让模型画：`scripts/compose_app_icon.py` 把抠好的松鼠放到墨黑渐变深绿的圆角方块上（1024 画布里 824 的主体，
按 Apple 网格），橡果后面加青柠光晕，按底板形状裁切并加投影。打包时 `scripts/build_app.sh` 用系统自带的 `sips` 和 `iconutil`
把 `Art/app-icon.png` 做成 `AppIcon.icns`。选墨黑底而不是浅纸色底：抠图后毛发边缘有一圈暗边，浅底上看得出来。

Cutout source (mascot idle as reference image, ink background, then background removal with the Heavy model at 2048):
抠图来源（以待机吉祥物为参考图，墨黑底出图，再用 Heavy 模型 2048 分辨率去背景）：

```
The same squirrel mascot as in the reference image, shown as a close-up head-and-shoulders portrait for an app icon:
its face, round ears and two small front paws hugging the oversized glowing lime green #a3d233 glass acorn held in
front of its chest, the tip of its big fluffy curled tail rising behind one shoulder. Big friendly glossy eyes, small
smile, warm caramel fur, cream chest. Facing the viewer with a slight three-quarter turn, centered, the squirrel and
acorn filling about 80% of the frame.
Style: premium macOS app icon artwork, 3D render, designer vinyl toy, soft studio key light from the upper left, thin
bright rim light, the acorn's lime glow lighting the chin and paws from below, gentle reflections. Simple bold
silhouette that still reads at 32 px.
Plain flat solid #0a0a0a background with no gradient, no ground shadow, no text, no letters, no logo, no frame, no
rounded square plate, no border.
```

| Asset | URL |
|---|---|
| Render / 原图 | https://cdn.xinyuai.app/image/original/2f0cd0d3-71df-4364-aae7-0e3ae8dc5124-original.png |
| Cutout / 抠图 | https://cdn.xinyuai.app/image/original/7c21750d-8ac2-4e63-853b-42adb5e671fa-original.png |
