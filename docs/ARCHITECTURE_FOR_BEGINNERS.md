# G-PID 架构学习：从真实代码读懂设计原则

> [!p] 阅读说明
> 这不是 API 手册，而是一堂**用你自己的项目当教材**的架构课。
> 本文基于 **2026-09-26** 基线（`src/**/*.gd` 175 文件 / 32,376 行），所有代码引用均已逐文件核对。
> 读完之后，你应该能回答三类问题：**Godot 的机制到底解决了什么问题**、**这套分层为什么长成这样**、**下次要加功能时该把代码放在哪一层**。

> [!b] 怎么读
> 第一、二部分是"看懂"，第三部分是"想通"，第四、五部分是"会用"，第六部分是"迁移到别的项目"。
> 如果时间有限，建议按 **§2 五层架构 → §3 设计原则落点 → §5.4 决策清单** 的顺序读。

---

## 导言：为什么"能跑的代码"不等于"好架构"

先看一个真实场景。项目里曾有一个 1,758 行的文件 `main_window.gd`，它能正常工作，但：

- 改一个"保存"逻辑，需要通读文件存取、菜单分发、快捷条装配、DPI 布局、对话框、图元级联删除、状态栏、关闭护栏 **八件事**
- 想为"关闭时提示保存"写个测试，必须先把整个窗口装配起来
- 两个人同时改这个文件，几乎必然冲突

它**能跑**，但**改不动、测不了、没法并行**。这就是架构问题的典型特征：**它不表现为 bug，而表现为"每次改动都让人心虚"**。

后来它被拆成 1 个 root（`main_window.gd`，610 行）+ 7 个协调者。本文要讲的，就是"为什么这样拆是对的"，以及背后的通用原则。

---

## §1 先懂 Godot：四个机制与它们对应的设计思想

Godot 的机制不是"语法糖"，每一个都在替你做架构决策。

### 1.1 节点（Node）= 组合优于继承

Godot 里没有"控件继承体系"，只有**节点树**。一个界面是"容器节点 + 叶子节点"的组合结果。

本项目 `scenes/main.tscn` 的骨架：

```
Main (Control)              ← 挂 GPMainWindow 脚本
├─ VLayout (VBoxContainer)
│  ├─ MenuBar (HBoxContainer)
│  ├─ Body (HSplitContainer)
│  │  ├─ LeftDock  (图元库)
│  │  ├─ Center    (标签页容器)
│  │  └─ RightDock (检查器)
│  └─ StatusBar (HBoxContainer)
└─ OverlayChrome (Control)
```

**只有约 30 个节点**——这个数字本身就是设计信号：界面复杂度没有堆在场景树里，而是被……（见 §1.3）。

> [!b] 原则落点：组合优于继承
> 如果你想让"带边框的、可滚动的、带标题的属性面板"，继承要写三层类；组合只需 `ScrollContainer > VBoxContainer > 表单`。**Godot 用节点树强制你走组合路线**——这是引擎层面帮你避开了继承爆炸。

### 1.2 场景（Scene）= 可复用的节点树

`.tscn` 文件就是"保存下来的节点树"。本项目刻意只用**一个**入口场景（`main.tscn`），其余界面全部由代码构造。

这是有意的权衡：

| 做法 | 好处 | 代价 |
|---|---|---|
| 多用 `.tscn` 场景 | 可视化编辑、结构清晰 | 加载期需解析每个场景；跨场景引用易形成隐式依赖 |
| 少用场景 + 代码构造 | 装配顺序可控、可 headless 测试 | 失去可视化编辑 |

本项目选后者，理由在 §3.8 会讲——**它换来了 2,901 条断言能在无窗口环境跑完**。

### 1.3 脚本（Script）= 挂在节点上的行为

一个 `.gd` 文件挂到一个节点上，就成为该节点的"大脑"。因为场景树只有约 30 个节点，**大量类根本不是节点**——它们是普通对象：

| 基类 | 用途 | 本项目示例 |
|---|---|---|
| `Node` / `Control` | 存在于场景树中，可发信号、可绘制 | `GPMainWindow`、`GPCanvas2D`、`GPInspector` |
| `RefCounted` | 纯内存对象，引用计数自动回收 | `GPPIDGraph`、`GPPIDNode`、`GPEdgeRoute` |
| `Resource` | 可序列化、可在编辑器里编辑 | `GPSymbolDef`、`GPPropertyDef` |

> [!a] 关键事实：本项目 `core/` 的 49 个类**没有一个**是 `Node`
> 这不是巧合。`Node` 意味着"必须存在于场景树"，而场景树需要一个运行中的引擎——那就无法在 headless 下测试。
> **选择基类 = 选择可测试性**。这是 §3.8 的地基。

### 1.4 信号（Signal）= 观察者模式的引擎级实现

信号是 Godot 内建的"发布-订阅"：

```gdscript
# ① 定义（GPCenterArea 里）
signal gpActiveChanged()

# ② 订阅（main_window 装配时）
gpCenter.gpActiveChanged.connect(_gpOnActiveTabChanged)

# ③ 触发
gpActiveChanged.emit()
```

关键价值：**发布者不知道谁在听**。`GPCenterArea` 换标签页时只负责 `emit()`，它不需要知道主窗口要刷新标题、状态栏要更新缩放。

> [!b] 原则落点：观察者模式
> 如果不用信号，`GPCenterArea` 就得持有 `main_window` 的引用并直接调用它——**这会让"下层组件"依赖"上层容器"，依赖方向就反了**。
> 信号把"我需要通知别人"和"别人是谁"解耦了。

### 1.5 autoload = 全局单例，以及为什么本项目只有三个

autoload 是引擎启动时自动实例化的全局对象，任何地方都能按名字访问。

**方便，但要付代价**：

- 它是**隐式依赖**——读代码时看不出某个函数依赖了全局状态
- 它是**全局可变状态**——测试之间会互相污染
- 它让**单元测试必须启动引擎**

