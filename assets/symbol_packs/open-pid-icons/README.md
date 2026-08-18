# open-pid-icons 图元包
# open-pid-icons symbol pack

本文件夹包含从 npm 包 `open-pid-icons@1.0.0` 转换而来的 P&ID SVG 图标。\
This folder contains P&ID SVG icons converted from the npm package `open-pid-icons@1.0.0`.

- 上游仓库 / upstream repo: https://github.com/tbo47/open-pid-icons
- 上游许可证 / upstream license: MIT (Copyright 2025 tbo47)
- 本包图标数量 / icon count: 6

## 文件说明 · File layout

| 文件 / file | 说明 / description |
|------------|--------------------|
| `svg/` | 独立 SVG 文件，可直接在 Godot 中作为图元引用。Individual SVG files ready to be used as symbols in Godot. |
| `manifest.json` | 图标清单，含名称、类型、尺寸与连接点（anchors）。Symbol manifest including name, type, size and anchor points. |
| `open-pid-icons.json` | 上游原始数据（path / width / height / anchors）。Upstream raw data. |
| `LICENSE` | 上游 MIT 许可证副本。Upstream MIT license copy. |
| `_convert.py` | 本地转换脚本（将 JSON 拆分为 SVG 与 manifest）。Local converter script. |

## 使用方式 · Usage

在 Godot 编辑器中直接引用 `svg/*.svg` 作为 Sprite2D 或 TextureRect 的纹理，\
or read `manifest.json` at runtime to draw the path via `CanvasItem.draw_polyline()` / `draw_colored_polygon()`.
