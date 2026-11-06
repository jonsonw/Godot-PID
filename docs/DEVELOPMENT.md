# 开发指南：架构与规则 / Development Guide: Architecture & Rules

> 面向**要改这个项目的人**。定位：`CONTRIBUTING.md` 是入口（命名/注释/图元 id 三条硬规范 + 如何提 PR），
> 本文件是纵深（架构地图、**新增功能落位**、强制规则、扩展点、门禁、常见陷阱）。
> 想先读懂系统，读 [`ARCHITECTURE.md`](ARCHITECTURE.md)（精简）或 [`ARCHITECTURE_FOR_BEGINNERS.md`](ARCHITECTURE_FOR_BEGINNERS.md)（权威完整）。
> **只读一节的话读 §2.1** —— 它决定你这次的新代码写在哪里，而后面的门禁只是它的执行者。
> **与代码冲突时，一律以代码为准**；当前基线数字（文件数 / 套件数 / 断言数）见 `ARCHITECTURE.md`，本文件不重复抄写以免漂移。

---

## 一、架构地图 / Architecture Map

| 层 | 路径 | 职责 | 硬约束 |
|---|---|---|---|
| UI | `src/ui` | shell（组合根 `GPMainWindow` + 外壳契约 `GPShellHost` + 7 协调者 + 跨图纸控制器 + DRC 呈现器）、canvas（`GPCanvas2D` + 16 个协作者）、tools、panels、dialogs | **唯一**可依赖 Godot 控件与 autoload 的层 |
| App | `src/app` | 用例编排：命令栈、事件总线、文档管理、自动保存、实时 DRC 调度 | 纯 `RefCounted`；**不引用 UI** |
| Core | `src/core` | model（`GPPIDGraph` 聚合根）、geometry、symbol、view（纯状态）、validation（DRC 规则与发现值对象）、text、platform、service | **不得出现 `Node`** ⇒ 可 headless 单测 |
| IO | `src/io` | `*.pid.json` 读写 + 原子写 + schema 迁移 + DEXPI（Proteus XML）导入导出 + DXF/PDF + 导出注册表 | **唯一**允许碰 `FileAccess` 的层 |
| Render | `src/render` | 图元/管线/图框/底图视图节点与绘制器 | 只读模型 |
| Autoload | `src/autoload` | `I18n` / `Settings` / `SnapState` 三个全局单例 | **仅 ui 可依赖** |
| Addons | `src/addons` | `GPIPIDAddon` 商业化插件契约（**契约 v3，12 个钩子**）+ `GPAddonLoader` | Pro 代码不进本仓；⚠️ 加载器**已存在但外壳尚未挂载**（`src/` 零调用点） |

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

### 2.1 新增功能落位（ADR-47，先读这一节）/ Where new code lands

> 这一节存在的原因只有一句：**过去每加一批功能，就要再做一次大规模架构梳理。**
> 那种循环的机制是「先把代码塞进已经打开的那个文件，等它长大再拆」。拆一次的成本是几周，
> 而避免它的成本是每次多建一个文件。

| | 规则 | 一句话判据 |
|---|---|---|
| **R1** | **模块先行** | 新的领域职责 → 新 `src/<层>/<模块>.gd` + 配套 `tests/gp_test_<模块>.gd`。既有大文件只允许**接线**（实例化、注入、connect）或**变短**（把代码搬出去）。 |
| **R2** | **预算只减不增** | 超 **500 行**的文件、超 **200 行**的函数已被钉在今天的行数上（`gp_test_architecture.gd` 末尾四问）；**加一行即红**。上调预算是评审级决议，不是顺手改数字。 |
| **R3** | **按「谁会一起变」切** | 不按「谁调用谁」切。这段代码需要自己的测试 → 它就需要自己的文件。 |
| **R4** | **跨模块只经端口/契约** | 私有成员不出对象边界（`Class._gpX` 与 `var x: GP类` 两种形态都有守卫）。推论：**谁持有处理器，谁持有接线** —— 信号的 `connect` 写在实现其处理器的那个类里。 |
| **R5** | **没有测试的提取只叫「搬家」** | 同一次提交里三件套：套件文件 + 一条行为断言 + 一条防回流断言。 |
| **R6** | **例外必须走评审级** | 先证明「搬不出去」，再**同时**改在用表与冻结快照（diff 里一眼可见），并在 ADR-47 附录 B 登记理由与偿还计划。 |

