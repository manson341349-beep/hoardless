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
