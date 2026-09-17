class_name UpgradeDefs
extends RefCounted
##
## 升级项纯数据。武器数值与武器设计文档严格一致，
## 改数值时请同时改文档，避免两边漂移。
##
## 每项结构：
##   id      唯一标识，也是 Loadout.levels 的键
##   kind    KIND_WEAPON / KIND_PASSIVE
##   name    显示名
##   icon    语法符号（卡片上的大字符）
##   sub     代码注释风格的一句话，是主题感最强的地方
##   max     满级
##   levels  长度为 max 的数组，索引 i = 升到 (i+1) 级时的效果
##

const KIND_WEAPON := 0
const KIND_PASSIVE := 1

## 从 Lv n 升到 Lv n+1 所需经验。索引 0 = Lv1→Lv2。
## 曲线目标：前期几秒就升一级（立刻给正反馈），20 分钟一局约 60 级。
##
## 尾部斜率是被实测推着调的：原 +250/级 时，10 分钟后每级要 2000+ 经验，
## 而中后期经验获取率稳定在 ~1900/分 —— 两者撞上了，
## 表现为 8~10 分钟整整 3 分钟不弹升级（冒烟日志 Lv35 卡住三次）。
## 幸存者品类的核心爽点就是"升级三选一"，长时间不弹 = 后半程体验塌掉。
## 降到 +160 后升级间隔回到 40~50 秒，全程都有正反馈。
const EXP_TABLE := [
	4, 7, 11, 15, 21, 27, 34, 42, 51, 61,
	72, 84, 97, 111, 126, 142, 159, 177, 196, 216,
	237, 259, 282, 306, 331, 357, 384, 412, 441, 471,
]


static func exp_to_next(level: int) -> int:
	if level <= EXP_TABLE.size():
		return EXP_TABLE[level - 1]
	return EXP_TABLE[EXP_TABLE.size() - 1] + (level - EXP_TABLE.size()) * 160