所以本项目把它严格收敛到三个**纯环境态**单例：

| 单例 | 职责 | 为什么可以做全局 |
|---|---|---|
| `I18n` | 翻译 | 只读的词典，语言切换是全局事实 |
| `Settings` | 字体 / 字号 / 语言 / 偏好 | 配置文件驱动的只读状态 |
| `SnapState` | CAD 开关（正交、捕捉） | 全局交互偏好，工具需实时取用 |

而"当前文档、脏标记"这类**文档级状态**，改由 `GPAppDocumentManager` 承担——它**不是 autoload**，由主窗口持有。

> [!b] 原则落点：限制全局状态
> 判断标准很简单：**这个状态是"整个应用共享"，还是"某个文档/会话共享"？**
> 前者才配做 autoload。把早期的全局 `GPAppState` 换成 `GPAppDocumentManager`，换来的正是"可以同时持有两个文档对象做测试"。

### 1.6 关键约束：`--script` 运行时 `add_child()` 不触发 `_ready`

本项目的画布拆分有个实现细节值得学习：4 个实现类在 **`_init()` 构造期**装配，而不是 `_ready()`。

```gdscript
# src/ui/canvas/canvas_2d.gd —— 刻意放在构造期
func _init() -> void:
    gpViewController = GPCanvasViewController.new()
    gpInputRouter = GPCanvasInputRouter.new()
    ...
```

**原因**：以 `godot --headless --script res://tests/xxx.gd` 方式跑测试时，`add_child()` **不会**触发 `_ready`（`is_inside_tree()` 为 false）。若协作对象只在 `_ready` 里装配，headless 测试拿到的就是半成品对象。

> [!a] 可测试性会反向影响设计
> 这是一个极好的例子：**"能被测试"这个需求，直接决定了"对象在何时装配"这个设计决策**。
> 好的架构不是先设计再想测试，而是让测试约束参与设计。

---

## §2 五层架构：隔离的本质是"不知道"

### 2.1 分层总览

```svg
<svg viewBox="0 0 900 520" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system,PingFang SC,sans-serif">
  <defs>
    <marker id="d1" markerWidth="9" markerHeight="9" refX="7" refY="4.5" orient="auto">
      <path d="M0,0 L9,4.5 L0,9 z" fill="#5f5e5a"/>
    </marker>
  </defs>

  <rect x="60" y="20" width="780" height="66" rx="9" fill="#eeedfe" stroke="#3c3489" stroke-width="1.2"/>
  <text x="80" y="48" font-size="14.5" font-weight="600" fill="#3c3489">ui/ · 界面层 · 62 文件 / 13,402 行</text>
  <text x="80" y="70" font-size="11.5" fill="#3c3489">它知道：场景树、鼠标键盘、autoload。它不知道：业务规则细节（要问 app 层）</text>

  <path d="M250,86 L250,120" stroke="#5f5e5a" stroke-width="1.2" marker-end="url(#d1)"/>
  <path d="M450,86 L450,120" stroke="#5f5e5a" stroke-width="1.2" marker-end="url(#d1)"/>
  <path d="M650,86 L650,120" stroke="#5f5e5a" stroke-width="1.2" marker-end="url(#d1)"/>

  <rect x="150" y="126" width="200" height="60" rx="8" fill="#faeeda" stroke="#854f0b" stroke-width="1.2"/>
  <text x="166" y="150" font-size="13" font-weight="600" fill="#854f0b">app/ · 应用服务</text>
  <text x="166" y="170" font-size="11" fill="#854f0b">34 / 3,064 · 命令 + 事件</text>

  <rect x="360" y="126" width="180" height="60" rx="8" fill="#e1f5ee" stroke="#0f6e56" stroke-width="1.2"/>
  <text x="376" y="150" font-size="13" font-weight="600" fill="#0f6e56">io/ · 持久化</text>
  <text x="376" y="170" font-size="11" fill="#0f6e56">9 / 1,862 · 唯一文件 IO</text>

  <rect x="550" y="126" width="200" height="60" rx="8" fill="#e6f1fb" stroke="#185fa5" stroke-width="1.2"/>
  <text x="566" y="150" font-size="13" font-weight="600" fill="#185fa5">render/ · 渲染</text>
  <text x="566" y="170" font-size="11" fill="#185fa5">8 / 926 · 只读模型</text>

  <path d="M250,186 L250,222" stroke="#1f8a3b" stroke-width="1.6" marker-end="url(#d1)"/>
  <path d="M450,186 L450,222" stroke="#1f8a3b" stroke-width="1.6" marker-end="url(#d1)"/>
  <path d="M650,186 L650,222" stroke="#1f8a3b" stroke-width="1.6" marker-end="url(#d1)"/>

  <rect x="60" y="228" width="780" height="122" rx="10" fill="#f7f7f5" stroke="#2c2c2a" stroke-width="1.4"/>
  <text x="80" y="256" font-size="14.5" font-weight="600" fill="#2c2c2a">core/ · 领域内核 · 47 文件 / 8,213 行</text>
  <text x="80" y="280" font-size="11.5" fill="#2c2c2a">model(16) · geometry(9) · view(8) · service(7) · symbol(4) · platform(2) · constants(1)</text>
  <text x="80" y="303" font-size="11.5" fill="#0f6e56">它知道：图数据、几何算法、位号规则。它一无所知：UI、文件格式、autoload、Node</text>
  <text x="80" y="326" font-size="11.5" fill="#0f6e56">✓ 49 个类中 0 个是 Node → 可以完全 headless 测试 → 2,901 条断言的基础</text>
  <text x="80" y="345" font-size="11" fill="#5f5e5a">这是整个系统里最"纯"的一层：换掉 Godot，它几乎能原样搬到别的引擎</text>

  <rect x="60" y="366" width="380" height="52" rx="8" fill="#ffffff" stroke="#e2e0da" stroke-width="1.2"/>
  <text x="78" y="388" font-size="12" font-weight="600" fill="#2c2c2a">autoload/ · 3 文件 / 736 行</text>
  <text x="78" y="407" font-size="11" fill="#5f5e5a">I18n · Settings · SnapState（仅 ui 可依赖）</text>

  <rect x="460" y="366" width="380" height="52" rx="8" fill="#ffffff" stroke="#e2e0da" stroke-width="1.2"/>
  <text x="478" y="388" font-size="12" font-weight="600" fill="#2c2c2a">addons/ · 1 文件 / 55 行</text>
  <text x="478" y="407" font-size="11" fill="#5f5e5a">商业化契约 GPIPIDAddon（仅声明钩子）</text>

  <text x="60" y="450" font-size="12" font-weight="600" fill="#2c2c2a">依赖只能向下（箭头方向），永不向上、永不横穿：</text>
  <text x="60" y="472" font-size="11.5" fill="#5f5e5a">ui → app / io / render → core。实测反向引用 0 处，全项目无循环依赖。</text>
  <text x="60" y="494" font-size="11.5" fill="#1f8a3b">排除越层：render → autoload 曾 7 处，经 GPRenderStyle 依赖注入后为 0。</text>
</svg>
```

