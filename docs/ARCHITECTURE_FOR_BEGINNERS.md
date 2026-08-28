# G-PID 项目架构新手导读

> 本文用「Godot 新手能看懂」的方式，解释 G-PID 的代码组织、文件关系、类与函数分工。
> 读完之后，你应该能知道：程序从哪里开始运行、数据存在哪里、界面如何更新、以及改哪里可以添加新功能。

---

## 0. 先看两张图

下面两张图分别是**架构总览**和**启动后的场景树**。读文字时可以随时翻回来看。

（图1：数据层 → 渲染层 → UI 层，三层分工）

（图2：Godot 启动后自动创建出来的节点树，从根节点到 world_root）

---

## 1. 你必须先懂的 4 个 Godot 概念

### 1.1 节点（Node）= 乐高积木

Godot 里所有东西都是**节点（Node）**。窗口是节点、按钮是节点、画布是节点、图元也是节点。

- 节点可以**挂脚本**（gd 文件），脚本决定这个节点做什么。
- 节点可以**嵌套**：一个节点下面可以有子节点，形成一棵树。
- 节点之间通过**信号（signal）**通信，类似「微信订阅」：A 节点发一条消息，B 节点如果订阅了就会收到。

### 1.2 场景（Scene）= 保存好的节点树

`.tscn` 文件就是**场景文件**，它记录了一棵节点树的结构和属性。

- `project.godot` 里的 `run/main_scene="res://scenes/main.tscn"` 告诉 Godot：程序启动后，先把这棵树实例化出来。
- 我们的主场景是 `scenes/main.tscn`，里面已经摆好了菜单栏、左侧面板、画布、属性面板、状态栏。

### 1.3 脚本（Script）= 节点的大脑

`.gd` 文件就是 GDScript 脚本，它挂在某个节点上，给节点添加行为。

- 例如 `Canvas` 节点挂了 `canvas_2d.gd`，所以它能监听鼠标、缩放、画图元。
- `extends Control` 表示这个脚本继承自 Godot 的 `Control` 类（UI 控件基类）。
- `extends Node2D` 表示它是 2D 游戏对象基类。
- `extends Resource` 表示它是「数据资源」，不显示在场景里，但可以保存到磁盘。

### 1.4 信号（Signal）= 节点之间的消息

信号是 Godot 的「发布-订阅」机制。

```gdscript
# A 节点定义信号
signal gpGraphChanged

# B 节点订阅信号
canvas.gpGraphChanged.connect(_gpOnGraphChanged)

# A 节点在适当时机触发信号
gpGraphChanged.emit()
```

在 G-PID 里，**画布负责发信号，主窗口负责接收并更新界面**。这样数据和界面就解耦了。

---

## 2. 项目启动后发生了什么？（执行流程）

```
1. Godot 读取 project.godot
   └── run/main_scene = "res://scenes/main.tscn"

2. 加载 main.tscn，按里面的描述创建节点树
   └── Main（根 Control）
       ├── VLayout（垂直布局容器）
       │   ├── MenuBar
       │   ├── Body（三栏分栏 HSplitContainer）
       │   │   ├── LeftDock（左侧图元库）
       │   │   ├── Center/Canvas（画布）
       │   │   └── RightDock/InspectorTabs/PropTab（属性面板）
       │   └── StatusBar（状态栏）

3. 每个有 script 属性的节点，执行对应 .gd 脚本的 _ready() 函数
   └── Main 的 _ready() 把数据、画布、图元库、属性面板串起来

4. 程序进入循环，等待用户输入（鼠标、键盘）
```

所以：**project.godot 是入口，main.tscn 是界面骨架，main_window.gd 是启动时的「接线员」。**

---

## 3. 三层架构：数据层、渲染层、UI 层

G-PID 把代码分成三层，每层只关心自己的事。

### 3.1 数据层（唯一真相来源）

| 文件 | 类名 | 作用 |
|------|------|------|
| `src/core/pid_graph.gd` | `GPPIDGraph` | 保存整个 P&ID 图：有哪些节点、哪些边、工程元信息 |
| `src/core/symbol_def.gd` | `GPSymbolDef` | 一个图元「长什么样」的定义：id、名称、分类、尺寸、端口、属性模板 |
| `src/core/symbol_library.gd` | `GPSymbolLibrary` | 返回内置图元列表（泵、储罐、阀门、仪表、换热器） |

