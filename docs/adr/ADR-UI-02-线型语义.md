# ADR-UI-02：管线线型语义（Process / Utility）

> Architecture Decision Record — 管线线型语义决策。
> 本文件为 G-PID 仓库内 ADR 制度的首条实践，后续任何线型语义变更须先改本文件，再动代码/断言。

## Status / 状态

Accepted（2026-09-11，随连线功能 P1 落地；此前仅以 `src/core/model/edge_style.gd:69,71` 注释形式存在，未入仓库，导致 `tests/gp_test_edge_style.gd` 陈旧断言长期与代码冲突 —— CI 红，详见架构交付文档 §9.1）

## Context / 背景

连线条渲染采用纯函数样式表 `GPEdgeStyle.gpStyleFor(kind, signalType, zoom)`，把
`(类型, 信号类型, 缩放)` 映射为 `{width, color, pattern}`。把线重收在样式表一处，是为了让
"改样式"成为一行编辑，旧存档无需迁移即可重新配色。

早期约定：**PROCESS 与 UTILITY 仅靠线宽区分，两者都是实线。** 引入 AutoCAD 风格线型层
（`GPLinetypeManager` + `assets/linetype/acad.ltp` + 全局 `LTSCALE`）后，行业惯例与用户期望是
**UTILITY 显示为虚线（DASHED）**，与 PROCESS 实线形成语义区分，而不必依赖线宽。该决策最初没写进
仓库，只留在代码注释里，于是测试与代码各自按旧约定演化，CI 变红。

## Decision / 决策

- **PROCESS → `CONTINUOUS`**（空 `pattern` = 实线），保留语义工艺色 `#DCE3F0`，线宽 `3.0` 仍是其区别于 UTILITY 的唯一可见手段。
- **UTILITY → `DASHED`**（`[18.0, 6.0]`，受全局 `LTSCALE` 缩放），线宽 `1.6`，颜色 `#9AA6BE`。
- 线型名称经 `GPLinetypeManager.gpPatternFor()` 解析：`CONTINUOUS` 回退为空数组（实线）；`assets/linetypes/acad.ltp` 存在时覆盖内置值。
- 本决策写入仓库 `docs/adr/`，并修正 `gp_test_edge_style.gd` 对应断言，使 CI 恢复绿。
- **今后铁律**：任何线型语义变更，必须先更新本 ADR，再改 `edge_style.gd` 与测试；禁止再让"注释里的决策"与断言脱节。

## Consequences / 后果

- 正向：UTILITY 在每张图上都呈虚线，符合 AutoCAD 行业惯例，语义区分更直观；线型可经 `acad.ltp` 用户编辑覆盖。
- 正向：决策可追溯 —— 协作者不必去翻 `edge_style.gd` 注释，仓库内即可查到依据。
- 负向：PROCESS 与 UTILITY 的区分从「仅线宽」变为「线宽 + 线型」；旧存档中若曾有人用线宽区分二者，视觉上多一重差异（符合预期，非回归）。
- 负向（过程债已还清）：测试套件须随决策演进；今后变更若漏改本 ADR 与断言，CI 会立即红，作为强制护栏。

## Options considered / 备选方案

| 选项 | 内容 | 取舍 |
|---|---|---|
| A（采纳） | UTILITY 虚线 + 更新断言 + 本 ADR 入仓库 | 保留已落地的 AutoCAD 线型设计，决策可追溯 |
| B（否决） | 回退代码，UTILITY 改回实线，断言不动 | 推翻已落地设计，放弃行业惯例的语义区分，仅为了迁就旧断言 |