**写完需求先过这五问**（细节见 `ARCHITECTURE_FOR_BEGINNERS.md` §5.5）：

1. 它是一块**新的领域职责**吗（现有类名都盖不住）？→ 是，新建模块 + 新套件。
2. 它只是既有职责的**新分支**吗？→ 是，进既有模块，但**先看预算**：加完会超吗？会超就先提取。
3. 它需要读**别人的私有状态**吗？→ 是，停：把状态搬到"据它行动的那一方"，或开只读端口。
4. 它需要新信号/回调吗？→ 是，信号声明在**发出它的类**，`connect` 写在**持有处理器的类**。
5. 它会被**第二个地方**用到吗？→ 会，它必须是一个能被单独引用的模块，而不是"先放这儿以后再说"。

> ⚠️ 预算门覆盖 `src/`，**不覆盖 `tests/`**（套件天然按主题分散，膨胀不会拖慢产品迭代）。
> 完整推理与代价见内部 `docs/ADR/2026-11-06-ADR-47-模块化与新增功能落位.md`；对外可读的摘要见 `CONTRIBUTING.md` §Where new features go / §新增功能落位。

### 2.2 其余强制规则 / Other Mandatory Rules

1. **命名、注释、图元 id** —— 见 [`CONTRIBUTING.md`](../CONTRIBUTING.md)。三条最常犯的：函数/变量必须显式声明类型（禁 `var x =` / `:=`）；函数必须有显式返回类型；注释**中英双语**且覆盖到声明与函数内的非平凡分支。
2. **不得跨层**：`core` / `app` / `io` / `render` 中出现 `ui` 或 autoload 的引用即为缺陷。需要全局能力时**依赖注入**（把值或回调传进去），不要取全局单例。
3. **autoload 只能经场景树解析**：Godot 4 里 autoload 是 `/root` 下的**节点**，必须 `get_node_or_null("/root/<名>")`；`Engine.has_singleton()` **恒为 false 且失败无声**（写成这样会静默退化为默认值）。
4. **所有编辑必须走命令层**：改图形状态请新增/复用 `GPCommand`（`src/app/commands/`）。绕过命令层的编辑**没有撤销能力，也无法 headless 单测**。
5. **界面文案一律走 i18n 单表**：`I18n.gpTr("key")`；新增键必须同时补 zh/en 文案（测试会扫描静态表引用，缺键即失败）。
6. **端口与几何换算不许自己算**：端口世界坐标/朝向一律经 `GPPortResolver`（端口圆点与管线端点共用同一个解析器，各算一遍必然分家）。
7. **存档变更只在字典上做**：持久化只经 `gpToDict()` / `gpFromDict()`；新增字段一律 `dict.get(key, default)`，只有非默认值才写出（保持旧档字节稳定）；schema 迁移链**幂等且只在读取路径**执行。
8. **新增导出格式 = 注册表加一行**：`GPExporterRegistry`（标签键 / 扩展名 / 对话框过滤器键 / 是否需要图纸）。注册表里加了字段就必须有**消费方**，否则就是静默功能（历史事故：过滤器键无人读取，用户选不到新格式）。
9. **测试只增不减**：新增套件必须同步套件计数常量（防套件静默不加载）；改完必查三项——`failed=0`、**断言总数不下降**、`SCRIPT ERROR` 计数为 0。断言数下降本身就是缺陷，即使全绿。
10. **DEXPI 侧的四条不变量**：所有坐标经唯一翻转点；`null` 省略属性而不是写空串；标准库 URI 只写已核实项、不臆造；单位与 Extent 自洽。

---

## 三、目录导航 / Where Things Live