#### GPPIDGraph 里面存了什么？

```gdscript
var gpMeta: Dictionary = {"version": "1.0", "title": "", "sheets": 1}
var gpNodes: Array[GPPIDNode] = []
var gpEdges: Array[GPPIDEdge] = []
```

- `gpNodes`：每个元素是一个 `GPPIDNode` 对象，字段有 `gpInstanceId` / `gpSymbolId` / `gpTag` / `gpPosition` / `gpAttrValues` 等（强类型，写错字段名会在编译期报错）。
- `gpEdges`：每个元素是一个 `GPPIDEdge` 对象，字段有 `gpInstanceId` / `gpFromRef` / `gpToRef` / `gpKind` / `gpAttrs` 等。

**重要**：`GPPIDGraph` 不画图，只存数据。它就像 Excel 的「表格」，里面只有数字和文字。

#### GPSymbolDef 是什么？

它是「图元模板」。比如「泵」这个模板说：

- id 是 `"pump"`
- 显示名是 `"泵"`
- 分类是 `"pump"`
- 默认尺寸是 80×56
- 有两个端口：左入口、右出口

用户从左侧图元库点「泵」时，程序就按这个模板在 `GPPIDGraph` 里新建一个节点。

### 3.2 渲染层（把数据画出来）

| 文件 | 类名 | 作用 |
|------|------|------|
| `src/ui/canvas_2d.gd` | `GPCanvas2D` | 2D 画布：监听鼠标、管理相机、同步视图、画网格 |
| `src/render/symbol_view.gd` | `GPSymbolView` | 一个图元实例的视觉表现（矩形、颜色、文字、端口） |
| `src/render/edge_view.gd` | `GPEdgeView` | 一条连线的视觉表现（两个节点之间的线） |

#### 关键设计：world_root

`GPCanvas2D` 内部创建了一个 `Node2D`，叫 `gpWorldRoot`（世界根节点）。

- 所有 `GPSymbolView` 和 `GPEdgeView` 都挂在这个 `world_root` 下面。
- 平移画布 = 改变 `world_root.position`
- 缩放画布 = 改变 `world_root.scale`
- 这样所有图元和连线会一起移动/缩放，不用逐个算位置。

#### 视图是「薄」的

`GPSymbolView` 不保存「我在哪」，它只问底层的 `GPPIDGraph`：「n1 这个节点的 pos 是多少？」然后把自己画到那个位置。

> 数据在 `GPPIDGraph`，视图只是投影。改数据后重绘，视图就自动更新。

### 3.3 UI 层（你看到的控件）

| 文件 | 类名 | 作用 |
|------|------|------|
| `src/ui/main_window.gd` | （无 class_name，挂在 Main 上） | 主窗口控制器：把数据、画布、图元库、属性面板、状态栏串起来 |
| `src/ui/menu_bar.gd` | `GPPIDMenuBar` | 顶部菜单栏 |
| `src/ui/toolbar.gd` | `GPPIDToolbar` | 左侧图元库/工具栏 |
| `src/ui/inspector.gd` | `GPInspector` | 右侧属性面板 |
| `src/ui/settings_dialog.gd` | `GPSettingsDialog` | 设置弹窗 |

`main_window.gd` 是「总指挥」。它的 `_ready()` 做了这些事：

1. 新建一个空的 `GPPIDGraph` 作为当前工程数据。
2. 从 `GPSymbolLibrary.gpDefaultDefs()` 拿到内置图元列表。
3. 把图元和数据交给画布。
4. 把图元列表交给左侧工具栏，让它生成按钮。
5. 连接各种信号（画布变化 → 刷新属性面板；状态更新 → 刷新状态栏）。

---

## 4. 一个完整的交互流程：从点图元到画布出现图元

下面用「用户点击左侧的『泵』，然后在画布上点一下」这个流程，展示各文件如何协作。

