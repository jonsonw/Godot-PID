# Copyright © 2026 Jonson Wang
# MIT License — converted from open-pid-icons (npm, MIT, Copyright 2025 tbo47)
# Convert open-pid-icons.json into individual SVG files and a manifest.

import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT: Path = Path(__file__).parent
JSON_PATH: Path = ROOT / "open-pid-icons.json"
OUT_DIR: Path = ROOT / "svg"


def gp_safe_id(name: str) -> str:
    """Convert a human readable icon name into a snake_case file name."""
    safe: str = re.sub(r"[^a-zA-Z0-9 ]", "", name)
    return re.sub(r"\s+", "_", safe.strip()).lower()


def gp_write_svg(item: dict, out_path: Path) -> None:
    """Wrap the SVG path data into a standalone SVG file."""
    width: int = int(item.get("width", 64))
    height: int = int(item.get("height", 64))
    path_d: str = item.get("path", "")

    ns: str = "http://www.w3.org/2000/svg"
    svg: ET.Element = ET.Element("svg", {
        "xmlns": ns,
        "viewBox": f"0 0 {width} {height}",
        "width": str(width),
        "height": str(height)
    })
    if path_d != "":
        ET.SubElement(svg, "path", {
            "d": path_d,
            "fill": "none",
            "stroke": "currentColor",
            "stroke-width": "2"
        })

    tree: ET.ElementTree = ET.ElementTree(svg)
    tree.write(str(out_path), encoding="utf-8", xml_declaration=True)


def gp_run_conversion() -> None:
    """Read the upstream JSON and emit one SVG per icon plus a manifest."""
    raw_text: str = JSON_PATH.read_text(encoding="utf-8")
    dataset: dict = json.loads(raw_text)
    icons: list[dict] = dataset.get("data", [])

    OUT_DIR.mkdir(exist_ok=True)
    manifest: dict = {
        "source": "open-pid-icons@1.0.0 (npm, MIT)",
        "license": "MIT",
        "upstream_author": "tbo47",
        "icons": []
    }

    icon_info: dict
    for icon_info in icons:
        file_id: str = gp_safe_id(icon_info["name"])
        svg_path: Path = OUT_DIR / f"{file_id}.svg"
        gp_write_svg(icon_info, svg_path)

        manifest["icons"].append({
            "id": file_id,
            "name": icon_info["name"],
            "type": icon_info.get("type", ""),
            "file": f"svg/{file_id}.svg",
            "width": icon_info.get("width", 0),
            "height": icon_info.get("height", 0),
            "anchors": icon_info.get("anchors", [])
        })

    manifest_path: Path = ROOT / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Wrote {len(icons)} SVGs to {OUT_DIR} and manifest to {manifest_path}")


if __name__ == "__main__":
    gp_run_conversion()
