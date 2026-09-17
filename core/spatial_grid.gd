class_name SpatialGrid
extends RefCounted
##
## 空间哈希网格：把"敌人两两比较"从 O(n²) 降到 O(n·k)。
##
## 为什么必须有它：
##   800 个敌人两两比较 = 320000 次距离计算/帧，直接爆掉帧预算。
##   用网格后，每个敌人只查自己周围 3×3 个格子，通常只命中几个候选。
##
## 实现要点：
##   用 heads + next 两条数组组成链表（不是"每格一个 Array"）。
##   这样每帧重建是 fill(-1) + 一次遍历，零内存分配，没有 GC 抖动。
##

var cell := 64.0
var cols := 1
var rows := 1
var origin_x := 0.0
var origin_y := 0.0

var heads := PackedInt32Array()   # 每个格子链表的头（实体索引），-1 表示空
var next := PackedInt32Array()    # 链表中下一个实体索引

var out := PackedInt32Array()     # 查询结果复用缓冲，避免每次 new
var out_count := 0


func setup(cell_size: float, half_extent: float, cap: int) -> void:
	cell = cell_size
	var span := half_extent * 2.0
	cols = maxi(1, int(ceil(span / cell)))
	rows = cols
	origin_x = -half_extent
	origin_y = -half_extent
	heads.resize(cols * rows)
	next.resize(cap)
	out.resize(cap)
	# 必须初始化成 -1：任何"还没 rebuild 就 query"的调用（例如测试脚本在
	# step 之前查最近敌人）会读到全 0，next[0]==0 让链表自环，
	# 死循环把 out 写爆 —— 报出来的错是 out 越界，根因却在这里。
	heads.fill(-1)


func _cx(x: float) -> int:
	return clampi(int((x - origin_x) / cell), 0, cols - 1)


func _cy(y: float) -> int:
	return clampi(int((y - origin_y) / cell), 0, rows - 1)


## 每帧调用一次。O(n)。
func rebuild(pool: EnemyPool) -> void:
	heads.fill(-1)
	var n := pool.count
	var i := 0
	while i < n:
		var ci := _cy(pool.py[i]) * cols + _cx(pool.px[i])
		next[i] = heads[ci]
		heads[ci] = i
		i += 1


## 查询 (x,y) 周围半径 r 覆盖到的所有格子里的实体索引。
## 结果写入 out[0..返回值)，调用方需自行做精确距离判断。
##
## limit：最多返回多少个候选。
##   分离计算必须传一个较小的 limit（见 GameConfig.SEP_MAX_CHECKS）——
##   敌群中心一个格子里可能有上百个实体，全遍历会让耗时随密度平方增长。
##   武器命中判定要传默认值（不限），否则会漏掉本该打中的敌人。
##
## 注意：返回的是"格子里的全部实体"，比真实圆范围大，这是空间网格的固有特性。
func query(x: float, y: float, r: float, limit: int = 2147483647) -> int:
	out_count = 0
	var min_cx := _cx(x - r)
	var max_cx := _cx(x + r)
	var min_cy := _cy(y - r)
	var max_cy := _cy(y + r)

	var cy := min_cy
	while cy <= max_cy:
		var row := cy * cols
		var cx := min_cx
		while cx <= max_cx:
			var i := heads[row + cx]
			while i != -1 and out_count < limit:
				out[out_count] = i
				out_count += 1
				i = next[i]
			cx += 1
		cy += 1
	return out_count