```
1. 用户点击左侧「泵」按钮
   └── toolbar.gd 收到点击
       └── 发出 gpSymbolPicked("pump") 信号

2. main_window.gd 收到信号
   └── _gpOnSymbolPicked("pump")
       ├── 找到 id="pump" 的 GPSymbolDef
       └── 告诉画布：gpCanvas.gpPendingDef = 这个定义

3. 用户移动鼠标到画布
   └── canvas_2d.gd 的 _gui_input() 收到 InputEventMouseMotion
       └── 更新状态栏坐标

4. 用户在画布上点左键
   └── canvas_2d.gd 的 _gui_input() 收到 InputEventMouseButton
       └── _gpOnLeftDown()
           ├── 发现 gpPendingDef 不为空
           ├── 生成新 id：n1、n2、n3…
           ├── 调用 gpGraph.gpAddNode(gpGraph.gpNewNode("n1", "pump", "", 鼠标世界坐标, {}))
           │   └── 数据被写入 GPPIDGraph.gpNodes
           ├── gpSelectedId = "n1"
           ├── gpPendingDef = null
           ├── queue_redraw() 让画布重绘
           └── gpGraphChanged.emit() 通知主窗口

5. 画布重绘时
   └── _draw() 被调用
       └── _gpSyncViews()
           ├── 遍历 gpGraph.gpNodes
           ├── 发现 n1 还没有对应的 GPSymbolView
           ├── 新建一个 GPSymbolView，gpInit(n1, pump 定义)
           ├── 把它挂到 gpWorldRoot 下
           └── GPSymbolView._draw() 把自己画成蓝色矩形 + 「泵」字

6. main_window.gd 收到 gpGraphChanged
   └── _gpOnGraphChanged()
       └── _gpRefreshSelection()
           ├── 找到当前选中的 n1
           ├── 在 Inspector 显示它的属性
           └── 在 Info 标签显示类型、尺寸、分类
```

**这个流程体现了核心设计**：

- 用户操作 → UI 层发信号 → 数据层更新 → 渲染层同步 → UI 层再更新显示。
- 所有文件各司其职，没有互相硬编码。

---

## 5. 核心类/文件逐个讲

### 5.1 GPPIDGraph（数据核心）

位置：`src/core/pid_graph.gd`

它是 `Resource` 类型，可以保存到磁盘（以后就是 `*.pid.json` 的内容来源）。

主要函数：

| 函数 | 作用 |
|------|------|
| `gpAddNode(node: GPPIDNode)` / `gpNewNode(id, symbol_id, label, pos, attrs)` | 添加一个节点（先造对象再添加） |
| `gpAddEdge(edge: GPPIDEdge)` / `gpNewEdge(id, from_id, to_id, attrs)` | 添加一条边（先造对象再添加） |
| `gpToDict()` | 把整个图转成 Dictionary，用于保存 JSON |
| `gpFromDict(data)` | 从 Dictionary 恢复出一个 GPPIDGraph |

### 5.2 GPSymbolDef（图元定义）

位置：`src/core/symbol_def.gd`

主要字段：

| 字段 | 含义 |
|------|------|
| `gpId` | 图元唯一标识，如 `"pump"` |
| `gpDisplayName` | 显示名称，如 `"泵"` |
| `gpCategory` | 分类，如 `"pump"` / `"tank"` |
| `gpDefaultSize` | 默认尺寸（Vector2） |
| `gpPorts` | 端口列表，连接管线时用 |
| `gpAttrsSchema` | 属性模板，Inspector 据此生成表单 |

### 5.3 GPSymbolLibrary（符号库）

位置：`src/core/symbol_library.gd`

这是一个 `RefCounted` 工具类，不用实例化，直接调用静态函数。

| 函数 | 作用 |
|------|------|
| `gpDefaultDefs()` | 返回内置图元数组 |
| `list_by_category()` | 按分类分组，左侧工具栏用 |
| `search(q)` | 按名称/id/分类搜索 |

### 5.4 GPCanvas2D（2D 画布）

位置：`src/ui/canvas_2d.gd`

它是 `Control` 子类，负责接收鼠标事件和渲染。

主要变量：

