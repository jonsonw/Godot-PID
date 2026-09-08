# G-PID 项目架构新手导读

> 本文用「Godot 新手能看懂」的方式，解释 G-PID 的代码组织、文件关系、类与函数分工。
> 读完之后，你应该能知道：程序从哪里开始运行、数据存在哪里、界面如何更新、撤销是怎么做的、以及改哪里可以添加新功能。
>
> **本文按实际代码（v0.9 阶段 / M7 之后）重写。旧版本里的部分路径与类名已失效，差异见文末 §12。**

---

## 0. 先看两张图

### 图 1：四层分工

```
┌─────────────────────────────────────────────────────────────┐
│  UI 层        src/ui/      用户看到的控件，接收鼠标键盘        │
│  shell / panels / canvas / dialogs / tools                   │
└───────────────────────┬─────────────────────────────────────┘
                        │ 调用（只走公开端口，不直接翻内部变量）
┌───────────────────────▼─────────────────────────────────────┐
│  应用服务层   src/app/      把「用户意图」翻译成一次可撤销的命令  │
│  GPEditService / GPCommand / GPCommandStack / GPEventBus      │
│  GPAppDocumentManager                                        │
└───────────────────────┬─────────────────────────────────────┘
                        │ 读写
┌───────────────────────▼─────────────────────────────────────┐
│  数据层       src/core/model/   唯一真相来源，不画图不碰 UI    │
│  GPPIDGraph / GPPIDNode / GPPIDEdge / GPSymbolDef / GPShape   │
└─────────────────────────────────────────────────────────────┘
                        ▲ 读取后投影
┌───────────────────────┴─────────────────────────────────────┐
│  渲染层       src/render/    GPSymbolView / GPEdgeView        │
│  （由 src/ui/canvas/graph_binder.gd 增量同步）                │
└─────────────────────────────────────────────────────────────┘

旁挂支撑（不属于任何一层，被各处复用）：
  src/core/geometry/  几何算法    src/core/symbol/   图元库与归一化
  src/core/view/      画布状态    src/core/service/  IdGen / IOResult
  src/core/platform/  窗口/弹窗    src/autoload/     I18n / Settings
```

**一句话**：数据层管「是什么」，应用服务层管「怎么改（且能反悔）」，渲染层管「画成什么样」，UI 层管「用户怎么操作」。

### 图 2：启动后的场景树

```
Main (Control) — 挂 src/ui/shell/main_window.gd
└── VLayout (VBoxContainer)
    ├── MenuBar (HBoxContainer) — src/ui/shell/menu_bar.gd
    ├── Body (HSplitContainer)
    │   ├── LeftDock (VBoxContainer) — src/ui/panels/toolbar.gd   ① 左侧图元库
    │   ├── Center (VBoxContainer) — src/ui/panels/center_area.gd ② 多标签绘图区
    │   │   └── （运行时由 gpAddTab() 动态创建）
    │   │       └── GPCanvas2D — src/ui/canvas/canvas_2d.gd       ③ 画布
    │   │           └── gpWorldRoot (Node2D)
    │   │               ├── GPSymbolView (Node2D) × N
    │   │               └── GPEdgeView   (Node2D) × N
    │   └── RightDock (VBoxContainer)
    │       └── InspectorTabs (TabContainer)
    │           ├── PropTab (ScrollContainer) — src/ui/panels/inspector.gd
    │           ├── InfoTab → InfoLabel
    │           └── DocTab  → DocLabel
    └── StatusBar (HBoxContainer)
        └── SelLabel / CoordLabel / ZoomLabel / StateLabel
```

> ⚠️ **画布不在 `main.tscn` 里**。场景文件里 `Center` 只是一个空容器；画布由 `GPCenterArea.gpAddTab()` 在 `_ready()` 中动态创建，并通过 `gpOnCanvasReady` 信号告诉主窗口。这是为多图纸（W21）预留的结构。

---

## 1. 你必须先懂的 4 个 Godot 概念

### 1.1 节点（Node）= 乐高积木

Godot 里所有东西都是**节点（Node）**。窗口是节点、按钮是节点、画布是节点、图元也是节点。

- 节点可以**挂脚本**（`.gd` 文件），脚本决定这个节点做什么。
- 节点可以**嵌套**：一个节点下面可以有子节点，形成一棵树。
- 节点之间通过**信号（signal）**通信，类似「订阅公众号」：A 发一条消息，订阅过的 B 就会收到。

### 1.2 场景（Scene）= 保存好的节点树

`.tscn` 文件就是**场景文件**，记录一棵节点树的结构和属性。

- `project.godot` 里的 `run/main_scene="res://scenes/main.tscn"` 告诉 Godot：启动后先把这棵树实例化出来。
- 主场景 `scenes/main.tscn` 里摆好了菜单栏、左图元库、中间容器、右侧属性面板、状态栏。

### 1.3 脚本（Script）= 节点的大脑