### 2.2 隔离的本质是"不知道"，不是"不调用"

初学者常把分层理解成"目录分类"。**不是**。分层的价值在于：**每一层对世界的认知被主动裁剪。**

| 层 | 它知道 | 它**刻意不知道** |
|---|---|---|
| `core` | 图数据、几何、规则 | UI 长什么样、文件格式、有没有窗口 |
| `app` | 用户意图、命令、事件 | 按钮叫什么、面板怎么摆 |
| `io` | 文件格式、JSON 结构 | 图元在屏幕上画成什么 |
| `render` | 怎么把模型画出来 | 谁触发的、为什么要画 |
| `ui` | 控件、输入、装配 | 存档格式的内部结构 |

**"不知道"换来的是"可以独立变化"**：

- `core` 不知道 UI → 可以给同一份数据换三套界面
- `render` 不知道谁触发 → 可以用在任何需要画图的地方（主画布、缩略图、打印）
- `io` 不知道 UI → 可以在命令行里批量转格式

> [!b] 一条实用的自检法
> 想问"这段代码该放哪层"，就问：**它需要知道什么？**
> 如果它需要知道"按钮的文本"，它属于 `ui`；如果它只需要知道"图里有哪些节点"，它属于 `core`。

### 2.3 已经用机器验证过的边界

架构文档里最常见的谎言是"我们遵守了分层"。本项目把它变成了**可执行检查**：

| 检查 | 实测 |
|---|---|
| `core` 引用 UI / render | **0** |
| `core` 引用 autoload | **0** |
| `core` 里基类是 `Node` 的类 | **0 / 47** |
| `app` 引用 UI | **0** |
| `io` / `render` → `ui` | **0** |
| 层间循环依赖 | **0** |

这些数字不是估算，是用源码检索跑出来的（见架构说明 §1.3）。

> [!b] 原则落点：让约束可验证
> "我们会遵守分层"是愿望；"`core` 里 autoload 引用必须为 0，且能被一条命令查出来"才是**约束**。
> 差别在于：前者靠自觉，后者靠机制。**能被推翻的约束才叫约束。**

---

## §3 六大设计原则在这里的具体落点

### 3.1 分层架构：为什么 `core` 必须不认识 UI

`core` 的 49 个类**全部**是 `RefCounted` 或 `Resource`，没有一个是 `Node`。

连锁反应是这样的：

```
core 不认识 Node
   ↓
core 不依赖场景树
   ↓
core 不需要运行中的引擎窗口
   ↓
core 可以在 headless 下实例化
   ↓
2,901 条断言能跑完（其中绝大多数测的是 core）
```

**这是一条因果链，不是巧合。** 如果某天有人为了方便，在 `core/model/pid_node.gd` 里加一句 `I18n.gpTr(...)` 来格式化显示名，这条链就断了——虽然功能上"能跑"，但 `core` 从此再也无法独立测试。

> [!a] 反例长什么样
> ```gdscript
> # ❌ 在 core 里这么写，等于把整层的可测试性抵押出去
> func gpDisplayLabel() -> String:
>     return I18n.gpTr("sym." + gpId)     # core 现在依赖 autoload 了
> ```
> 正确做法：`core` 只暴露**中性数据**（id、类型、原始名），由 `ui` 层负责翻译。
> 本项目图元显示名走 `iso.<id>` 键 + `I18n.gpTr`，**翻译动作发生在 `ui`/`render` 边界，而不是 `core` 内部**。

### 3.2 高内聚：一个类只回答一个问题

**内聚**的判据：这个类的所有方法，是否都在服务同一个概念？

看 `main_window.gd` 的拆分前后：

| | 拆分前 | 拆分后 |
|---|---|---|
| 文件行数 | 1,758 | 610（root）+ 7 个协调者 |
| 它要回答的问题 | 保存、打开、菜单、快捷条、DPI、对话框、图元删除、状态栏、关闭护栏（**9 个**） | 只回答"把各部件装配起来"（**1 个**） |
| 改保存逻辑要读多少行 | 通读 1,758 行 | 打开 `file_coordinator.gd` |
| 能否单独测试文件逻辑 | 不能（要装配整个窗口） | 能（协调者只依赖注入的宿主端口） |

拆分后的 7 个协调者，每个名字就是它所回答的问题：

- `GPFileCoordinator` —— "文件生命周期怎么走？"
- `GPLayoutCoordinator` —— "窗口尺寸变化时怎么摆？"
- `GPSelectionCoordinator` —— "选择变化后谁要刷新？"
- `GPTagRuleCoordinator` —— "位号规则怎么套用？"

> [!b] 内聚的反向指标
> 如果你需要给一个类写"注意事项"清单来说明"这里负责 A，但那里其实负责 B"，那它内聚不足。

