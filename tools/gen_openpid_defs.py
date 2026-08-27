#!/usr/bin/env python3
# tools/gen_openpid_defs.py
# Generate src/core/open_pid_icons_defs.gd from assets/symbol_packs/open-pid-icons/manifest.json.
# 从 open-pid-icons/manifest.json 生成图元定义脚本 src/core/open_pid_icons_defs.gd。
#
# It reuses the SVG path parser from svg_to_gpsym.py to turn each icon's path "d" into a
# UNIFORMLY normalized vector shape spec (GPSymbolDef.gpShape):
#   * the glyph bbox is scaled by min(100/bw, 100/bh) * FIT_MARGIN and centered in a 100x100
#     unit box, so the aspect ratio is preserved (a flat valve stays flat, a tall tank stays tall);
#   * the resulting unit-space bbox is emitted as gpShape["box"], which GPSymbolPainter uses to
#     derive the render-time uniform scale min(rect.w/box.w, rect.h/box.h);
#   * gpDefaultSize is NOT the raw SVG size any more — it is the CATEGORY nominal envelope from
#     src/core/symbol_categories.gd, so every member of a family renders at the same size;
#   * SVG anchors become ports normalized 0..1 against that nominal envelope.
# 复用 svg_to_gpsym.py 的 SVG 路径解析器，把每个图元的 path "d" 转成「均匀」归一化的矢量形状
# 规格（GPSymbolDef.gpShape）：
#   * 字形包围盒按 min(100/bw, 100/bh) * FIT_MARGIN 缩放并在 100x100 单位框内居中，保留长宽比
#     （扁阀门仍扁、高储罐仍高）；
#   * 归一化后的单位空间包围盒写入 gpShape["box"]，供 GPSymbolPainter 推导渲染期均匀缩放系数
#     min(rect.w/box.w, rect.h/box.h)；
#   * gpDefaultSize 不再是原始 SVG 尺寸，而是取自 src/core/symbol_categories.gd 的「类别」标称
#     包络，使同族图元恒为等大；
#   * SVG 锚点换算为相对该标称包络归一化到 0..1 的端口。
#
# The effective SVG->pixel scale is min(env.w/bw, env.h/bh): the intermediate unit-box scale and
# the FIT_MARGIN cancel out, which is why ports computed here match what the painter draws.
# 有效的 SVG→像素缩放为 min(env.w/bw, env.h/bh)：中间的单位框缩放与 FIT_MARGIN 相互抵消，
# 这正是此处算出的端口能与渲染器绘制结果吻合的原因。
#
# IMPORTANT / 重要:
#   After editing GP_NOMINAL in src/core/symbol_categories.gd, re-run this generator so the baked
#   port coordinates stay consistent with the new envelope sizes.
#   修改 src/core/symbol_categories.gd 中的 GP_NOMINAL 后，请重跑本生成器，
#   使内置端口坐标与新的包络尺寸保持一致。
#
# Usage / 用法:
#   python3 tools/gen_openpid_defs.py
#
# Output / 输出:
#   src/core/open_pid_icons_defs.gd   (auto-generated — DO NOT edit by hand)
#                                      （自动生成，请勿手改；改本脚本后重跑即可）

import json
import os
import re
import sys

# Reuse the battle-tested path parser from the sibling converter.
# 复用同目录转换器的路径解析器。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_to_gpsym as S  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # Godot-PID-Core
MANIFEST_PATH = os.path.join(ROOT, "assets", "symbol_packs", "open-pid-icons", "manifest.json")
SVG_DIR = os.path.join(ROOT, "assets", "symbol_packs", "open-pid-icons", "svg")
CATEGORIES_GD = os.path.join(ROOT, "src", "core", "symbol_categories.gd")
OUT_PATH = os.path.join(ROOT, "src", "core", "open_pid_icons_defs.gd")

# Fallback envelope when a category is missing from symbol_categories.gd.
# 当 symbol_categories.gd 中缺少某类别时使用的兜底包络。
FALLBACK_SIZE = (64.0, 64.0)

# id -> Chinese display name (the engine falls back to the key if no translation exists).
# id -> 中文显示名（引擎在无翻译时回退为键本身）。
DISPLAY_NAMES = {
    "gate_valve": "闸阀",
    "hand_operated_gate_valve": "手动闸阀",
    "hand_operated_globe_valve": "手动截止阀",
    "rotary_valve": "旋转阀",
    "check_valve": "止回阀",
    "tank": "储罐",
}