`.gd` 是 GDScript 脚本，挂在节点上给节点添加行为。

| 写法 | 含义 |
|------|------|
| `extends Control` | 继承 UI 控件基类（画布 `GPCanvas2D` 就是它） |
| `extends Node2D` | 继承 2D 对象基类（`GPSymbolView` / `GPEdgeView`） |
| `extends Resource` | 数据资源，可存盘（`GPSymbolDef` 就是它） |
| `extends RefCounted` | 纯内存对象，不进场景树，引用计数自动释放 |

> **本项目大量使用 `RefCounted`**：数据模型（`GPPIDGraph`）、命令层（`GPCommand`）、服务层（`GPEditService`）、画布交互工具（`GPCanvasTool`）都是它。好处是**不依赖场景树，可以 headless 单测**——这是本项目「core 层无 UI 依赖」原则的具体体现。

### 1.4 信号（Signal）= 节点之间的消息

```gdscript
# A 定义信号
signal gpGraphChanged

# B 订阅
canvas.gpGraphChanged.connect(_gpOnGraphChanged)

# A 在适当时机触发
gpGraphChanged.emit()
```

在 G-PID 里，**画布负责发信号，主窗口负责接收并更新界面**，这样数据和界面就解耦了。

除了节点信号，本项目还额外引入了一条**应用级事件总线**（`GPEventBus`，见 §7），用于「不是节点的对象之间」通信。

---

## 2. 项目启动后发生了什么？

```
1. Godot 读取 project.godot
   ├── run/main_scene = "res://scenes/main.tscn"
   └── [autoload] 先创建两个全局单例：I18n、Settings

2. 加载 main.tscn，创建节点树（结构见 §0 图 2）

3. 各节点执行 _ready()，其中 main_window.gd 是「接线员」：
   ├── GPSymbolLibrary.gpLoadUserPacks()   恢复用户自建图元包
   ├── gpDefs = GPSymbolLibrary.gpDefaultDefs()
   ├── 抓取场景里的静态节点（菜单栏、左右停靠栏、状态栏标签…）
   ├── gpCenter.gpSetDefs(gpDefs)          把图元列表交给中间绘图区
   ├── gpCenter.gpAddTab()                 动态创建首张图纸（画布）
   ├── gpLeftDock.gpPopulate(gpDefs)       左侧图元库生成按钮
   └── 连接信号：gpSymbolPicked / gpToolSelected / gpSymbolDeleteRequested …

4. 画布就绪回调 _gpOnCanvasReady()：
   ├── gpCanvas.gpBindDocument(gpDocManager)   画布绑定文档管理器
   └── gpDocManager.gpSetGraph(gpCanvas.gpGraph)

5. 进入主循环，等待用户输入
```

所以：**`project.godot` 是入口，`main.tscn` 是界面骨架，`main_window.gd` 是启动时的接线员。**

---

## 3. 数据层：GPPIDGraph 是唯一真相来源

### 3.1 一张图里有什么

```gdscript
# src/core/model/pid_graph.gd
class_name GPPIDGraph
extends RefCounted

var gpMeta: Dictionary = { "version": "1.0", "title": "", "sheets": 1 }
var gpNodes: Array[GPPIDNode]   = []   # 图元实例（设备/阀门/仪表…）
var gpEdges: Array[GPPIDEdge]   = []   # 连线
var gpShapes: Array[GPShape]    = []   # 注释图形（手画的线/圆/矩形/折线）
var gpUserSymbolPacks: Array[GPSymbolPack] = []  # 内嵌的用户图元包
```

> 注意：`GPPIDGraph` 是 `RefCounted` 而**不是** `Resource`。它不靠 Godot 的资源序列化，而是手写 `gpToDict()` / `gpFromDict()` 转 JSON——因为 Godot 的 `@export` 只支持内置类型 / Resource / Node / 枚举，无法导出自定义 `RefCounted` 数组。

### 3.2 节点与边

```gdscript
# src/core/model/pid_node.gd
var gpInstanceId: String  = ""      # 实例 id，如 "n1"
var gpSymbolId: String    = ""      # 指向哪个图元定义，如 "pump"
var gpTag: String         = ""      # 位号，如 "P-101"
var gpPosition: Vector2   = Vector2.ZERO
var gpRotationDeg: float  = 0.0
var gpFlipped: bool       = false
var gpAttrValues: Dictionary = {}

# src/core/model/pid_edge.gd
var gpInstanceId: String  = ""
var gpFromRef: Dictionary = {}      # 起点（只存 id，不存端口名）
var gpToRef: Dictionary   = {}      # 终点
var gpKind: String        = "PROCESS"
var gpRouting: Array[Vector2] = []
var gpTag: String         = ""
var gpAttrs: Dictionary   = {}
```

> **设计要点**：边只存 `from/to` 的 **id**，不存端口名。这样你在符号编辑器里删改端口时，已有连线不会断链。

### 3.3 存盘长什么样

`gpToDict()` 产出 5 个顶层键，写入 `*.pid.json`：