还有一处**微观内聚**值得注意：`snap_resolver.gd` 的 `_gpSnapIntersection` 原本把 `_gpEdgePolyline()` 调用写在**边对循环内部**——同一个计算结果被重复求 O(E) 次。这不只是性能问题，也是内聚问题：**"解析折线"这件事的归属不清晰**，导致它被散落在循环里重复执行。修正后改为"按调用预算一次"，职责回到该有的位置。

### 3.3 低耦合：门面端口与依赖注入

#### (a) 门面端口（Facade）—— 隐藏内部结构

`GPCanvas2D` 是"1 个 root + 4 个实现类"的结构。**但外部调用方看到的仍然只有 `GPCanvas2D` 一个对象**（44 个公开端口）：

```gdscript
# ✅ 外部这样写（推荐）
gpCv.gpScreenFromWorld(worldPos)

# ❌ 而不是这样写（会把内部结构暴露给 800+ 个调用点 —— 实测 879 处）
gpCv.gpViewController.gpScreenFromWorld(worldPos)
```

**为什么这很重要**：假设明天要把 `gpViewController` 拆成两个类、或改个名字——第二种写法意味着要改 800 处调用；第一种写法只改门面里的 1 行。

> [!a] 一个真实踩坑（值得反复体会）
> 项目里有一批方法形如 `_gpRefreshSelection()`（下划线开头，看起来是私有），却被**其它类**调用。曾有判断认为"这是冗余转发壳，应该删掉，让调用方直连协调者"。
> 逐一核查后发现**恰恰相反**：它们正是门面端口。删掉它们，等于把 `gpViewController` / `gpEditFacade` / `gpSymbolLayer` 的内部结构暴露给全部调用点——**耦合会上升，不是下降**。
> 最终处理是把这 11 个方法**去下划线改为公开**（`gpRefreshSelection()`），消除"私有命名却公开使用"的语义矛盾，同时保住门面。
>
> **教训**：判断一个方法是"冗余"还是"门面"，依据不是它的名字，而是**调用方在不在本类**。

#### (b) 依赖注入 —— 让下层不反向依赖

`render` 层需要字体和语言信息，而这两者原本来自 autoload。直接读取会造成**反向依赖**（`render` 在依赖链上位于 `ui` 之下，却去读全局单例）。

本项目把它收敛成一个**值对象** `GPRenderStyle`：

```
Settings / I18n（autoload）
      ↓  ui 层在装配时读取
   GPRenderStyle（纯数据快照）
      ↓  注入
   render 层的每个视图
```

于是 `render` 变成这样取用：

```gdscript
# src/render/symbol_view.gd
gpRenderStyle.gpFontSize    # 从注入的样式取，而不是 Settings.gpSymbolFontSize
```

好处有三个：`render` 可以脱离 autoload 测试；语言切换变成**显式重推**而不是隐式全局读取；`render` 的依赖在构造函数签名里**看得见**。

> [!b] 原则落点：依赖注入的本质
> 不是"用了某个框架"，而是**把"我从哪里拿依赖"变成"别人给我依赖"**。
> 前者是隐式的、难以替换的；后者是显式的、可测试的。

### 3.4 职责分离：命令模式 + 事件总线

本项目对"修改数据"这一件事，做了非常严格的职责切分：

| 关注点 | 谁负责 | 谁**不**负责 |
|---|---|---|
| 用户想干什么 | `GPEditService`（翻译意图） | 命令不知道自己为何被创建 |
| 怎么改数据 | `GPCommand.do()` | 命令不知道怎么撤销界面 |
| 怎么撤销 | `GPCommand.undo()` | 命令栈不知道数据的语义 |
| 谁需要知道变了 | `GPEventBus`（广播事实） | 发布者不知道订阅者是谁 |
| 界面怎么刷新 | 各 UI 组件自行订阅 | 模型不反向调用 UI |

一处能说明问题的真实细节：`GPSelectionCoordinator` 的选择处理函数原本既要刷新状态栏、又要刷新属性面板，还得靠**比对字符串**猜测"选择是否变化了"。后来画布显式发射了 `gpSelectionChanged` 事件，这个函数就**瘦身回只负责状态栏**——单一职责。

> [!b] 三个原则在这一个改动里同时体现
> - **职责分离**：状态栏和属性面板各自订阅
> - **低耦合**：不再靠"猜"（比对字符串），改为显式事件
> - **可维护性**：以后要加"第三个东西响应选择变化"，只需新增订阅者，不改发布者

### 3.5 开闭原则：对扩展开放，对修改关闭

#### (a) 画布工具注册表

新增一种画布交互（比如"测量长度工具"）：

1. 在 `ui/tools/` 新建一个文件，`extends GPCanvasTool`
2. 在 `GPCanvasToolRegistry` 加一行注册

**`GPCanvas2D` 主体一行不改。**

这就是开闭原则的教科书形态：扩展点是**注册表**，而不是"在某个巨型 `if-else` 里加一个分支"。

#### (b) 数据驱动的图元库

图元不是硬编码的类，而是由 `tools/gen_symbol_packs.py` 的 `CATEGORY_SCHEMA` 声明几何与端口，生成到 `core/symbol/symbol_packs/`。

新增"压缩机"图元：改 schema + 跑生成器 + 补 i18n 词条。**没有一行 `if symbol == "compressor"`。**

#### (c) 商业化扩展契约

`GPIPIDAddon`（`src/addons/ipid_addon.gd`，仅 55 行）声明了插件钩子：注册工具 / 面板 / 导出器 / 图元包 / 图变更回调。

关键设计：**开源仓里没有任何加载器**。这意味着开源核心完全不知道商业版存在——商业版在编译期就被隔离，不会污染开源代码，也不占用开源用户的启动时间。

### 3.6 单一真相来源（SSOT）：模型是唯一的

`GPPIDGraph` 是唯一的数据真相。渲染层不缓存"自己那份数据"，UI 也不持有副本。

