# DEXPI 覆盖报告 / DEXPI Coverage

> 由 `tools/gp_dexpi_coverage.gd -- --write` 生成；不要手改。
> **DO NOT EDIT** — regenerate with the command above.

- 标准 / Standard: `DEXPI 1.4 / Proteus 4.2.0`
- 报告哈希 / Report SHA-256: `17c25aae41468f1de7ceb207cff34906711990791ea48f435173dc85768a76a5`
- 生成命令 / Command: `HOME=/tmp/gpidhome godot --headless --script res://tools/gp_dexpi_coverage.gd -- --write`

## 概念类 / Concept symbols

| 项 | 数量 |
|---|---:|
| 映射图元 / mapped symbols | 24 |
| 类 + URI 已验证 / class + verified URI | 1 |
| 类已定、URI 待核实 / class, URI pending | 17 |
| 纯图形 / annotation-only | 6 |
| 无类 / no class | 6 |

### URI 缺口 / URI gaps

- `DGENERAL003` — class mapped, URI intentionally empty (not fabricated)
- `DGENERAL004` — class mapped, URI intentionally empty (not fabricated)
- `DGENERAL007` — class mapped, URI intentionally empty (not fabricated)
- `DGENERAL008` — class mapped, URI intentionally empty (not fabricated)
- `DGENERAL010` — class mapped, URI intentionally empty (not fabricated)
- `DGENERAL012` — class mapped, URI intentionally empty (not fabricated)
- `DHEAT001` — class mapped, URI intentionally empty (not fabricated)
- `DHEAT002` — class mapped, URI intentionally empty (not fabricated)
- `DINSTRUMENT001` — class mapped, URI intentionally empty (not fabricated)
- `DINSTRUMENT002` — class mapped, URI intentionally empty (not fabricated)
- `DPUMP002` — class mapped, URI intentionally empty (not fabricated)
- `DTANK001` — class mapped, URI intentionally empty (not fabricated)
- `DVALVE001` — class mapped, URI intentionally empty (not fabricated)
- `DVALVE002` — class mapped, URI intentionally empty (not fabricated)
- `DVALVE003` — class mapped, URI intentionally empty (not fabricated)
- `DVALVE004` — class mapped, URI intentionally empty (not fabricated)
- `DVALVE005` — class mapped, URI intentionally empty (not fabricated)

## 属性 / Attributes

| 项 | 数量 |
|---|---:|
| 映射属性 / mapped | 8 |
| URI 已验证 / verified URI | 0 |
| 无 URI / no URI | 7 |
| 内部 / internal (never exported) | 1 |

## 明确缺口 / Explicit gaps

- DEXPI 1.4 的 568 个类型中，本报告**只**声明上表映射到的图元；不声称 568 全量覆盖。
- 无 URI 的行是**刻意留空**，不是已验证；见 `GP_DEXPI_MAPPING` 的 URI 原则。
- 本报告不修改映射实现；缺口只能通过补表和验证 URI 关闭。

## 复算 / Reproduce

```bash
cd Godot-PID-Core
HOME=/tmp/gpidhome godot --headless --script res://tools/gp_dexpi_coverage.gd
```

JSON 中的 `REPORT_SHA256` 必须与上方哈希一致。