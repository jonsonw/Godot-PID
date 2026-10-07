# G-PID 文档索引 / Documentation Index

> 本文件是 `docs/` 的**总入口**：所有文档在此登记。
> 新增文档必须同时在下方表格里登记一行 —— 否则它对读者而言不存在。

## 一、公开文档（随仓库分发，GitHub 可见）/ Public Docs (shipped with the repo)

| 文档 | 内容 | 适合谁 |
|---|---|---|
| [`DEVELOPMENT.md`](DEVELOPMENT.md) | **开发指南：架构地图 + 强制开发规则 + 扩展点 + 提交约定** | 想改代码的人（第一站） |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 架构总览（精简版）：分层表、依赖方向、单档格式、扩展接缝、测试与 CI | 想快速理解系统的人 |
| [`ARCHITECTURE_FOR_BEGINNERS.md`](ARCHITECTURE_FOR_BEGINNERS.md) | **新手导读**（权威完整版）：从 Godot 概念讲到「加功能该改哪里」 | 第一次接触本项目的人 |
> 说明：以下内容已于 **2026-10-07 移除**：连线功能专项文档（`P4_CONNECTION_PANEL.md`、`connection_feature_baseline.md`），
> 以及样例工程目录 `samples/`（原含空白 A3 模板与一份**含客户项目名**的历史存档）。
> 连线部分的行为约定与规则改由 `DEVELOPMENT.md`（开发规则、扩展点）与 `ARCHITECTURE.md`（分层与接缝）承载；
> 需要空白 A3 起点图时，运行 `Godot --headless --script res://tools/make_blank_a3.gd` 在本地生成
> （默认写到 `user://blank_a3.pid.json`，也可追加参数指定路径；**产物不入库**）。

**仓库根目录还有：** [`README.md`](../README.md)（项目总览 / 下载 / 上手）、[`CONTRIBUTING.md`](../CONTRIBUTING.md)（命名与注释规范：双语注释、`GP`/`gp` 前缀、图元 id 规则）、[`CHANGELOG.md`](../CHANGELOG.md)（语义化版本变更记录）。

## 二、本地过程文档（**不随仓库分发**）/ Local-only Process Docs

以下三个分区是本项目的**开发过程文档**（内部资产），已在 `.gitignore` 中排除，**不会上传到远端仓库**。
它们的索引在各分区自己的 `README.md` 里：

| 分区 | 回答的问题 | 为什么不上传 |
|---|---|---|
| `ADR/` | **为什么这样决定**（每个决策一篇，含前后因果链） | 决策过程属内部资产 |
| `SDLC/` | **长期往哪走 / 本周走到哪**（按周长期方向 spec） | 含内部排期与里程碑判断 |
| `YAGNI/` | **明确不做什么**（禁令 + 原因 + 替代方案） | 含试错记录与失败模式 |

> ⚠️ **铁律**：公开文档**不得**用相对链接指向上面三个分区 —— 远端取不到这些文件，链接会断。
> 代码注释里可以按**编号**引用决策（如 `ADR-4`、`ADR-9`），编号是稳定引用键，但不要写成链接。

## 三、建议阅读路径 / Suggested Paths

| 你是谁 | 建议顺序 |
|---|---|
| 第一次来，只想看看 | `README.md` → `docs/ARCHITECTURE.md` |
| 想加一个图元（不写代码） | `README.md` → `CONTRIBUTING.md` §图元 id 规则 → `tools/gen_symbol_packs.py` |
| 想改代码 / 提 PR | 本索引 → `docs/DEVELOPMENT.md` → `docs/ARCHITECTURE_FOR_BEGINNERS.md` → `CONTRIBUTING.md` |
| 想接后端 / 批处理 / 二次开发 | `docs/ARCHITECTURE.md`（分层与扩展接缝）→ `docs/DEVELOPMENT.md` §扩展点 |
| 项目维护者（本人） | 本索引 → `ADR/README.md`（决策）→ `SDLC/README.md`（方向）→ `YAGNI/README.md`（禁令） |

## 四、维护规则 / Maintenance Rules

1. **登记制**：新增文档必须在上表登记；删除文档必须同时删掉登记行。
2. **公开 ≠ 内部**：公开文档只写对外成立的内容（架构、规则、扩展方式）；决策的取舍细节与排期留在本地分区。
3. **不写断链**：公开文档禁止相对链接到 `ADR/`、`SDLC/`、`YAGNI/`（见上面铁律）。
4. **与代码同步**：架构与基线类表述改完必须**核验代码**（`docs/` 与代码冲突时，以代码为准）；带日期的历史记录保留原值，不追改。
