class_name LocalFileBackend
extends StorageBackend

# v1.0 default storage backend: read/write the local *.pid.json file.
# v1.0 默认存储后端：读写本地 *.pid.json 文件。
# See Dev Guide §4.11.
# 见开发指南 §4.11。

func write(doc: Dictionary, uri: String) -> bool:
	# TODO: FileAccess store JSON to uri
	# TODO：用 FileAccess 将 JSON 写入 uri
	return false

func read(uri: String) -> Dictionary:
	# TODO: FileAccess + JSON.parse from uri
	# TODO：用 FileAccess + JSON.parse 从 uri 读取
	return {}
