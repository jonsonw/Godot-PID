#!/usr/bin/env python3
# tools/dxf2svg.py
# Split a symbol-library DXF into one standalone SVG per block, plus a metadata
# JSON carrying connection points and attribute definitions.
# 把一个「图元库型」DXF 按块拆成一个个独立 SVG，并输出含连接点与属性定义的元数据 JSON。
#
# Why blocks matter / 为什么按块拆:
#   A P&ID symbol library DXF stores each symbol as a named BLOCK (VALVE_BALL,
#   VALVE_GATE ...) referenced by INSERTs in modelspace. One block == one symbol,
#   so blocks -- not modelspace geometry -- are the correct split unit.
#   P&ID 图元库 DXF 把每个符号存为命名块，模型空间只放 INSERT 引用。
#   一个块 = 一个图元，所以拆分单位是块而不是模型空间几何。
#
# Usage / 用法:
#   python3 tools/dxf2svg.py <input.dxf> [--out DIR] [--size 100] [--pad 0.06]
#
# Output / 输出:
#   <out>/<BLOCKNAME>.svg        standalone vector SVG (geometry only, no text)
#   <out>/<BLOCKNAME>.json       ports + attributes + bbox metadata
#   <out>/_index.json            merged index of every emitted symbol
#   <out>/_preview.html          contact sheet for eyeballing every symbol

import argparse
import json
import math
import os
import sys

try:
    import ezdxf
    from ezdxf import disassemble, path as ezpath
except ImportError:
    sys.exit("ezdxf not installed: pip install ezdxf")

# Entity types that carry visible geometry.
# 承载可见几何的实体类型。
GEOM = {"LINE", "CIRCLE", "ARC", "LWPOLYLINE", "POLYLINE", "ELLIPSE", "SPLINE",
        "SOLID", "3DFACE", "TRACE", "HATCH", "MPOLYGON"}
# Entity types that carry semantics rather than drawing.
# 承载语义而非图形的实体类型。
META = {"POINT", "ATTDEF", "ATTRIB", "TEXT", "MTEXT"}

# Blocks whose geometry is empty or degenerate are skipped.
# 几何为空或退化的块会被跳过。
SKIP_PREFIXES = ("__", "A$")


class Ctx:
    """Holds the Y-flip transform and accumulates SVG fragments.
    承载 Y 翻转变换并累积 SVG 片段。"""

    def __init__(self) -> None:
        self.parts = []
        self.pts = []        # geometry sample points, raw DXF coords
        self.ports = []      # POINT entities
        self.attrs = []      # ATTDEF entities
        self.texts = []      # plain TEXT/MTEXT

    # DXF is Y-up, SVG is Y-down; flip on the way out.
    # DXF 的 Y 轴朝上，SVG 朝下；输出时翻转。
    @staticmethod
    def fx(x: float) -> float:
        return x

    @staticmethod
    def fy(y: float) -> float:
        return -y

    def n(self, v: float) -> str:
        return f"{v:.3f}".rstrip("0").rstrip(".")

    def sample(self, x: float, y: float) -> None:
        self.pts.append((x, y))


def _arc_to_path(c, cx, cy, r, a0, a1):
    """Emit an ARC as an SVG path segment; Y-flip turns CCW into CW (sweep=1).
    把 ARC 输出为 SVG 路径段；Y 翻转使逆时针变顺时针（sweep=1）。"""
    p0 = (c.fx(cx + r * math.cos(math.radians(a0))), c.fy(cy + r * math.sin(math.radians(a0))))
    p1 = (c.fx(cx + r * math.cos(math.radians(a1))), c.fy(cy + r * math.sin(math.radians(a1))))
    delta = (a1 - a0) % 360.0
    large = 1 if delta > 180.0 else 0
    c.sample(cx + r * math.cos(math.radians(a0)), cy + r * math.sin(math.radians(a0)))
    c.sample(cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1)))
    # Also sample the midpoint so the bbox counts the arc bulge.
    # 同时采样中点，使包围盒包含弧的鼓出部分。
    am = math.radians(a0 + delta / 2.0)
    c.sample(cx + r * math.cos(am), cy + r * math.sin(am))
    return (f'<path d="M {c.n(p0[0])} {c.n(p0[1])} '
            f'A {c.n(r)} {c.n(r)} 0 {large} 1 {c.n(p1[0])} {c.n(p1[1])}"/>')


