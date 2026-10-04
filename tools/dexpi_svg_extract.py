#!/usr/bin/env python3
# tools/dexpi_svg_extract.py
# Extract the standard P&ID symbol set out of a DEXPI SVG export into a G-PID
# symbol-pack source folder (assets/symbol_packs/dexpi/).
# 从 DEXPI SVG 导出文件中提取标准 P&ID 图元集，生成 G-PID 图元包源目录。
#
# Why this exists / 为什么需要它:
# A DEXPI SVG is a FLAT drawing: every symbol instance repeats its own geometry inline,
# there is no <symbol>/<use> reuse, and instance placement lives in a `transform` on the
# shape group. So "the symbol library" has to be recovered by clustering the groups that
# share an id (e.g. <g id="BALL_VALVE_SHAPE">) and then taking ONE canonical instance.
# DEXPI 的 SVG 是**扁平**图纸：每个图元实例都把自身几何内联重复一遍，没有 <symbol>/<use>
# 复用，实例摆放位姿写在形状组的 transform 上。因此「图元库」只能这样还原：把 id 相同
# 的组聚类（如 <g id="BALL_VALVE_SHAPE">），再取其中一个规范实例。
#
# The unit decision that matters / 关键的单位决策:
# The v0.1 editor adopts "1 world unit == 1 mm" (plan Phase 0), so a symbol must carry its
# REAL millimetre size or "1:1 reproduction" is meaningless. The local coordinates inside a
# shape group are the DEXPI *definition* grid; the instance `scale(sx, sy)` converts them to
# millimetres on the sheet. We therefore bake |sx|, |sy| into the emitted geometry and record
# the resulting bounding box as `size_mm`. Rotation and mirroring are stripped on purpose:
# those are PLACEMENT, not identity — a butterfly valve rotated 270 degrees is still the same
# library symbol, and shipping a rotated glyph would force every user to un-rotate it.
# v0.1 编辑器采用「1 世界单位 = 1mm」（计划 Phase 0），故图元必须携带**真实毫米尺寸**，
# 否则「1:1 复刻」无从谈起。形状组内的局部坐标是 DEXPI 的**定义网格**；实例上的
# scale(sx, sy) 才把它换算成图面上的毫米。因此我们把 |sx|、|sy| 烘焙进输出几何，
# 并把所得包围盒记为 size_mm。**刻意**剥掉旋转与镜像：那是**摆放**而非**身份** ——
# 旋转 270° 的蝶阀仍是同一个库图元，若把旋转后的字形入库，用户每次都得把它转回来。
#
# Usage / 用法:
#   python3 tools/dexpi_svg_extract.py <dexpi.svg> [--out assets/symbol_packs/dexpi]
#
# Output / 产物:
#   <out>/svg/*.svg          one normalized glyph per shape / 每个形状一个归一化字形
#   <out>/manifest.json      pack manifest consumed by tools/gen_symbol_packs.py
#   <out>/_preview.html      side-by-side visual check / 供目检的对照预览页

import argparse
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_to_gpsym as S  # reuse the shared path/transform parser / 复用共用的路径与变换解析

SVG_NS = "http://www.w3.org/2000/svg"
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-")
SHAPE_ID_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")

# Fallback scale for a shape whose every instance is degenerate (scale 0).
# WHY 0.40: it is the scale class DEXPI uses for the sibling inline fittings (reducer,
# nozzle, valves), so a T-connection comes out the same visual weight as the parts it
# joins. A T-connection in C01 is exported with scale(0,0) — literally invisible — so
# there is no ground truth on the sheet to measure; consistency with its neighbours is
# the only defensible choice.
# 所有实例都是退化变换（scale 0）时的兜底缩放。为何取 0.40：这是 DEXPI 给同类
# 内联管件（异径管、接管嘴、阀门）所用的缩放档，使 T 型三通与它连接的部件视觉分量一致。
# C01 中的 T 型三通被导出为 scale(0,0) —— 字面意义上不可见 —— 故图面上没有可测的
# 真值，与同类件保持一致是唯一可辩护的选择。
FITTING_SCALE_FALLBACK = 0.40

