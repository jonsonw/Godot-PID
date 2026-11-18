# Copyright 2026 G-PID Contributors. MIT License. See LICENSE.
class_name GPSheetIdentity
extends RefCounted

# Stable identity for NEW sheets (2026-11-18 duplicate-number fix). Never derive a sheet id or
# display-name index from a tab counter: the counter is reset by gpLoadSheets, so deleting the
# first sheet and creating a new one re-minted the SURVIVOR's id/name ("002 图纸 2" twice),
# which also broke activation, saving and cross-sheet link references.
# 新建图纸的**稳定身份**（2026-11-18 重号修复）：id 与显示名序号都不得从标签计数器推导。
# 该计数器会被 gpLoadSheets 重置 —— 删掉第一张再新建，就会重铸幸存图纸的 id 与名称
#（两个「002 图纸 2」），进而破坏激活、保存与跨图连接引用。
#
# Pure core statics: the caller supplies the already-collected sheet list, so nothing here
# reaches the UI or an autoload. Old archives keep their "sheet-N" ids verbatim — this file
# only mints identities for sheets born after the fix.
# 纯 core 静态：调用方传入已收集的图纸列表，本文件不触碰 UI 或 autoload。旧存档的
# "sheet-N" id 原样保留 —— 本文件只为修复后新生的图纸铸身份。
#
# Coding rule: every variable declares its type explicitly. / 编码规范：所有变量均显式声明类型。

# A collision-free opaque id. gpTick is injectable for deterministic tests; production passes
# the default (milliseconds since epoch) and a 6-digit random suffix.
# 无碰撞的不透明 id。gpTick 可注入以便测试确定性；生产用默认（epoch 毫秒）+ 6 位随机后缀。
static func gpNewId(gpSheets: Array, gpTick: int = -1) -> String:
	var gpUsed: Dictionary = {}
	for gpRaw in gpSheets:
		var gpSheet: GPSheet = gpRaw as GPSheet
		if gpSheet != null:
			gpUsed[gpSheet.gpId] = true
	var gpBase: int = gpTick if gpTick >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	for gpI in range(128):
		var gpId: String = "sheet-s%d-%06d" % [gpBase + gpI, randi() % 1000000]
		if not gpUsed.has(gpId):
			return gpId
	return "sheet-s%d-r%d" % [gpBase, randi()]


# Next display-name index = highest trailing number across ALL existing names + 1. Reading the
# trailing digits (not a hard-coded locale prefix) keeps both "图纸 2" and "Sheet 2" working;
# hand-named sheets such as "PFD" simply do not occupy a slot.
# 下一个显示名序号 = 全部现存名称末尾数字的最大值 +1。只读末尾数字（不硬编码语言前缀），
# 「图纸 2」与「Sheet 2」都成立；手改的「PFD」之类名称自然不占槽位。
static func gpNextNameIndex(gpSheets: Array) -> int:
	var gpMax: int = 0
	for gpRaw in gpSheets:
		var gpSheet: GPSheet = gpRaw as GPSheet
		if gpSheet == null:
			continue
		gpMax = maxi(gpMax, GPSheetNumbering.gpSequenceOf(gpSheet.gpName))
	return gpMax + 1