| 变量 | 含义 |
|------|------|
| `gpGraph` | 当前显示的 GPPIDGraph |
| `gpDefs` | 可用的 GPSymbolDef 列表 |
| `gpWorldRoot` | 内部的 Node2D，所有图元/边都挂在这里 |
| `gpViewOffset` | 相机偏移（平移） |
| `gpViewZoom` | 相机缩放 |
| `gpMode` | 当前模式：选择 / 连线 |
| `gpPendingDef` | 等待放置的图元定义 |
| `gpSelectedId` | 当前选中的节点 id |

主要函数：

| 函数 | 作用 |
|------|------|
| `_ready()` | 创建 world_root，连接 I18n/Settings 信号 |
| `_gui_input(event)` | 处理鼠标事件（滚轮缩放、中键平移、左键放置/选择/拖拽/连线） |
| `_draw()` | 画背景、网格、连线预览 |
| `_gpSyncViews()` | 把 GPPIDGraph 同步成 GPSymbolView/GPEdgeView 节点 |
| `gpWorldFromScreen(s)` / `gpScreenFromWorld(w)` | 屏幕坐标和世界坐标互转 |

### 5.5 GPSymbolView（单个图元视图）

位置：`src/render/symbol_view.gd`

它是 `Node2D`，挂在 `world_root` 下面。

主要函数：

| 函数 | 作用 |
|------|------|
| `gpInit(node, def)` | 绑定到图数据节点和图元定义 |
| `gpUpdateTransform()` | 根据 node.pos 更新自己的 position |
| `gpSetSelected(sel)` | 设置是否选中，选中会变黄色 |
| `_draw()` | 画矩形、边框、文字、端口 |

### 5.6 GPEdgeView（单条连线视图）

位置：`src/render/edge_view.gd`

它也是 `Node2D`，挂在 `world_root` 下面。

主要函数：

| 函数 | 作用 |
|------|------|
| `gpInit(edge, graph)` | 绑定到图边和图数据 |
| `_draw()` | 从 from 节点中心画线到 to 节点中心 |

### 5.7 main_window.gd（总指挥）

位置：`src/ui/main_window.gd`

它挂在 `Main` 节点上，程序启动后 `_ready()` 把所有东西串起来。

主要函数：

| 函数 | 作用 |
|------|------|
| `_ready()` | 初始化数据、图元库、画布、属性面板、状态栏、布局比例 |
| `_gpOnSymbolPicked()` | 左侧图元被点击 |
| `_gpOnToolSelected()` | 工具模式切换（选择/连线/自定义） |
| `_gpOnGraphChanged()` | 图数据变化时刷新属性面板 |
| `_gpOnStatus()` | 更新状态栏文字 |
| `_gpOnMenu()` | 处理菜单动作（新建、清空、缩放、删除、设置） |
| `_gpOnAttrChanged()` | 用户在 Inspector 改属性时更新图数据 |

---

## 6. Autoload 全局单例：到处都能用的「公共服务」

在 `project.godot` 的 `[autoload]` 段里注册了三个全局单例：

```ini
I18n="*res://src/autoload/i18n.gd"
Settings="*res://src/autoload/settings.gd"
GPAppState="*res://src/autoload/app_state.gd"
```

它们**不是** main.tscn 里的节点，而是 Godot 启动时自动创建并挂在 `root` 下的单例。任何脚本里都可以直接写 `I18n.xxx`、`Settings.xxx`、`GPAppState.xxx`。

### 6.1 I18n（翻译官）

```gdscript
var text: String = I18n.gpTr("symbol_lib.title")
```

- 维护一个中英对照的字符串表。
- 切换语言时发出 `gpLocaleChanged` 信号，所有订阅者刷新文字。
- 图元的显示名也走这里，所以切换语言时图元文字会变。

### 6.2 Settings（设置/字体管理员）

```gdscript
Settings.gpSymbolFont      # 当前图元字体
Settings.gpSymbolFontSize  # 当前图元字号
Settings.gpLocale          # 当前语言
```

- 启动时从 `user://settings.cfg` 读取设置。
- 提供字体预设（内置 Arial Unicode、冬青黑体等）。
- 字体变化时发出 `gpSymbolStyleChanged`，画布重绘图元。

### 6.3 GPAppState（工程状态管理员）

目前还是桩代码（函数都是 `pass`）。未来会负责：

- 当前打开的是哪个工程
- 是否有未保存修改
- 工程切换、新建、关闭

---