一个具体体现是**持久化**：`core/model` 只暴露 `gpToDict()` / `gpFromDict()`，**新增字段一律在 dict 上做变换**。

```gdscript
# 新增字段的规范写法
func gpToDict() -> Dictionary:
    var gpD: Dictionary = { "id": gpId, "from": gpFrom }
    if gpOrtho:                       # ← 仅在非默认值时写出
        gpD["ortho"] = gpOrtho
    return gpD

func gpFromDict(gpD: Dictionary) -> void:
    gpOrtho = gpD.get("ortho", true)  # ← 一律带默认值
```

> [!b] 为什么"仅在非默认值时写出"这么重要
> 它保证**旧存档文件的字节序列保持稳定**。如果每次保存都把所有字段写出，那么一次"只是打开又保存"的操作也会让文件 diff 满天飞，版本控制失去意义，用户也会怀疑"我什么都没改，为什么文件变了"。
> 这是**可逆性**思维在数据格式上的体现。

### 3.7 可逆性：为什么首选"容易改回去"的方案

架构决策里有一条常被忽略的原则：**优先选容易撤回的方案**，而不是当下最优的方案。

本项目的三个实例：

| 决策 | "最优"方案 | 实际选择（更可逆） | 理由 |
|---|---|---|---|
| 保存策略 | 自动保存（体验好） | **显式 Ctrl+S 为主**（ADR-7） | 自动保存一旦出错会静默毁数据；显式保存的失败是可见的、可回滚的 |
| 导入冲突 | 覆盖（干净） | **派生新值**（非破坏，ADR-6） | 覆盖不可逆；派生可以事后手工合并 |
| 迁移链 | 转换后原地覆盖 | **只读路径迁移 + 幂等** | 迁移出错时原始数据仍在 |

> [!b] 原则落点：可逆性
> 问自己：**如果这个决定是错的，我多久能发现、要付出什么代价撤回？**
> "自动保存 + 覆盖导入"的问题在于——你通常要等到数据已经没了才发现它错了。

### 3.8 可测试性：分层换来的钱，最终在这里兑现

把前面所有原则串起来，最终收益集中体现在测试上：

| 因为…… | 所以…… |
|---|---|
| `core` 不依赖 UI / autoload | 2,901 条断言在 headless 下跑完（约 6–17 秒） |
| 命令模式可自我求逆 | 每条命令都能测"执行 → 撤销 → 重做"的一致性 |
| 几何函数全静态无状态 | 给定输入就有确定输出，无需搭建环境 |
| 门面端口稳定 | UI 测试可以驱动真实 `main.tscn` 而不碰内部结构 |
| 装配在 `_init()` 而非 `_ready()` | `--script` 模式下也能拿到完整接线的对象 |

> [!b] 一个反直觉的推论
> **"能不能测"往往不是测试技巧问题，而是架构问题。**
> 当你说"这个函数没法测"，通常真实原因是：它同时依赖了全局状态、UI 和文件系统——**这是分层失败的信号，不是测试的锅。**

---

## §4 一个请求的完整旅程

### 4.1 放置图元：从一次鼠标点击到画面出现

