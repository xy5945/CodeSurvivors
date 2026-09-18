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
# 需要常驻视觉的武器（光环 / 蓄力环）由 AuraRenderer 直接读，
# 走具名引用而不是在 weapons 里遍历 —— 渲染每帧都要拿，别做字符串查找。
var forever: ForeverWeapon
var buffer: BufferWeapon
var rebuild: RebuildWeapon
# 断言（断点调试进化）要在敌人死亡时连锁，死亡判定在 sim._reap，
# 走具名引用最快 —— 那里每帧都可能被调到。
# 注意：不能叫 breakpoint —— 那是 GDScript 的保留字（调试断点语句），
# 用作变量名会报 "Expected variable name after var"。
var breakpoint_w: BreakpointWeapon

var weapons := []       # 所有已获得的武器实例，sim 每帧遍历它
var weapon_map := {}    # id -> 实例

# id -> 等级。0 或不存在 = 未持有。
var levels := {}

# 已完成的进化：武器 id -> true。不进 levels —— 进化不是"第 9 级"，
# 它是换一种行为，混进 levels 会让"满级"和"命中上限"之类的判断全线出错。
var evolved := {}

# ---- 被动聚合结果（recompute 时统一算一次）----
var max_hp_bonus := 0.0
var move_speed_mult := 1.0
var pickup_range_mult := 1.0
var damage_mult := 1.0
var cooldown_mult := 1.0
var pickup_range := GameConfig.PICKUP_RANGE

# ---- 角色修正（由 sim.setup 注入，见 core/char_defs.gd）----
# 放在 loadout 里是因为武器数值在 apply_stats 时就要用到它，
# 而 apply_stats 只拿得到 loadout。
var char_dmg_mult := 1.0
var char_cd_mult := 1.0
var char_pickup_mult := 1.0
var char_trait := CharDefs.T_LEARN


func setup(start_weapon := "whip") -> void:
	levels[start_weapon] = 1    # 起始武器由角色决定
	recompute()


## 全部武器立刻冷却完毕（算法工程师「递归返回」）。
## 只清真实存在的实例：环绕类和力场类没有冷却字段，跳过即可。
func reset_weapon_cooldowns() -> void:
	for w in weapons:
		if "cooldown" in w:
			w.cooldown = 0.0


func level_of(id: String) -> int:
	return int(levels.get(id, 0))


func apply_upgrade(id: String) -> void:
	levels[id] = level_of(id) + 1
	recompute()


## 完成一次进化。进化不吃等级：它只是把武器换一种行为，
## 数值（伤害/冷却）仍然走 8 级表的满级那一档。
func apply_evolution(id: String) -> void:
	var d := EvolveDefs.def_of(id)
	if d.is_empty():
		return
	evolved[str(d["base"])] = true
	recompute()


func is_evolved(id: String) -> bool:
	return bool(evolved.get(id, false))


## 当前已满足解锁条件、但还没拿的进化。
##
## 条件：对应武器满级 + 指定被动满级。两者都是"满级"而不是"拿到就行"，
## 是因为进化是这局最后的追求目标 —— 随便就能拿到的话，
## 玩家在第 5 分钟就把 Build 定死了，后面 15 分钟没有期待。
func available_evolutions() -> Array:
	var out := []
	for e in EvolveDefs.EVOLUTIONS:
		var base := str(e["base"])
		if is_evolved(base):
			continue
		var wd := UpgradeDefs.def_of(base)
		var pd := UpgradeDefs.def_of(str(e["passive"]))
		if level_of(base) < int(wd["max"]):
			continue
		if level_of(str(e["passive"])) < int(pd["max"]):
			continue
		out.append(e)
	return out


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

	# 角色修正：被动加成算完再乘，这样"被动 + 角色"是叠乘而不是互相覆盖
	damage_mult *= char_dmg_mult
	cooldown_mult *= char_cd_mult
	# 架构师「模块堆叠」：每多一把武器，伤害再 +5%。
	# 它奖励的是"铺开拿武器"而不是"死堆一把"，和被动的线性加成不是一回事。
	if char_trait == CharDefs.T_MODULE:
		var wcount := 0
		for id in levels:
			if level_of(id) > 0 and int(UpgradeDefs.def_of(id)["kind"]) == UpgradeDefs.KIND_WEAPON:
				wcount += 1
		damage_mult += CharDefs.MODULE_DMG * float(wcount)

	pickup_range = GameConfig.PICKUP_RANGE * pickup_range_mult * char_pickup_mult

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
			elif id == "forever":
				forever = w
			elif id == "buffer":
				buffer = w
			elif id == "rebuild":
				rebuild = w
			elif id == "breakpoint":
				breakpoint_w = w

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
		"volley":
			return VolleyWeapon.new()
		"gc":
			return GcWeapon.new()
		"buffer":
			return BufferWeapon.new()
		"breakpoint":
			return BreakpointWeapon.new()
		"forever":
			return ForeverWeapon.new()
		"rebuild":
			return RebuildWeapon.new()
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

	# 进化必占一席（最多一席，多条同时满足时随机取一条）。
	# 不塞进池子里随机抽：玩家把武器和被动都刷满是很明确的投入，
	# 结果还要靠运气才看得到进化卡，体验上等于"我白刷了"。
	var evos := available_evolutions()
	if not evos.is_empty():
		out.append({"def": evos[randi() % evos.size()], "level": 1})

	while out.size() < n and not pool.is_empty():
		out.append({"def": pool[0], "level": level_of(str(pool[0]["id"])) + 1})
		pool.remove_at(0)

	while out.size() < n:
		out.append({"def": UpgradeDefs.HEAL_PICK, "level": 1})
	return out