# Minimum envelope in mm. A blind cover is a single vertical bar, so its true width is
# zero — an envelope of 0 mm would divide by zero in the uniform fit and place every
# port on top of itself. / 最小包络（mm）。盲板是一根竖线，真实宽度为 0 —— 0mm 的包络
# 会在等比适配时除零，并使所有端口叠在同一点。
MIN_MM = 1.0

# ---- shape -> category / 形状 -> 类别 ----
CATEGORY = {
    "ANGLE_SAFETY_VALVE_SPRING_LOADED_SHAPE": "valve",
    "BALL_VALVE_SHAPE": "valve",
    "BUTTERFLY_VALVE_SHAPE": "valve",
    "GLOBE_VALVE_SHAPE": "valve",
    "SWING_CHECK_VALVE_SHAPE": "valve",
    "CENTRIFUGAL_PUMP_SHAPE": "pump",
    "RECIPROCATING_PUMP_SHAPE": "pump",
    "FLOATING_HEAD_TUBE_BUNDLE_HEAT_EXCHANGER_SHAPE": "heat",
    "PLATE_TYPE_HEAT_EXCHANGER_SHAPE": "heat",
    "VESSEL_WITH_DISHED_HEADS_SHAPE": "tank",
    "INSTRUMENTATION_BUBBLE_SHAPE_CENTRAL": "instrument",
    "INSTRUMENTATION_BUBBLE_SHAPE_FIELD": "instrument",
}

# ---- shape -> bilingual display name (standard terminology, not machine translation) ----
# ---- 形状 -> 中英对照显示名（标准术语，非机翻）----
NAMES = {
    "ANGLE_SAFETY_VALVE_SPRING_LOADED_SHAPE": ("角式弹簧安全阀", "Angle Spring-Loaded Safety Valve"),
    "ARROW_FOR_INLET_OF_ESSENTIAL_SUBSTANCES_SHAPE": ("关键介质进口箭头", "Arrow — Inlet of Essential Substances"),
    "ARROW_FOR_OUTLET_OF_ESSENTIAL_SUBSTANCES_SHAPE": ("关键介质出口箭头", "Arrow — Outlet of Essential Substances"),
    "BALL_VALVE_SHAPE": ("球阀", "Ball Valve"),
    "BLIND_COVER_SHAPE": ("盲板", "Blind Cover"),
    "BUTTERFLY_VALVE_SHAPE": ("蝶阀", "Butterfly Valve"),
    "CENTRIFUGAL_PUMP_SHAPE": ("离心泵", "Centrifugal Pump"),
    "CONTROLLED_ACTUATOR_SHAPE": ("控制执行机构", "Controlled Actuator"),
    "DIRECTION_OF_FLOW_SHAPE_FOR_PRIMARY_SEGMENT": ("流向（主管段）", "Direction of Flow (Primary Segment)"),
    "DIRECTION_OF_FLOW_SHAPE_FOR_SECONDARY_SEGMENT": ("流向（支管段）", "Direction of Flow (Secondary Segment)"),
    "FLOATING_HEAD_TUBE_BUNDLE_HEAT_EXCHANGER_SHAPE": ("浮头式管束换热器", "Floating-Head Tube-Bundle Heat Exchanger"),
    "GLOBE_VALVE_SHAPE": ("截止阀", "Globe Valve"),
    "INSTRUMENTATION_BUBBLE_SHAPE_CENTRAL": ("仪表气泡（中控室）", "Instrumentation Bubble (Central)"),
    "INSTRUMENTATION_BUBBLE_SHAPE_FIELD": ("仪表气泡（现场）", "Instrumentation Bubble (Field)"),
    "MANHOLE_SHAPE": ("人孔", "Manhole"),
    "NOZZLE_SHAPE": ("接管嘴", "Nozzle"),
    "PIPING_INSULATED_SHAPE": ("保温管道", "Insulated Piping"),
    "PLATE_TYPE_HEAT_EXCHANGER_SHAPE": ("板式换热器", "Plate-Type Heat Exchanger"),
    "RECIPROCATING_PUMP_SHAPE": ("往复泵", "Reciprocating Pump"),
    "REDUCER_GENERAL_SHAPE": ("异径管", "Reducer (General)"),
    "SLOPE_SHAPE": ("管道坡度", "Slope"),
    "SWING_CHECK_VALVE_SHAPE": ("旋启式止回阀", "Swing Check Valve"),
    "T_TYPE_CONNECTION_SHAPE": ("T 型三通", "T-Type Connection"),
    "VESSEL_WITH_DISHED_HEADS_SHAPE": ("碟形封头容器", "Vessel with Dished Heads"),
}