```svg
<svg viewBox="0 0 900 400" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system,PingFang SC,sans-serif">
  <defs>
    <marker id="e1" markerWidth="8" markerHeight="8" refX="6.5" refY="4" orient="auto">
      <path d="M0,0 L8,4 L0,8 z" fill="#185fa5"/>
    </marker>
    <marker id="e2" markerWidth="8" markerHeight="8" refX="6.5" refY="4" orient="auto">
      <path d="M0,0 L8,4 L0,8 z" fill="#0f6e56"/>
    </marker>
  </defs>

  <rect x="30" y="24" width="180" height="52" rx="8" fill="#eeedfe" stroke="#3c3489" stroke-width="1.1"/>
  <text x="46" y="46" font-size="12" font-weight="600" fill="#3c3489">① 图元库点击</text>
  <text x="46" y="64" font-size="10.5" fill="#3c3489">GPSymbolPaletteItem</text>

  <path d="M210,50 L290,50" stroke="#185fa5" stroke-width="1.4" marker-end="url(#e1)"/>
  <text x="216" y="42" font-size="10" fill="#5f5e5a">signal</text>

  <rect x="296" y="24" width="190" height="52" rx="8" fill="#eeedfe" stroke="#3c3489" stroke-width="1.1"/>
  <text x="312" y="46" font-size="12" font-weight="600" fill="#3c3489">② 协调者接单</text>
  <text x="312" y="64" font-size="10.5" fill="#3c3489">GPRibbonCoordinator</text>

  <path d="M486,50 L560,50" stroke="#185fa5" stroke-width="1.4" marker-end="url(#e1)"/>
  <text x="492" y="42" font-size="10" fill="#5f5e5a">记录待放置</text>

  <rect x="566" y="24" width="200" height="52" rx="8" fill="#eeedfe" stroke="#3c3489" stroke-width="1.1"/>
  <text x="582" y="46" font-size="12" font-weight="600" fill="#3c3489">③ 画布点击</text>
  <text x="582" y="64" font-size="10.5" fill="#3c3489">GPPlaceTool 捕获</text>

  <path d="M666,76 L666,118" stroke="#185fa5" stroke-width="1.4" marker-end="url(#e1)"/>
  <text x="674" y="102" font-size="10" fill="#5f5e5a">gpRequestAddNode(defId, pos)</text>

  <rect x="500" y="124" width="266" height="54" rx="8" fill="#faeeda" stroke="#854f0b" stroke-width="1.2"/>
  <text x="516" y="146" font-size="12" font-weight="600" fill="#854f0b">④ GPEditService（唯一入口）</text>
  <text x="516" y="165" font-size="10.5" fill="#854f0b">把「用户意图」翻译成一条命令</text>

  <path d="M500,151 L420,151" stroke="#0f6e56" stroke-width="1.4" marker-end="url(#e2)"/>
  <text x="428" y="143" font-size="10" fill="#5f5e5a">创建</text>

  <rect x="196" y="124" width="218" height="54" rx="8" fill="#faeeda" stroke="#854f0b" stroke-width="1.2"/>
  <text x="212" y="146" font-size="12" font-weight="600" fill="#854f0b">⑤ GPAddNodeCommand</text>
  <text x="212" y="165" font-size="10.5" fill="#854f0b">do() / undo() 自成一对</text>

  <path d="M196,151 L120,151" stroke="#2c2c2a" stroke-width="1.4" marker-end="url(#e1)"/>
  <text x="126" y="143" font-size="10" fill="#5f5e5a">写入</text>

  <rect x="20" y="124" width="96" height="54" rx="8" fill="#f7f7f5" stroke="#2c2c2a" stroke-width="1.3"/>
  <text x="34" y="146" font-size="11.5" font-weight="600" fill="#2c2c2a">⑥ GPPIDGraph</text>
  <text x="34" y="164" font-size="10" fill="#5f5e5a">唯一真相</text>

  <path d="M68,178 L68,222" stroke="#0f6e56" stroke-width="1.4" marker-end="url(#e2)"/>
  <text x="76" y="204" font-size="10" fill="#5f5e5a">广播</text>

  <rect x="20" y="228" width="200" height="50" rx="8" fill="#faeeda" stroke="#854f0b" stroke-width="1.1"/>
  <text x="34" y="250" font-size="11.5" font-weight="600" fill="#854f0b">⑦ GPEventBus</text>
  <text x="34" y="268" font-size="10" fill="#854f0b">图变更 / 状态更新事件</text>

  <path d="M220,253 L320,253" stroke="#0f6e56" stroke-width="1.4" marker-end="url(#e2)"/>

  <rect x="326" y="228" width="220" height="50" rx="8" fill="#e6f1fb" stroke="#185fa5" stroke-width="1.1"/>
  <text x="340" y="250" font-size="11.5" font-weight="600" fill="#185fa5">⑧ GPGraphBinder</text>
  <text x="340" y="268" font-size="10" fill="#185fa5">增量同步（不是全量重建）</text>

  <path d="M546,253 L640,253" stroke="#185fa5" stroke-width="1.4" marker-end="url(#e1)"/>

  <rect x="646" y="228" width="200" height="50" rx="8" fill="#e6f1fb" stroke="#185fa5" stroke-width="1.1"/>
  <text x="660" y="250" font-size="11.5" font-weight="600" fill="#185fa5">⑨ render 重绘</text>
  <text x="660" y="268" font-size="10" fill="#185fa5">GPSymbolView 等</text>

  <path d="M746,278 L746,312" stroke="#2c2c2a" stroke-width="1.4" marker-end="url(#e1)"/>

  <rect x="596" y="318" width="250" height="50" rx="8" fill="#ffffff" stroke="#2c2c2a" stroke-width="1.2"/>
  <text x="610" y="340" font-size="11.5" font-weight="600" fill="#2c2c2a">⑩ GPCommandStack 压栈</text>
  <text x="610" y="358" font-size="10" fill="#5f5e5a">Ctrl+Z 时按此命令撤销</text>

  <text x="30" y="340" font-size="11.5" fill="#5f5e5a">数据流是单向的：</text>
  <text x="30" y="360" font-size="11.5" fill="#5f5e5a">写入只能向下走命令，</text>
  <text x="30" y="380" font-size="11.5" fill="#5f5e5a">通知只能向上走事件。</text>
</svg>
```

值得注意的是 **⑧ 增量同步**：模型变化后，`GPGraphBinder` 只增删变化的视图节点，而不是清空重建。这是一个"性能优化"，但它的前提是**架构允许**——因为视图是"数据的投影"（纯函数式关系），所以才能算出差量。如果视图自己持有状态，增量同步根本无从下手。

### 4.2 撤销：命令模式的价值演示

```gdscript
# 伪代码，展示契约
var gpCmd: GPCommand = GPAddNodeCommand.new(ctx, defId, pos)
gpCmd.do()                       # 执行
gpStack.gpPush(gpCmd)            # 压栈
...
gpStack.gpUndo()                 # 内部调用 gpCmd.undo()，模型精确回滚
gpStack.gpRedo()                 # 复用同一个 gpCmd 对象，再次 do()
```

**为什么"复用同一个对象"很重要**：如果重做时新建一个命令，命令里保存的上下文（比如临时 id、快照）就得重建，很容易出现"重做后状态和执行时不一致"的诡异 bug。复用则天然一致。

这也是"职责分离"的收益：`GPCommandStack` 不需要理解"添加节点"是什么意思，它只知道"有这么个东西，能 do 能 undo"。

### 4.3 保存：原子写与失败回滚

```
① 写入 <file>.tmp
② 校验 tmp 内容（能读回、schema 合法）
③ 备份原文件为 <file>.bak
④ rename tmp → 目标文件（原子操作）
   任一步失败 → 回滚，原文件保持不变
```

> [!b] 原则落点：失败是常态，不是例外
> 幼稚的实现是"直接覆盖原文件"。问题是：如果写到一半断电/磁盘满，用户的图纸就**永久损坏**了。
> 原子写的思路是——**永远不要让"原始数据"处于可能损坏的中间态**。先写副本、校验、再原子替换。
> 这个思路可以迁移到任何"重要数据的更新"场景。

---

## §5 动手改代码

### 5.1 我要加一种图元

| 步骤 | 位置 |
|---|---|
| ① 声明几何与端口 | `tools/gen_symbol_packs.py` 的 `CATEGORY_SCHEMA` |
| ② 生成 | 运行生成器 → 产出到 `core/symbol/symbol_packs/` |
| ③ 补翻译 | `src/autoload/i18n.gd` 的 `GP_STRINGS`，键为 `iso.<id小写>` |
| ④（可选）商业图元 | 经 `GPIPIDAddon` 钩子挂载，不动开源仓 |

