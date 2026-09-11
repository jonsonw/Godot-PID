class_name GPLinetypeMaterial
extends RefCounted
# Copyright © 2026 Jonson Wang
# Builds the shared Linetype GPU material used by the dashed-edge ink path
# (GPEdgeView, behind GP_GPU_DASH). Compiling one shader and cloning the material per
# edge is far cheaper than compiling the shader for every edge.
# 构建虚线边墨线路径（GPEdgeView，受 GP_GPU_DASH 开关控制）所用的共享 Linetype GPU 材质。
# 只需编译一次着色器、按边克隆材质，远比每条边都编译着色器省。
# 编码规范：所有变量均显式声明类型。

const GP_SHADER_PATH: String = "res://assets/shaders/linetype.gdshader"

# One compiled material shared by every edge (the shader is shared by the engine).
# 每条边共享的一份已编译材质（着色器由引擎共享）。
static var gpShared: ShaderMaterial = null


# Return a per-edge material clone carrying the Linetype shader.
# 返回携带 Linetype 着色器的按边材质克隆。
static func gpMake() -> ShaderMaterial:
	if gpShared == null:
		var gpSh: Shader = load(GP_SHADER_PATH) as Shader
		gpShared = ShaderMaterial.new()
		gpShared.shader = gpSh
	var gpM: ShaderMaterial = ShaderMaterial.new()
	gpM.shader = gpShared.shader
	return gpM