```
scenes/        主场景与对话框场景（main.tscn 为应用入口）
src/core/      内核：model / geometry / symbol / view / validation / text / platform / service
src/app/       编排：commands/（51 条命令）、事件总线、文档管理、自动保存、rules/
src/io/        存档与交换：project_io、原子写、schema 迁移、dexpi_*、exporter_registry
src/render/    视图节点与绘制器
src/ui/        shell（组合根 + 外壳契约 + 协调者）/ canvas / tools / panels / dialogs / symbol_editor
src/autoload/  I18n / Settings / SnapState
src/addons/    GPIPIDAddon 插件契约（v3）+ GPAddonLoader（尚未挂载）
tests/         GPGTest 套件（gp_test_*.gd）+ GUT 用例与桥接（gut/）+ 架构守卫（gp_test_architecture.gd）
tools/         图元包生成、DEXPI 覆盖报告等脚本（Python / GDScript）
assets/        图元 SVG、字体、主题
docs/          文档（索引见 docs/README.md）
```

> 找文件的两个捷径：**按层找**（这段逻辑属于哪个领域）与**按名字找**（`gp_test_<模块>.gd` 与该模块同名）。
> 模块与套件**同名成对**是 R1/R3 的副产品，也是"这段代码有没有自己的测试"最快的判据 —— 找不到同名套件，通常说明它被塞进了别人的文件里。

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

> **编号约定**（本项目内部通用说法）：门 1 `--import` · **门 2 GPGTest（权威）** · 门 3 GUT · 门 4 `--editor --quit` ·
> 门 5 单文件 `--check-only` · 门 6 90 帧冒烟。CI 只跑其中四道，且顺序与编号不同（上面的 bash 块按 CI 顺序排）。
> 下文说"门 2 红"，指的始终是 `run_core_tests.gd` 那一道。

⚠️ **「`failed=0` 不可信」**：GDScript 只报 SCRIPT ERROR 不中断执行，且套件可能静默不加载。每次重构后三项必须同时看：
**① `failed=0` ② 断言总数不下降 ③ `SCRIPT ERROR` 计数为 0**。
⚠️ GUT 侧的断言数是**弱信号**（桥接对每个方法只加 2 条），**权威永远是 GPGTest 的总断言数**。
⚠️ GUT 编辑器插件默认关闭（常驻约占 35% 编辑器启动时间）；命令行运行器不受影响。

### 4.1 架构守卫：规则怎么"拦人"而不是"劝人"

第 2 道门（GPGTest 全套）里有一个套件不是测功能的，而是测**这份代码的结构**：`tests/gp_test_architecture.gd`。

| 检查 | 判据 | 失败时你会看到（键格式） |
|---|---|---|
| 层间引用 | `core/app/io/render` 不得引用 `ui`/`autoload`；层矩阵白名单之外的新边一律红 | `class\|<文件>\|<被引用的类>` |
| 资源路径 | `res://src/<层>/…` 只能指向本层或允许的同级层 | `path\|<文件>\|res://src/…` |
| autoload 访问 | 不得绕过场景树（`Engine.get_singleton` 一类写法） | `autoload\|<文件>\|<名字>` |
| 文件写入 | `FileAccess.WRITE` 只允许出现在 `atomic_file.gd`（与 xlsx 模板例外） | `io\|<文件>\|<类名>` |
| 跨对象私有（静态形态） | `Class._gpX` 且该类声明在**另一个文件** | `private\|<文件>\|Class._gpX` |
| 跨对象私有（实例形态） | `var x: GP某类` 解析出的声明类型是**外来类**（自身类实例＝工厂，豁免；未标注/内建类型**不判**） | `private\|<文件>\|Class._gpX` |

另有一张**已知违规登记表**（当前为空、上限 0）：新增违规则红；修好却不删登记行 → 报 `stale` 也红。**只减不增**。

### 4.2 预算门：往大文件里加一行会红

后四条测试钉住 `src/` 的形状：文件软上限 **500 行**、函数软上限 **200 行**；超限者必须有预算行，行值＝登记当天的实测值。

```
file budget exceeded — extract a module, do not raise the cap:
  src/ui/canvas/canvas_2d.gd 2026>2024
```

看到这句话时，**唯一正确反应是把新代码搬到新文件**（R1），而不是把 2024 改成 2026。四种失败各不相同：