## 7. 代码规范：为什么变量都叫 `gpXxx`？

这是项目硬性约定，目的是避免和 Godot 内置名冲突，同时一眼看出是项目代码。

| 规则 | 例子 |
|------|------|
| 类名 | `GPPIDGraph`、`GPCanvas2D`、`GPSymbolView`（GP + PascalCase） |
| 函数/变量 | `gpAddNode`、`_gpPanning`、`gpViewZoom`（gp + camelCase） |
| 私有函数/变量 | 下划线开头，如 `_gpSyncViews`、`_gpSymbolViews` |
| 常量/枚举 | `GP_MODE_SELECT`、`GPSymbolCategory`（GP_ 或 GP 前缀） |
| 显式类型 | 所有变量必须写类型：`var gpX: int = 0`，禁止 `var x := 0` |
| 中英注释 | 每段注释英文一行 + 中文一行 |

---

## 8. 新手常见问题：我想加功能，该改哪里？

### 8.1 我想添加一种新图元（比如「压缩机」）

改 `src/core/symbol_library.gd` 的 `gpDefaultDefs()`：

```gdscript
gpOut.append(_gpMk("compressor", "压缩机", "compressor", Vector2(80, 56),
    [{"name": "in", "pos": [-40, 0]}, {"name": "out", "pos": [40, 0]}]))
```

如果想让「压缩机」有独特颜色，再改 `src/render/symbol_view.gd` 的 `_gpCategoryColor()`。

### 8.2 我想让画布支持右键菜单

改 `src/ui/canvas_2d.gd` 的 `_gui_input()`，在 `MOUSE_BUTTON_RIGHT` 分支里加逻辑。

### 8.3 我想保存图纸到文件

在 `GPPIDGraph.gpToDict()` 基础上，用 `FileAccess` 把 JSON 写到磁盘；读取时用 `GPPIDGraph.gpFromDict()` 恢复。

### 8.4 我想让 Inspector 显示更多属性

改 `src/ui/inspector.gd`，让它根据 `GPSymbolDef.gpAttrsSchema` 动态生成更多输入框。

---

## 9. 文件关系速查表

| 文件 | 依赖谁 | 被谁依赖 | 职责一句话 |
|------|--------|----------|-----------|
| `project.godot` | 无 | Godot 引擎 | 项目入口、窗口设置、Autoload 注册 |
| `scenes/main.tscn` | 无 | Godot 引擎 | 主窗口界面骨架 |
| `src/ui/main_window.gd` | 几乎所有 | 无（顶层） | 启动接线、总指挥 |
| `src/core/pid_graph.gd` | 无 | 画布、边视图、主窗口 | 图数据核心 |
| `src/core/symbol_def.gd` | 无 | 符号库、图元视图、主窗口 | 单个图元定义 |
| `src/core/symbol_library.gd` | symbol_def | 主窗口、工具栏 | 内置图元集合 |
| `src/ui/canvas_2d.gd` | pid_graph、symbol_def、symbol_view、edge_view | 主窗口 | 2D 画布交互与渲染 |
| `src/render/symbol_view.gd` | symbol_def、Settings/I18n | canvas_2d | 单个图元视觉 |
| `src/render/edge_view.gd` | pid_graph | canvas_2d | 单条连线视觉 |
| `src/ui/toolbar.gd` | symbol_library | 主窗口 | 左侧图元库 |
| `src/ui/inspector.gd` | symbol_def、I18n | 主窗口 | 右侧属性面板 |
| `src/ui/menu_bar.gd` | 无 | 主窗口 | 顶部菜单 |
| `src/autoload/i18n.gd` | 无 | 全项目 | 翻译 |
| `src/autoload/settings.gd` | 无 | 全项目 | 设置/字体 |
| `src/autoload/app_state.gd` | 无 | 全项目（未来） | 工程状态 |

---

## 10. 一句话总结

> **G-PID 把「P&ID 图纸」当成一份数据（GPPIDGraph）来管理；画布和视图只是这份数据的实时投影；UI 层负责接收用户操作并更新数据；Autoload 单例提供翻译、字体、工程等公共服务。**

只要记住「数据唯一、视图投影、信号驱动」这九个字，再看代码就会清晰很多。