| 键 | 内容 |
|------|------|
| `meta` | 版本、标题、图纸数 |
| `nodes` | 图元实例数组 |
| `edges` | 连线数组 |
| `shapes` | 注释图形数组 |
| `user_symbol_packs` | **内嵌**的用户图元包 |

最后一项是品牌主张「**数据主权 / 无锁定**」的技术保证：文件自带图元定义，拷到任何一台机器打开都长得一样，不依赖外部图元库。

---

## 4. 应用服务层：所有修改都走「命令」

这是本项目**最重要、也最容易看漏**的一层。_old 版本的导读完全没有这一节。_

### 4.1 为什么需要它

早期写法是「UI 直接改数据」。问题是：撤销做不了、批量操作容易改一半、状态散落各处。

现在改成：**用户的任何一次修改，都被包装成一个命令对象，压进命令栈。**

```
用户操作 → UI 调 GPEditService → 造一个 GPCommand → GPCommandStack.gpDo()
                                                      ├─ 执行 → 改数据
                                                      └─ 压栈 → 可撤销
```

### 4.2 三个零件

| 类 | 文件 | 职责 |
|------|------|------|
| `GPCommand` | `src/app/command.gd` | 命令基类。`gpExecute(ctx) -> bool` / `gpUndo(ctx)` / `gpRedo(ctx)` |
| `GPCommandContext` | `src/app/command_context.gd` | 注入依赖（图 + IdGen），命令不自己去全局找 |
| `GPCommandStack` | `src/app/command_stack.gd` | 撤销栈。`gpDo` / `gpUndo` / `gpRedo` / `gpClear`，深度上限 `GP_DEFAULT_LIMIT = 200` |

关键契约：**命令是「自我求逆的值对象」**——执行时就把撤销所需的全部信息捕获下来（比如删除节点时，把整个节点对象存进命令里），撤销时不依赖任何外部状态。因此命令可以脱离 UI、脱离场景树，在 headless 下单测。

现有 8 个命令（`src/app/commands/`）：

```
add_node_command / add_shape_command / connect_command
delete_nodes_command / delete_shapes_command / delete_selection_command
duplicate_nodes_command / move_nodes_command
```

`delete_selection_command` 是复合命令：**混合删除图元 + 注释图形只算一个撤销步**（否则按一次 Ctrl+Z 只撤掉一半，很反直觉）。

### 4.3 GPEditService：用户意图的翻译器

`src/app/edit_service.gd`，它**只依赖图和 IdGen，不持有任何 UI 引用**（这是刻意的，为了可测）。

```gdscript
func gpPlaceNode(gpSymbolId: String, gpWorld: Vector2, gpTag: String = "") -> String:
    if gpSymbolId == "":
        return ""
    var gpCmd: GPAddNodeCommand = GPAddNodeCommand.new(gpSymbolId, gpWorld, gpTag)
    if not gpStack.gpDo(gpCmd, gpCtx):
        return ""
    return gpCmd.gpCreatedId
```

看清楚这个模式：**造命令 → 交给栈 → 从命令上读结果**。其余方法同一套路：

| 方法 | 作用 |
|------|------|
| `gpBindGraph(gpGraph, gpIds)` | 切换当前图（会清空命令栈） |
| `gpPlaceNode(gpSymbolId, gpWorld, gpTag="")` | 放置图元，返回新 id |
| `gpConnect(gpFromId, gpToId)` | 连线 |
| `gpDeleteSelection(gpNodeIds, gpShapeIdxs)` | 混合删除（一步撤销） |
| `gpDuplicateSelection(gpNodeIds)` | 复制，返回新 id 数组 |
| `gpMoveNodes(gpNodeIds, gpDelta)` | 整组移动 |
| `gpAddShape(gpShape)` | 添加注释图形，返回下标 |
| `gpUndo()` / `gpRedo()` / `gpCanUndo()` / `gpCanRedo()` | 撤销重做 |
| `gpUndoLabel()` / `gpRedoLabel()` | 菜单上显示的文字 |

---

## 5. 渲染层：视图只是数据的投影

| 文件 | 类名 | 基类 | 作用 |
|------|------|------|------|
| `src/render/symbol_view.gd` | `GPSymbolView` | `Node2D` | 一个图元实例的视觉表现 |
| `src/render/edge_view.gd` | `GPEdgeView` | `Node2D` | 一条连线的视觉表现 |
| `src/render/symbol_painter.gd` | `GPSymbolPainter` | — | 实际绘制图元字形 |
| `src/ui/canvas/graph_binder.gd` | `GPGraphBinder` | `Node` | 增量同步器 |

### 5.1 world_root 技巧

`GPCanvas2D` 内部创建一个 `Node2D`（`gpWorldRoot`），所有 `GPSymbolView` / `GPEdgeView` 都挂在它下面。

- 平移画布 = 改 `gpWorldRoot.position`
- 缩放画布 = 改 `gpWorldRoot.scale`