# ---- per-shape ports (normalized 0..1 inside the glyph box) ----
# ---- 按形状定义的端口（字形框内归一化 0..1）----
# Shapes absent from this table fall back to the generator's category default
# (valve/pump/heat: left+right; tank: top+bottom; instrument: proc+sig; general: none).
# 未列入本表的形状回落到生成器的类别默认端口。
def _nozzle(name, x, y, dx, dy):
    return {"name": name, "pos": [x, y], "dir": [dx, dy], "type": "NOZZLE"}


def _terminal(name, x, y, dx, dy):
    return {"name": name, "pos": [x, y], "dir": [dx, dy], "type": "TERMINAL"}


PORTS = {
    # 仪表气泡：下方取自工艺（proc），上方发出信号（sig）/ bubble: taps the process at the
    # bottom, emits the signal at the top
    "INSTRUMENTATION_BUBBLE_SHAPE_CENTRAL": [
        _nozzle("proc", 0.5, 1.0, 0, 1),
        {"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
    ],
    "INSTRUMENTATION_BUBBLE_SHAPE_FIELD": [
        _nozzle("proc", 0.5, 1.0, 0, 1),
        {"name": "sig", "pos": [0.5, 0.0], "dir": [0, -1], "type": "SIGNAL"},
    ],
    # 三通：主管左右贯通 + 下方支管 / tee: main run left-right plus a branch downward
    "T_TYPE_CONNECTION_SHAPE": [
        _nozzle("in", 0.0, 0.0, -1, 0),
        _nozzle("out", 1.0, 0.0, 1, 0),
        _nozzle("branch", 0.5, 1.0, 0, 1),
    ],
    # 异径管：左右两个管口 / reducer: two nozzles
    "REDUCER_GENERAL_SHAPE": [
        _nozzle("in", 0.0, 0.5, -1, 0),
        _nozzle("out", 1.0, 0.5, 1, 0),
    ],
    # 接管嘴：只有一条朝**外**的连接 / nozzle: ONE outward connection only.
    # The inboard "equip" end is where the part MEETS the vessel — a mount, not a process
    # connection — so it must not offer a port there (the user reported two dots on one nozzle).
    # 内端「equip」是部件与设备的**接合面**——是挂载而非工艺连接——故不得设端口
    #（用户报告一支管嘴出现两个圆点）。
    "NOZZLE_SHAPE": [
        _nozzle("pipe", 1.0, 0.5, 1, 0),
    ],
    # 保温管道：穿过的管段两端 / insulated piping: the run passes straight through
    "PIPING_INSULATED_SHAPE": [
        _nozzle("in", 0.0, 0.5, -1, 0),
        _nozzle("out", 1.0, 0.5, 1, 0),
    ],
    # 坡度：管段两端 / slope: both ends of the run
    "SLOPE_SHAPE": [
        _nozzle("in", 0.0, 0.5, -1, 0),
        _nozzle("out", 1.0, 0.5, 1, 0),
    ],
    # 盲板：单侧法兰端点 / blind: a single terminal on the flanged side
    "BLIND_COVER_SHAPE": [_terminal("end", 0.5, 0.0, 0, -1)],
    # 人孔：设备壁上的一个接口，供人进出 —— **不是**工艺连接，没有任何端口。
    # A manhole is an access opening in the wall, NOT a process connection: it carries no port
    # at all (the user reported a stray dot plus a bare i18n key where "M1" belongs).
    # 人孔是壁上的进出孔，**不是**工艺连接，一个端口都没有（用户报告：多出的圆点 +
    # 本应是「M1」的位置裸显 i18n 键）。
    "MANHOLE_SHAPE": [],
    # 执行机构：顶部信号输入 + 底部阀杆输出 / actuator: signal in at top, stem out at bottom
    "CONTROLLED_ACTUATOR_SHAPE": [
        {"name": "sig", "pos": [0.0, 0.5], "dir": [-1, 0], "type": "SIGNAL"},
        {"name": "stem", "pos": [1.0, 0.5], "dir": [1, 0], "type": "ACTUATOR"},
    ],
    # 角式安全阀：底部进、右侧出（角型）/ angle safety valve: bottom inlet, side outlet
    "ANGLE_SAFETY_VALVE_SPRING_LOADED_SHAPE": [
        _nozzle("in", 0.33, 1.0, 0, 1),
        _nozzle("out", 1.0, 0.14, 1, 0),
    ],
    # 换热器：壳程左右 + 管程上下 / exchanger: shell side left-right, tube side top-bottom
    "PLATE_TYPE_HEAT_EXCHANGER_SHAPE": [
        _nozzle("shell_in", 0.0, 0.5, -1, 0),
        _nozzle("shell_out", 1.0, 0.5, 1, 0),
    ],
    "FLOATING_HEAD_TUBE_BUNDLE_HEAT_EXCHANGER_SHAPE": [
        _nozzle("shell_in", 0.0, 0.5, -1, 0),
        _nozzle("shell_out", 1.0, 0.5, 1, 0),
    ],
    # 容器：顶 / 底 / 两侧 / vessel: top, bottom and two side nozzles
    "VESSEL_WITH_DISHED_HEADS_SHAPE": [
        _nozzle("top", 0.5, 0.0, 0, -1),
        _nozzle("bottom", 0.5, 1.0, 0, 1),
        _nozzle("left", 0.0, 0.5, -1, 0),
        _nozzle("right", 1.0, 0.5, 1, 0),
    ],
}


def _localname(tag):
    return tag.split("}")[-1]


def _parse_scale(transform):
    # Return |sx|, |sy| from a transform string; (1,1) when no scale() is present.
    # 从变换串中返回 |sx|、|sy|；无 scale() 时为 (1,1)。
    sx = sy = 1.0
    for name, args in re.findall(r"([a-zA-Z]+)\s*\(([^)]*)\)", transform or ""):
        nums = [float(v) for v in re.findall(r"[-+]?[0-9]*\.?[0-9]+", args)]
        if name == "scale":
            sx = nums[0] if len(nums) > 0 else 1.0
            sy = nums[1] if len(nums) > 1 else sx
    return abs(sx), abs(sy)


def _find_shapes(root):
    # Collect {shape_id: [ (scale, [primitives]) ]}. A "primitive" is a tuple
    # ("poly", [(x,y)...]) | ("ellipse", cx, cy, rx, ry).
    # 收集 {形状 id: [(缩放, [基元])]}。基元为 ("poly", 点列) 或 ("ellipse", cx,cy,rx,ry)。
    out = {}

    def walk(el):
        tag = _localname(el.tag)
        gid = el.attrib.get("id", "")
        # "_SHAPE" is matched ANYWHERE, not just as a suffix: DEXPI ids include both
        # "..._SHAPE" and "..._SHAPE_CENTRAL" / "..._SHAPE_FOR_PRIMARY_SEGMENT".
        # "_SHAPE" 在**任意位置**匹配，而非仅作后缀：DEXPI 的 id 既有 "..._SHAPE"，
        # 也有 "..._SHAPE_CENTRAL" / "..._SHAPE_FOR_PRIMARY_SEGMENT"。
        if tag == "g" and gid and SHAPE_ID_RE.match(gid) and not UUID_RE.match(gid) \
                and "_SHAPE" in gid:
            sx, sy = _parse_scale(el.attrib.get("transform", ""))
            prims = []
            for d in el.iter():
                t = _localname(d.tag)
                if t == "polyline" or t == "polygon":
                    pts = S._pts_from(d.attrib.get("points", ""), S._ident())
                    if len(pts) >= 2:
                        prims.append(("poly", pts))
                elif t == "line":
                    p1 = (float(d.attrib.get("x1", 0)), float(d.attrib.get("y1", 0)))
                    p2 = (float(d.attrib.get("x2", 0)), float(d.attrib.get("y2", 0)))
                    prims.append(("poly", [p1, p2]))
                elif t == "ellipse":
                    prims.append(("ellipse",
                                  float(d.attrib.get("cx", 0)), float(d.attrib.get("cy", 0)),
                                  float(d.attrib.get("rx", 0)), float(d.attrib.get("ry", 0))))
                elif t == "circle":
                    r = float(d.attrib.get("r", 0))
                    prims.append(("ellipse", float(d.attrib.get("cx", 0)),
                                  float(d.attrib.get("cy", 0)), r, r))
                elif t == "path":
                    for poly, _closed in S._path_to_polylines(d.attrib.get("d", "")):
                        if len(poly) >= 2:
                            prims.append(("poly", poly))
            if prims:
                out.setdefault(gid, []).append(((sx, sy), prims))
        for c in el:
            walk(c)

    walk(root)
    return out


def _pick_instance(instances):
    # Choose the canonical instance: the most common NON-DEGENERATE scale wins, so a lone
    # zero-scaled (invisible) export quirk cannot poison the library.
    # 选取规范实例：取出现次数最多的**非退化**缩放，以免个别 scale(0) 的导出瑕疵污染整个库。
    counts = {}
    for scale, _ in instances:
        if scale[0] > 1e-6 and scale[1] > 1e-6:
            counts[scale] = counts.get(scale, 0) + 1
    if not counts:
        return (FITTING_SCALE_FALLBACK, FITTING_SCALE_FALLBACK), instances[0][1]
    best = max(sorted(counts), key=lambda k: counts[k])
    for scale, prims in instances:
        if scale == best:
            return scale, prims
    return None


def _flatten(prims, sx, sy):
    # Apply the sheet scale and drop rotation / translation / mirroring.
    # 施加图面缩放，并丢弃旋转 / 平移 / 镜像。
    out = []
    for p in prims:
        if p[0] == "poly":
            out.append(("poly", [(x * sx, y * sy) for (x, y) in p[1]]))
        else:
            _, cx, cy, rx, ry = p
            out.append(("ellipse", cx * sx, cy * sy, rx * sx, ry * sy))
    return out


def _bbox(prims):
    pts = []
    for p in prims:
        if p[0] == "poly":
            pts.extend(p[1])
        else:
            _, cx, cy, rx, ry = p
            pts.extend([(cx - rx, cy - ry), (cx + rx, cy + ry)])
    xs = [q[0] for q in pts]
    ys = [q[1] for q in pts]
    return min(xs), min(ys), max(xs), max(ys)


def _emit_svg(prims, minx, miny, w, h):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>']
    lines.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.2f %.2f" '
                 'width="%.2fmm" height="%.2fmm">' % (w, h, w, h))
    for p in prims:
        if p[0] == "poly":
            pts = " ".join("%.3f,%.3f" % (x - minx, y - miny) for (x, y) in p[1])
            lines.append('  <polyline points="%s" fill="none" stroke="#000000" '
                         'stroke-width="0.3"/>' % pts)
        else:
            _, cx, cy, rx, ry = p
            lines.append('  <ellipse cx="%.3f" cy="%.3f" rx="%.3f" ry="%.3f" fill="none" '
                         'stroke="#000000" stroke-width="0.3"/>' % (cx - minx, cy - miny, rx, ry))
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


