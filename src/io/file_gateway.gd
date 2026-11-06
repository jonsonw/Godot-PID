class_name GPFileGateway
extends RefCounted
# Copyright © 2026 Jonson Wang
# The file-system primitives of the application. ADR-2 / ADR-4 say the io layer is the ONLY place
# that touches FileAccess / DirAccess; this class is where that right is actually exercised, so
# the boundary is one file instead of forty.
# 应用的文件系统原语层。ADR-2 / ADR-4 规定 io 层是**唯一**触碰 FileAccess / DirAccess 的地方；
# 本类就是行使该权利的那一处，使边界收敛到一个文件而不是四十处。
#
# WHY A SHARED PRIMITIVE LAYER / 为何要一层共享原语：
# The W12 review found the same four lines (make the directory, open, store, close) copy-pasted
# into a dialogs, an autoload, a coordinator and two core classes. Five copies means five chances
# to forget the null check and five places to change if the error handling ever improves. These
# are PRIMITIVES: no schema, no domain knowledge, no policy. Anything that knows what the bytes
# MEAN belongs in a domain class (e.g. GPSymbolPackStore, GPDRCReportFile), not here.
# W12 审查发现同样的四行（建目录、open、store、close）被复制进对话框、autoload、协调器与两个 core
# 类。五份拷贝就是五次漏写空判断的机会，也是错误处理改进时要改的五处。本类只提供**原语**：
# 不认 schema、不带领域知识、不做策略。任何"知道这些字节是什么意思"的东西都属于领域类
#（如 GPSymbolPackStore、GPDRCReportFile），不在这里。
#
# The ONE policy that does live here is crash safety: every write is atomic (ADR-4). A plain
# "overwrite in place" primitive would exist only to be misused — its only advantage over the
# atomic one is being four lines shorter, and its failure mode is a truncated archive. So there
# is no non-atomic write in this API and callers cannot opt out of it.
# 唯一留在本类的策略是崩溃安全：每次写入都是原子的（ADR-4）。"原地覆写"这种原语存在的唯一意义
# 就是被误用 —— 它相比原子写只短四行，而失效形式是存档被截断。故本 API 不提供非原子写，
# 调用方也无法选择退出。
#
# FAILURE POLICY IS "RETURN, DON'T THROW" / 失败策略是"返回，不抛"：
# Every function degrades to a falsy value ("" / false / empty array) instead of pushing an error.
# Callers that care show the failure to the user; callers that do not (a missing optional file)
# stay silent. This is the behaviour the old per-call-site copies had, kept deliberately.
# 每个函数都退化为假值（"" / false / 空数组）而不报错。在意的调用方把失败显示给用户；不在意的
#（可选的缺失文件）保持沉默。这正是旧的一处处拷贝所具备的行为，刻意保留。
#
# Coding rule: every variable declares its type explicitly.
# 编码规范：所有变量均显式声明类型。


# Read a whole UTF-8 text file. Returns "" when the file is missing or unreadable.
# 读取整个 UTF-8 文本文件。文件缺失或不可读时返回 ""。
static func gpReadText(gpPath: String) -> String:
	if gpPath == "" or not FileAccess.file_exists(gpPath):
		return ""
	var gpFile: FileAccess = FileAccess.open(gpPath, FileAccess.READ)
	if gpFile == null:
		return ""
	var gpText: String = gpFile.get_as_text()
	gpFile.close()
	return gpText


# Read a whole file as raw bytes. Returns an empty array when the file is missing or unreadable.
# 读取整个文件的原始字节。文件缺失或不可读时返回空数组。
static func gpReadBytes(gpPath: String) -> PackedByteArray:
	if gpPath == "" or not FileAccess.file_exists(gpPath):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(gpPath)


# Write text to a file, creating parent directories as needed. True on success.
# 把文本写入文件，必要时递归创建父目录。成功返回 true。
#
# THIS WRITE IS CRASH-SAFE / 本次写入是崩溃安全的：
# It delegates to GPAtomicFile (tmp -> verify -> bak -> rename), so a process killed mid-write
# leaves the previous file intact instead of a truncated one. That matters here more than it
# looks: the five callers of this function are the symbol packs, the project standard, the repair
# plan and both DRC reports — every one of them is user-authored content that exists nowhere
# else. Before 2026-11-06 this function was a direct store_string, i.e. the ADR-4 guarantee held
# for *.pid.json but silently did not hold for these five.
# 委托给 GPAtomicFile（tmp -> 校验 -> bak -> rename），故写入途中进程被杀时留下的是**上一份完好
# 文件**，而不是截断的文件。这一点在此比看上去更重要：本函数的五个调用方分别是图元包、项目标准、
# 修复计划与两份 DRC 报告 —— 每一个都是别处没有副本的用户产出。2026-11-06 之前本函数是直接
# store_string，即 ADR-4 的保证对 *.pid.json 成立、对上述五类**静默不成立**。
#
# The bool return is kept (not GPIOResult) because every caller only asks "did it land?" and
# shows the path itself; converting them to the result type would add five unused branches.
# 保留 bool 返回（不用 GPIOResult）：调用方只问"写成了吗"并自己显示路径；改成结果类型只会
# 多出五处用不上的分支。
static func gpWriteText(gpPath: String, gpText: String) -> bool:
	if gpPath == "":
		return false
	var gpDir: String = gpPath.get_base_dir()
	if gpDir != "" and gpDir != gpPath and not gpEnsureDir(gpDir):
		return false
	return GPAtomicFile.gpWriteAtomic(gpPath, gpText).gpIsOk()