所有图元一起动，不用逐个算位置。

### 5.2 视图是「薄」的

`GPSymbolView` 不保存「我在哪」，只问数据层要位置。它的公开方法就四个：

```gdscript
func gpInit(gpN: GPPIDNode, gpD: GPSymbolDef) -> void   # 绑定数据节点与图元定义
func gpSetSelected(gpSel: bool) -> void                 # 选中态（换颜色）
func gpSetConnectSource(gpSrc: bool) -> void            # 连线起点高亮
func gpUpdateTransform() -> void                        # 按 node.gpPosition 更新自己
```

### 5.3 GPGraphBinder 增量同步

`_draw()` 每次都重建整棵视图树会卡，所以由 `GPGraphBinder.gpSync()` 做增量同步：

```gdscript
func gpSync(gpG: GPPIDGraph, gpD: Array[GPSymbolDef],
            gpSelection: Array[String], gpConnectFrom: String) -> void
```

它比对「数据里有哪些 id」与「现有视图有哪些 id」，只新建新增的、只更新变化的、移除已删的。

---

## 6. UI 层

### 6.1 画布 `GPCanvas2D`（`src/ui/canvas/canvas_2d.gd`）

972 行的 `Control` 子类。它是**对外端口最密集**的类，也是重构中重点收敛的对象（已从 1640 行降到 972 行）。

**信号**（5 个）：

| 信号 | 时机 |
|------|------|
| `gpGraphChanged` | 图数据变化 |
| `gpStatusUpdated(info: Dictionary)` | 状态栏要更新 |
| `gpSymbolEditRequested(gpSymbolId: String)` | 请求就地编辑某图元 |
| `gpModeChanged(gpNewMode: int)` | 交互模式切换 |
| `gpMakeSymbolRequested(gpDraft: Dictionary)` | 请求新建图元 |

**主要公开属性**：

| 属性 | 含义 |
|------|------|
| `gpGraph` / `gpDefs` | 当前图 / 可用图元定义 |
| `gpEvents: GPEventBus` | 事件总线（懒加载） |
| `gpActions: GPEditService` | 编辑服务（所有修改都经它） |
| `gpBinder: GPGraphBinder` / `gpWorldRoot: Node2D` | 同步器 / 世界根 |
| `gpState: GPCanvasInteractState` | 交互状态（相机、模式、选择、框选） |
| `gpMode: int` | 当前模式，取值见下 |
| `gpPendingDef: GPSymbolDef` | 等待放置的图元定义 |
| `gpSelection: Array[String]` / `gpSelectedId` | 选择集 |
| `gpConnectFrom: String` | 连线起点 |
| `gpMarq: GPCanvasMarquee` / `gpAnno: GPAnnotationEditor` | 框选 / 注释编辑 |

`gpMode` 取自 `GPCanvasInteractState.GPMode`：

```gdscript
enum GPMode { GP_SELECT, GP_CONNECT, GP_DRAW_LINE, GP_DRAW_CIRCLE,
              GP_DRAW_RECT, GP_DRAW_POLYLINE, GP_DRAW_ARC }
```

**主要公开方法**（按用途分组）：

| 组 | 方法 |
|------|------|
| 装配 | `gpSetMode(gpM)`、`gpBindDocument(gpMgr)` |
| 修改入口 | `gpRequestPlaceNode`、`gpRequestConnect`、`gpRequestAddShape`、`gpRequestMoveNodes`、`gpRequestSelectAll`、`gpRequestDeleteSelected`、`gpRequestDuplicateSelected` |
| 撤销 | `gpUndo()` / `gpRedo()` / `gpCanUndo()` / `gpCanRedo()` |
| 选择 | `gpSetSelection(gpIds)`、`gpDeleteSelection()`、`gpClearSelection()` |
| 命中 | `gpHitTest(gpWorld) -> String`、`gpHitShape(gpWorld) -> int`、`gpNodeRect(gpId) -> Rect2`、`gpNodeCenter(gpId) -> Vector2` |
| 坐标 | `gpWorldFromScreen(gpS)` / `gpScreenFromWorld(w)` |
| 视图 | `gpZoomStep(gpFactor)`、`gpResetView()` |
| 其他 | `gpCancelActiveTool()`（ESC 路径）、`gpSnapshot()`（测试用快照）、`gpEmitStatus()` |

> **命名规律**：`gpRequest*` 开头的是「外部请画布改数据」的唯一入口。这么做是为了让画布内部状态不被外部直接翻——M3 重构把 56 处越界访问清零，换来的是画布可以安全地继续瘦身。

### 6.2 画布交互工具（`src/ui/tools/`）

画布自己不处理鼠标逻辑，而是把它**委派**给一个 `RefCounted` 工具对象，按 `gpMode` 分派：

