# Copyright 2026 G-PID Contributors. MIT License. See LICENSE.
# A2 (W12 closure plan §4.2): thin container-level wrapper over the live off-page link
# table. The array itself stays THE single source of truth — commands and providers keep
# holding the same array by reference (no data moves) — but every mutation now flows
# through here so ONE signal (`gpChanged`) can drive the snapshot republish, the dirty
# mark and the repaints. This kills the D03 root cause: 10+ call sites that each had to
# "remember" to call gpRefreshOffPageContext(); forgetting one meant "screen right /
# file not dirty".
# A2（W12 收口方案 §4.2）：容器级 link 表的**薄封装**。数组本身仍是唯一事实源 —— 命令与
# 来源依旧按引用持有同一个数组（数据不搬家）—— 但一切变更必须流经此处，让**一个**信号
# （gpChanged）统一驱动快照重发、脏标记与重绘。这根治了 D03 的病根：10+ 处调用点各自
# 「记得」调 gpRefreshOffPageContext()，漏一处就是「显示对了 / 文件没脏」。
# Layering: core/service — references GPOffPageLink (core/model) only; zero UI/autoload.
# 分层：core/service —— 仅引用 GPOffPageLink（core/model）；零 UI / autoload 依赖。
class_name GPOffPageStore
extends RefCounted

## Emitted after ANY mutation accepted through this store. Reasons: "add" / "remove" /
## "attr" (in-place attribute or flag edit) / "replace" (bulk swap, e.g. project load) /
## "history" (an undo/redo settled a cross-sheet command).
## 本 store 接受的任何变更之后发出。reason：add（新增）/ remove（移除）/
## attr（原地属性或旗标编辑）/ replace（整体替换，如工程载入）/ history（撤销/重做落定）。
signal gpChanged(gpReason: String)

# Bound BY REFERENCE to the container's live array (GPCenterArea.gpOffPageLinks).
# Never re-assigned afterwards — gpReplaceAll mutates it in place so that every command
# and provider that captured the array earlier keeps seeing the truth.
# 按引用绑定到容器的**活**数组（GPCenterArea.gpOffPageLinks）。此后绝不重新赋值 ——
# gpReplaceAll 原地改写，使早前捕获了该数组的每条命令与每个来源继续看到真相。
var _gpLinks: Array[GPOffPageLink] = []


## Bind the store to the container's live array. MUST be called once before use; the
## argument is kept by reference, not copied.
## 把 store 绑定到容器的活数组。使用前必须调用一次；参数按引用保留，不做复制。
func gpSetup(gpLinks: Array[GPOffPageLink]) -> void:
	_gpLinks = gpLinks


## The live link table (same identity the commands mutate — never a copy).
## **活的** link 表（与命令改写的是同一身份 —— 绝不复制）。
func gpLinks() -> Array[GPOffPageLink]:
	return _gpLinks


## Append one link and notify ("add"). No-op on null (defensive: callers already
## guarantee non-null, but a silent no-op beats a crash in a signal-driven path).
## 追加一条 link 并通知（add）。null 时静默跳过（防御：调用方已保证非空，但信号驱动的
## 路径里静默跳过优于崩溃）。
func gpAdd(gpLink: GPOffPageLink) -> void:
	if gpLink == null:
		return
	_gpLinks.append(gpLink)
	gpTouch("add")


## Remove the FIRST occurrence of [param gpLink] and notify ("remove").
## Returns true when something was actually removed.
## 移除**第一处** [param gpLink] 并通知（remove）。确实移除了东西才返回真。
func gpRemove(gpLink: GPOffPageLink) -> bool:
	if gpLink == null:
		return false
	var gpIdx: int = _gpLinks.find(gpLink)
	if gpIdx < 0:
		return false
	_gpLinks.remove_at(gpIdx)
	gpTouch("remove")
	return true


## Bulk-swap the CONTENTS in place (clear + append): array identity survives, so earlier
## captures (commands, providers, the store binding itself) stay valid. Notifies "replace".
## 原地整体替换内容（clear + append）：数组身份不变，早前捕获（命令、来源、store 绑定
## 本身）全部继续有效。通知 replace。
func gpReplaceAll(gpList: Array[GPOffPageLink]) -> void:
	_gpLinks.clear()
	for gpLink in gpList:
		if gpLink != null:
			_gpLinks.append(gpLink)
	gpTouch("replace")


## The ONE notification path (D03): emit gpChanged. Every mutation funnels here; direct
## array writes outside the store bypass the notification and are a contract violation.
## 唯一通知路径（D03）：发出 gpChanged。一切变更汇流于此；绕过本 store 直接写数组会
## 跳过通知，属违反契约。
func gpTouch(gpReason: String = "attr") -> void:
	gpChanged.emit(gpReason)


## D09: re-mint every NON-manual link tag after a sheet renumber, as
## "<peer (B) sheet number>-<seq>" — the same convention the create command uses. A link
## whose attrs carry tag_manual is a deliberate hand choice and is skipped (identical to
## edge renumbering). Pure over the link array + the {sheet_id -> number} map; returns the
## number of tags actually rewritten.
## D09：图纸重编号后重铸**非手改**的 link 编号，形如「<对端(B)图号>-<序号>」—— 与创建
## 命令同一惯例。attrs 带 tag_manual 的 link 是刻意的手改选择，跳过（与边重编号一致）。
## 对 link 数组 + {sheet_id -> 图号} 映射的纯函数；返回实际重写的编号数。
static func gpRenumberTags(gpLinks: Array[GPOffPageLink], gpNumbers: Dictionary) -> int:
	var gpCount: int = 0
	var gpSeq: int = 0
	for gpL in gpLinks:
		gpSeq += 1
		if gpL == null or bool(gpL.gpAttrs.get("tag_manual", false)):
			continue
		var gpPeerId: String = str(gpL.gpB.get(GPOffPageLink.GP_KEY_SHEET, ""))
		var gpPeerNum: String = str(gpNumbers.get(gpPeerId, ""))
		var gpWant: String = (gpPeerNum + "-" + str(gpSeq)) if gpPeerNum != "" else str(gpSeq)
		if gpWant != gpL.gpTag:
			gpL.gpTag = gpWant
			gpCount += 1
	return gpCount
