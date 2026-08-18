class_name GPLocalFileBackend
extends GPStorageBackend

# v1.0 default storage backend: read/write the local *.pid.json file.
# v1.0 默认存储后端：读写本地 *.pid.json 文件。
# See Dev Guide §4.11.
# 见开发指南 §4.11。

# Write a document dictionary to a local file URI.
# 将文档字典写入本地文件 URI。
func gpWrite(gpDoc: Dictionary, gpUri: String) -> bool:
	# TODO: FileAccess store JSON to uri
	# TODO：用 FileAccess 将 JSON 写入 uri
	return false


# Read a document dictionary from a local file URI.
# 从本地文件 URI 读取文档字典。
func gpRead(gpUri: String) -> Dictionary:
	# TODO: FileAccess + JSON.parse from uri
	# TODO：用 FileAccess + JSON.parse 从 uri 读取
	return {}
