class_name GPIOResult
extends RefCounted

## Uniform result object for every operation that can fail with a reason:
## export, validation / 校验, promote, save/load, connection legality / 连接合法性.
## 统一结果对象，供一切「可能因某个原因失败」的操作使用：
## 导出、校验、promote、存读、连接合法性。
##
## Why it exists / 为何存在：
## before this, failures were reported as bare `false` or a silent `return`, so the UI could
## never tell the user WHY an export or a promote failed. Carrying an i18n KEY (not a literal
## string) keeps core translation-free while letting the shell show a localized reason.
## 此前失败只用裸 `false` 或静默 `return` 表达，界面永远无法告诉用户导出或 promote
## 为何失败。携带 i18n「键」（而非字面串）使 core 保持无翻译依赖，同时外壳能显示本地化原因。
##
## Design note / 设计说明：
## this class deliberately does NOT call the I18n autoload — core must stay free of autoload
## dependencies so it remains headless-testable. The caller passes a translator Callable in.
## 本类刻意不调用 I18n 自动加载——core 必须不依赖 autoload 才能保持 headless 可测。
## 由调用方传入翻译器 Callable。

# True when the operation succeeded.
# 操作成功时为 true。
var gpOk: bool = true

# Machine-readable failure code ("" when ok). Use dotted ids: "io.write_failed", "conn.self".
# 机器可读的失败码（成功时为 ""）。使用点分 id，如 "io.write_failed"、"conn.self"。
var gpCode: String = ""

# i18n KEY (not a literal) for the human-readable reason.
# 面向用户原因的 i18n 键（非字面串）。
var gpMessageKey: String = ""

# Optional extra detail (e.g. a filesystem path) appended verbatim, already untranslated.
# 可选的附加细节（如文件路径），原样追加，不做翻译。
var gpDetail: String = ""

# Build a success result, optionally with a message key (e.g. "io.saved").
# 构造成功结果，可附消息键（如 "io.saved"）。
static func gpSuccess(gpMessageKey: String = "", gpDetail: String = "") -> GPIOResult:
	var gpR: GPIOResult = GPIOResult.new()
	gpR.gpOk = true
	gpR.gpCode = ""
	gpR.gpMessageKey = gpMessageKey
	gpR.gpDetail = gpDetail
	return gpR


# Build a failure result. gpCode is machine-readable; gpMessageKey is an i18n key.
# 构造失败结果。gpCode 供机器读取；gpMessageKey 为 i18n 键。
static func gpFailure(gpCode: String, gpMessageKey: String, gpDetail: String = "") -> GPIOResult:
	var gpR: GPIOResult = GPIOResult.new()
	gpR.gpOk = false
	gpR.gpCode = gpCode
	gpR.gpMessageKey = gpMessageKey
	gpR.gpDetail = gpDetail
	return gpR


# Did the operation succeed?
# 操作是否成功？
func gpIsOk() -> bool:
	return gpOk


# Convenience: a failure result carries gpCode; a success never does.
# 便捷判断：失败结果必带 gpCode，成功结果必不带。
func gpFailedWith(gpWantCode: String) -> bool:
	return (not gpOk) and gpCode == gpWantCode


# Human-readable text. gpTr must be a Callable taking an i18n key and returning a String
# (typically `I18n.gpTr`), injected by the UI layer so core stays autoload-free.
# 可读文本。gpTr 须是「接收 i18n 键、返回 String」的 Callable（通常为 `I18n.gpTr`），
# 由界面层注入，使 core 保持无 autoload 依赖。
func gpText(gpTr: Callable) -> String:
	if gpMessageKey == "":
		return gpDetail
	var gpBase: String = str(gpTr.call(gpMessageKey))
	if gpDetail == "":
		return gpBase
	return "%s: %s" % [gpBase, gpDetail]


# Compact form for logs and assertions.
# 供日志与断言使用的紧凑形式。
func gpToString() -> String:
	if gpOk:
		return "OK(%s)" % gpMessageKey
	return "FAIL(%s / %s)" % [gpCode, gpMessageKey]


func _to_string() -> String:
	return gpToString()
