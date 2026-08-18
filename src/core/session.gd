class_name GPSession
extends RefCounted

# Auth stub; v1.0 is always local anonymous. See Dev Guide §4.11 seam ③.
# 鉴权桩；v1.0 恒为本地匿名。见开发指南 §4.11 接缝③。

# Local anonymous user id
# 本地匿名用户 id
var gpUserId: String = "local"

# Role: owner in v1.0
# 角色：v1.0 中恒为 owner
var gpRole: String = "owner"

# Auth token (empty until Pro)
# 鉴权令牌（Pro 前为空）
var gpToken: String = ""