```gdscript
# src/ui/tools/canvas_tool.gd
class_name GPCanvasTool
extends RefCounted

func gpOnActivate() -> void: pass
func gpOnDeactivate() -> void: pass
func gpOnPress(gpWorld: Vector2, gpShift: bool, gpDouble: bool) -> bool: return false
func gpOnMove(gpWorld: Vector2) -> bool: return false
func gpOnRelease(gpWorld: Vector2) -> bool: return false
func gpOnKey(gpKey: InputEventKey) -> bool: return false
func gpCancel() -> bool: return false
func gpDrawOverlay(gpCv: CanvasItem) -> void: pass
func gpCursor() -> int: return Input.CURSOR_ARROW
```

返回值 `true` 表示「这个事件我处理了，别再往下传」。

| 工具 | 文件 | 职责 |
|------|------|------|
| Select | `select_tool.gd` | 选择、拖拽、框选、连线起点 |
| Place | `place_tool.gd` | 落放 `gpPendingDef` |
| Draw shape | `draw_shape_tool.gd` | 画注释图形（线/圆/矩形/折线） |
| Grip | `grip_tool.gd` | 抓取点编辑 |

注册表 `GPCanvasToolRegistry` 维护 `gpMode → 工具` 映射。

> 这套抽象后来被**符号编辑器直接复用**（M7），见 §8.4。

### 6.3 其他 UI 部件

| 文件 | 类名 | 基类 | 职责 |
|------|------|------|------|
| `src/ui/shell/main_window.gd` | （无 `class_name`） | `Control` | 组合根 / 总指挥 |
| `src/ui/shell/menu_bar.gd` | `GPPIDMenuBar` | `HBoxContainer` | 顶部菜单 |
| `src/ui/panels/toolbar.gd` | `GPPIDToolbar` | `VBoxContainer` | 左侧图元库 |
| `src/ui/panels/center_area.gd` | `GPCenterArea` | `VBoxContainer` | 多标签绘图区 |
| `src/ui/panels/inspector.gd` | `GPInspector` | `ScrollContainer` | 右侧属性面板 |
| `src/ui/panels/symbol_grid.gd` | — | — | 图元按钮网格 |
| `src/ui/dialogs/settings_dialog.gd` | `GPSettingsDialog` | `Window` | 设置弹窗 |
| `src/ui/dialogs/make_symbol_dialog.gd` | — | — | 新建/编辑图元对话框 |
| `src/ui/canvas/annotation_editor.gd` | `GPAnnotationEditor` | — | 注释图形编辑 |
| `src/ui/canvas/canvas_shortcuts.gd` | — | — | 键盘快捷键（Ctrl+Z/Y 等下沉于此） |
| `src/ui/canvas/canvas_context_menu.gd` | — | — | 右键菜单 |

工具栏信号：`gpSymbolPicked(type)` / `gpToolSelected(type)` / `gpSymbolDeleteRequested(type)`。

---

## 7. 事件总线与文档管理器

### 7.1 GPEventBus（`src/app/event_bus.gd`）

节点信号只能给节点用。服务层那些 `RefCounted` 对象（EditService、DocumentManager）之间要通信，就靠这条总线。

```gdscript
class_name GPEventBus
extends RefCounted

signal gpGraphChanged(gpGraph: GPPIDGraph)
signal gpSelectionChanged(gpIds: Array[String])
signal gpStatusUpdated(gpInfo: Dictionary)
signal gpModeChanged(gpNewMode: int)
signal gpDocChanged(gpGraph: GPPIDGraph)
signal gpDirtyChanged(gpDirty: bool)
```

**每图纸一条总线**，由文档管理器持有。这样未来开多文档时，不同图纸的事件不会串台。

### 7.2 GPAppDocumentManager（`src/app/document_manager.gd`）

```gdscript
class_name GPAppDocumentManager
extends RefCounted

var gpGraph: GPPIDGraph = null
var gpDirty: bool = false
var gpBus: GPEventBus = GPEventBus.new()
```

它管「当前打开哪张图、脏不脏」。主窗口在启动时 `gpCanvas.gpBindDocument(gpDocManager)`，画布随后从管理器取总线并订阅 `gpGraphChanged`。

> 它**不是** autoload，只是一個普通对象，由 `main_window.gd` 持有（M6 引入，同时删掉了旧的 `GPAppState` 桩）。

---

## 8. 一个完整的交互流程：点图元 → 画布出现图元 → 撤销