# Whether a regular file exists.
# 常规文件是否存在。
static func gpFileExists(gpPath: String) -> bool:
	if gpPath == "":
		return false
	return FileAccess.file_exists(gpPath)


# Whether a directory exists.
# 目录是否存在。
static func gpDirExists(gpDir: String) -> bool:
	if gpDir == "":
		return false
	return DirAccess.dir_exists_absolute(gpDir)


# Create a directory and every missing parent. True when the directory exists afterwards.
# Godot accepts res:// / user:// paths here; the globalize step is what makes a plain relative
# path behave the same way the old call sites expected.
# 递归创建目录及其所有缺失的父目录。创建后目录存在即返回 true。Godot 此处接受 res:// 与 user://
# 路径；globalize 一步使普通相对路径的表现与旧调用点一致。
static func gpEnsureDir(gpDir: String) -> bool:
	if gpDir == "":
		return false
	if DirAccess.dir_exists_absolute(gpDir):
		return true
	var gpErr: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(gpDir))
	if gpErr != OK:
		return false
	return DirAccess.dir_exists_absolute(gpDir)


# List the FILES (not directories) directly under gpDir, optionally filtered by a suffix
# (e.g. ".json"). Order is whatever the OS returns — callers that need a stable order sort.
# 列出 gpDir 下的**文件**（不含目录），可按后缀过滤（如 ".json"）。顺序即系统返回顺序 ——
# 需要稳定顺序的调用方自行排序。
static func gpListFiles(gpDir: String, gpSuffix: String = "") -> PackedStringArray:
	var gpOut: PackedStringArray = PackedStringArray()
	if gpDir == "" or not DirAccess.dir_exists_absolute(gpDir):
		return gpOut
	var gpDirAccess: DirAccess = DirAccess.open(gpDir)
	if gpDirAccess == null:
		return gpOut
	for gpName in gpDirAccess.get_files():
		if gpSuffix == "" or str(gpName).ends_with(gpSuffix):
			gpOut.append(str(gpName))
	return gpOut


# Delete one file. True when it is gone afterwards — including when it never existed, because a
# delete of an absent file has already achieved the caller's goal. This matches the old inline
# "if exists: remove" pairs, which also returned success for a missing file.
# 删除一个文件。删除后文件不存在即返回 true —— 包括原本就不存在的情形，因为"删一个不存在的文件"
# 已经达成了调用方的目的。这与旧的内联"若存在则删除"写法一致，那种写法对缺失文件也返回成功。
static func gpDeleteFile(gpPath: String) -> bool:
	if gpPath == "" or not FileAccess.file_exists(gpPath):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(gpPath)) == OK


# Delete a file together with the .tmp / .bak siblings a crash-safe write leaves behind.
# 连同崩溃安全写入留下的 .tmp / .bak 伴生文件一起删除。
# WHY THIS IS NEEDED / 为何需要它：
# Since gpWriteText became atomic, deleting only the target leaves a .bak holding the very data
# the user just asked to delete. The readers filter by suffix so nothing breaks visibly — the
# user would simply find "deleted" content still sitting on disk, and a later re-creation of the
# same id would inherit a stale backup. Deletion has to cover the archive, not just the file.
# 自 gpWriteText 改为原子写后，只删目标会留下一个 .bak，里面正是用户要求删除的数据。各读取方按
# 后缀过滤，故表面上不会出错 —— 用户只会发现「已删除」的内容还躺在磁盘上，并且同一 id 日后重建
# 时会继承一份过期的备份。删除必须覆盖整个存档，而不只是那个文件。
static func gpDeleteArchive(gpPath: String) -> bool:
	if gpPath == "":
		return false
	GPAtomicFile.gpDiscardTempRemains(gpPath)
	gpDeleteFile(GPAtomicFile.gpBackupPath(gpPath))
	return gpDeleteFile(gpPath)
