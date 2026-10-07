# 开发指南：架构与规则 / Development Guide: Architecture & Rules

> 面向**要改这个项目的人**。定位：`CONTRIBUTING.md` 是入口（命名/注释/图元 id 三条硬规范 + 如何提 PR），
> 本文件是纵深（架构地图、强制规则、扩展点、门禁、常见陷阱）。
> 想先读懂系统，读 [`ARCHITECTURE.md`](ARCHITECTURE.md)（精简）或 [`ARCHITECTURE_FOR_BEGINNERS.md`](ARCHITECTURE_FOR_BEGINNERS.md)（权威完整）。
> **与代码冲突时，一律以代码为准**；当前基线数字（文件数 / 断言数）见 `ARCHITECTURE.md`，本文件不重复抄写以免漂移。

---

## 一、架构地图 / Architecture Map

| 层 | 路径 | 职责 | 硬约束 |
|---|---|---|---|
| UI | `src/ui` | shell（组合根 `GPMainWindow` + 协调者）、canvas（`GPCanvas2D` + 实现类）、tools、panels、dialogs | **唯一**可依赖 Godot 控件与 autoload 的层 |
| App | `src/app` | 用例编排：命令栈、事件总线、文档管理、自动保存 | 纯 `RefCounted`；**不引用 UI** |
| Core | `src/core` | model（`GPPIDGraph` 聚合根）、geometry、symbol、view（纯状态）、platform、service | **不得出现 `Node`** ⇒ 可 headless 单测 |
| IO | `src/io` | `*.pid.json` 读写 + 原子写 + schema 迁移 + DEXPI（Proteus XML）导入导出 + 导出注册表 | **唯一**允许碰 `FileAccess` 的层 |
| Render | `src/render` | 图元/管线/图框/底图视图节点与绘制器 | 只读模型 |
| Autoload | `src/autoload` | `I18n` / `Settings` / `SnapState` 三个全局单例 | **仅 ui 可依赖** |
| Addons | `src/addons` | `GPIPIDAddon` 商业化插件契约（8 个钩子，仅契约、无加载器） | Pro 代码不进本仓 |

```
依赖方向（单向，不可逆）
    ui ──► { app, io, render } ──► core
     │            │                 ▲
     └──► autoload（只有 ui 可以）
core / app / io / render 对 ui 与 autoload 的引用数必须为 0（可用 grep 直接验证）
```

**一次编辑的完整链路（改功能前先认清这条链）**

```
输入(鼠标/快捷键/菜单) → 画布工具或协调者 → GPCommand（入 GPCommandStack）
   → 改模型（GPPIDGraph） → GPEventBus 发布事件 → 视图/停靠栏/状态栏订阅重绘
保存：gpToDict() → 原子写（tmp → 校验 → bak → rename）→ 清脏标记
```

---

## 二、强制开发规则 / Mandatory Rules

1. **命名、注释、图元 id** —— 见 [`CONTRIBUTING.md`](../CONTRIBUTING.md)。三条最常犯的：函数/变量必须显式声明类型（禁 `var x =` / `:=`）；函数必须有显式返回类型；注释**中英双语**且覆盖到声明与函数内的非平凡分支。
2. **不得跨层**：`core` / `app` / `io` / `render` 中出现 `ui` 或 autoload 的引用即为缺陷。需要全局能力时**依赖注入**（把值或回调传进去），不要取全局单例。
3. **autoload 只能经场景树解析**：Godot 4 里 autoload 是 `/root` 下的**节点**，必须 `get_node_or_null("/root/<名>")`；`Engine.has_singleton()` **恒为 false 且失败无声**（写成这样会静默退化为默认值）。
4. **所有编辑必须走命令层**：改图形状态请新增/复用 `GPCommand`（`src/app/commands/`）。绕过命令层的编辑**没有撤销能力，也无法 headless 单测**。
5. **界面文案一律走 i18n 单表**：`I18n.gpTr("key")`；新增键必须同时补 zh/en 文案（测试会扫描静态表引用，缺键即失败）。
6. **端口与几何换算不许自己算**：端口世界坐标/朝向一律经 `GPPortResolver`（端口圆点与管线端点共用同一个解析器，各算一遍必然分家）。
7. **存档变更只在字典上做**：持久化只经 `gpToDict()` / `gpFromDict()`；新增字段一律 `dict.get(key, default)`，只有非默认值才写出（保持旧档字节稳定）；schema 迁移链**幂等且只在读取路径**执行。
8. **新增导出格式 = 注册表加一行**：`GPExporterRegistry`（标签键 / 扩展名 / 对话框过滤器键 / 是否需要图纸）。注册表里加了字段就必须有**消费方**，否则就是静默功能（历史事故：过滤器键无人读取，用户选不到新格式）。
9. **测试只增不减**：新增套件必须同步套件计数常量（防套件静默不加载）；每个重构后的必查项见 §四。
10. **DEXPI 侧的四条不变量**：所有坐标经唯一翻转点；`null` 省略属性而不是写空串；标准库 URI 只写已核实项、不臆造；单位与 Extent 自洽。

---

## 三、目录导航 / Where Things Live

