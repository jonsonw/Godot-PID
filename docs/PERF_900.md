# 900 节点基准 / 900-node benchmark (D06)

> 目标：先测量，不先优化。本文只记录 headless 可证明的**模型层**数字；GPU 重绘 / 平移 60fps 不在 headless 中伪造。
> Goal: measure first. This file records only model-layer numbers a headless run can prove; GPU redraw / 60 fps panning are **not** claimed from headless.

## 夹具 / Fixture

- 900 个图元节点（`DPUMP001`，网格排布）
- 450 条工艺边
- 30 条注释线
- 来源：`tools/gp_bench.gd`（固定数量，无随机数）

## 复现 / Reproduce

```bash
cd Godot-PID-Core
HOME=/tmp/gpidhome godot --headless --path . res://tools/gp_bench.tscn
```

## 基线 / Baseline（2026-10-31，Godot 4.7）

| 项 | 数值 |
|---|---:|
| 建 900 节点 | 2,338 µs |
| 加 450 条边 | 1,374 µs |
| `gpToDict()` 序列化 | 1,519 µs |
| `gpFromDict()` 解析 | 5,203 µs |
| 100 次位置编辑（模型） | 235 µs |
| 往返节点 / 边 | 900 / 450 |
| headless 进程总墙钟（含引擎启动+夹具） | ≈350 ms（不是 GUI 启动到可编辑） |

> 数字来自一次本机 headless 运行；用于同机前后对比，不宣称跨机器绝对性能。运行会打印 JSON，重复运行取同量级即可。

## 结论与边界 / Verdict & boundary

- 模型层 900 节点构建/往返在毫秒级，未发现必须引入 MultiMesh 的证据。
- **未测**：GPU draw calls、编辑后首帧重绘、平移 60fps、应用启动到可编辑；这些需要带渲染的 GUI 基准，headless 不可信。
- 下一步若需要 GUI 预算：在 D03 的 revision 刷新接缝上加 `Performance.TIME_PROCESS` / `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` 探针，记录 900 节点下的首帧与平移；不达标先做分组/脏矩形，不盲目 MultiMesh。
