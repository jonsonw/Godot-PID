class_name GPIdentityCredentials
extends RefCounted
# Copyright © 2026 Jonson Wang
# Password hashing for user identity (ADR-40 D4; W14). Pure computation, zero I/O.
# 用户身份的密码哈希（ADR-40 D4；W14）。纯计算，零 I/O。
#
# SECURITY POSITION / 安全定位（ADR-40 D8, honest）：
# SHA-256 + per-user salt + fixed iterations. NOT GPU-brute-force resistant — the model is
# "防误操作 / 留痕可追溯", and credentials NEVER leave the local machine (D4), so the
# hash material is never exposed on a share. Cloud-grade KDFs are a Cloud-line decision.
# SHA-256 + 每用户独立盐 + 固定迭代次数。**不抗 GPU 爆破** —— 模型定位是「防误操作 /
# 留痕可追溯」，且凭据**绝不离开本机**（D4），哈希材料从不出现在共享盘上。
# 云级 KDF 属 Cloud 线决策。
#
# LAYER RULE / 分层约束：pure static helpers, zero autoload / FileAccess — core stays
# headless-testable. Crypto / HashingContext are engine classes, not autoloads.
# 纯静态助手，零 autoload / FileAccess —— core 保持 headless 可测。
# Crypto / HashingContext 是引擎类，不是 autoload。

# Frozen iteration count (W14 plan §7; changing it invalidates every stored hash).
# 冻结的迭代次数（W14 方案 §7；改动会使全部已存哈希失效）。
const GP_ITERATIONS: int = 4096

# Salt length in bytes (16 bytes = 128 bits of entropy, hex-encoded to 32 chars).
# 盐的字节长度（16 字节 = 128 位熵，十六进制编码为 32 字符）。
const GP_SALT_BYTES: int = 16

# Minimum accepted password length for first-time setup.
# 首次设置密码的最短长度。
const GP_MIN_PASSWORD_LEN: int = 6


# Fresh random salt, hex-encoded. / 新随机盐，十六进制编码。
static func gpNewSalt() -> String:
	var gpBytes: PackedByteArray = Crypto.new().generate_random_bytes(GP_SALT_BYTES)
	return gpBytes.hex_encode()


# Iterated hash: digest_0 = sha256(salt || password); digest_i = sha256(digest_{i-1}).
# Returns the hex digest. The salt stays OUTSIDE the iteration chain on purpose — it is
# stored in the clear next to the hash, so it must not be hidden inside it.
# 迭代哈希：digest_0 = sha256(salt || password)；digest_i = sha256(digest_{i-1})。
# 返回十六进制摘要。盐刻意置于迭代链之外 —— 它以明文与哈希并列存放，
# 不应被藏进链里。
static func gpHashPassword(gpPassword: String, gpSalt: String) -> String:
	var gpDigest: PackedByteArray = _gpSha256((gpSalt + gpPassword).to_utf8_buffer())
	for gpI in range(GP_ITERATIONS - 1):
		gpDigest = _gpSha256(gpDigest)
	return gpDigest.hex_encode()


# Verify a password against a stored salt + hash.
# 以存储的盐 + 哈希校验密码。
static func gpVerify(gpPassword: String, gpSalt: String, gpExpected: String) -> bool:
	if gpSalt == "" or gpExpected == "":
		return false
	return gpHashPassword(gpPassword, gpSalt) == gpExpected


# First-time setup gate: reject empty and too-short passwords (honest minimum).
# 首次设置闸：拒绝空密码与过短密码（诚实下限）。
static func gpIsValidPassword(gpPassword: String) -> bool:
	return gpPassword.length() >= GP_MIN_PASSWORD_LEN


# SHA-256 of raw bytes. / 原始字节的 SHA-256。
static func _gpSha256(gpData: PackedByteArray) -> PackedByteArray:
	var gpCtx: HashingContext = HashingContext.new()
	gpCtx.start(HashingContext.HASH_SHA256)
	gpCtx.update(gpData)
	return gpCtx.finish()
