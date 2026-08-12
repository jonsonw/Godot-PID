class_name Session
extends RefCounted

# Auth stub; v1.0 is always local anonymous. See Dev Guide §4.11 seam ③.
# 鉴权桩；v1.0 恒为本地匿名。见开发指南 §4.11 接缝③。

var user_id: String = "local"   # Local anonymous user id / 本地匿名用户 id
var role: String = "owner"      # Role: owner in v1.0 / v1.0 中角色恒为 owner
var token: String = ""          # Auth token (empty until Pro) / 鉴权令牌（Pro 前为空）
