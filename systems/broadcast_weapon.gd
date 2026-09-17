class_name BroadcastWeapon
extends RefCounted
##
## 广播冲击波 `broadcast_pulse`：以玩家为中心发出一圈向外扩散的消息波，
## 波扫过的敌人受伤。每个敌人每次广播只挨一次。
##
## 第 4 级的"回卷"就是 Scratch 里 **`广播并等待`** 那个积木 ——
## 发完消息，等所有人都处理完，再往回收。语义完全对上。
##
## 它是所有武器里碰撞开销最低的：每帧只需要维护一个当前半径，
## 判断"距离落在上一帧半径与这一帧半径之间"即可（见 FxStore）。
##

var enabled := false
var damage := 0.0
var cd_base := 0.0
var max_r := 0.0
var spd := 0.0
var can_back := false
var back_bonus := 1.0
var hit_cap := 0        # 每波命中上限（0 = 不限，见 FxStore._damage_ring）

var cooldown := 0.0


func apply_stats(level: int, lo: Loadout) -> void:
	var s := UpgradeDefs.stats_for("broadcast", level)
	damage = float(s["dmg"]) * lo.damage_mult
	cd_base = float(s["cd"]) * lo.cooldown_mult
	max_r = float(s["max_r"])
	spd = float(s["spd"])
	can_back = bool(s["back"])
	back_bonus = float(s["back_bonus"])
	hit_cap = int(s["hit_cap"])
	enabled = true


func update(dt: float, sim) -> void:
	if not enabled:
		return
	cooldown -= dt
	if cooldown > 0.0:
		return
	cooldown = cd_base
	sim.fx.add_wave(sim.player_x, sim.player_y, max_r, spd, damage, can_back, back_bonus, hit_cap)
