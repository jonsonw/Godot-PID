# ISO / GB 采用与偏离表 / Adoption & Deviations

> 来源：**ADR-28**（`docs/ADR/2026-10-31-ADR-28-一把尺的边界与标准偏离.md`）。本文件是 H02 的可交付摘要；冲突以 ADR-28 为准。
> Source: **ADR-28**; this is the H02 deliverable summary. ADR-28 wins on conflict.

## 结论 / Verdict

本项目**不声称严格 ISO 5457 合规**。下列项目明确采用 ISO/GB 或明确偏离；空白不是「默认合规」。

The project does **not** claim strict ISO 5457 compliance. Each row is either adopted or an explicit deviation.

| 项 / Item | 项目值 / Project | 标准值 / Standard | 决定 / Decision | 说明 |
|---|---|---|---|---|
| A1 图签 / Title block | 270×100 mm（A3 基础 135×50 × frame_scale 2.0） | ISO 5457 不规定单一图签尺寸 | **项目自定** | 图签随 `gpFrameScale`，A3=135×50、A1=270×100 |
| 坐标带 / Zone grid | 12 × 8 | ISO 5457 分区带（可按图幅调整） | **偏离**（固定计数） | A1/A3 均 12×8；分区数不随纸幅 |
| 线宽 / Line widths | 0.35 / 0.30 / 0.25 / 0.18 mm；引出线 0.13 mm | ISO 128 系列 | **采用**（0.13 为项目补充最细档） | 线宽是绝对 mm，不乘 frame/symbol scale |
| 装订边距 / Filing margins | A0–A1: 25/10 mm；A2–A4: 25/5 mm | GB/T 14689（与 ISO 5457 的 20/10 不同） | **采用 GB/T 14689，明确偏离 ISO 5457** | 代码 `gpDefaultMarginsFor()` |
| 裁边内缩 / Trim inset | 1.0 mm | ISO 5457 裁边概念 | 采用概念；当前实现乘 `gpFrameScale`，待 B05/C03 修正 | 修正后 A3/A1 均 1.0 mm |
| 符号邻接 / Symbol adjacency | 标签 gap 7.0 / 最小 0.8 mm；cell pad 1.0 mm（A3 时代实测） | 无单一 ISO 值 | **采用「随 symbol_scale」** | 旧档 0.5 保持 A3 观感；新档 1.0；B05 落地 |
| 箭头 / 悬空端 / Arrow & dangling | 箭头 7.0 mm；悬空端 0.35 mm | 项目制图记号 | **绝对 mm** | 不随 frame/symbol scale |

## 复算 / Reproduce

- 本表逐行对应 ADR-28 §2.2 / §3；修改任一行必须先改 ADR-28。
- DEXPI 侧的覆盖数字见 `docs/DEXPI_COVERAGE.md`（由 `tools/gp_dexpi_coverage.gd` 生成）。