```
① 用户点左侧「泵」按钮
   GPPIDToolbar 发出 gpSymbolPicked("pump")

② main_window._gpOnSymbolPicked("pump")
   ├── gpActiveCanvas().gpPendingDef = _gpDefFor("pump")   # 待放置
   ├── gpActiveCanvas().gpSetMode(GPMode.GP_SELECT)
   └── _gpSetState("status.symbol_picked", ["泵"])          # 状态栏

③ 用户在画布上点左键
   GPCanvas2D._gui_input() 收到 InputEventMouseButton
   └── 按 gpMode 分派给 PlaceTool.gpOnPress(world)
       └── 画布.gpRequestPlaceNode("pump", world)

④ GPEditService.gpPlaceNode("pump", world)
   ├── 造 GPAddNodeCommand(symbolId, world, tag)
   ├── GPCommandStack.gpDo(cmd, ctx)
   │   └── cmd.gpExecute(ctx)
   │       ├── 向 GPIdGen 要一个新 id（"n13"）
   │       ├── 造 GPPIDNode 并 gpGraph.gpAddNode()
   │       └── 命令内部记下 gpCreatedId（供撤销定位）
   └── 返回 gpCmd.gpCreatedId

⑤ 数据变了 → 通知
   ├── 画布 gpGraphChanged.emit()  → 主窗口刷新属性面板
   └── 总线 bus.gpGraphChanged.emit(gpGraph) → 其他订阅者

⑥ 画布重绘 _draw()
   └── GPGraphBinder.gpSync(graph, defs, selection, connectFrom)
       ├── 发现 "n13" 还没有视图
       ├── new GPSymbolView → gpInit(node, def)
       └── 挂到 gpWorldRoot 下，它自己 _draw() 画出图形

⑦ 用户按 Ctrl+Z
   GPCanvasShortcuts → 画布.gpUndo()
   └── GPEditService.gpUndo() → 栈弹出命令 → cmd.gpUndo(ctx)
       └── 从图里移除 "n13"（命令执行时已记下整个节点对象）
   └── 再走一遍 ⑤⑥，视图消失
```

**这个流程体现的核心设计**：

- 用户操作 → UI 层 → **服务层造命令** → 命令改数据 → 事件通知 → 渲染层同步 → UI 层刷新
- 每一步都能单独测试：命令可 headless 测、服务不碰 UI、画布只转发

### 8.1 顺带一提：符号编辑器复用了同一套工具抽象

M7 新建了 `src/ui/dialogs/symbol_editor/`（13 个文件），让「新建/编辑图元」对话框复用主画布的 `GPCanvasTool` 抽象：

- `GPSymbolEditor`（`RefCounted`）持有工作模型 + 自己的 `GPCommandStack`
- `GPSymbolEditorTool` / `Context` / `Registry` + Select / Draw / Port 三工具
- 6 条命令：图元/端口的 **增、删、移**（`symbol_add/delete/move_shape/port_command.gd`）

所以符号编辑器里画一笔、放一个端口、删一条线，**全都可以 Ctrl+Z 撤销**——和主画布完全一致的体验，而代码是复用出来的。

---

## 9. Autoload 全局单例

`project.godot` 里只注册了**两个**（不是三个）：

```ini
[autoload]
I18n="*res://src/autoload/i18n.gd"
Settings="*res://src/autoload/settings.gd"
```

它们不是 `main.tscn` 里的节点，而是 Godot 启动时自动创建、挂在 `root` 下的单例，任何脚本里都能直接写 `I18n.xxx` / `Settings.xxx`。

### 9.1 I18n（翻译官）

```gdscript
signal gpLocaleChanged(locale: String)
func gpTr(gpKey: String, gpFallback: String = "") -> String
func gpSetLocale(gpLocaleCode: String) -> void
```

```gdscript
var gpText: String = I18n.gpTr("symbol_lib.title")
```

维护中英对照表；切语言时发 `gpLocaleChanged`，订阅者刷新文字。图元显示名也走这里，所以切语言时图元文字会变。

### 9.2 Settings（设置 / 字体管理员）

```gdscript
var gpFontSize: int = 16          # UI 字号
var gpLocale: String = "en"
var gpFontKey: String = "arial_cjk"
var gpSymbolFontKey: String = "hiragino"
var gpSymbolFontSize: int = 16
var gpAutoScale: bool = true
var gpSymbolFont: Font = null

signal gpSymbolStyleChanged
signal gpUIFontChanged

func gpLoad() -> void          # 从 user://settings.cfg 读取
func gpSave() -> void
func gpLoadFont(p_gpKey: String) -> Font
func gpEffectiveFontSize() -> int
func gpApplyFontSize() -> void
```

内置字体不含中日韩字形，所以项目自带真实中文字体（`res://assets/fonts/`），并在 `.import` 里设 `oversampling=4.0` 保证小字清晰。

### 9.3 关于 GPAppState（已删除）

旧文档提到的第三个 autoload `GPAppState` **已不存在**。它的职责（当前工程、脏标记、新建/切换）已由 `GPAppDocumentManager` 接管（§7.2），且后者不是全局单例而是被主窗口持有——依赖更清晰，也更容易测。

---

## 10. 代码规范：为什么变量都叫 `gpXxx`？

项目硬性约定，目的是避免和 Godot 内置名冲突，同时一眼看出是项目代码。

