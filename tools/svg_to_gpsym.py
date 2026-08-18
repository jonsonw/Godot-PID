#!/usr/bin/env python3
# tools/svg_to_gpsym.py
# Batch converter: a folder of SVG P&ID symbols -> G-PID symbol shape specs (symbols.json).
# 批量转换器：把一文件夹的 SVG P&ID 图元 -> G-PID 图元形状规格（symbols.json）。
#
# Why vector (not raster): P&ID diagrams zoom in/out a lot and must print to A1 / export
# PDF / DXF crisply. Storing each symbol as a *normalized vector primitive spec* lets G-PID
# render it natively (GPSymbolView._draw), so it stays sharp at any zoom, can be recolored
# for selection/highlight, and needs zero runtime dependencies.
# 为什么用矢量（而非位图）：P&ID 频繁缩放、要印 A1 / 导出 PDF / DXF，必须清晰。把图元存成
# “归一化矢量基元规格”，G-PID 即可原生渲染（GPSymbolView._draw），任意缩放都清晰、可随选中态
# 变色、且零运行时依赖。
#
# Usage / 用法:
#   python3 svg_to_gpsym.py <input_svgs_dir> [--out symbols.json] [--size 100] [--default-cat general]
#
# Output format (one entry per symbol), consumed by GPSymbolDef.gpFromDict:
# 输出格式（每个图元一条），由 GPSymbolDef.gpFromDict 读取：
#   {
#     "id": "pump_centrifugal",
#     "display_name": "Pump Centrifugal",
#     "category": "pump",
#     "standard_ref": "ISO 10628",
#     "default_size": [64, 64],
#     "ports": [],
#     "attrs_schema": {},
#     "shape": {
#       "paths":   [ {"pts": [[x,y], ...], "closed": false}, ... ],
#       "circles": [ {"c": [cx, cy], "r": r}, ... ],
#       "rects":   [ {"pos": [x, y], "size": [w, h]}, ... ]
#     }
#   }
# All shape coordinates are normalized into a 0..SIZE box, aspect preserved, centered.
# 所有形状坐标归一化到 0..SIZE 方框，保持比例并居中。

import argparse
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

SVG_NS = "{http://www.w3.org/2000/svg}"


# ---------------------------------------------------------------------------
# 2D affine transform helpers / 仿射变换辅助
# ---------------------------------------------------------------------------
def _ident():
    # a, b, c, d, e, f  ->  [a c e; b d f; 0 0 1]
    return [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]


def _mul(m, n):
    a = m[0] * n[0] + m[2] * n[1]
    b = m[1] * n[0] + m[3] * n[1]
    c = m[0] * n[2] + m[2] * n[3]
    d = m[1] * n[2] + m[3] * n[3]
    e = m[0] * n[4] + m[2] * n[5] + m[4]
    f = m[1] * n[4] + m[3] * n[5] + m[5]
    return [a, b, c, d, e, f]


def _apply(m, x, y):
    return (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])


def _parse_transform(text):
    # Supports translate, scale, rotate, matrix (the common subset).
    # 支持 translate / scale / rotate / matrix（常用子集）。
    if not text:
        return _ident()
    m = _ident()
    for name, args in re.findall(r"([a-zA-Z]+)\s*\(([^)]*)\)", text):
        nums = [float(v) for v in re.findall(r"[-+]?[0-9]*\.?[0-9]+", args)]
        if name == "translate":
            tx = nums[0] if len(nums) > 0 else 0.0
            ty = nums[1] if len(nums) > 1 else 0.0
            m = _mul(m, [1, 0, 0, 1, tx, ty])
        elif name == "scale":
            sx = nums[0] if len(nums) > 0 else 1.0
            sy = nums[1] if len(nums) > 1 else sx
            m = _mul(m, [sx, 0, 0, sy, 0, 0])
        elif name == "rotate":
            ang = math.radians(nums[0]) if len(nums) > 0 else 0.0
            cx = nums[1] if len(nums) > 1 else 0.0
            cy = nums[2] if len(nums) > 2 else 0.0
            m = _mul(m, [1, 0, 0, 1, cx, cy])
            m = _mul(m, [math.cos(ang), math.sin(ang), -math.sin(ang), math.cos(ang), 0, 0])
            m = _mul(m, [1, 0, 0, 1, -cx, -cy])
        elif name == "matrix":
            if len(nums) >= 6:
                m = _mul(m, nums[0:6])
    return m