```
scenes/        主场景与对话框场景（main.tscn 为应用入口）
src/core/      内核：model / geometry / symbol / view / platform / service
src/app/       编排：commands/（命令）、事件总线、文档管理、自动保存
src/io/        存档与交换：project_io、原子写、schema 迁移、dexpi_*、exporter_registry
src/render/    视图节点与绘制器
src/ui/        shell / canvas / tools / panels / dialogs / symbol_editor
src/autoload/  I18n / Settings / SnapState
src/addons/    GPIPIDAddon 插件契约
tests/         GPGTest 套件（gp_test_*.gd）+ GUT 用例与桥接（gut/）
tools/         图元包生成等脚本（Python）
assets/        图元 SVG、字体、主题
docs/          文档（索引见 docs/README.md）
```

---

## 四、门禁与测试 / Gates & Tests

双轨测试：自研 **GPGTest**（`tests/gp_test_*.gd`）+ vendored **GUT**（`addons/gut`，桥接脚本用反射驱动既有套件，无需改写测试）。

```bash
# CI 四道（任一步失败即红）
godot --headless --path . --import                       # 注册 class_name（缺此步 GUT 起不来）
godot --headless --path . --editor --quit                # 编译扫描
godot --headless --path . --script res://tests/run_core_tests.gd   # GPGTest 全套（权威）
godot --headless --path . --script res://addons/gut/gut_cmdln.gd -gexit -gdir=res://tests/gut

# 本地另两道
godot --headless --path . --check-only --script res://<改动文件>.gd   # 单文件解析
godot --headless --path . --quit-after 90 res://scenes/main.tscn      # 运行时冒烟
```

⚠️ **「`failed=0` 不可信」**：GDScript 只报 SCRIPT ERROR 不中断执行，且套件可能静默不加载。每次重构后三项必须同时看：
**① `failed=0` ② 断言总数不下降 ③ `SCRIPT ERROR` 计数为 0**。
⚠️ GUT 侧的断言数是**弱信号**（桥接对每个方法只加 2 条），**权威永远是 GPGTest 的总断言数**。
⚠️ GUT 编辑器插件默认关闭（常驻约占 35% 编辑器启动时间）；命令行运行器不受影响。

---

## 五、扩展点 / Extension Seams

| 想做的事 | 改哪里 | 契约 |
|---|---|---|
| 加一个图元（不写代码） | `tools/gen_symbol_packs.py` 声明几何 + 端口 → 生成图元包 | 图元 id 必须由 `GPSymbolNaming.gpAllocate` / `GPSymbolLibrary.gpAllocateCustomId` 分配，禁止手写 |
| 加一种画布交互 | `GPCanvasToolRegistry` 加一行 + 一个新工具文件 | 画布主体不改 |
| 加一条可撤销操作 | `src/app/commands/` 新增 `GPCommand` 子类 | 自我求逆（do/undo 成对）；执行后只发事件，不直接刷界面 |
| 加一种导出格式 | `GPExporterRegistry` 加一行 + 各菜单加一行字面量 | 必须有消费方读取新字段（菜单/对话框/状态行/分发） |
| 加一个外挂功能（商业/外围） | 继承 `GPIPIDAddon`（8 个钩子） | 核心代码不动；Pro 代码不进本仓 |

---

## 六、提交与发布约定 / Commits & Releases

- **提交信息**：`<type>(<scope>): <中文摘要>`，类型用 `feat` / `fix` / `refactor` / `perf` / `docs` / `test` / `chore`（例：`fix(dexpi): 导入节点键与边引用统一（修连线锚原点）`）。
- **版本**：语义化版本（SemVer），功能性变更必须写进 [`CHANGELOG.md`](../CHANGELOG.md)。
- **发布**：二进制走 GitHub Release 附件分发，不入库；**推 tag ≠ 发 Release**（附件是独立对象）——发版后必须同时核对「Release 附件数」与「下载链接可 200 访问」。

---

## 七、已知陷阱 / Known Pitfalls（Godot 4.7 实测）

| 陷阱 | 正确做法 |
|---|---|
| `String(variant)` 会**挂死**（不是报错，是卡住） | 用 `str(variant)` |
| `--check-only` 报 `Identifier not found: I18n / Settings` | **误报**，只认 `Parse Error` |
| 测试脚本存在 Parse Error | 会让测试运行器崩成 `exit=137` —— 先修语法再看结果 |
| `Vector2` 为单精度 | 极紧的比较界留 `1e-6` 量级余量 |
| `--script` 模式下 `add_child` 不触发 `_ready` | 不要依赖 `_ready`，显式初始化 |
| 删除 `.godot/` 或强杀编辑器 | 会造成冷启动重建脚本/类/文档缓存（编辑器启动明显变慢）——**不要做** |
| 把构建产物放进项目扫描路径 | 产物目录加 `.gdignore` |

---

## 八、提问与反馈 / Questions

用 Issue 描述「期望行为 / 实际行为 / 复现步骤 / 环境（Godot 版本、OS）」。涉及架构取舍的改动，建议先开 Issue 讨论再动手 —— 决策一旦落地会以「决策记录」的形式固定下来（内部维护，不随仓库分发）。