> [!a] id 不能手写
> 图元 id 遵循 `<来源码><类别码><三位序号>`，**必须**由 `GPSymbolNaming.gpAllocate` 分配。
> 手写 id 会在插入新图元时造成序号冲突——这类问题在测试里表现为"图元对不上号"，很难排查。

### 5.2 我要加一个编辑操作（比如"对齐选中图元"）

| 步骤 | 位置 |
|---|---|
| ① 新建命令类，实现 `do()` / `undo()` | `src/app/commands/gp_align_nodes_command.gd` |
| ② 保证自我求逆 | `undo()` 必须精确还原，不重建对象 |
| ③ 暴露意图入口 | `GPEditService` 加 `gpRequestAlignNodes(...)` |
| ④ 接入 UI | 在菜单 / 快捷条里加一项，**必须通过 UI 暴露** |
| ⑤ 补测试 | `tests/gp_test_*.gd`，覆盖"执行 → 撤销 → 重做" |

### 5.3 我要加一个画布交互工具

| 步骤 | 位置 |
|---|---|
| ① 新建工具类 | `src/ui/tools/`，`extends GPCanvasTool` |
| ② 经上下文取协作者 | 用 `GPCanvasToolContext`，**不要直接抓 `gpCv` 内部成员** |
| ③ 注册 | `GPCanvasToolRegistry` 加一行 |
| ④ 画布主体 | **无需改动** ← 这就是抽象的价值 |

### 5.4 决策清单：这段代码该放哪层？

| 你的逻辑是…… | 放这里 | 原因 |
|---|---|---|
| 判断两个图元是否重叠 | `core/model` 或 `core/geometry` | 纯计算，无 UI |
| 计算连线怎么走 | `core/geometry`（`GPEdgeRoute`） | 几何算法，渲染与命中测试共用 |
| 把"用户拖了图元"变成可撤销操作 | `app/commands` + `GPEditService` | 变更必须走命令 |
| 读/写 `.pid.json` | `io` | 只有这层能碰文件 |
| 决定图元在屏幕上什么颜色 | `render` | 只读模型的绘制 |
| 响应按钮点击 | `ui` | 唯一的交互层 |
| 显示一句提示文案 | `ui` + `I18n.gpTr` | 翻译发生在 UI 边界 |

> [!b] 一个高频错误
> **把业务规则写在 UI 事件处理函数里。** 例如"连线前检查端口类型是否匹配"——如果写在 `ui/tools/` 里，那么批量导入图纸时就无法复用这个校验。
> 正确做法：规则属于 `core`（可测、可复用），`ui` 只负责"触发它并展示结果"。

---

## §6 从本项目提炼的六条架构思维

### 6.1 每当想加抽象，先问"它省掉了什么"

本项目每个抽象都有代价也有收益：

| 抽象 | 省掉了什么 | 代价 |
|---|---|---|
| 门面端口（Facade） | 调用方对内部结构的依赖 | 多一层转发 |
| 命令模式 | 撤销逻辑的重复实现 | 每条命令要写 `undo()` |
| 事件总线 | 组件之间的直接引用 | 调用链变隐式，调试需查订阅关系 |
| 数据驱动图元库 | 每加图元写一个类 | 要维护生成器 schema |

**没有"纯粹的好抽象"**。如果某个抽象说不出它省掉了什么，那它大概只是增加了一层。

### 6.2 权衡而不是"最佳实践"

同一个问题在本项目里的两个相反选择：

| 场景 | 选择 | 为什么 |
|---|---|---|
| 界面构建 | 集中在一个 `main.tscn` + 代码装配 | 要可 headless 测试 |
| 图元定义 | 数据驱动的生成器 | 要可批量扩展 |

若"最佳实践"有唯一答案，这两个选择不可能同时成立。**决策的依据是约束，不是教条。**

### 6.3 用实测代替直觉（本项目的四堂反直觉课）

这四条都是本项目真实踩过、并用数据纠正过的：

**① "拆分大文件能让启动变快"——错。**

正序/逆序对照实验显示：约 850 ms 的 `main.tscn` 加载成本是**整个 UI 依赖图的一次性解析成本**，谁先加载谁买单（`main_window.gd` 单独先加载 = 842 ms，其余文件随后全部 0 ms）。
→ **拆分只改变"记账归属"，不减少总成本。** 拆分的理由只能是可维护性。

**② "关掉测试插件会让 CI 跑不了"——错。**

实测：关闭 GUT 编辑器插件后，`gut_cmdln.gd` 命令行门禁照常运行。
→ 编辑器插件（常驻，占编辑器启动 2.3–2.6 秒 ≈ 35%）与命令行运行器是**两条独立路径**。两者混为一谈会让"优化编辑器启动"变成不敢碰的事。

**③ "带下划线的转发方法都是冗余，删掉能降低耦合"——错。**

核查发现它们是被 800+ 处调用的**门面端口**。删掉会让调用方直连内部实现类，**耦合上升**。
→ 判断依据是**调用方位置**（在不在本类），不是命名。最终改为"去下划线公开"而非删除。

**④ "最大的问题一定在最大的文件里"——错。**

按**文件行数**排序时，`center_area.gd`（543 行）根本排不进前十；但按**函数体行数**扫描才发现，
全项目最长的函数（139 行的 `_ready`）就住在它里面 —— 比当时 1,011 行的 `canvas_2d` 里最长的函数还大。
→ **度量单位的选取会决定你看见什么问题。** 想找"哪里最难改"，就要按**函数**度量，而不是按**文件**。
  本项目因此补做了一次全项目函数扫描，把 4 个藏在"不大"文件里的超长函数挖了出来。

> [!b] 方法论
> 直觉在架构决策里**不可靠**，因为架构问题的因果链通常很长。
> 养成习惯：**在改动前，先用最小的实验把假设量化。** 本项目三次都用了几十行临时脚本 + headless 计时，成本极低，但避免了三次错误决策。