def _slug(shape_id):
    # Strip the "_SHAPE" TOKEN, not the last six characters: DEXPI ids place the token in
    # the middle too ("..._SHAPE_CENTRAL", "..._SHAPE_FOR_PRIMARY_SEGMENT"), and a blind
    # [:-6] slice truncated those file names and collided two of them.
    # 剥掉 "_SHAPE" 这个**词元**，而非最后六个字符：DEXPI 的 id 也把词元放在中间
    #（"..._SHAPE_CENTRAL"、"..._SHAPE_FOR_PRIMARY_SEGMENT"），盲切 [:-6] 会截断文件名
    # 并让两个图元撞名。
    return shape_id.replace("_SHAPE", "").lower()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("svg")
    ap.add_argument("--out", default=os.path.join("assets", "symbol_packs", "dexpi"))
    args = ap.parse_args()

    root = ET.parse(args.svg).getroot()
    shapes = _find_shapes(root)
    if not shapes:
        print("[error] no *_SHAPE groups found in %s" % args.svg, file=sys.stderr)
        sys.exit(1)

    svg_dir = os.path.join(args.out, "svg")
    os.makedirs(svg_dir, exist_ok=True)

    icons = []
    preview = []
    for shape_id in sorted(shapes):
        instances = shapes[shape_id]
        picked = _pick_instance(instances)
        if picked is None:
            print("[skip] %s: no usable instance" % shape_id, file=sys.stderr)
            continue
        scale, prims = picked
        flat = _flatten(prims, scale[0], scale[1])
        minx, miny, maxx, maxy = _bbox(flat)
        w = max(maxx - minx, MIN_MM)
        h = max(maxy - miny, MIN_MM)
        # Re-clamp the box so a zero-width glyph still has a usable envelope.
        # 重新收紧包围盒，使零宽字形也具备可用包络。
        if maxx - minx < MIN_MM:
            maxx = minx + MIN_MM
        if maxy - miny < MIN_MM:
            maxy = miny + MIN_MM
        w = maxx - minx
        h = maxy - miny

        slug = _slug(shape_id)
        fname = "%s.svg" % slug
        with open(os.path.join(svg_dir, fname), "w", encoding="utf-8") as f:
            f.write(_emit_svg(flat, minx, miny, w, h))

        zh, en = NAMES.get(shape_id, (slug.replace("_", " "), slug.replace("_", " ").title()))
        cat = CATEGORY.get(shape_id, "general")
        icons.append({
            "id": slug,
            "file": "svg/%s" % fname,
            "name": en,
            "name_zh": zh,
            "name_en": en,
            "type": cat,
            "size_mm": [round(w, 2), round(h, 2)],
            "ports": PORTS.get(shape_id, []),
            "source_shape": shape_id,
            "instance_scale": [scale[0], scale[1]],
        })
        preview.append((slug, fname, zh, en, cat, w, h, len(instances)))
        print("[ok] %-46s -> %-11s %6.2f x %6.2f mm  (instances=%d, scale=%s)" % (
            shape_id, cat, w, h, len(instances), scale))

    manifest = {
        "name": "DEXPI Example C01",
        "source": "DEXPI Example C01 (P&ID reference drawing, SVG export)",
        "standard_ref": "DEXPI / ISO 10628",
        "license": "CC BY 4.0 (DEXPI example drawing)",
        "upstream_author": "DEXPI initiative",
        # Source code "D" keeps DEXPI ids out of the ISO namespace (LVALVE001 vs DVALVE001).
        # 来源码 "D" 使 DEXPI 的 id 与 ISO 命名空间互不重叠。
        "source_code": "D",
        # Display names resolve through I18n as "dexpi.<id>", giving the palette a real
        # 中文 / English pair instead of a single hard-coded string.
        # 显示名经 I18n 以 "dexpi.<id>" 解析，使图元库获得真正的中英对照，而非单语硬编码。
        "i18n_prefix": "dexpi",
        "icons": icons,
    }
    with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    _write_preview(os.path.join(args.out, "_preview.html"), preview)
    print("\n-> %d symbols written to %s" % (len(icons), args.out))