| 规则 | 例子 |
|------|------|
| 类名 | `GPPIDGraph`、`GPCanvas2D`、`GPSymbolView`（`GP` + PascalCase） |
| 函数 / 变量 | `gpAddNode`、`gpViewZoom`、`gpWorldRoot`（`gp` + camelCase） |
| 私有 | 下划线开头：`_gpSyncViews`、`_gpSymbolViews` |
| 常量 / 枚举 | `GP_DEFAULT_LIMIT`、`GPMode.GP_SELECT` |
| 显式类型 | 必须写类型：`var gpX: int = 0`，**禁止** `var x := 0` |
| 函数返回类型 | 必须显式标注：`func gpTr(...) -> String` |
| 中英注释 | 每段注释英文一行 + 中文一行 |

**禁改名清单**：Godot 虚方法（`_ready` / `_draw` / `_gui_input`）、内置属性（`position` / `name` / `size`）、字典键（`id` / `from` / `to`，因为要兼容存档格式）、单字母坐标（`x` / `y` / `z` / `w` / `h`）。

> ⚠️ 一个已踩过的坑：本版 GDScript **不会把 enum 成员注入类作用域**。想直接用 `GP_SELECT`，得写 `const GP_SELECT: int = GPSymbolToolKind.GP_SELECT` 之类的别名。

---

## 11. 新手常见问题：我想加功能，该改哪里？

### 11.1 添加一种新图元（比如「压缩机」）

改 `src/core/symbol/symbol_library.gd` 的 `gpDefaultDefs()`，或改 ISO 图元包 `src/core/symbol/symbol_packs/pack_iso_10628.gd`（内置图元由 `tools/gen_symbol_packs.py` 生成，**不要手改生成产物**）。

想让某分类有独特颜色，改 `src/render/symbol_view.gd` 的颜色分派。

### 11.2 加一种新的编辑操作（比如「对齐选中图元」）

**不要直接在画布里改数据**，按命令模式来：

1. 在 `src/app/commands/` 新建 `align_nodes_command.gd extends GPCommand`，实现 `gpExecute` / `gpUndo` / `gpRedo`
2. 在 `src/app/edit_service.gd` 加一个 `gpAlignNodes(...)` 方法，内部造命令 + `gpStack.gpDo()`
3. 在 `src/ui/canvas/canvas_2d.gd` 加一个 `gpRequestAlignNodes()` 转发端口
4. 在菜单（`menu_bar.gd`）或快捷键（`canvas_shortcuts.gd`）上调它

这样新功能**自动获得撤销/重做**，且可 headless 单测。

### 11.3 加一种画布交互（比如新工具）

在 `src/ui/tools/` 新建 `xxx_tool.gd extends GPCanvasTool`，实现需要的虚方法，然后在注册表里 `gpRegister(模式, 工具)`。

### 11.4 保存图纸到文件

用现成的 `GPProjectIO`（`src/io/project_io.gd`，全是 `static func`）：

```gdscript
var gpRes: GPIOResult = GPProjectIO.gpWriteProjectResult(gpGraph, gpPath)
if gpRes.gpOk:
    print("saved")
```

写之前记得先 `gpGraph.gpEmbedUserPacks(...)` 把用户图元包嵌进去，保证文件自包含。

### 11.5 让 Inspector 显示更多属性

改 `src/ui/panels/inspector.gd`，让它根据 `GPSymbolDef.gpAttrsSchema` 动态生成更多输入框。

---

## 12. 测试：双轨运行

本项目有**两套**测试运行器，CI 里两个都跑。

### 12.1 自研 GPGTest（历史主力）

```bash
godot --headless --script res://tests/run_core_tests.gd
```

- 基类 `GPGTest`（`tests/gp_test.gd`），断言方法 `gpCheck` / `gpEq` / `gpApprox`
- 自动发现 `tests/gp_test_*.gd`，反射调用其中 `gpTest*` 开头的方法
- 当前 **21 套 / 443 条断言全绿**

### 12.2 GUT 9.6.1（新主力）

```bash
godot --headless --script res://addons/gut/gut_cmdln.gd -gexit
```

- 已 vendored 到 `addons/gut/`（MIT，257 文件）
- 原生测试继承 `GutTest`，方法名 `test_*`
- 桥接器 `tests/gut/test_gp_suites.gd` 反射驱动全部 21 套旧 GPGTest，无需改写既有断言

**为什么两套并存**：既有 443 条断言全量迁移成本高、回归风险大；桥接让它们立刻进入 GUT 报告，代价是 GUT 侧粒度为「方法级」而非「单条断言级」。**新写的测试一律用 GUT 原生**（`extends GutTest`）。

> ⚠️ 跑 GUT 前**必须先** `godot --headless --import`，否则报 `class_names have not been imported`。这步已写进 CI。

### 12.3 CI 四道门禁

`.github/workflows/ci.yml`，Godot 版本由 `GODOT_TAG` 单点控制：

```
① godot --headless --import                      注册全局类名
② godot --headless --editor --quit               编译扫描（零错误）
③ godot --headless --script tests/run_core_tests.gd   GPGTest
④ godot --headless --script addons/gut/gut_cmdln.gd -gexit   GUT
```

---