def _read_nominal_sizes():
    # Parse GP_NOMINAL and GP_FIT_MARGIN out of src/core/symbol_categories.gd so the GDScript
    # table stays the single source of truth (no duplicated numbers in this script).
    # 从 src/core/symbol_categories.gd 解析 GP_NOMINAL 与 GP_FIT_MARGIN，
    # 使 GDScript 表保持唯一事实来源（本脚本内不复制数字）。
    with open(CATEGORIES_GD, "r", encoding="utf-8") as f:
        text = f.read()

    block = re.search(r"const\s+GP_NOMINAL[^{]*\{(.*?)\}", text, re.S)
    sizes = {}
    if block:
        for k, w, h in re.findall(
            r'"([^"]+)"\s*:\s*Vector2\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)', block.group(1)
        ):
            sizes[k] = (float(w), float(h))

    m = re.search(r"const\s+GP_FIT_MARGIN\s*:\s*float\s*=\s*([\d.]+)", text)
    margin = float(m.group(1)) if m else 1.0

    if not sizes:
        print("[error] could not parse GP_NOMINAL from %s" % CATEGORIES_GD, file=sys.stderr)
        sys.exit(1)
    return sizes, margin


def _fmt(v) -> str:
    # Format a float/int for a GDScript literal, avoiding "-0.0".
    # 把浮点/整数格式化为 GDScript 字面量，规避 "-0.0"。
    v = round(float(v), 4)
    if v == 0:
        return "0"
    if v == int(v):
        return str(int(v))
    return ("%.4f" % v).rstrip("0").rstrip(".")


def _to_gd(v) -> str:
    # Serialize a Python value into a GDScript literal (dict/list/str/num/bool).
    # 把 Python 值序列化为 GDScript 字面量（dict/list/str/num/bool）。
    if isinstance(v, dict):
        items = ", ".join('"%s": %s' % (k, _to_gd(val)) for k, val in v.items())
        return "{%s}" % items
    if isinstance(v, (list, tuple)):
        return "[%s]" % ", ".join(_to_gd(x) for x in v)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
    return _fmt(v)


def _bbox(polylines):
    # Compute the bounding box of all polyline points.
    # 计算所有折点的包围盒。
    xs = [p[0] for poly, _ in polylines for p in poly]
    ys = [p[1] for poly, _ in polylines for p in poly]
    return min(xs), max(xs), min(ys), max(ys)


def _unit_transform(minx, maxx, miny, maxy, margin):
    # Uniform SVG -> 100x100 unit box transform: scale by min(100/bw, 100/bh) * margin,
    # then translate so the glyph bbox center lands on (50, 50).
    # 均匀的 SVG → 100x100 单位框变换：按 min(100/bw, 100/bh) * margin 缩放，
    # 再平移使字形包围盒中心落在 (50, 50)。
    bw = (maxx - minx) or 1.0
    bh = (maxy - miny) or 1.0
    s = min(100.0 / bw, 100.0 / bh) * margin
    cx = (minx + maxx) * 0.5
    cy = (miny + maxy) * 0.5
    return s, cx, cy, bw, bh


def _to_unit(pt, s, cx, cy):
    # Map one absolute SVG point into the 100x100 unit box.
    # 把一个绝对 SVG 点映射到 100x100 单位框内。
    return [round((pt[0] - cx) * s + 50.0, 2), round((pt[1] - cy) * s + 50.0, 2)]


def _build_shape(polylines, s, cx, cy, bw, bh):
    # Encode the polylines in unit space and stamp the glyph's unit-space bbox as "box".
    # 在单位空间编码折线，并把字形的单位空间包围盒写入 "box"。
    paths = []
    for pts, closed in polylines:
        if len(pts) < 2:
            continue
        paths.append({"pts": [_to_unit(p, s, cx, cy) for p in pts], "closed": closed})
    uw = bw * s
    uh = bh * s
    box = [round(50.0 - uw * 0.5, 2), round(50.0 - uh * 0.5, 2), round(uw, 2), round(uh, 2)]
    return {"paths": paths, "circles": [], "rects": [], "box": box}


def _build_ports(icon, minx, maxx, miny, maxy, env):
    # Convert SVG anchors to ports normalized 0..1 against the CATEGORY nominal envelope.
    # 把 SVG 锚点换算为相对「类别」标称包络归一化到 0..1 的端口。
    # Effective SVG->pixel scale is min(env.w/bw, env.h/bh) — see the module docstring.
    # 有效的 SVG→像素缩放为 min(env.w/bw, env.h/bh) —— 见模块说明。
    bw = (maxx - minx) or 1.0
    bh = (maxy - miny) or 1.0
    s_eff = min(env[0] / bw, env[1] / bh)
    cx = (minx + maxx) * 0.5
    cy = (miny + maxy) * 0.5
    ports = []
    for i, anch in enumerate(icon.get("anchors", [])):
        ax = float(anch["x"])
        ay = float(anch["y"])
        nx = 0.5 + (ax - cx) * s_eff / env[0]
        ny = 0.5 + (ay - cy) * s_eff / env[1]
        # Outward normal snapped to the nearest envelope edge; drives future edge routing.
        # 向外法线按最近的包络边吸附；供后续连线路由使用。
        dx = 0
        dy = 0
        if min(nx, 1.0 - nx) <= min(ny, 1.0 - ny):
            dx = -1 if nx <= 0.5 else 1
        else:
            dy = -1 if ny <= 0.5 else 1
        ports.append({
            "name": anch.get("name", "p%d" % (i + 1)),
            "pos": [round(nx, 4), round(ny, 4)],
            "dir": [dx, dy],
        })
    return ports


