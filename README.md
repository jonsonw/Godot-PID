[简体中文](README.md) · [English](README.en.md)

# Godot-PID

基于 **Godot 引擎**的开源 **P&ID（管道及仪表流程图）编辑器**。

面向流程工业，如化工、石化、医药、食品、采矿、冶金等行业，把 P&ID 绘图、符号库管理、HAZOP 知识沉淀与导出做成一套可自托管的轻量工具。

## 命名

- **产品品牌：G-PID**
- **GitHub 仓库名：`Godot-PID`**
- **官网：[g-pid.com](https://g-pid.com)**

## 授权模式

核心代码以 **MIT 授权**发布，可自由使用、修改、再分发。

## 快速开始

1. 用 **Godot 4.3+** 打开本目录（即包含 `project.godot` 的目录）。
2. 按 **F5** 运行主场景 `scenes/main.tscn`。

## 目录结构

```
Godot-PID/                # GitHub 仓库根（本地工作文件夹为 Godot-PID-Core/）
├── project.godot          # Godot 项目文件
├── project.pid.json       # P&ID 数据契约示例
├── scenes/                # 主场景 / 画布场景 / 控件
├── src/
│   ├── core/              # PIDGraph、SymbolDef、PIDNode/Edge/Document、Session、PIDCommand
│   ├── model/             # FrameDef、SymbolPack
│   ├── render/            # 3D 联动渲染
│   ├── ai/                # 单元操作生成（规则引擎，不接云端）
│   ├── doc/               # 多文档管理
│   ├── export/            # DXF / PDF / 基础清单导出
│   ├── save/              # 存档/读档（单文件 *.pid.json）
│   ├── project/           # 工程库 / 注册表
│   ├── autoload/          # 全局单例（AppState）
│   ├── addons/            # 插件挂载点（IPIDAddon）
│   └── ui/                # 画布 / 工具栏 / 菜单栏 / 检查器 等
├── assets/                # 符号、主题、字体
└── tests/                 # 单元 / 冒烟测试
```

## 核心概念

- **`PIDGraph`** — 节点-边图内核，2D 画布、3D 联动、清单导出都读取它。
- **`SymbolDef`** — 数据驱动图元定义，避免为每个符号建一个类。
- **`IPIDAddon`** — 插件契约，外围功能通过继承此类挂载，核心代码不动。

## 贡献

欢迎以 Issue / PR 参与。图元采用 `SymbolDef` 数据驱动，新增符号零门槛。

---

Copyright © 2026 Jonson Wang