# ---------------------------------------------------------------------------
# Path parser / 路径解析（M L H V C S Q T A Z，曲线与圆弧采样为线段）
# ---------------------------------------------------------------------------
def _tokenize_path(d):
    # Split into (command, [numbers...]) pairs.
    # 切分为 (命令, [数值...]) 对。
    tokens = []
    for cmd, nums in re.findall(r"([MmLlHhVvCcSsQqTtAaZz])\s*([^MmLlHhVvCcSsQqTtAaZz]*)", d):
        vals = [float(v) for v in re.findall(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?", nums)]
        tokens.append((cmd, vals))
    return tokens


def _arc_to_points(x0, y0, rx, ry, rot, large, sweep, x1, y1, seg=18):
    # Endpoint -> center parameterization, then sample.
    # 端点->圆心参数化，再采样。
    if rx == 0 or ry == 0:
        return [(x1, y1)]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(rot)
    cos_p, sin_p = math.cos(phi), math.sin(phi)
    dx = (x0 - x1) / 2.0
    dy = (y0 - y1) / 2.0
    x0p = cos_p * dx + sin_p * dy
    y0p = -sin_p * dx + cos_p * dy
    lam = (x0p * x0p) / (rx * rx) + (y0p * y0p) / (ry * ry)
    if lam > 1.0:
        rx *= math.sqrt(lam)
        ry *= math.sqrt(lam)
    sign = 1.0 if large != sweep else -1.0
    num = rx * rx * ry * ry - rx * rx * y0p * y0p - ry * ry * x0p * x0p
    den = rx * rx * y0p * y0p + ry * ry * x0p * x0p
    co = 0.0 if den == 0 else sign * math.sqrt(max(0.0, num / den))
    cxp = co * (rx * y0p) / ry
    cyp = co * (-ry * x0p) / rx
    cx = cos_p * cxp - sin_p * cyp + (x0 + x1) / 2.0
    cy = sin_p * cxp + cos_p * cyp + (y0 + y1) / 2.0
    def ang(ux, uy):
        a = math.atan2(uy, ux)
        if a < 0:
            a += 2 * math.pi
        return a
    theta1 = ang((x0p - cxp) / rx, (y0p - cyp) / ry)
    theta2 = ang((x1p := (x1 - cx) / rx, (-(y1 - cy)) / ry)[0], (-(y1 - cy)) / ry)
    # recompute cleanly
    theta2 = ang((x1 - cx) / rx, (y1 - cy) / ry)
    dth = theta2 - theta1
    if sweep == 0 and dth > 0:
        dth -= 2 * math.pi
    if sweep == 1 and dth < 0:
        dth += 2 * math.pi
    pts = []
    for i in range(seg + 1):
        t = theta1 + dth * i / seg
        ex = cx + rx * math.cos(t)
        ey = cy + ry * math.sin(t)
        # rotate back / 旋转回原坐标系
        xr = cos_p * (ex - cx) - sin_p * (ey - cy) + cx
        yr = sin_p * (ex - cx) + cos_p * (ey - cy) + cy
        pts.append((xr, yr))
    return pts


def _path_to_polylines(d):
    # Returns list of polylines (each a list of (x,y)); open paths stay open.
    # 返回折线列表（每条为 (x,y) 序列）；开放路径保持开放。
    cmds = _tokenize_path(d)
    polylines = []
    cur = []
    cx = cy = 0.0
    sx = sy = 0.0  # subpath start / 子路径起点
    px = py = 0.0  # last point / 上一点
    def flush():
        if len(cur) >= 2:
            polylines.append((cur, False))
    for cmd, vals in cmds:
        if cmd == "M":
            flush(); cur = []
            cx, cy = vals[0], vals[1]; sx, sy = cx, cy; px, py = cx, cy
            cur.append((cx, cy))
        elif cmd == "m":
            flush(); cur = []
            cx += vals[0]; cy += vals[1]; sx, sy = cx, cy; px, py = cx, cy
            cur.append((cx, cy))
        elif cmd in ("L", "l"):
            for i in range(0, len(vals), 2):
                nx = vals[i] + (0 if cmd == "L" else cx)
                ny = vals[i + 1] + (0 if cmd == "L" else cy)
                cx, cy = nx, ny; px, py = cx, cy
                cur.append((cx, cy))
        elif cmd in ("H", "h"):
            for v in vals:
                nx = v + (0 if cmd == "H" else cx)
                cx = nx; px = cx
                cur.append((cx, cy))
        elif cmd in ("V", "v"):
            for v in vals:
                ny = v + (0 if cmd == "V" else cy)
                cy = ny; py = cy
                cur.append((cx, cy))
        elif cmd in ("C", "c"):
            for i in range(0, len(vals), 6):
                x0, y0 = px, py
                x1 = vals[i] + (0 if cmd == "C" else cx)
                y1 = vals[i + 1] + (0 if cmd == "C" else cy)
                x2 = vals[i + 2] + (0 if cmd == "C" else cx)
                y2 = vals[i + 3] + (0 if cmd == "C" else cy)
                x3 = vals[i + 4] + (0 if cmd == "C" else cx)
                y3 = vals[i + 5] + (0 if cmd == "C" else cy)
                seg = 16
                for j in range(1, seg + 1):
                    t = j / seg
                    mt = 1 - t
                    bx = mt**3 * x0 + 3 * mt**2 * t * x1 + 3 * mt * t**2 * x2 + t**3 * x3
                    by = mt**3 * y0 + 3 * mt**2 * t * y1 + 3 * mt * t**2 * y2 + t**3 * y3
                    cur.append((bx, by))
                cx, cy = x3, y3; px, py = cx, cy
        elif cmd in ("S", "s"):
            for i in range(0, len(vals), 4):
                x0, y0 = px, py
                x2 = vals[i] + (0 if cmd == "S" else cx)
                y2 = vals[i + 1] + (0 if cmd == "S" else cy)
                x3 = vals[i + 2] + (0 if cmd == "S" else cx)
                y3 = vals[i + 3] + (0 if cmd == "S" else cy)
                seg = 16
                for j in range(1, seg + 1):
                    t = j / seg
                    mt = 1 - t
                    bx = mt**3 * x0 + 3 * mt**2 * t * (2 * px - x0) + 3 * mt * t**2 * x2 + t**3 * x3
                    by = mt**3 * y0 + 3 * mt**2 * t * (2 * py - y0) + 3 * mt * t**2 * y2 + t**3 * y3
                    cur.append((bx, by))
                cx, cy = x3, y3; px, py = cx, cy
        elif cmd in ("Q", "q"):
            for i in range(0, len(vals), 4):
                x0, y0 = px, py
                x1 = vals[i] + (0 if cmd == "Q" else cx)
                y1 = vals[i + 1] + (0 if cmd == "Q" else cy)
                x2 = vals[i + 2] + (0 if cmd == "Q" else cx)
                y2 = vals[i + 3] + (0 if cmd == "Q" else cy)
                seg = 12
                for j in range(1, seg + 1):
                    t = j / seg
                    mt = 1 - t
                    bx = mt**2 * x0 + 2 * mt * t * x1 + t**2 * x2
                    by = mt**2 * y0 + 2 * mt * t * y1 + t**2 * y2
                    cur.append((bx, by))
                cx, cy = x2, y2; px, py = cx, cy
        elif cmd in ("T", "t"):
            for i in range(0, len(vals), 2):
                x0, y0 = px, py
                x2 = vals[i] + (0 if cmd == "T" else cx)
                y2 = vals[i + 1] + (0 if cmd == "T" else cy)
                seg = 12
                for j in range(1, seg + 1):
                    t = j / seg
                    mt = 1 - t
                    bx = mt**2 * x0 + 2 * mt * t * (2 * px - x0) + t**2 * x2
                    by = mt**2 * y0 + 2 * mt * t * (2 * py - y0) + t**2 * y2
                    cur.append((bx, by))
                cx, cy = x2, y2; px, py = cx, cy
        elif cmd in ("A", "a"):
            for i in range(0, len(vals), 7):
                rx, ry = vals[i], vals[i + 1]
                rot = vals[i + 2]
                large = int(vals[i + 3])
                sweep = int(vals[i + 4])
                nx = vals[i + 5] + (0 if cmd == "A" else cx)
                ny = vals[i + 6] + (0 if cmd == "A" else cy)
                seg_pts = _arc_to_points(px, py, rx, ry, rot, large, sweep, nx, ny)
                for p in seg_pts:
                    cur.append(p)
                cx, cy = nx, ny; px, py = cx, cy
        elif cmd in ("Z", "z"):
            if len(cur) >= 2 and cur[0] != cur[-1]:
                cur.append(cur[0])  # close visually / 视觉闭合
            if len(cur) >= 2:
                polylines.append((cur, True))
            cur = []
    flush()
    return polylines


# ---------------------------------------------------------------------------
# Element collection / 图元收集
# ---------------------------------------------------------------------------
def _localname(tag):
    return tag.split("}")[-1] if "}" in tag else tag


def _collect(svg_root, size, default_cat):
    """Walk the SVG, collect normalized shape primitives. Returns (entry_dict_or_None, warnings)."""
    prim_paths = []     # (pts, closed)
    prim_circles = []   # (cx, cy, r)
    prim_rects = []     # (x, y, w, h)
    raw_pts = []        # for bounding box / 用于计算包围盒

    def add_point(x, y):
        raw_pts.append((x, y))

    def walk(el, m):
        tm = m
        if "transform" in el.attrib:
            tm = _mul(m, _parse_transform(el.attrib["transform"]))
        tag = _localname(el.tag)
        if tag == "rect":
            x = float(el.attrib.get("x", 0)); y = float(el.attrib.get("y", 0))
            w = float(el.attrib.get("width", 0)); h = float(el.attrib.get("height", 0))
            p1 = _apply(tm, x, y)
            p2 = _apply(tm, x + w, y + h)
            x0, y0 = min(p1[0], p2[0]), min(p1[1], p2[1])
            ww, hh = abs(p2[0] - p1[0]), abs(p2[1] - p1[1])
            prim_rects.append((x0, y0, ww, hh))
            for px in (x0, x0 + ww):
                for py in (y0, y0 + hh):
                    add_point(px, py)
        elif tag == "circle":
            cx = float(el.attrib.get("cx", 0)); cy = float(el.attrib.get("cy", 0))
            r = float(el.attrib.get("r", 0))
            c = _apply(tm, cx, cy)
            prim_circles.append((c[0], c[1], r))
            add_point(c[0] - r, c[1] - r); add_point(c[0] + r, c[1] + r)
        elif tag == "ellipse":
            cx = float(el.attrib.get("cx", 0)); cy = float(el.attrib.get("cy", 0))
            rx = float(el.attrib.get("rx", 0)); ry = float(el.attrib.get("ry", 0))
            c = _apply(tm, cx, cy)
            # Approximate ellipse as a polygon / 用多边形近似椭圆
            seg = 32
            pts = []
            for i in range(seg):
                a = 2 * math.pi * i / seg
                px = cx + rx * math.cos(a)
                py = cy + ry * math.sin(a)
                pp = _apply(tm, px, py)
                pts.append(pp)
                add_point(pp[0], pp[1])
            prim_paths.append((pts, True))
        elif tag == "line":
            x1 = float(el.attrib.get("x1", 0)); y1 = float(el.attrib.get("y1", 0))
            x2 = float(el.attrib.get("x2", 0)); y2 = float(el.attrib.get("y2", 0))
            p1 = _apply(tm, x1, y1); p2 = _apply(tm, x2, y2)
            prim_paths.append(([p1, p2], False))
            add_point(*p1); add_point(*p2)
        elif tag == "polyline":
            pts = _pts_from(el.attrib.get("points", ""), tm)
            if len(pts) >= 2:
                prim_paths.append((pts, False))
                for p in pts:
                    add_point(*p)
        elif tag == "polygon":
            pts = _pts_from(el.attrib.get("points", ""), tm)
            if len(pts) >= 2:
                prim_paths.append((pts + [pts[0]], True))
                for p in pts:
                    add_point(*p)
        elif tag == "path":
            d = el.attrib.get("d", "")
            for poly, closed in _path_to_polylines(d):
                if len(poly) >= 2:
                    prim_paths.append((poly, closed))
                    for p in poly:
                        add_point(*p)
        for child in el:
            walk(child, tm)

    walk(svg_root, _ident())

    if not raw_pts:
        return None

    # Normalize: fit bounding box into SIZE x SIZE, preserve aspect, center.
    # 归一化：包围盒适配 SIZE×SIZE，保持比例并居中。
    xs = [p[0] for p in raw_pts]; ys = [p[1] for p in raw_pts]
    minx, maxx = min(xs), max(xs); miny, maxy = min(ys), max(ys)
    bw = maxx - minx or 1.0; bh = maxy - miny or 1.0
    scale = size / max(bw, bh)
    offx = (size - bw * scale) / 2.0 - minx * scale
    offy = (size - bh * scale) / 2.0 - miny * scale

    def norm(p):
        return [round(p[0] * scale + offx, 3), round(p[1] * scale + offy, 3)]

    shape = {"paths": [], "circles": [], "rects": []}
    for pts, closed in prim_paths:
        shape["paths"].append({"pts": [norm(p) for p in pts], "closed": closed})
    for (cx, cy, r) in prim_circles:
        c = norm((cx, cy))
        shape["circles"].append({"c": c, "r": round(r * scale, 3)})
    for (x, y, w, h) in prim_rects:
        p = norm((x, y))
        shape["rects"].append({"pos": p, "size": [round(w * scale, 3), round(h * scale, 3)]})
    return shape


def _pts_from(text, m):
    nums = [float(v) for v in re.findall(r"[-+]?(?:\d*\.\d+|\d+)", text)]
    pts = []
    for i in range(0, len(nums) - 1, 2):
        pts.append(_apply(m, nums[i], nums[i + 1]))
    return pts


# ---------------------------------------------------------------------------
# Category inference / 类目推断
# ---------------------------------------------------------------------------
CAT_RULES = [
    ("pump", "pump"), ("compressor", "pump"), ("blower", "pump"), ("turbine", "pump"),
    ("tank", "tank"), ("vessel", "tank"), ("drum", "tank"), ("column", "tank"),
    ("tower", "tank"), ("reactor", "tank"), ("silo", "tank"),
    ("exchanger", "heat"), ("heat", "heat"), ("cooler", "heat"), ("heater", "heat"),
    ("condenser", "heat"), ("boiler", "heat"), ("furnace", "heat"),
    ("valve", "valve"), ("gate", "valve"), ("globe", "valve"), ("ball", "valve"),
    ("check", "valve"), ("relief", "valve"), ("control", "valve"),
    ("instrument", "instrument"), ("gauge", "instrument"), ("meter", "instrument"),
    ("controller", "instrument"), ("sensor", "instrument"), ("transmitter", "instrument"),
    ("indicator", "instrument"),
    ("filter", "fitting"), ("separator", "fitting"), ("cyclone", "fitting"),
    ("screen", "fitting"), ("mixer", "fitting"), ("agitator", "fitting"),
    ("pipe", "pipe"), ("tee", "pipe"), ("elbow", "pipe"), ("reducer", "pipe"),
    ("fitting", "fitting"), ("nozzle", "fitting"), ("flange", "fitting"),
    ("motor", "electrical"), ("fan", "electrical"),
]


def infer_category(name, default_cat):
    low = name.lower()
    for key, cat in CAT_RULES:
        if key in low:
            return cat
    return default_cat


# ---------------------------------------------------------------------------
# Main / 主流程
# ---------------------------------------------------------------------------
def convert_dir(in_dir, out_path, size, default_cat, standard_ref):
    entries = []
    svg_files = sorted(
        f for f in os.listdir(in_dir)
        if f.lower().endswith((".svg", ".svgz"))
    )
    if not svg_files:
        print(f"[warn] no SVG files found in {in_dir}", file=sys.stderr)
    for fn in svg_files:
        path = os.path.join(in_dir, fn)
        try:
            if fn.lower().endswith(".svgz"):
                import gzip
                data = gzip.decompress(open(path, "rb").read())
                root = ET.fromstring(data)
            else:
                root = ET.parse(path).getroot()
        except Exception as e:  # noqa
            print(f"[skip] {fn}: parse error {e}", file=sys.stderr)
            continue
        shape = _collect(root, size, default_cat)
        if shape is None:
            print(f"[skip] {fn}: no drawable primitives", file=sys.stderr)
            continue
        base = os.path.splitext(fn)[0]
        cat = infer_category(base, default_cat)
        entries.append({
            "id": base,
            "display_name": base.replace("_", " ").replace("-", " ").title(),
            "category": cat,
            "standard_ref": standard_ref,
            "default_size": [64, 64],
            "ports": [],
            "attrs_schema": {},
            "shape": shape,
        })
        print(f"[ok] {fn} -> id={base} category={cat} "
              f"paths={len(shape['paths'])} circles={len(shape['circles'])} rects={len(shape['rects'])}")
    out = {
        "version": 1,
        "size": size,
        "standard_ref": standard_ref,
        "symbols": entries,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"\nWrote {len(entries)} symbols to {out_path}")
    return entries


def main(argv=None):
    ap = argparse.ArgumentParser(description="Batch convert SVG P&ID symbols to G-PID shape specs.")
    ap.add_argument("input_dir", help="Directory containing .svg symbol files.")
    ap.add_argument("--out", default="symbols.json", help="Output JSON path.")
    ap.add_argument("--size", type=float, default=100.0, help="Normalized box size (default 100).")
    ap.add_argument("--default-cat", default="general", help="Fallback category when no keyword matches.")
    ap.add_argument("--standard-ref", default="ISO 10628", help="Standard reference tag stored per symbol.")
    args = ap.parse_args(argv)
    convert_dir(args.input_dir, args.out, args.size, args.default_cat, args.standard_ref)


if __name__ == "__main__":
    main()
