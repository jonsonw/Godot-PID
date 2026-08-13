class_name GPStorageBackend
extends RefCounted

# Storage backend interface (Dev Guide §4.11 seam ①). Persistence depends on this,
# not on files directly. v1.0 uses LocalFileBackend.
# 存储后端接口（开发指南 §4.11 接缝①）。Persistence 依赖本接口而非直接碰文件。v1.0 用 LocalFileBackend。
func gpWrite(gpDoc: Dictionary, gpUri: String) -> bool:
	return false

func gpRead(gpUri: String) -> Dictionary:
	return {}
