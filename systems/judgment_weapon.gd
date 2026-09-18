class_name JudgmentWeapon
extends RefCounted
##
## 随机数审判 `random_judgment`：在屏幕内随机位置降下落雷。
##
## 第 4 级有个转折：落点从"真随机"改成 **随机抽一个敌人所在的位置**。
## 这看起来像是加权算法，其实只是从敌人群里等概率抽一个 ——
## 敌人越密集的地方，被抽中的概率自然越高。
##
## 玩家的主观感受是"这武器突然变聪明了"，但严格说它依然是个随机数。
## 这正是"伪随机"的语义，也是设计给玩家的小惊喜。
##

var enabled := false
var damage := 0.0
var cd_base := 0.0
var radius := 0.0
var bolt_count := 1
var weighted := false
var dot_dps := 0.0
var hit_cap := 0        # 单道落雷的命中上限（0 = 不限）
var evolved := false    # 随机种子：同点三连击

var cooldown := 0.0


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("judgment", level)
	damage = float(s["dmg"]) * lo.damage_mult
	cd_base = float(s["cd"]) * lo.cooldown_mult
	radius = float(s["radius"])
	bolt_count = int(s["bolts"])
	weighted = bool(s["weighted"])
	dot_dps = float(s["dot"]) * lo.damage_mult
	hit_cap = int(s["hit_cap"])
	enabled = true
	evolved = lo.is_evolved("judgment")


func update(dt: float, sim) -> void:
	if not enabled:
		return
	cooldown -= dt
	if cooldown > 0.0:
		return
	cooldown = cd_base
	sim.sfx_events.append("bolt")

	var i := 0
	while i < bolt_count:
		var tx: float
		var ty: float

		if weighted and sim.enemies.count > 0:
			# 从敌人群里等概率抽一个 —— 密度高的地方自然更容易被抽中
			var j: int = randi() % sim.enemies.count
			tx = sim.enemies.px[j] + randf_range(-28.0, 28.0)
			ty = sim.enemies.py[j] + randf_range(-28.0, 28.0)
		else:
			# sqrt 是为了让落点在圆内均匀分布，否则会全部挤在中心
			var a := randf() * TAU
			var d := sqrt(randf()) * GameConfig.JUDGMENT_SCREEN_R
			tx = sim.player_x + cos(a) * d
			ty = sim.player_y + sin(a) * d

		# 随机种子：同一个落点连摇三次。
		# 每一击都单独算命中上限 —— 这才是它值钱的地方：
		# 满级单发封顶 28 个，三连击就是三个独立的 28，
		# 敌群越密越明显。单发伤害砍到 55%，总伤 1.65 倍但**覆盖**是 3 倍。
		var times := 3 if evolved else 1
		var mul := 0.55 if evolved else 1.0
		for k in times:
			var jx := 0.0
			var jy := 0.0
			if evolved:
				jx = randf_range(-16.0, 16.0)
				jy = randf_range(-16.0, 16.0)
			sim.fx.strike(sim, tx + jx, ty + jy, radius, damage * mul, dot_dps, hit_cap)
		i += 1
