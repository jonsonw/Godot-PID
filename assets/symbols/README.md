# P&ID SVG Symbol Library (ISO 10628 / ISA 5.1 — sample)

This folder contains a sample set of P&ID symbols in standalone SVG format, intended as a starting point for drawings that follow ISO 10628 and ISA 5.1 conventions.

Contents
- 25 standalone SVG symbol files (stroke-only vector graphics)
- symbols-legend.svg — a printable legend/sample sheet
- mapping.csv — table mapping filenames to ISA codes and descriptions

Usage notes
- Each SVG includes metadata attributes on the top-level <svg> element: data-isa, data-iso, data-tag-example. Use these for automated processing or scripting.
- These are sample symbols and should be validated against the official ISO 10628 and ISA 5.1 documents before use in contract or installation drawings.
- To use in AutoCAD: import SVG into Illustrator or Inkscape and export as DXF/DWG (convert text to outlines where needed). Adjust stroke widths according to your drawing scale.

License
- MIT License. You are free to use, modify, and redistribute these files. No warranty is provided.

Notes about compliance
- These SVGs are designed to match common P&ID conventions and include ISA-style instrument codes, but they are not a legal substitute for the official standards. For full compliance, consult ISO 10628 and ISA 5.1.

