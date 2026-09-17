class_name Targeting
extends RefCounted
##
## 目标选择。追踪弹每帧都要用，所以全程不开方（比的是距离平方），
## 并且不分配任何对象 —— 只返回索引，调用方自己去池子里读坐标。
##
## exclude / exclude2：让"向多个不同目标各发一发"不用维护临时数组。
## 两个排除位够用到 3 连发（第 3 发排除前两个），再多就该上重型结构了。
##

static func nearest(sim, g: SpatialGrid, e: EnemyPool, x: float, y: float,
		max_r: float, exclude := -1, exclude2 := -1) -> int:
	var best := -1
	var best_d2 := max_r * max_r

	var n := g.query(x, y, max_r)
	var k := 0
	while k < n:
		var j := g.out[k]
		k += 1
		if j == exclude or j == exclude2:
			continue
		var dx := e.px[j] - x
		var dy := e.py[j] - y
		var d2 := dx * dx + dy * dy
		if d2 <= best_d2:
			best_d2 = d2
			best = j

	return best


##
## 排除一批目标后再找最近的。
##
## 指针追踪满级是 6 发齐射，"每发换一个目标"要排除前 5 个 —— 两个排除位不够用。
## 传数组进来而不是加 exclude3/4/5/6：调用方复用同一个数组，零分配。
## excl_n = "前几个元素有效"，省掉每次 resize。
##
## 只有齐射这种低频场景用它。每帧都要跑的追踪用 nearest（零分配、走局部变量）。
##
static func nearest_except(sim, g: SpatialGrid, e: EnemyPool, x: float, y: float,
		max_r: float, excl: PackedInt32Array, excl_n: int) -> int:
	var best := -1
	var best_d2 := max_r * max_r

	var n := g.query(x, y, max_r)
	var k := 0
	while k < n:
		var j := g.out[k]
		k += 1
		var skip := false
		for m in excl_n:
			if excl[m] == j:
				skip = true
				break
		if skip:
			continue
		var dx := e.px[j] - x
		var dy := e.py[j] - y
		var d2 := dx * dx + dy * dy
		if d2 <= best_d2:
			best_d2 = d2
			best = j

	return best
