# ADR-000：ADR 制度本身

> 本文件定义 G-PID「何时必须写架构决策记录、写在哪里、用什么模板」。
> 建立动因：多个决策曾只以代码注释或工作区 HTML 形式存在，协作者无法追溯，测试与代码各自演化——
> 这直接造成了 2026-09-11 的 CI 红（详见 `ADR-UI-02-线型语义.md`）。

## Status / 状态

Accepted（2026-09-11）

## Context / 背景

- 决策曾只以代码注释存在：`edge_style.gd:69,71` 引用「ADR-UI-02」，但仓库内查无此文件；
- 或只存在于**工作区根目录**的设计 HTML（`Godot-PID界面及UI设计.html` §③、`Godot-CAD与Godot-PID_UI对比.html`），**不在 git 仓库内**，GitHub 访客与协作者无法追溯；
- 直接后果：`gp_test_edge_style.gd::gpTestPipesAreAlwaysSolid` 长期与代码冲突，CI 变红（2026-09-11 已按 ADR-UI-02 路径 A 修复，门禁转绿 `passed=1830 failed=0`）。

需要一套明确约定，把「决策必须落库」制度化。

## Decision / 决策

1. **位置与命名**：`docs/adr/ADR-<编号>-<主题>.md`。既有 `ADR-UI-02-线型语义.md` 沿用；新增按序号递增，编号不复用。
2. **必须写 ADR 的情形**：
   - 引入或变更**跨模块契约**（数据格式、schema 版本、端口协议、命令接口）；
   - 影响**存档兼容**的变更（持久化格式、迁移链 v1→v2→v3）；
   - 采用或推翻某个**行业惯例 / 标准**（AutoCAD 线型、ISO 10628 图元命名、GB / IEC 规范映射）；
   - 引入新的**架构层或全局机制**（autoload、插件钩子 `GPIPIDAddon`、shader 渲染路径）；
   - 任何**已被代码注释引用为「ADR-xxx」**的决策 —— 发现即补。
3. **不必写 ADR**：局部实现细节、不改变外部行为的纯重构、测试构造。
4. **模板**（每篇必含，中英双语）：
   - `Status`（Proposed / Accepted / Deprecated / Superseded by ADR-XXX）
   - `Context`（为什么现在必须做这个决定）
   - `Decision`（决定做什么）
   - `Consequences`（变容易了什么、变难了什么 —— 正向与负向都要写）
   - 可选：`Options considered`（备选方案与取舍）
5. **维护铁律**：
   - **先改 ADR，再改代码与测试**；
   - 变更已接受的 ADR 时，**新建一篇并标注 `Superseded by`**，不原地改写历史；
   - 与 `CONTRIBUTING.md` 的双语注释规范保持一致。

## Consequences / 后果

- 正向：决策可追溯；新成员不必考古代码注释；「决策没进仓库导致测试与代码脱节」这一类事故被制度化消除。
- 负向：增加写作成本；需要靠 review 习惯维持 —— 建议在 PR 模板加一条提醒（「本次改动是否引入了需要记录的决策？」）。
- 负向：ADR 目录会随项目增长，应定期归档而非删除（历史决策是资产）。