### 6.4 让约束可被机器验证

"我们会遵守分层"是愿望；下面这些才是约束：

| 约束 | 验证方式 |
|---|---|
| `core` 不依赖 UI / autoload | 源码检索，计数必须为 0 |
| 新增测试套件必须被加载 | `GP_EXPECTED_SUITES` 常量必须与实际套件数一致，否则 GUT 红灯 |
| 旧存档字节稳定 | 持久化往返测试 |
| 遗留死代码不得复活 | "正向钉"测试断言该定义**必须仍在**（或必须已删除） |
| 命令可逆 | 每条命令的"执行→撤销→重做"一致性断言 |

> [!b] 判据
> **一个约束如果无法被一条命令推翻，它就不是约束，而是口号。**

### 6.5 给未来的自己留线索

注释与文档的写法，本项目确立了明确边界：

| 该写 | 不该写 |
|---|---|
| 这段代码**是什么**（组件职责） | 变更记录 / 版本流水 |
| 为什么**只能这样写**（约束、反直觉点） | "原来是 X，后来改成 Y"（历史叙述） |
| 引用的决策依据（ADR 编号、设计文档章节） | 里程碑标记（M3 / P2 之类） |
| 外部约束（引擎限制、时序要求） | 作者与日期签名 |

> [!a] 一个具体对照
> ```gdscript
> # ❌ 无信息量 + 会过时
> # 原来这里是直接调 _gpReflow，后来改成公开端口了（P2 重构 · M3）
>
> # ✅ 解释约束，永不过时
> # 刻意不写类型标注：一旦标注，编译器会在启动期解析该类并把它拉进启动依赖图，
> # 延迟加载便形同虚设。
> ```
> 第二种注释即使在两年后读到，仍然**有效且有用**——因为它描述的是"为什么不能那样写"，而不是"曾经是什么样"。

### 6.6 一次只解决一类问题

本项目最近一轮改动的排序值得参考——**先做零风险的，再做有风险的**：

| 顺序 | 改动 | 风险 | 收益 |
|---|---|---|---|
| 1 | 关闭常驻编辑器插件 | 零（已验证 CLI 不受影响） | 编辑器启动 -2.3~2.6 s |
| 2 | 移除 45.6 MB 字体改 SystemFont | 低（有备份、验证中文覆盖） | 运行时 -65~126 ms，仓库瘦身 82 MB |
| 3 | 修 `O(E²·V²)` 交点捕捉 | 低（局部改动 + 回归钉） | 300 条边时 **116×** |
| 4 | 削减启动依赖图 | 中（牺牲 3 处静态类型检查） | 启动 **-20%** |
| 5 | 装配拆分 / 死壳清理 / 门面改名 | 中（需全量回归） | 可维护性 |

> [!b] 排序原则
> **按"收益/风险比"排，而不是按"收益绝对值"排。** 收益再大，若风险不可控且无法回滚，也不该排在前面。
> 每一档改完都跑完整门禁——这样任何一步出问题，都只可能是**最近这一步**的问题。

---

## §7 术语表与常见误区

### 7.1 术语速查

| 术语 | 在本项目里指什么 |
|---|---|
| **领域模型 / `core/model`** | 图数据本身（节点、边、图元定义、属性） |
| **命令（Command）** | 一次可撤销的模型变更，自我求逆 |
| **协调者（Coordinator）** | `main_window` 拆分出的专职对象，各自负责一类用例 |
| **门面端口（Facade Port）** | host 对外暴露的公开方法（`gp*`），隐藏内部协作结构 |
| **依赖注入** | 上层把值对象（如 `GPRenderStyle`）推给下层，而非下层自己读全局 |
| **事件总线（Event Bus）** | 领域事件的发布/订阅中枢 |
| **落点恢复** | 图元压到连线上导致拓扑改写时，记录原状以便删除时还原 |
| **正向钉（Regression Pin）** | 断言"某段代码必须仍在/必须已删除"的测试 |
| **门禁（Gate）** | 六道必过的验证（import / 编译 / GPGTest / GUT / check-only / 冒烟） |

### 7.2 常见误区

| 误区 | 事实 |
|---|---|
| "分层就是把文件放进不同目录" | 分层的本质是**认知裁剪**：每层主动不知道某些事 |
| "带下划线的一定该删/该私有" | 判断依据是**调用方在不在本类**，不是命名 |
| "拆分大文件能提升性能" | 启动成本是依赖图的一次性成本，拆分不减少它 |
| "能跑就行，架构是以后的事" | 架构债的利息表现为"每次改动都心虚"，越晚还越贵 |
| "注释要写下改动历史" | 历史注释会过时且误导；只写"是什么/为什么不能那样写" |
| "自动保存更友好" | 出错时静默毁数据；显式保存的失败是可见可回滚的 |
| "测试是测试工程师的事" | 在分层良好的项目里，**可测试性是设计产物**，不是测试技巧 |

### 7.3 下一步可以自己做的练习

1. 打开 `src/app/commands/`，挑一条最简单的命令（如 `gp_set_name_command.gd`），读它的 `do()` / `undo()`，然后**自己写一个**"把选中节点按 X 坐标排序"的命令
2. 打开 `src/core/geometry/edge_route.gd`，理解 `gpRoute()` 为什么必须被所有折线场景共用
3. 跑一次六门门禁（命令见架构说明 §7.2），观察每道门在防什么
4. 找一个 `ui/` 里"顺手写了业务判断"的地方，试着把它挪到 `core` 并补一条测试

---

> [!p] 结语
> 这套架构最值得学的不是"它拆成了几层"，而是**每个决策背后都有能被验证的理由**：
> 为什么只有 3 个 autoload、为什么 `core` 里没有 Node、为什么门面方法不删而改名、为什么拆分文件不加速启动。
> 当你下次面对自己的项目时，希望你能问出同样的问题——
> **"我这样做的依据是什么？如果它是错的，我多久能发现、要付出什么代价撤回？"**
