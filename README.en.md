[简体中文](README.md) · [English](README.en.md)

# Godot-PID

An open-source **P&ID (Piping and Instrumentation Diagram) editor** built on the **Godot engine**.

A self-hostable, lightweight tool for process industries — chemical, petrochemical, pharmaceutical, food, mining, smelting, and more — covering P&ID drawing, symbol library management, HAZOP knowledge capture, and export.

## Naming

- **Product brand: G-PID**
- **GitHub repo: `Godot-PID`**
- **Official site: [g-pid.com](https://g-pid.com)**

## License

The core code is released under the **MIT License** — free to use, modify, and redistribute.

## Quick Start

1. Open this directory (the one containing `project.godot`) with **Godot 4.3+**.
2. Press **F5** to run the main scene `scenes/main.tscn`.

## Directory Structure

```
Godot-PID/                # GitHub repo root (local working folder: Godot-PID-Core/)
├── project.godot          # Godot project file
├── project.pid.json       # P&ID data contract sample
├── scenes/                # Main & canvas scenes / widgets
├── src/
│   ├── core/              # PIDGraph, SymbolDef, PIDNode/Edge/Document, Session, PIDCommand
│   ├── model/             # FrameDef, SymbolPack
│   ├── render/            # 3D linkage rendering
│   ├── ai/                # Unit-operation generation (rule engine, no cloud)
│   ├── doc/               # Multi-document management
│   ├── export/            # DXF / PDF / basic list export
│   ├── save/              # Save/load (single *.pid.json)
│   ├── project/           # Project hub / registry
│   ├── autoload/          # Global singleton (AppState)
│   ├── addons/            # Addon mount point (IPIDAddon)
│   └── ui/                # Canvas / toolbar / menu bar / inspector, etc.
├── assets/                # Symbols, themes, fonts
└── tests/                 # Unit & smoke tests
```

## Core Concepts

- **`PIDGraph`** — node-edge graph core; read by the 2D canvas, 3D linkage, and BOM export.
- **`SymbolDef`** — data-driven symbol definition; avoids a class per symbol.
- **`IPIDAddon`** — addon contract; peripheral features mount via subclassing without touching core code.

## Contributing

Contributions are welcome via Issues / PRs. Symbols are `SymbolDef`-driven, so adding a new one has near-zero friction.

---

Copyright © 2026 Jonson Wang
