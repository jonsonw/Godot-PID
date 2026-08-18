#!/usr/bin/env python3
# tools/gen_openpid_defs.py
# Generate src/core/open_pid_icons_defs.gd from assets/symbol_packs/open-pid-icons/open-pid-icons.json.
# 从 open-pid-icons.json 生成图元定义脚本 src/core/open_pid_icons_defs.gd。
#
# It reuses the SVG path parser from svg_to_gpsym.py to turn each icon's path "d" into a
# normalized vector shape spec (GPSymbolDef.gpShape). Coordinates are normalized PER AXIS into a
# 0..100 box using the SVG viewBox (x/width*100, y/height*100) so that, when GPSymbolView draws
# the shape with independent x/y scales and gpDefaultSize = (width, height), the symbol keeps its
# native aspect ratio and its connection ports (converted to node-centered SVG coords) line up.
# 复用 svg_to_gpsym.py 的 SVG 路径解析器，把每个图元的 path "d" 转成归一化矢量形状规格
# （GPSymbolDef.gpShape）。坐标按轴归一化到 0..100（x/width*100, y/height*100），配合
# GPSymbolView 的独立 x/y 缩放 + gpDefaultSize=(width,height)，图元即可保持原生比例，
# 且连接端口（换算为节点中心 SVG 坐标）与图形端点精确对齐。
#
# Usage / 用法:
#   python3 tools/gen_openpid_defs.py
#
# Output / 输出:
#   src/core/open_pid_icons_defs.gd   (auto-generated — DO NOT edit by hand)
#                                      （自动生成，请勿手改；改本脚本后重跑即可）

import json
import os
import sys

# Reuse the battle-tested path parser from the sibling converter.
# 复用同目录转换器的路径解析器。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_to_gpsym as S  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # Godot-PID-Core
MANIFEST_PATH = os.path.join(ROOT, "assets", "symbol_packs", "open-pid-icons", "manifest.json")
SVG_DIR = os.path.join(ROOT, "assets", "symbol_packs", "open-pid-icons", "svg")
OUT_PATH = os.path.join(ROOT, "src", "core", "open_pid_icons_defs.gd")

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


def _fmt(v) -> str:
    # Format a float/int for a GDScript literal, avoiding "-0.0".
    # 把浮点/整数格式化为 GDScript 字面量，规避 "-0.0"。
    v = round(float(v), 2)
    if v == 0:
        return "0"
    if v == int(v):
        return str(int(v))
    return f"{v:.2f}"


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


def _normalize_point(pt, minx, maxx, miny, maxy):
    # Normalize one absolute SVG point into the 0..100 per-axis box using the shape bbox.
    # 把绝对 SVG 点按轴归一化到 0..100 方框（基于图形包围盒，保证居中且充满方框）。
    x, y = pt
    bw = (maxx - minx) or 1.0
    bh = (maxy - miny) or 1.0
    return [round((x - minx) / bw * 100.0, 2), round((y - miny) / bh * 100.0, 2)]


def _bbox(polylines):
    # Compute the bounding box of all polyline points.
    # 计算所有折点的包围盒。
    xs = [p[0] for poly, _ in polylines for p in poly]
    ys = [p[1] for poly, _ in polylines for p in poly]
    return min(xs), max(xs), min(ys), max(ys)


def _build_shape(d, width, height):
    # Parse the icon path into polylines (absolute SVG coords), then normalize per axis
    # by the shape's own bounding box (so it is centered and fills the 0..100 box).
    # 把图元 path 解析为折线（绝对 SVG 坐标），再按图形自身包围盒按轴归一化（居中且充满方框）。
    polylines = S._path_to_polylines(d)
    minx, maxx, miny, maxy = _bbox(polylines)
    paths = []
    for pts, closed in polylines:
        if len(pts) < 2:
            continue
        norm_pts = [_normalize_point(p, minx, maxx, miny, maxy) for p in pts]
        paths.append({"pts": norm_pts, "closed": closed})
    return {"paths": paths, "circles": [], "rects": []}


