# ADR-UI-01：Ribbon 式顶部命令栏

> 本 ADR 规定：主窗口顶部以 AutoCAD / Office 风格的 Ribbon（TabContainer）命令栏取代旧的扁平 DrawToolBar。

## Status / 状态

Accepted（代码引用见 `ui/shell/ribbon.gd:4`、`ui/shell/ribbon_coordinator.gd:67`、`ui/shell/main_window.gd:180`）

## Context / 背景

早期 `DrawToolBar` 是一行横向排开的扁平按钮。随着工具、模式、图元类别增多，扁平栏无法容纳分组、无法表达「同一功能在不同上下文下的子集」，且模式高亮 / 工具选中态只能散落在工具栏自身逻辑里。维护成本随功能增长非线性上升。

需要一个可扩展、可分组、能承载模式高亮的统一命令表面。

## Decision / 决策

1. **Ribbon 取代 DrawToolBar**：在菜单栏下方放置 `GPPIDRibbon`（TabContainer），按用例分 Tab，每 Tab 内分组排布命令按钮；
2. **命令经统一信号**：Ribbon 不直连业务，点击经 `gpActionTriggered(action: String)` 上抛，由 `GPMainWindow` 的 `match` 转发到对应协调者（与菜单同构，避免反向依赖）；
3. **模式高亮归 Ribbon 所有**：当前交互模式（选择 / 连线 / 绘图工具）的高亮态由 Ribbon 负责呈现，工具栏不直接管高亮；
4. **装配由协调者持有**：`GPRibbonCoordinator` 负责构建 Ribbon、样式、模式映射、图元拾取与工具选中转发，旧 `DrawToolBar` 同位置退役。

## Consequences / 后果

- 正向：命令表面可横向扩展（新增 Tab / 分组即可），且模式高亮有了单一归属，不再散落；
- 正向：Ribbon 与菜单共用「action 字符串 → 协调者」转发链，调用方零改动；
- 负向：Ribbon 的布局 / 样式 / DPI 适配代码多于旧扁平栏，且需与 `GPLayoutCoordinator` 的分隔条布局协同；
- 负向：旧 `DrawToolBar` 残留代码需待 Ribbon 稳定后清理（见架构优化 §5 P3 #6），清理前须保留「Ribbon 已接管」的断言防回退。
