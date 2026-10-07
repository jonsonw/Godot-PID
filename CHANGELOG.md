# 更新日志 / Changelog

> 本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)（SemVer）。所有功能性变更均记录于此。

---

## [v0.1] — 2026-09-24 · 标准对齐首版 / First standards-aligned release

本版本以 **DEXPI 示例 C01（国际标准示例 P&ID，A3 420×297mm）** 为唯一对齐基准，完成「线型 / 线宽 / 字体 / 字号 / 箭头 / 图幅严格按标准执行、库只保留标准图元、可 1:1 复刻」的目标。

### 新增 / Added
- **标准图框与双语标题栏（图幅 A0–A4）** / **Standard drawing frame & bilingual title block (A0–A4)**
  - `GPSheet` 模型新增 `gpWidthMM` / `gpHeightMM` / `gpFrameOn` / `gpLabelMode` 与 13 个双语标题栏字段（公司、图名、图号、设计/校核/审核、日期、比例、阶段、版本等）。
  - `GPFrameView` 渲染层：裁边线 + 内图框 + 标题栏，随图纸平移缩放（z_index = -1），headless 下字体回退安全。
  - 标题栏对话框（`GPTitleBlockDialog`）：图框开关、图幅选择、语言模式（中文/English/中英对照）、13 字段双语录入，实时重绘。
  - 语言模式 `gpLabelMode` 仅作用于**图纸自带文字**；位号 / 管线号始终单语（符合 ISO 图纸惯例）。
- **DEXPI C01 标准图元包（24 个符号）** / **DEXPI C01 standard symbol pack (24 symbols)**
  - 从 `svg_full_pid.svg` 提取并归一化 24 个真实比例图元：容器（碟形封头）、板式/浮头式换热器、离心泵（卧式/立式）、球阀/闸阀/截止阀/蝶阀/旋塞阀、仪表气泡（中央/右侧/左侧）、三通、异径管、人孔、接管嘴、坡度、流向箭头、盲板、法兰等。
  - 每个图元带**真实 mm 尺寸**（`size_mm`）与类型化端口（NOZZLE / SIGNAL / ACTUATOR / TERMINAL），画布按比例呈现、左侧图元库统一缩略。
  - 新增源代号 `D`（DEXPI），命名规则扩展为 `L/C/D + 类别 + 三位序号`；旧别名表改为 24 条 DEXPI slug→D-id 映射。
- **1:1 手绘复刻能力** / **1:1 tracing capability**
  - `GPBackgroundView` 背景追踪底图层（z_index = -2）：可载入标准图位图淡色铺满整张图纸，作为描摹底图。
  - 标题栏对话框新增「追踪底图」分组：路径选择、清除、透明度调节。
  - 新增空白 A3 模板 `docs/samples/blank_a3.pid.json`（由真实代码路径生成，schema 与运行时一致）。**（自 2026-10-07 起仓库不再分发样例文件，改为运行 `tools/make_blank_a3.gd` 在本地生成到 `user://`）**

### 变更 / Changed
- **图元库切换为 DEXPI C01**：内置库由已删除的 ISO 10628 包（25 符号）切换为 DEXPI C01 包（24 符号，提取自标准示例图）。
- **线宽/字号基准统一为 mm**：`1 世界单位 = 1 mm`，ISO 多级线宽（设备 0.35 / 工艺 0.30 / 公用 0.25 / 信号 0.18 mm）与 mm 字高贯穿画布、导出与图框。

### 移除 / Removed
- 删除 ISO 10628 / ISA-5.1 / IEC 62424 三套旧图元包及其生成产物（`pack_iso_10628.gd` 等），库恢复为单一标准来源，避免双格式漂移。

### 测试 / Tests
- 核心测试套件 **2304 → 2310 断言全绿**（门 2）；新增图框双语/序列化、背景底图往返、DEXPI 端口表等测试。
- GUT 套件 **58 套**（`GP_EXPECTED_SUITES` 同步），已知 headless 绘制噪音已纳入白名单。
- 六门 CI 全绿：导入 / 核心测试 / GUT / 全量编译 / check-only / 冒烟。

---

## 计划 / Roadmap
- **Phase 7（v0.1 后）**：按 `B` 键呼出类游戏「背包」图元选择界面；多文档深化（W21）；跨页连接器（W22）；AI 辅助仅桩（W23）。
- **DEXPI 双向校验器（W10 / W18）** 与导入器（W18）按既定顺序推进（决策记录 ADR-8「原生存档与 DEXPI」）。