def _build_ports(icon, minx, maxx, miny, maxy, width, height):
    # Convert SVG anchors to node-centered pixel ports using the SAME bbox mapping as the shape,
    # so they line up exactly with the drawn endpoints.
    # 用与图形相同的包围盒映射把 SVG 锚点换算为节点中心像素端口，使其与绘制端点精确对齐。
    bw = (maxx - minx) or 1.0
    bh = (maxy - miny) or 1.0
    ports = []
    for i, anch in enumerate(icon.get("anchors", [])):
        ax = float(anch["x"])
        ay = float(anch["y"])
        px = (ax - minx) / bw * width - width / 2.0
        py = (ay - miny) / bh * height - height / 2.0
        ports.append({
            "name": "p%d" % (i + 1),
            "pos": [round(px, 2), round(py, 2)],
        })
    return ports


def _extract_path_d(svg_path):
    # Pull the first <path d="..."> from an SVG file.
    # 从 SVG 文件取出第一个 <path d="...">。
    with open(svg_path, "r", encoding="utf-8") as f:
        text = f.read()
    m = __import__("re").search(r'd="([^"]*)"', text)
    return m.group(1) if m else ""


def _run() -> None:
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
        width = float(icon["width"])
        height = float(icon["height"])
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
        shape = _build_shape(d, width, height)
        ports = _build_ports(icon, minx, maxx, miny, maxy, width, height)
        entries.append({
            "id": gid,
            "name": name,
            "cat": cat,
            "size": [width, height],
            "ports": ports,
            "shape": shape,
        })
        print("[ok] %s -> %s (%s) paths=%d ports=%d" % (
            gid, name, cat, len(shape["paths"]), len(ports)))

    # ---- emit GDScript ----
    # ---- 生成 GDScript ----
    lines = []
    lines.append("# Copyright © 2026 Jonson Wang")
    lines.append("# MIT License — generated from assets/symbol_packs/open-pid-icons/open-pid-icons.json")
    lines.append("# (upstream: open-pid-icons npm, MIT, Copyright 2025 tbo47)")
    lines.append("# Auto-generated by tools/gen_openpid_defs.py — DO NOT edit by hand.")
    lines.append("# 自动生成，请勿手改；修改请编辑 tools/gen_openpid_defs.py 后重跑。")
    lines.append("")
    lines.append("extends RefCounted")
    lines.append("")
    lines.append('const GPSymbolDef := preload("res://src/core/symbol_def.gd")')
    lines.append("")
    lines.append("")
    lines.append("# Build the open-pid-icons vector symbol definitions (shape normalized 0..100 per axis).")
    lines.append("# 构造 open-pid-icons 矢量图元定义（形状按轴归一化到 0..100）。")
    lines.append("static func gpDefs() -> Array[GPSymbolDef]:")
    lines.append("\tvar gpOut: Array[GPSymbolDef] = []")
    for e in entries:
        ports_lit = _to_gd(e["ports"])
        shape_lit = _to_gd(e["shape"])
        lines.append("\tgpOut.append(_gpMk(%s, %s, %s, Vector2(%s, %s), %s, %s))" % (
            _to_gd(e["id"]), _to_gd(e["name"]), _to_gd(e["cat"]),
            _fmt(e["size"][0]), _fmt(e["size"][1]), ports_lit, shape_lit))
    lines.append("\treturn gpOut")
    lines.append("")
    lines.append("")
    lines.append("# Internal: build one open-pid-icon SymbolDef from parsed data.")
    lines.append("# 内部：从解析数据构造一个 open-pid-icons 图元定义。")
    lines.append("static func _gpMk(gpId: String, gpName: String, gpCat: String, gpSize: Vector2, gpPorts: Array[Dictionary], gpShape: Dictionary) -> GPSymbolDef:")
    lines.append("\tvar gpD: GPSymbolDef = GPSymbolDef.new()")
    lines.append("\tgpD.gpId = gpId")
    lines.append("\tgpD.gpDisplayName = gpName")
    lines.append("\tgpD.gpCategory = gpCat")
    lines.append("\tgpD.gpDefaultSize = gpSize")
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