def _flatten_to_path(c, e, seg: int = 24):
    """Fallback: approximate any entity via ezdxf Path, then flatten to a polyline.
    兜底：用 ezdxf Path 近似任意实体，再展平为折线。"""
    try:
        p = ezpath.make_path(e)
    except Exception:
        return None
    verts = []
    for v in p.flattening(distance=0.02):
        verts.append((c.n(c.fx(v[0])), c.n(c.fy(v[1]))))
        c.sample(v[0], v[1])
    if len(verts) < 2:
        return None
    d = "M " + verts[0][0] + " " + verts[0][1] + " " + " ".join(f"L {x} {y}" for x, y in verts[1:])
    return f'<path d="{d}"/>'


def _polyline_points(e):
    """Return [(x, y, bulge), ...] for LWPOLYLINE or legacy POLYLINE.
    返回多段线的 [(x, y, bulge), ...]。"""
    out = []
    try:
        if e.dxftype() == "LWPOLYLINE":
            pts = list(e.get_points("xyb"))
            out = [(p[0], p[1], (p[2] if len(p) > 2 else 0.0)) for p in pts]
        else:
            # Legacy R12 POLYLINE: ezdxf exposes .points with (x, y[, bulge]).
            # 旧式 R12 POLYLINE：ezdxf 用 .points 暴露 (x, y[, bulge])。
            raw = list(e.points)
            for p in raw:
                x, y = float(p[0]), float(p[1])
                b = float(p[4]) if len(p) > 4 else 0.0
                out.append((x, y, b))
    except Exception:
        out = []
    return out


def _add_entity(c, e):
    """Convert one DXF entity into an SVG fragment. 把一个 DXF 实体转为 SVG 片段。"""
    t = e.dxftype()
    if t == "LINE":
        c.sample(e.dxf.start.x, e.dxf.start.y)
        c.sample(e.dxf.end.x, e.dxf.end.y)
        c.parts.append(f'<line x1="{c.n(c.fx(e.dxf.start.x))}" y1="{c.n(c.fy(e.dxf.start.y))}" '
                       f'x2="{c.n(c.fx(e.dxf.end.x))}" y2="{c.n(c.fy(e.dxf.end.y))}"/>')
    elif t == "CIRCLE":
        r = e.dxf.radius
        c.sample(e.dxf.center.x - r, e.dxf.center.y - r)
        c.sample(e.dxf.center.x + r, e.dxf.center.y + r)
        c.parts.append(f'<circle cx="{c.n(c.fx(e.dxf.center.x))}" cy="{c.n(c.fy(e.dxf.center.y))}" '
                       f'r="{c.n(r)}"/>')
    elif t == "ARC":
        c.parts.append(_arc_to_path(c, e.dxf.center.x, e.dxf.center.y, e.dxf.radius,
                                    e.dxf.start_angle, e.dxf.end_angle))
    elif t in ("LWPOLYLINE", "POLYLINE"):
        pts = _polyline_points(e)
        if not pts:
            f = _flatten_to_path(c, e)
            if f:
                c.parts.append(f)
            return
        closed = bool(e.dxf.get("flags", 0) & 1)
        # Walk the vertex list, turning bulge arcs into A segments.
        # 遍历顶点表，把 bulge 弧转成 A 段。
        d = []
        for i in range(len(pts) - (0 if closed else 1)):
            x0, y0, b = pts[i]
            x1, y1, _ = pts[(i + 1) % len(pts)]
            sx, sy = c.fx(x0), c.fy(y0)
            ex, ey = c.fx(x1), c.fy(y1)
            if i == 0:
                d.append(f"M {c.n(sx)} {c.n(sy)}")
            if abs(b) < 1e-9:
                d.append(f"L {c.n(ex)} {c.n(ey)}")
                c.sample(x1, y1)
            else:
                # Bulge -> arc. Y-flip negates the bulge sign.
                # bulge 转弧；Y 翻转使 bulge 符号取反。
                ang = 4.0 * math.atan(b)
                chord = math.hypot(x1 - x0, y1 - y0)
                r = chord / (2.0 * math.sin(abs(ang) / 2.0)) if abs(ang) > 1e-9 else 0.0
                large = 1 if abs(ang) > math.pi else 0
                sweep = 1 if (-b) > 0 else 0
                d.append(f"A {c.n(r)} {c.n(r)} 0 {large} {sweep} {c.n(ex)} {c.n(ey)}")
                c.sample(x1, y1)
                c.sample((x0 + x1) / 2.0, (y0 + y1) / 2.0 + (r if b > 0 else -r) * (1 - math.cos(ang / 2.0)))
        if closed:
            d.append("Z")
        if d:
            c.parts.append(f'<path d="{" ".join(d)}"/>')
    elif t in ("SOLID", "3DFACE", "TRACE"):
        vs = []
        for i in range(3, 11):
            if e.dxf.hasattr(f"vtx{i}"):
                v = getattr(e.dxf, f"vtx{i}")
                vs.append((c.n(c.fx(v.x)), c.n(c.fy(v.y))))
                c.sample(v.x, v.y)
        if len(vs) >= 3:
            c.parts.append('<polygon points="' + " ".join(f"{x},{y}" for x, y in vs) + '"/>')
    else:
        f = _flatten_to_path(c, e)
        if f:
            c.parts.append(f)