const UPGRADES := [
	# ================= 武器 =================
	{
		"id": "whip", "kind": KIND_WEAPON, "name": "分支长鞭", "icon": "if",
		"sub": "// 条件成立，就往这一边抽下去",
		"max": 8,
		"levels": [
			{"desc": "朝面朝方向挥出鞭击，最多命中 10 个", "dmg": 12.0, "cd": 1.2, "reach": 110.0, "branches": 1, "push": 0.0, "heal": 0.0, "hit_cap": 10 },
			{"desc": "伤害 +4，范围 +8", "dmg": 16.0, "cd": 1.18, "reach": 116.0, "branches": 1, "push": 0.0, "heal": 0.0, "hit_cap": 11 },
			{"desc": "伤害 +4，冷却 -0.05s", "dmg": 20.0, "cd": 1.14, "reach": 122.0, "branches": 1, "push": 0.0, "heal": 0.0, "hit_cap": 12 },
			{"desc": "增加一条反向鞭：前后同时攻击", "dmg": 23.0, "cd": 1.1, "reach": 128.0, "branches": 2, "push": 0.0, "heal": 0.0, "hit_cap": 14 },
			{"desc": "伤害 +3，范围 +8，命中上限 +2", "dmg": 25.0, "cd": 1.05, "reach": 134.0, "branches": 2, "push": 0.0, "heal": 0.0, "hit_cap": 16 },
			{"desc": "伤害 +3，命中时击退", "dmg": 27.0, "cd": 1.02, "reach": 140.0, "branches": 2, "push": 14.0, "heal": 0.0, "hit_cap": 18 },
			{"desc": "增加一条垂直鞭：上下也打得到", "dmg": 29.0, "cd": 0.98, "reach": 144.0, "branches": 3, "push": 14.0, "heal": 0.0, "hit_cap": 21 },
			{"desc": "伤害 +4，范围 +5；每次挥鞭回复 6 点生命", "dmg": 32.0, "cd": 0.95, "reach": 148.0, "branches": 3, "push": 14.0, "heal": 6.0, "hit_cap": 24 },
		],
	},
	{
		"id": "orbit", "kind": KIND_WEAPON, "name": "循环护盾", "icon": "for",
		"sub": "// 同样的事，一直做下去",
		"max": 8,
		"levels": [
			{"desc": "2 个环绕物绕身旋转，碰到的敌人受击", "orbiters": 2, "dmg": 12.0, "radius": 65.0, "spin": 2.2, "hit_cd": 0.50},
			{"desc": "伤害 +2，半径 +6", "orbiters": 2, "dmg": 12.0, "radius": 71.0, "spin": 2.4, "hit_cd": 0.5},
			{"desc": "环绕物 2 → 3", "orbiters": 3, "dmg": 14.0, "radius": 77.0, "spin": 2.6, "hit_cd": 0.47},
			{"desc": "伤害 +3，半径 +5", "orbiters": 3, "dmg": 17.0, "radius": 82.0, "spin": 2.8, "hit_cd": 0.44},
			{"desc": "环绕物 3 → 4", "orbiters": 4, "dmg": 20.0, "radius": 87.0, "spin": 3.0, "hit_cd": 0.41},
			{"desc": "伤害 +3，环绕物 4 → 5", "orbiters": 5, "dmg": 23.0, "radius": 91.0, "spin": 3.2, "hit_cd": 0.38},
			{"desc": "伤害 +4，半径 +3", "orbiters": 5, "dmg": 26.0, "radius": 94.0, "spin": 3.4, "hit_cd": 0.35},
			{"desc": "环绕物 5 → 6，转速拉满", "orbiters": 6, "dmg": 29.0, "radius": 96.0, "spin": 3.6, "hit_cd": 0.33},
		],
	},

	{
		"id": "broadcast", "kind": KIND_WEAPON, "name": "广播冲击波", "icon": "bcast",
		"sub": "// 喊一嗓子，让所有人都听见",
		"max": 8,
		"levels": [
			{"desc": "向四周发出一圈消息波，最多命中 16 个", "dmg": 14.0, "cd": 3.0, "max_r": 120.0, "spd": 240.0, "back": false, "back_bonus": 1.0, "hit_cap": 30 },
			{"desc": "伤害 +2，最大半径 +8，命中上限 +6", "dmg": 15.0, "cd": 2.95, "max_r": 125.0, "spd": 255.0, "back": false, "back_bonus": 1.0, "hit_cap": 36 },
			{"desc": "伤害 +2，最大半径 +8，命中上限 +6", "dmg": 17.0, "cd": 2.9, "max_r": 130.0, "spd": 270.0, "back": false, "back_bonus": 1.0, "hit_cap": 42 },
			{"desc": "波到边缘后回卷，二次伤害（广播并等待）", "dmg": 18.0, "cd": 2.85, "max_r": 135.0, "spd": 285.0, "back": true, "back_bonus": 1.0, "hit_cap": 50 },
			{"desc": "伤害 +2，最大半径 +4，命中上限 +8", "dmg": 20.0, "cd": 2.8, "max_r": 139.0, "spd": 300.0, "back": true, "back_bonus": 1.0, "hit_cap": 58 },
			{"desc": "伤害 +2，最大半径 +4，命中上限 +10", "dmg": 21.0, "cd": 2.75, "max_r": 143.0, "spd": 315.0, "back": true, "back_bonus": 1.0, "hit_cap": 68 },
			{"desc": "伤害 +2，最大半径 +4，命中上限 +10", "dmg": 22.0, "cd": 2.68, "max_r": 147.0, "spd": 330.0, "back": true, "back_bonus": 1.0, "hit_cap": 78 },
			{"desc": "伤害 +2，最大半径 +4，命中上限 +12；回卷伤害 +30%", "dmg": 24.0, "cd": 2.6, "max_r": 152.0, "spd": 350.0, "back": true, "back_bonus": 1.3, "hit_cap": 90 },
		],
	},
	{
		"id": "judgment", "kind": KIND_WEAPON, "name": "随机数审判", "icon": "rand()",
		"sub": "// 落哪儿，全看运气",
		"max": 8,
		"levels": [
			{"desc": "随机位置降下 1 道落雷，最多命中 12 个", "dmg": 30.0, "cd": 3.5, "radius": 45.0, "bolts": 1, "weighted": false, "dot": 0.0, "hit_cap": 12 },
			{"desc": "伤害 +8，半径 +5", "dmg": 38.0, "cd": 3.2, "radius": 50.0, "bolts": 1, "weighted": false, "dot": 0.0, "hit_cap": 13 },
			{"desc": "落雷数 1 → 2", "dmg": 44.0, "cd": 3.0, "radius": 52.0, "bolts": 2, "weighted": false, "dot": 0.0, "hit_cap": 15 },
			{"desc": "落点改为敌群密度加权 —— 它变聪明了", "dmg": 52.0, "cd": 2.8, "radius": 56.0, "bolts": 2, "weighted": true, "dot": 0.0, "hit_cap": 17 },
			{"desc": "落雷数 2 → 3", "dmg": 60.0, "cd": 2.6, "radius": 60.0, "bolts": 3, "weighted": true, "dot": 0.0, "hit_cap": 19 },
			{"desc": "伤害 +10，冷却 -0.2s，命中上限 +3", "dmg": 70.0, "cd": 2.4, "radius": 63.0, "bolts": 3, "weighted": true, "dot": 0.0, "hit_cap": 22 },
			{"desc": "落雷数 3 → 4", "dmg": 82.0, "cd": 2.2, "radius": 66.0, "bolts": 4, "weighted": true, "dot": 0.0, "hit_cap": 25 },
			{"desc": "伤害 +13，命中上限 +3；落雷留下 0.5s 电痕持续伤害", "dmg": 95.0, "cd": 2.0, "radius": 70.0, "bolts": 4, "weighted": true, "dot": 57.0, "hit_cap": 28 },
		],
	},
	{
		"id": "blade", "kind": KIND_WEAPON, "name": "递归飞刃", "icon": "rec()",
		"sub": "// 每一次调用，都会分裂出一个更弱的自己",
		"max": 8,
		"levels": [
			{"desc": "飞出一把飞刃，命中后弹向下一个目标", "dmg": 18.0, "cd": 1.1, "pspeed": 420.0, "bounces": 2, "decay": 0.60, "spd_bonus": 0.0},
			{"desc": "伤害 +4，冷却 -0.08s，弹射 +1", "dmg": 22.0, "cd": 1.02, "pspeed": 430.0, "bounces": 3, "decay": 0.62, "spd_bonus": 0.0},
			{"desc": "伤害 +4，弹射 +1", "dmg": 26.0, "cd": 0.94, "pspeed": 440.0, "bounces": 3, "decay": 0.65, "spd_bonus": 0.0},
			{"desc": "伤害 +4，冷却 -0.10s", "dmg": 30.0, "cd": 0.86, "pspeed": 450.0, "bounces": 4, "decay": 0.68, "spd_bonus": 0.0},
			{"desc": "伤害 +5，弹射 +1", "dmg": 35.0, "cd": 0.78, "pspeed": 460.0, "bounces": 4, "decay": 0.72, "spd_bonus": 0.04},
			{"desc": "伤害 +5，弹射 +1", "dmg": 40.0, "cd": 0.7, "pspeed": 470.0, "bounces": 5, "decay": 0.76, "spd_bonus": 0.06},
			{"desc": "伤害 +7，弹射 +1", "dmg": 47.0, "cd": 0.6, "pspeed": 480.0, "bounces": 6, "decay": 0.80, "spd_bonus": 0.07},
			{"desc": "伤害 +8，弹射 +1，衰减放缓至 85%", "dmg": 55.0, "cd": 0.48, "pspeed": 490.0, "bounces": 7, "decay": 0.85, "spd_bonus": 0.08},
		],
	},
	{
		"id": "pointer", "kind": KIND_WEAPON, "name": "指针追踪", "icon": "*p",
		"sub": "// 只要拿到地址，就一定能找到",
		"max": 8,
		"levels": [
			{"desc": "发射必中的追踪弹（1 发）", "dmg": 22.0, "cd": 2.20, "radius": 260.0, "bolts": 1, "pspeed": 340.0, "pierce": 0, "mark": false},
			{"desc": "伤害 +5，追踪范围 +25", "dmg": 27.0, "cd": 2.00, "radius": 285.0, "bolts": 1, "pspeed": 350.0, "pierce": 0, "mark": false},
			{"desc": "伤害 +5，弹数 1 → 2", "dmg": 32.0, "cd": 1.80, "radius": 310.0, "bolts": 2, "pspeed": 360.0, "pierce": 0, "mark": false},
			{"desc": "命中标记目标：受伤 +10%（3 秒）", "dmg": 36.0, "cd": 1.65, "radius": 335.0, "bolts": 2, "pspeed": 370.0, "pierce": 0, "mark": true},
			{"desc": "伤害 +5，弹数 2 → 3，可穿透 1 个目标", "dmg": 41.0, "cd": 1.50, "radius": 365.0, "bolts": 3, "pspeed": 380.0, "pierce": 1, "mark": true},
			{"desc": "伤害 +5，冷却 -0.10s", "dmg": 46.0, "cd": 1.40, "radius": 400.0, "bolts": 3, "pspeed": 400.0, "pierce": 1, "mark": true},
			{"desc": "伤害 +6，弹数 3 → 4", "dmg": 52.0, "cd": 1.30, "radius": 440.0, "bolts": 4, "pspeed": 420.0, "pierce": 1, "mark": true},
			{"desc": "伤害 +6，冷却 -0.15s；弹速翻倍，可穿透 2 个目标", "dmg": 58.0, "cd": 1.15, "radius": 600.0, "bolts": 4, "pspeed": 680.0, "pierce": 2, "mark": true},
		],
	},

	# ================= 被动 =================
	{
		"id": "malloc", "kind": KIND_PASSIVE, "name": "内存扩容", "icon": "malloc",
		"sub": "// 先申请一块更大的空间",
		"max": 5,
		"levels": [
			{"desc": "生命上限 +20", "max_hp": 20.0},
			{"desc": "生命上限 +20", "max_hp": 20.0},
			{"desc": "生命上限 +20", "max_hp": 20.0},
			{"desc": "生命上限 +20", "max_hp": 20.0},
			{"desc": "生命上限 +20", "max_hp": 20.0},
		],
	},
	{
		"id": "overclock", "kind": KIND_PASSIVE, "name": "超频", "icon": "OC",
		"sub": "// 跑得快一点，但要注意散热",
		"max": 5,
		"levels": [
			{"desc": "移动速度 +8%", "move_speed": 0.08},
			{"desc": "移动速度 +8%", "move_speed": 0.08},
			{"desc": "移动速度 +8%", "move_speed": 0.08},
			{"desc": "移动速度 +8%", "move_speed": 0.08},
			{"desc": "移动速度 +8%", "move_speed": 0.08},
		],
	},
	{
		"id": "ptr", "kind": KIND_PASSIVE, "name": "磁吸指针", "icon": "*ptr",
		"sub": "// 让指针自己找到地址",
		"max": 5,
		"levels": [
			{"desc": "拾取范围 +35%", "pickup_range": 0.35},
			{"desc": "拾取范围 +35%", "pickup_range": 0.35},
			{"desc": "拾取范围 +35%", "pickup_range": 0.35},
			{"desc": "拾取范围 +35%", "pickup_range": 0.35},
			{"desc": "拾取范围 +35%", "pickup_range": 0.35},
		],
	},
	{
		"id": "optimize", "kind": KIND_PASSIVE, "name": "编译器优化", "icon": "-O2",
		"sub": "// 全局伤害提升，代价是编译更久",
		"max": 5,
		"levels": [
			{"desc": "全部伤害 +8%", "damage": 0.08},
			{"desc": "全部伤害 +8%", "damage": 0.08},
			{"desc": "全部伤害 +8%", "damage": 0.08},
			{"desc": "全部伤害 +8%", "damage": 0.08},
			{"desc": "全部伤害 +8%", "damage": 0.08},
		],
	},
	{
		"id": "thread", "kind": KIND_PASSIVE, "name": "多线程", "icon": "thread",
		"sub": "// 几件事一起做",
		"max": 5,
		"levels": [
			{"desc": "武器冷却 -8%", "cooldown": 0.92},
			{"desc": "武器冷却 -8%", "cooldown": 0.92},
			{"desc": "武器冷却 -8%", "cooldown": 0.92},
			{"desc": "武器冷却 -8%", "cooldown": 0.92},
			{"desc": "武器冷却 -8%", "cooldown": 0.92},
		],
	},
]

## 兜底选项：武器和被动都满级（或没得选）时给出，不占等级、不进 levels。
const HEAL_PICK := {
	"id": "_heal", "kind": KIND_PASSIVE, "name": "紧急补丁", "icon": "hotfix",
	"sub": "// 先补上再说，注释以后再写",
	"max": 999,
	"levels": [{"desc": "立刻回复 30 点生命", "heal_now": 30.0}],
}


## 取某个升级项升到第 level 级时的效果字典。level 从 1 起。
static func stats_for(id: String, level: int) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u["levels"][mini(level, u["levels"].size()) - 1]
	return {}


static func def_of(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return HEAL_PICK
