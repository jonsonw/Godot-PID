#!/usr/bin/env bash
# 测量 G-PID 编辑器启动耗时，并列出真正的「停顿点」。
# Measure the G-PID editor startup cost and list the real stalls.
#
# 为什么需要这个脚本 / Why this exists:
# 只看总耗时无法定位问题。Godot 的 --verbose 输出里，真正的时间都花在「相邻两行之间
# 没人打印」的那几段静默期；把每行打上相对时间戳，再筛出间隔 > 0.3s 的停顿，才能看出
# 是引擎着色器缓存、脚本文档缓存，还是恢复场景在吃时间。
# A single total number tells you nothing. In Godot's --verbose stream the real cost sits in
# the SILENT gaps between lines; timestamp every line, then filter gaps > 0.3s, and you can
# tell whether the engine shader cache, the script doc cache, or the restored scene is eating
# the time.
#
# 用法 / Usage:
#   tools/measure_editor_startup.sh [项目路径]
#   项目路径默认取脚本所在仓库根目录（本脚本在 tools/ 下）。
#
# 注意 / Caveats:
# - 测的是 **GUI 编辑器**（含 GPU / 着色器缓存 / 资源预览）；headless 的
#   `--editor --quit` 只要 2 秒，因为它跳过了这些，**不能**用它评估真实体感。
# - `--quit-after 240` 是干净退出路径，但它**不会**写回 `.godot/editor/editor_script_doc_cache.res`；
#   反复测量会让下一次真实启动重建该缓存（多花约 1 秒）。

set -uo pipefail

GP_GODOT_BIN="${GP_GODOT_BIN:-/Users/macbook/Godot/Godot.app/Contents/MacOS/Godot}"
GP_FRAMES="${GP_FRAMES:-240}"
GP_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GP_PROJECT="${1:-$(cd "$GP_HERE/.." && pwd)}"
GP_PY="${GP_PY:-python3}"

echo "Godot  : $GP_GODOT_BIN  ($("$GP_GODOT_BIN" --version 2>/dev/null))"
echo "项目   : $GP_PROJECT"
echo "退出帧 : $GP_FRAMES"
echo "---"

"$GP_GODOT_BIN" --path "$GP_PROJECT" --editor --verbose --quit-after "$GP_FRAMES" 2>&1 \
	| "$GP_PY" -u -c '
import sys, time
t0 = time.time()
prev = 0.0
last = 0.0
previews = 0
stalls = []
for line in sys.stdin:
    t = time.time() - t0
    if t - prev > 0.3:
        stalls.append((prev, t, line.strip()[:80]))
    prev = t
    last = t
    if "preview in" in line:
        previews += 1
print("启动完成于 %.2fs   文本资源预览 %d 条" % (last, previews))
if stalls:
    print("停顿点（间隔 > 0.3s）:")
    for a, b, l in stalls:
        print("  %6.2fs → %6.2fs  (%.2fs)  %s" % (a, b, b - a, l))
else:
    print("无 > 0.3s 的停顿")
'