def _write_preview(path, rows):
    # A one-page visual check: every glyph next to its bilingual name and real mm size.
    # 一页式目检：每个字形旁列出其中英名称与真实毫米尺寸。
    parts = ["<!DOCTYPE html><html><head><meta charset='utf-8'>",
             "<title>DEXPI C01 symbols</title>",
             "<style>body{font-family:-apple-system,Segoe UI,sans-serif;margin:24px;}"
             "table{border-collapse:collapse;}td,th{border:1px solid #ccd;padding:8px;}"
             ".g{background:#fff;}</style></head><body>",
             "<h1>DEXPI C01 图元提取结果 / extracted symbols</h1>",
             "<table><tr><th>#</th><th>glyph</th><th>中文</th><th>English</th>"
             "<th>category</th><th>size (mm)</th><th>file</th></tr>"]
    for i, (slug, fname, zh, en, cat, w, h, n) in enumerate(rows, 1):
        parts.append("<tr><td>%d</td><td class='g'><img src='svg/%s' width='120'></td>"
                     "<td>%s</td><td>%s</td><td>%s</td><td>%.2f × %.2f</td><td>%s</td></tr>"
                     % (i, fname, zh, en, cat, w, h, fname))
    parts.append("</table></body></html>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))


if __name__ == "__main__":
    main()