def _unit_map(minx, maxx, miny, maxy, size):
    """Mirror svg_to_gpsym._collect: uniform scale by max side, centred in the box.
    与 svg_to_gpsym._collect 一致：按最长边等比缩放，并在框内居中。"""
    bw, bh = maxx - minx, maxy - miny
    s = size / max(bw, bh) if max(bw, bh) > 0 else 1.0
    offx = (size - bw * s) / 2.0 - minx * s
    offy = (size - bh * s) / 2.0 - miny * s
    return s, offx, offy


def convert(dxf_path, out_dir, size=100.0, pad=0.06):
    doc = ezdxf.readfile(dxf_path)
    os.makedirs(out_dir, exist_ok=True)
    index = []
    for blk in doc.blocks:
        name = blk.name
        if name.startswith("*"):
            continue
        if any(name.startswith(p) for p in SKIP_PREFIXES):
            continue
        # Flatten nested INSERTs (e.g. VALVE_GATE references the empty PROTO_2016).
        # 展平嵌套 INSERT（如 VALVE_GATE 引用空的 PROTO_2016）。
        ents = list(disassemble.recursive_decompose(blk))
        c = Ctx()
        for e in ents:
            t = e.dxftype()
            if t in GEOM:
                _add_entity(c, e)
            elif t == "POINT":
                c.ports.append([round(e.dxf.location.x, 4), round(e.dxf.location.y, 4)])
            elif t == "ATTDEF":
                c.attrs.append({"tag": e.dxf.tag, "prompt": e.dxf.prompt,
                                "default": e.dxf.text,
                                "pos": [round(e.dxf.insert.x, 3), round(e.dxf.insert.y, 3)],
                                "height": round(e.dxf.height, 3)})
            elif t in ("TEXT", "MTEXT"):
                c.texts.append({"text": e.dxf.text if t == "TEXT" else e.text,
                                "pos": [round(e.dxf.insert.x, 3), round(e.dxf.insert.y, 3)]})
        if not c.pts:
            continue  # empty / metadata-only block

        xs = [p[0] for p in c.pts]
        ys = [p[1] for p in c.pts]
        minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
        bw, bh = maxx - minx, maxy - miny
        padv = max(bw, bh) * pad
        # viewBox in flipped space: y' = -y, so vertical extent is (-maxy, -miny).
        # 翻转空间的 viewBox：y' = -y，故纵向范围为 (-maxy, -miny)。
        vx, vy = minx - padv, -(maxy + padv)
        vw, vh = bw + 2 * padv, bh + 2 * padv

        svg = ['<?xml version="1.0" encoding="UTF-8"?>',
               # viewBox only -- no fixed width/height, so viewers scale to fit.
               # 仅保留 viewBox，不写死宽高，查看器可自适应缩放。
               f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{c.n(vx)} {c.n(vy)} '
               f'{c.n(vw)} {c.n(vh)}">',
               f'<!-- {name} : generated from {os.path.basename(dxf_path)} -->',
               '<g fill="none" stroke="#000" stroke-width="0.35" '
               'stroke-linecap="round" stroke-linejoin="round">']
        svg += ["  " + p for p in c.parts]
        svg.append("</g>")
        svg.append("</svg>")

        s, offx, offy = _unit_map(minx, maxx, miny, maxy, size)
        ports_unit = [[round(px * s + offx, 3), round((-py) * s + offy, 3)] for px, py in c.ports]

        meta = {"name": name, "source": os.path.basename(dxf_path),
                "bbox_dxf": [round(v, 4) for v in (minx, miny, maxx, maxy)],
                "size_dxf": [round(bw, 4), round(bh, 4)],
                "viewBox": [c.n(vx), c.n(vy), c.n(vw), c.n(vh)],
                "entity_count": len(c.parts),
                "ports_dxf": c.ports,
                "ports_unit": ports_unit,
                "attributes": c.attrs,
                "texts": c.texts}

        with open(os.path.join(out_dir, f"{name}.svg"), "w", encoding="utf-8") as f:
            f.write("\n".join(svg) + "\n")
        with open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)
        index.append(meta)

    with open(os.path.join(out_dir, "_index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=2)
    _preview(out_dir, index)
    return index


def _preview(out_dir, index):
    """Write a contact sheet so every symbol can be eyeballed at once.
    写一张联系表，便于一次性目视全部符号。"""
    cards = []
    for m in index:
        svg = os.path.basename(out_dir)  # unused, keeps linter quiet
        fn = m["name"] + ".svg"
        p = os.path.join(out_dir, fn)
        with open(p, "r", encoding="utf-8") as f:
            body = f.read().split("?>", 1)[-1]
        ports = m["ports_dxf"]
        cards.append(
            f'<div class="card"><div class="art">{body}</div>'
            f'<div class="nm">{m["name"]}</div>'
            f'<div class="mt">{m["size_dxf"][0]:.1f}x{m["size_dxf"][1]:.1f} · '
            f'{m["entity_count"]} prim · {len(ports)} pt</div></div>')
    html = ("<!doctype html><meta charset='utf-8'><title>symbol contact sheet</title>"
            "<style>body{font:13px/1.4 -apple-system,system-ui;margin:24px;background:#fff;color:#111}"
            ".grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:14px}"
            ".card{border:1px solid #e3e3e3;border-radius:8px;padding:10px;background:#fafafa}"
            ".art{height:110px;display:flex;align-items:center;justify-content:center;background:#fff;"
            "border:1px solid #eee;border-radius:4px}.art svg{max-width:100%;max-height:100%}"
            ".nm{font-weight:600;margin-top:8px;font-size:12px;word-break:break-all}"
            ".mt{color:#777;font-size:11px;margin-top:2px}</style>"
            f"<h2>{len(index)} symbols</h2><div class='grid'>" + "".join(cards) + "</div>")
    with open(os.path.join(out_dir, "_preview.html"), "w", encoding="utf-8") as f:
        f.write(html)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dxf", help="input DXF (symbol library) / 输入 DXF（图元库）")
    ap.add_argument("--out", default=None, help="output directory / 输出目录")
    ap.add_argument("--size", type=float, default=100.0)
    ap.add_argument("--pad", type=float, default=0.06)
    a = ap.parse_args()
    out = a.out or (os.path.splitext(a.dxf)[0] + "_svg")
    idx = convert(a.dxf, out, a.size, a.pad)
    print(f"{len(idx)} symbols -> {out}")
    for m in idx:
        print(f"  {m['name']:28s} {m['entity_count']:3d} prim  "
              f"{len(m['ports_dxf'])} pt  {m['size_dxf']}")


if __name__ == "__main__":
    main()
