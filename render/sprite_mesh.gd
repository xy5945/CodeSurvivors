class_name SpriteMesh
extends Object
##
## 精灵用的四边形网格 —— 替掉引擎内置的 QuadMesh。
##
## 为什么不用 QuadMesh：实测它在 2D 下把贴图上下颠倒了（UV 的 v 轴与屏幕
## y 轴相反）。画纯色方块时看不出来，一旦贴上有明确上下的素材（比如小恐龙），
## 就会整只倒过来 —— 腿在上、头在下。
##
## 这里显式给出 UV：屏幕上方（y 为负）的顶点取贴图顶端（v=0）。
## 验证方式：godot --path . -- --shot 截一张真实画面看敌人朝向。
##

static func quad(size: float) -> ArrayMesh:
	return quad_uv(size, size, Rect2(0.0, 0.0, 1.0, 1.0))


## 带宽高与 UV 子区域的版本：敌人精灵表是横条（一帧挨一帧），
## 每个 (类型×帧) 的 MultiMesh 用同一个 QuadMesh 只画表里的那一格。
static func quad_uv(w: float, h: float, uv: Rect2) -> ArrayMesh:
	var hw := w * 0.5
	var hh := h * 0.5
	# 顶点顺序：左上 → 右上 → 右下 → 左下（2D 屏幕坐标，y 向下为正）
	var verts := PackedVector3Array([
		Vector3(-hw, -hh, 0.0),
		Vector3(hw, -hh, 0.0),
		Vector3(hw, hh, 0.0),
		Vector3(-hw, hh, 0.0),
	])
	# UV：Godot 贴图原点在左上角，所以 v=0 是顶端 —— 给屏幕上方顶点配 v=0
	var L := uv.position.x
	var T := uv.position.y
	var R := uv.end.x
	var B := uv.end.y
	var uvs := PackedVector2Array([
		Vector2(L, T),
		Vector2(R, T),
		Vector2(R, B),
		Vector2(L, B),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