| 报错片段 | 含义 | 正确动作 |
|---|---|---|
| `… 2026>2024` | 这个文件今天比登记时又长了 2 行 | 新代码落新文件；或先把旧代码提取出去 |
| `(new row — no retroactive grandfathering)` | 想给一个新文件补预算行 | 不允许事后补票：先把它拆到 500 行以内 |
| `828>frozen 827` | 在用表被上调了 | 改回去；确需上调走 R6 评审流程 |
| `stale budget rows (… — delete the row from BOTH tables)` | 文件已回到 500 行以内，登记行成了借口 | 从**两张表**同时删掉那一行（进度就该被记下来） |

> 预算的意义不是"数字好看"，而是把**重构的决定**从"几周后一次性偿还"提前到"写第一行代码时"。
> 因此 `GP_FILE_BUDGET` 与 `GP_FILE_BUDGET_FROZEN`（函数侧 `GP_FUNC_BUDGET` / `GP_FUNC_BUDGET_FROZEN`）必须**逐键一致**：删一端、改一端都会红。

---

## 五、扩展点 / Extension Seams

| 想做的事 | 改哪里 | 契约 |
|---|---|---|
| **加一个新功能（新领域职责）** | **新建** `src/<层>/<模块>.gd` + `tests/gp_test_<模块>.gd` | 见 §2.1 R1–R6；主文件只加接线，加完不能超预算 |
| 加一个图元（不写代码） | `tools/gen_symbol_packs.py` 声明几何 + 端口 → 生成图元包 | 图元 id 必须由 `GPSymbolNaming.gpAllocate` / `GPSymbolLibrary.gpAllocateCustomId` 分配，禁止手写 |
| 加一种画布交互 | `GPCanvasToolRegistry` 加一行 + 一个新工具文件 | 画布主体不改；经 `GPCanvasToolContext` 取协作者，不抓画布私有成员 |
| 加一条可撤销操作 | `src/app/commands/` 新增 `GPCommand` 子类 | 自我求逆（do/undo 成对）；执行后只发事件，不直接刷界面 |
| 加一种导出格式 | `GPExporterRegistry` 加一行 + 各菜单加一行字面量 | 必须有消费方读取新字段（菜单/对话框/状态行/分发） |
| 加一个外挂功能（商业/外围） | 继承 `GPIPIDAddon`（**契约 v3，12 个钩子**，公开 `gp*` 命名） | 核心代码不动；Pro 代码不进本仓。⚠️ 加载器 `GPAddonLoader` 尚未被外壳挂载，契约目前只被测试行使 |

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
| 新增 `class_name` 后门 2 报 `Could not find base class` | 先跑门 1（`--import`），确认日志里出现 `update_scripts_classes \| <类名>` 再跑门 2 —— 类缓存由导入扫描刷新 |
| 往 500 行以上的文件加了一行，门 2 红 | 这是**设计意图**，不是误报：新代码落新文件（R1），别改预算数字（R2/R6） |
| 新增字段/常量却没人读 | **"声明了却没人读的常量，是最便宜的一种谎"**：常量、接口、注册表条目在加之前先问"谁读它"；没有读者就不加（历史上 `GP_CONTRACT_VERSION` 就空转过一段时间） |
| 重构后注释还说着旧世界 | **过期注释比没有注释更坏**：它不报错，只让下一个读者按不存在的约束做设计。搬走代码时同一条提交里改掉原处的注释 |
| `Vector2` 为单精度 | 极紧的比较界留 `1e-6` 量级余量 |
| `--script` 模式下 `add_child` 不触发 `_ready` | 不要依赖 `_ready`，显式初始化 |
| 删除 `.godot/` 或强杀编辑器 | 会造成冷启动重建脚本/类/文档缓存（编辑器启动明显变慢）——**不要做** |
| 把构建产物放进项目扫描路径 | 产物目录加 `.gdignore` |

---

## 八、提问与反馈 / Questions

用 Issue 描述「期望行为 / 实际行为 / 复现步骤 / 环境（Godot 版本、OS）」。涉及架构取舍的改动，建议先开 Issue 讨论再动手 —— 决策一旦落地会以「决策记录」的形式固定下来（内部维护，不随仓库分发）。