## 13. 文件关系速查表

| 文件 | 依赖 | 被谁依赖 | 职责一句话 |
|------|------|----------|-----------|
| `project.godot` | — | 引擎 | 入口、窗口、autoload、插件 |
| `scenes/main.tscn` | — | 引擎 | 界面骨架（画布不在此，动态创建） |
| `src/ui/shell/main_window.gd` | 几乎所有 | — | 组合根、总指挥 |
| `src/ui/panels/center_area.gd` | canvas_2d | main_window | 多标签绘图区，动态建画布 |
| `src/ui/canvas/canvas_2d.gd` | model、edit_service、binder、tools | main_window | 画布交互与渲染外壳 |
| `src/ui/canvas/graph_binder.gd` | model、symbol_view、edge_view | canvas_2d | 增量同步成视图树 |
| `src/ui/tools/*.gd` | canvas_tool_context | canvas_2d | 鼠标交互的委派实现 |
| `src/app/edit_service.gd` | command*、id_gen | canvas_2d | 意图 → 命令 |
| `src/app/command_stack.gd` | command | edit_service | 撤销栈（深 200） |
| `src/app/commands/*.gd` | command、model | edit_service | 8 条具体命令 |
| `src/app/event_bus.gd` | model | document_manager、canvas_2d | 应用级事件总线 |
| `src/app/document_manager.gd` | event_bus、model | main_window | 当前图 + 脏标记 |
| `src/core/model/pid_graph.gd` | pid_node/edge、shape | 全局 | 图数据聚合根 |
| `src/core/model/symbol_def.gd` | shape、port | symbol_library、view | 单个图元定义 |
| `src/core/symbol/symbol_library.gd` | symbol_def、symbol_pack | main_window、toolbar | 内置+用户图元集合 |
| `src/render/symbol_view.gd` | symbol_def、Settings/I18n | binder | 单个图元视觉 |
| `src/render/edge_view.gd` | pid_edge | binder | 单条连线视觉 |
| `src/io/project_io.gd` | pid_graph、io_result | main_window | `*.pid.json` 读写 |
| `src/autoload/i18n.gd` | — | 全项目 | 翻译 |
| `src/autoload/settings.gd` | — | 全项目 | 设置 / 字体 |
| `src/ui/dialogs/symbol_editor/*.gd` | canvas_tool、command | make_symbol_dialog | 图元几何编辑（可撤销） |

**当前未实现的桩**（读了会发现是空壳）：`src/io/dxf_exporter.gd`、`src/io/pdf_exporter.gd`、`src/io/list_basic.gd`、`src/render/pid_3d_builder.gd`。

---

## 14. 一句话总结

> **G-PID 把「P&ID 图纸」当成一份数据（`GPPIDGraph`）来管理；所有修改都必须经过命令（`GPCommand` + `GPCommandStack`），因此天然可撤销；画布和视图只是这份数据的实时投影；UI 层负责把用户操作翻译成意图并交给服务层；事件总线负责广播变化；Autoload 提供翻译与字体。**

记住这十二个字：**数据唯一、命令改数、视图投影、事件驱动**。

---

## 附：本次修订修正了旧版的哪些错误

| # | 旧版说法 | 实际情况 |
|---|---------|---------|
| 1 | 文件路径 `src/core/pid_graph.gd`、`src/ui/main_window.gd` 等 | 已重构为 `src/core/model/`、`src/core/symbol/`、`src/ui/shell/`、`src/ui/panels/`、`src/ui/dialogs/`、`src/ui/canvas/` |
| 2 | Autoload 有三个，含 `GPAppState` | 只有 **I18n / Settings** 两个；`GPAppState` 已删，职责归 `GPAppDocumentManager` |
| 3 | `GPPIDGraph` 是 `Resource` | 是 **`RefCounted`**，序列化靠手写 `gpToDict()` |
| 4 | 存盘只有 nodes / edges | 实际 5 个顶层键，多了 `shapes` 与 **`user_symbol_packs`**（自包含） |
| 5 | 画布是 `main.tscn` 里的静态节点 | 由 `GPCenterArea.gpAddTab()` **动态创建**，为多图纸预留 |
| 6 | 无命令层，UI 直接改数据 | 有完整 `GPCommand` / `GPCommandStack` / `GPEditService`（8 条命令，深 200） |
| 7 | 无事件总线 | 有 `GPEventBus`（6 个信号，每图纸一条） |
| 8 | `GPSymbolDef.gpPorts` 是字典 | 是 `Array[GPPort]`；且 `gpShapes: Array[GPShape]` 为统一模型 |
| 9 | 无测试章节 | 双轨：GPGTest（21 套/443）+ GUT 9.6.1（桥接），CI 四道门禁 |
| 10 | 无符号编辑器 | 有 `src/ui/dialogs/symbol_editor/`（13 文件，复用画布工具抽象 + 6 条命令） |
| 11 | 两张图是占位文字 | 已替换为真实的架构图与场景树 |
