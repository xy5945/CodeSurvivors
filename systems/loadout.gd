class_name Loadout
extends RefCounted
##
## 玩家持有物：武器等级 + 被动等级 + 由被动聚合出来的属性。
##
## 关键设计：武器实例只在这里创建，等级变化时调用 weapon.apply_stats() 把
## 数值"烤"进武器字段。热路径（每帧命中判定）读的是普通浮点字段，
## 不会去查字典 —— 字典查找在几百次/帧的量级上不是免费的。
##
## 武器是"按需创建"的：只有玩家真正选到它时才实例化。
## 未获得的武器不在 weapons 数组里，连 update() 的空转都省掉。
##

# 具名引用：分支长鞭的表现层（whip_arc）需要直接读它的挥击状态。
# 未持有分支长鞭时为 null，读取方需自行判空。
var whip: WhipWeapon
var orbit: OrbitWeapon

var weapons := []       # 所有已获得的武器实例，sim 每帧遍历它
var weapon_map := {}    # id -> 实例

# id -> 等级。0 或不存在 = 未持有。
var levels := {}

# ---- 被动聚合结果（recompute 时统一算一次）----
var max_hp_bonus := 0.0
var move_speed_mult := 1.0
var pickup_range_mult := 1.0
var damage_mult := 1.0
var cooldown_mult := 1.0
var pickup_range := GameConfig.PICKUP_RANGE


func setup() -> void:
	levels["whip"] = 1          # 起始武器：分支长鞭 Lv1
	recompute()


func level_of(id: String) -> int:
	return int(levels.get(id, 0))


func apply_upgrade(id: String) -> void:
	levels[id] = level_of(id) + 1
	recompute()


func recompute() -> void:
	max_hp_bonus = 0.0
	move_speed_mult = 1.0
	pickup_range_mult = 1.0
	damage_mult = 1.0
	cooldown_mult = 1.0

	for id in levels:
		var lv := level_of(id)
		if lv <= 0:
			continue
		var d := UpgradeDefs.def_of(id)
		if d["kind"] != UpgradeDefs.KIND_PASSIVE:
			continue
		# 被动是累加的：Lv3 的效果 = 第 1、2、3 级效果之和
		for i in lv:
			var s: Dictionary = d["levels"][i]
			if s.has("max_hp"):
				max_hp_bonus += float(s["max_hp"])
			if s.has("move_speed"):
				move_speed_mult += float(s["move_speed"])
			if s.has("pickup_range"):
				pickup_range_mult += float(s["pickup_range"])
			if s.has("damage"):
				damage_mult += float(s["damage"])
			if s.has("cooldown"):
				cooldown_mult *= float(s["cooldown"])

	pickup_range = GameConfig.PICKUP_RANGE * pickup_range_mult

	for id in levels:
		var lv := level_of(id)
		if lv <= 0:
			continue
		var d := UpgradeDefs.def_of(id)
		if d["kind"] != UpgradeDefs.KIND_WEAPON:
			continue

		var w = weapon_map.get(id)
		if w == null:
			w = _make_weapon(str(id))
			if w == null:
				continue
			weapon_map[id] = w
			weapons.append(w)
			if id == "whip":
				whip = w
			elif id == "orbit":
				orbit = w

		w.apply_stats(lv, self)


func _make_weapon(id: String):
	match id:
		"whip":
			return WhipWeapon.new()
		"orbit":
			return OrbitWeapon.new()
		"broadcast":
			return BroadcastWeapon.new()
		"judgment":
			return JudgmentWeapon.new()
		"blade":
			return BladeWeapon.new()
		"pointer":
			return PointerWeapon.new()
	return null


func weapon_count() -> int:
	var c := 0
	for id in levels:
		if level_of(id) > 0 and UpgradeDefs.def_of(id)["kind"] == UpgradeDefs.KIND_WEAPON:
			c += 1
	return c


func passive_count() -> int:
	var c := 0
	for id in levels:
		if level_of(id) > 0 and UpgradeDefs.def_of(id)["kind"] == UpgradeDefs.KIND_PASSIVE:
			c += 1
	return c


## 抽 n 个升级选项。返回 [{def, level}]，level 是"选了之后会变成几级"。
## 过滤规则：已满级的不出现；未持有的受武器/被动数量上限约束。
## 池子不够时用"紧急补丁"兜底 —— 高等级时必然会出现"没东西可升级"的情况。
func roll_choices(n: int) -> Array:
	var pool := []
	for u in UpgradeDefs.UPGRADES:
		var lv := level_of(u["id"])
		if lv >= int(u["max"]):
			continue
		if lv == 0:
			if int(u["kind"]) == UpgradeDefs.KIND_WEAPON and weapon_count() >= GameConfig.MAX_WEAPONS:
				continue
			if int(u["kind"]) == UpgradeDefs.KIND_PASSIVE and passive_count() >= GameConfig.MAX_PASSIVES:
				continue
		pool.append(u)

	pool.shuffle()

	var out := []
	for i in mini(n, pool.size()):
		var d: Dictionary = pool[i]
		out.append({"def": d, "level": level_of(d["id"]) + 1})
	while out.size() < n:
		out.append({"def": UpgradeDefs.HEAL_PICK, "level": 1})
	return out