def _extract_path_d(svg_path):
    # Pull the first <path d="..."> from an SVG file.
    # 从 SVG 文件取出第一个 <path d="...">。
    with open(svg_path, "r", encoding="utf-8") as f:
        text = f.read()
    m = re.search(r'd="([^"]*)"', text)
    return m.group(1) if m else ""


def _run() -> None:
    nominal, margin = _read_nominal_sizes()

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    icons = manifest.get("icons", [])
    if not icons:
        print("[error] no icons found in %s" % MANIFEST_PATH, file=sys.stderr)
        sys.exit(1)

    entries = []
    for icon in icons:
        gid = icon["id"]
        name = DISPLAY_NAMES.get(gid, icon.get("name", gid))
        cat = icon.get("type", "general")
        env = nominal.get(cat, FALLBACK_SIZE)
        svg_path = os.path.join(SVG_DIR, "%s.svg" % gid)
        if not os.path.exists(svg_path):
            print("[skip] %s: SVG file missing" % gid, file=sys.stderr)
            continue
        d = _extract_path_d(svg_path)
        if not d:
            print("[skip] %s: no path data" % gid, file=sys.stderr)
            continue
        polylines = S._path_to_polylines(d)
        minx, maxx, miny, maxy = _bbox(polylines)
        s, cx, cy, bw, bh = _unit_transform(minx, maxx, miny, maxy, margin)
        shape = _build_shape(polylines, s, cx, cy, bw, bh)
        ports = _build_ports(icon, minx, maxx, miny, maxy, env)
        entries.append({
            "id": gid,
            "name": name,
            "cat": cat,
            "ports": ports,
            "shape": shape,
        })
        print("[ok] %-26s -> %-6s env=%dx%d glyph=%.0fx%.0f paths=%d ports=%d" % (
            gid, cat, env[0], env[1], bw, bh, len(shape["paths"]), len(ports)))

    # ---- emit GDScript ----
    # ---- 生成 GDScript ----
    lines = []
    lines.append("# Copyright © 2026 Jonson Wang")
    lines.append("# MIT License — generated from assets/symbol_packs/open-pid-icons/manifest.json")
    lines.append("# (upstream: open-pid-icons npm, MIT, Copyright 2025 tbo47)")
    lines.append("# Auto-generated by tools/gen_openpid_defs.py — DO NOT edit by hand.")
    lines.append("# 自动生成，请勿手改；修改请编辑 tools/gen_openpid_defs.py 后重跑。")
    lines.append("")
    lines.append("extends RefCounted")
    lines.append("")
    lines.append("")
    lines.append("# Build the open-pid-icons vector symbol definitions.")
    lines.append("# 构造 open-pid-icons 矢量图元定义。")
    lines.append("# Shapes are uniformly normalized into a 100x100 unit box (gpShape[\"box\"] carries the")
    lines.append("# glyph bbox); sizes come from GPSymbolCategories; ports are normalized 0..1.")
    lines.append("# 形状均匀归一化到 100x100 单位框（gpShape[\"box\"] 携带字形包围盒）；")
    lines.append("# 尺寸取自 GPSymbolCategories；端口归一化到 0..1。")
    lines.append("static func gpDefs() -> Array[GPSymbolDef]:")
    lines.append("\tvar gpOut: Array[GPSymbolDef] = []")
    for e in entries:
        lines.append("\tgpOut.append(_gpMk(%s, %s, %s, %s, %s))" % (
            _to_gd(e["id"]), _to_gd(e["name"]), _to_gd(e["cat"]),
            _to_gd(e["ports"]), _to_gd(e["shape"])))
    lines.append("\treturn gpOut")
    lines.append("")
    lines.append("")
    lines.append("# Internal: build one open-pid-icon SymbolDef from parsed data.")
    lines.append("# 内部：从解析数据构造一个 open-pid-icons 图元定义。")
    lines.append("# The envelope size is resolved at runtime so GPSymbolCategories stays authoritative.")
    lines.append("# 包络尺寸在运行期解析，使 GPSymbolCategories 始终是权威来源。")
    lines.append("static func _gpMk(gpId: String, gpName: String, gpCat: String, gpPorts: Array[Dictionary], gpShape: Dictionary) -> GPSymbolDef:")
    lines.append("\tvar gpD: GPSymbolDef = GPSymbolDef.new()")
    lines.append("\tgpD.gpId = gpId")
    lines.append("\tgpD.gpDisplayName = gpName")
    lines.append("\tgpD.gpCategory = gpCat")
    lines.append("\tgpD.gpDefaultSize = GPSymbolCategories.gpSizeFor(gpCat)")
    lines.append("\tgpD.gpPorts = gpPorts")
    lines.append("\tgpD.gpShape = gpShape")
    lines.append('\tgpD.gpIconPath = "res://assets/symbol_packs/open-pid-icons/svg/%s.svg" % gpId')
    lines.append("\treturn gpD")
    lines.append("")

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("\nWrote %d symbol defs to %s" % (len(entries), OUT_PATH))


if __name__ == "__main__":
    _run()
