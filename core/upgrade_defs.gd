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
##   char    可选：专属角色 id。写了就只有该角色能拿到这把武器
##           （见 can_use）。5 个角色的起始武器都带这个键 ——
##           角色 = 开局打法，专属武器就是这份"打法差异"的载体：
##           实习生是先手近战，测试工程师是控制，算法工程师是远程穿透，
##           全栈工程师是贴身力场，架构师是环绕防御。
##           其他人拿不到，才不会出现"选谁最后都玩成同一套 build"。
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
		"char": "intern",
		"sub": "// 条件成立，就往这一边抽下去",
		"max": 8,
		"levels": [
			{"desc": "朝面朝方向挥出鞭击，最多命中 10 个", "dmg": 12.0, "cd": 1.2, "reach": 110.0, "branches": 1, "stun": 0.0, "heal": 0.0, "hit_cap": 10 },
			{"desc": "伤害 +4，范围 +8", "dmg": 16.0, "cd": 1.18, "reach": 116.0, "branches": 1, "stun": 0.0, "heal": 0.0, "hit_cap": 11 },
			{"desc": "伤害 +4，冷却 -0.05s", "dmg": 20.0, "cd": 1.14, "reach": 122.0, "branches": 1, "stun": 0.0, "heal": 0.0, "hit_cap": 12 },
			{"desc": "增加一条反向鞭：前后同时攻击", "dmg": 23.0, "cd": 1.1, "reach": 128.0, "branches": 2, "stun": 0.0, "heal": 0.0, "hit_cap": 14 },
			{"desc": "伤害 +3，范围 +8，命中上限 +2", "dmg": 25.0, "cd": 1.05, "reach": 134.0, "branches": 2, "stun": 0.0, "heal": 0.0, "hit_cap": 16 },
			{"desc": "伤害 +3，命中时定身 0.2 秒", "dmg": 27.0, "cd": 1.02, "reach": 140.0, "branches": 2, "stun": 0.20, "heal": 0.0, "hit_cap": 18 },
			{"desc": "增加一条垂直鞭：上下也打得到；定身 0.26 秒", "dmg": 29.0, "cd": 0.98, "reach": 144.0, "branches": 3, "stun": 0.26, "heal": 0.0, "hit_cap": 21 },
			{"desc": "伤害 +4，范围 +5，定身 0.32 秒；每次挥鞭回复 6 点生命", "dmg": 32.0, "cd": 0.95, "reach": 148.0, "branches": 3, "stun": 0.32, "heal": 6.0, "hit_cap": 24 },
		],
	},
	{
		"id": "orbit", "kind": KIND_WEAPON, "name": "循环护盾", "icon": "for",
		"char": "arch",
		"sub": "// 同样的事，一直做下去",
		"max": 8,
		"levels": [
			{"desc": "2 个环绕物绕身旋转，命中时回复 3 点生命（环绕物越多，吸血越弱）", "orbiters": 2, "dmg": 12.0, "radius": 65.0, "spin": 2.2, "hit_cd": 0.50, "lifesteal": 3.0},
			{"desc": "伤害 +2，半径 +6，吸血 3 → 2.5", "orbiters": 2, "dmg": 12.0, "radius": 71.0, "spin": 2.4, "hit_cd": 0.5, "lifesteal": 2.5},
			{"desc": "环绕物 2 → 3，吸血 → 2", "orbiters": 3, "dmg": 14.0, "radius": 77.0, "spin": 2.6, "hit_cd": 0.47, "lifesteal": 2.0},
			{"desc": "伤害 +3，半径 +5，吸血 → 1.5", "orbiters": 3, "dmg": 17.0, "radius": 82.0, "spin": 2.8, "hit_cd": 0.44, "lifesteal": 1.5},
			{"desc": "环绕物 3 → 4，吸血 → 1", "orbiters": 4, "dmg": 20.0, "radius": 87.0, "spin": 3.0, "hit_cd": 0.41, "lifesteal": 1.0},
			{"desc": "伤害 +3，环绕物 4 → 5，吸血 → 0.6", "orbiters": 5, "dmg": 23.0, "radius": 91.0, "spin": 3.2, "hit_cd": 0.38, "lifesteal": 0.6},
			{"desc": "伤害 +4，半径 +3，吸血 → 0.3", "orbiters": 5, "dmg": 26.0, "radius": 94.0, "spin": 3.4, "hit_cd": 0.35, "lifesteal": 0.3},
			{"desc": "环绕物 5 → 6，转速拉满，吸血归零（靠输出站住）", "orbiters": 6, "dmg": 29.0, "radius": 96.0, "spin": 3.6, "hit_cd": 0.33, "lifesteal": 0.0},
		],
	},

	{
		"id": "broadcast", "kind": KIND_WEAPON, "name": "广播冲击波", "icon": "bcast",
		"sub": "// 喊一嗓子，让所有人都听见",
		"max": 8,
		"levels": [
			{"desc": "向四周发出一圈消息波，最多命中 16 个", "dmg": 14.0, "cd": 3.55, "max_r": 100.0, "spd": 240.0, "back": false, "back_bonus": 1.0, "hit_cap": 16 },
			{"desc": "伤害 +2，最大半径 +8，命中上限 +4", "dmg": 15.0, "cd": 3.48, "max_r": 108.0, "spd": 255.0, "back": false, "back_bonus": 1.0, "hit_cap": 20 },
			{"desc": "伤害 +2，最大半径 +8，命中上限 +4", "dmg": 17.0, "cd": 3.41, "max_r": 116.0, "spd": 270.0, "back": false, "back_bonus": 1.0, "hit_cap": 24 },
			{"desc": "波到边缘后回卷，二次伤害（广播并等待）", "dmg": 18.0, "cd": 3.34, "max_r": 121.0, "spd": 285.0, "back": true, "back_bonus": 1.0, "hit_cap": 30 },
			{"desc": "伤害 +2，最大半径 +4，命中上限 +6", "dmg": 20.0, "cd": 3.27, "max_r": 125.0, "spd": 300.0, "back": true, "back_bonus": 1.0, "hit_cap": 36 },
			{"desc": "伤害 +2，最大半径 +4，命中上限 +8", "dmg": 21.0, "cd": 3.20, "max_r": 129.0, "spd": 315.0, "back": true, "back_bonus": 1.0, "hit_cap": 44 },
			{"desc": "伤害 +2，最大半径 +4，命中上限 +8", "dmg": 22.0, "cd": 3.13, "max_r": 133.0, "spd": 330.0, "back": true, "back_bonus": 1.0, "hit_cap": 52 },
			{"desc": "伤害 +2，最大半径 +4，命中上限 +8；回卷伤害 +30%", "dmg": 24.0, "cd": 3.06, "max_r": 137.0, "spd": 350.0, "back": true, "back_bonus": 1.3, "hit_cap": 60 },
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
		"char": "algo",
		"sub": "// 每一次调用，都会分裂出一个更弱的自己",
		"max": 8,
		"levels": [
			{"desc": "飞出一把飞刃，命中后弹向下一个目标", "dmg": 22.0, "cd": 0.95, "pspeed": 420.0, "bounces": 3, "decay": 0.70, "spd_bonus": 0.0},
			{"desc": "伤害 +4，冷却 -0.07s，弹射 +1", "dmg": 26.0, "cd": 0.88, "pspeed": 430.0, "bounces": 4, "decay": 0.73, "spd_bonus": 0.0},
			{"desc": "伤害 +4，弹射 +1", "dmg": 30.0, "cd": 0.82, "pspeed": 440.0, "bounces": 5, "decay": 0.76, "spd_bonus": 0.0},
			{"desc": "伤害 +4，冷却 -0.07s，弹射 +1", "dmg": 34.0, "cd": 0.75, "pspeed": 450.0, "bounces": 6, "decay": 0.79, "spd_bonus": 0.0},
			{"desc": "伤害 +5，弹射 +1", "dmg": 39.0, "cd": 0.68, "pspeed": 460.0, "bounces": 7, "decay": 0.82, "spd_bonus": 0.04},
			{"desc": "伤害 +6，弹射 +1", "dmg": 45.0, "cd": 0.60, "pspeed": 470.0, "bounces": 8, "decay": 0.85, "spd_bonus": 0.06},
			{"desc": "伤害 +8，冷却 -0.12s，弹射 +2", "dmg": 53.0, "cd": 0.48, "pspeed": 480.0, "bounces": 10, "decay": 0.89, "spd_bonus": 0.07},
			{"desc": "伤害 +11，冷却 -0.12s，弹射 +2，衰减放缓至 92%", "dmg": 64.0, "cd": 0.36, "pspeed": 490.0, "bounces": 12, "decay": 0.92, "spd_bonus": 0.08},
		],
	},
	{
		"id": "pointer", "kind": KIND_WEAPON, "name": "指针追踪", "icon": "*p",
		"sub": "// 只要拿到地址，就一定能找到",
		"max": 8,
		"levels": [
			{"desc": "发射必中的追踪弹（1 发）", "dmg": 26.0, "cd": 1.90, "radius": 260.0, "bolts": 1, "pspeed": 340.0, "pierce": 0, "mark": false},
			{"desc": "伤害 +6，追踪范围 +25", "dmg": 32.0, "cd": 1.72, "radius": 285.0, "bolts": 1, "pspeed": 350.0, "pierce": 0, "mark": false},
			{"desc": "伤害 +6，弹数 1 → 2，可穿透 1 个目标", "dmg": 38.0, "cd": 1.54, "radius": 310.0, "bolts": 2, "pspeed": 360.0, "pierce": 1, "mark": false},
			{"desc": "命中标记目标：受伤 +10%（3 秒）", "dmg": 44.0, "cd": 1.42, "radius": 335.0, "bolts": 3, "pspeed": 370.0, "pierce": 1, "mark": true},
			{"desc": "伤害 +6，弹数 3 → 4，可穿透 2 个目标", "dmg": 50.0, "cd": 1.32, "radius": 365.0, "bolts": 4, "pspeed": 380.0, "pierce": 2, "mark": true},
			{"desc": "弹数 4 → 5，可穿透 3 个目标", "dmg": 54.0, "cd": 1.24, "radius": 400.0, "bolts": 5, "pspeed": 400.0, "pierce": 3, "mark": true},
			{"desc": "伤害 +4，弹数 5 → 6，可穿透 4 个目标", "dmg": 58.0, "cd": 1.19, "radius": 440.0, "bolts": 6, "pspeed": 420.0, "pierce": 4, "mark": true},
			{"desc": "伤害 +4，弹速翻倍，可穿透 5 个目标", "dmg": 62.0, "cd": 1.15, "radius": 600.0, "bolts": 6, "pspeed": 680.0, "pierce": 5, "mark": true},
		],
	},

	{
		"id": "volley", "kind": KIND_WEAPON, "name": "多线程齐射", "icon": "|||",
		"sub": "// 几件事一起做，谁也别等谁",
		"max": 8,
		"levels": [
			{"desc": "同时向 2 个不同敌人各发射一枚弹", "dmg": 10.0, "cd": 1.10, "bolts": 2, "pspeed": 420.0, "pierce": 0, "hit_cap": 0},
			{"desc": "弹数 2 → 3，伤害 +1", "dmg": 11.0, "cd": 1.05, "bolts": 3, "pspeed": 420.0, "pierce": 0, "hit_cap": 0},
			{"desc": "伤害 +2，冷却 -0.05s", "dmg": 13.0, "cd": 1.00, "bolts": 3, "pspeed": 430.0, "pierce": 0, "hit_cap": 0},
			{"desc": "弹数 3 → 4，伤害 +2，弹速 +30", "dmg": 15.0, "cd": 0.95, "bolts": 4, "pspeed": 460.0, "pierce": 0, "hit_cap": 0},
			{"desc": "伤害 +2，冷却 -0.05s", "dmg": 17.0, "cd": 0.90, "bolts": 4, "pspeed": 470.0, "pierce": 0, "hit_cap": 0},
			{"desc": "弹数 4 → 5，伤害 +2", "dmg": 19.0, "cd": 0.85, "bolts": 5, "pspeed": 480.0, "pierce": 0, "hit_cap": 0},
			{"desc": "弹数 5 → 6，伤害 +2，冷却 -0.07s", "dmg": 21.0, "cd": 0.78, "bolts": 6, "pspeed": 500.0, "pierce": 0, "hit_cap": 0},
			{"desc": "弹数 6 → 7，伤害 +2，冷却 -0.08s；弹可穿透 1 个目标", "dmg": 23.0, "cd": 0.70, "bolts": 7, "pspeed": 520.0, "pierce": 1, "hit_cap": 0},
		],
	},
	{
		"id": "gc", "kind": KIND_WEAPON, "name": "垃圾回收", "icon": "free()",
		"sub": "// 用不上的东西，就该清掉",
		"max": 8,
		"levels": [
			{"desc": "每 8 秒回收范围内血量低于 15% 的敌人，并造成 30 点范围伤害", "cd": 8.0, "thr": 0.15, "radius": 120.0, "dmg": 30.0, "hit_cap": 14, "reset_n": 0},
			{"desc": "冷却 -0.5s，阈值 → 18%，范围 +20，伤害 +4", "cd": 7.5, "thr": 0.18, "radius": 140.0, "dmg": 34.0, "hit_cap": 16, "reset_n": 0},
			{"desc": "冷却 -0.5s，阈值 → 20%，范围 +15，伤害 +4", "cd": 7.0, "thr": 0.20, "radius": 155.0, "dmg": 38.0, "hit_cap": 18, "reset_n": 0},
			{"desc": "冷却 -0.5s，阈值 → 22%，伤害 +7", "cd": 6.5, "thr": 0.22, "radius": 170.0, "dmg": 45.0, "hit_cap": 22, "reset_n": 0},
			{"desc": "冷却 -0.5s，阈值 → 25%，伤害 +8", "cd": 6.0, "thr": 0.25, "radius": 185.0, "dmg": 53.0, "hit_cap": 26, "reset_n": 0},
			{"desc": "冷却 -0.5s，阈值 → 28%，伤害 +9", "cd": 5.5, "thr": 0.28, "radius": 200.0, "dmg": 62.0, "hit_cap": 30, "reset_n": 0},
			{"desc": "冷却 -0.5s，阈值 → 31%，伤害 +10", "cd": 5.0, "thr": 0.31, "radius": 210.0, "dmg": 72.0, "hit_cap": 34, "reset_n": 0},
			{"desc": "冷却 -0.5s，阈值 → 35%，伤害 +13；每回收 10 个，冷却立即重置", "cd": 4.5, "thr": 0.35, "radius": 220.0, "dmg": 85.0, "hit_cap": 40, "reset_n": 10},
		],
	},
	{
		"id": "buffer", "kind": KIND_WEAPON, "name": "缓冲区溢出", "icon": "buf[]",
		"sub": "// 装不下了，还往里塞一点",
		"max": 8,
		"levels": [
			{"desc": "每 2.4s 灼烧周围敌人；每次命中使自身伤害 +6%（上限 +60%）", "dmg": 14.0, "cd": 2.4, "radius": 80.0, "gain": 0.06, "cap": 0.60, "hit_cap": 18},
			{"desc": "伤害 +2，冷却 -0.1s，范围 +8", "dmg": 16.0, "cd": 2.3, "radius": 88.0, "gain": 0.06, "cap": 0.70, "hit_cap": 21},
			{"desc": "伤害 +2，冷却 -0.1s，层数上限 +10%", "dmg": 18.0, "cd": 2.2, "radius": 96.0, "gain": 0.07, "cap": 0.80, "hit_cap": 24},
			{"desc": "伤害 +2，冷却 -0.1s，范围 +8", "dmg": 20.0, "cd": 2.1, "radius": 104.0, "gain": 0.07, "cap": 0.90, "hit_cap": 27},
			{"desc": "伤害 +2，冷却 -0.1s，层数上限 +10%", "dmg": 22.0, "cd": 2.0, "radius": 112.0, "gain": 0.07, "cap": 1.00, "hit_cap": 30},
			{"desc": "伤害 +2，冷却 -0.1s，每次命中 +8%", "dmg": 24.0, "cd": 1.9, "radius": 118.0, "gain": 0.08, "cap": 1.20, "hit_cap": 34},
			{"desc": "伤害 +3，冷却 -0.15s，层数上限 +15%", "dmg": 27.0, "cd": 1.75, "radius": 124.0, "gain": 0.08, "cap": 1.35, "hit_cap": 38},
			{"desc": "伤害 +3，冷却 -0.15s，层数上限 +15%（最高 +150%）", "dmg": 30.0, "cd": 1.6, "radius": 130.0, "gain": 0.08, "cap": 1.50, "hit_cap": 45},
		],
	},
	{
		"id": "breakpoint", "kind": KIND_WEAPON, "name": "断点调试", "icon": "break",
		"char": "qa",
		"sub": "// 先停一下，看看出了什么事 —— 控得住，但打不疼",
		"max": 8,
		"levels": [
			{"desc": "每 5 秒暂停附近敌人 0.8 秒，并造成 36 点伤害（伤害不随等级成长）", "dmg": 36.0, "cd": 5.0, "radius": 90.0, "freeze": 0.80, "hit_cap": 20},
			{"desc": "冷却 -0.2s，暂停 +0.15s，范围 +10", "dmg": 36.0, "cd": 4.8, "radius": 100.0, "freeze": 0.95, "hit_cap": 24},
			{"desc": "冷却 -0.2s，暂停 +0.15s，范围 +12", "dmg": 36.0, "cd": 4.6, "radius": 112.0, "freeze": 1.10, "hit_cap": 28},
			{"desc": "冷却 -0.2s，暂停 +0.15s，范围 +10、伤害不变", "dmg": 36.0, "cd": 4.4, "radius": 122.0, "freeze": 1.25, "hit_cap": 32},
			{"desc": "冷却 -0.3s，暂停 +0.15s，范围 +10", "dmg": 36.0, "cd": 4.1, "radius": 132.0, "freeze": 1.40, "hit_cap": 36},
			{"desc": "冷却 -0.2s，暂停 +0.15s，范围 +10", "dmg": 36.0, "cd": 3.9, "radius": 142.0, "freeze": 1.55, "hit_cap": 40},
			{"desc": "冷却 -0.4s，暂停 +0.15s，范围 +8", "dmg": 36.0, "cd": 3.5, "radius": 150.0, "freeze": 1.70, "hit_cap": 44},
			{"desc": "冷却 -0.3s，暂停 1.8s，范围 +10；暂停期间受伤 +50%", "dmg": 36.0, "cd": 3.2, "radius": 160.0, "freeze": 1.80, "hit_cap": 50},
		],
	},
	{
		"id": "forever", "kind": KIND_WEAPON, "name": "永真力场", "icon": "loop",
		"char": "ops",
		"sub": "// while(true) —— 血越少，圈越大，越安全",
		"max": 8,
		"levels": [
			{"desc": "身周持续灼烧 8 点/秒；每秒自损 0.4 点生命；血量越低，力场范围越大", "dps": 8.0, "radius": 70.0, "self_dps": 0.40, "hit_cap": 12},
			{"desc": "每秒伤害 +3，范围 +10", "dps": 11.0, "radius": 80.0, "self_dps": 0.45, "hit_cap": 14},
			{"desc": "每秒伤害 +3，范围 +10", "dps": 14.0, "radius": 90.0, "self_dps": 0.50, "hit_cap": 16},
			{"desc": "每秒伤害 +3，范围 +10", "dps": 17.0, "radius": 100.0, "self_dps": 0.55, "hit_cap": 18},
			{"desc": "每秒伤害 +3，范围 +10", "dps": 20.0, "radius": 110.0, "self_dps": 0.60, "hit_cap": 20},
			{"desc": "每秒伤害 +4，范围 +10；自损提高到 0.7", "dps": 24.0, "radius": 120.0, "self_dps": 0.70, "hit_cap": 22},
			{"desc": "每秒伤害 +3，范围 +10", "dps": 27.0, "radius": 130.0, "self_dps": 0.75, "hit_cap": 23},
			{"desc": "每秒伤害 +3，范围 +10；自损 0.8（血量低于 30% 自动停机）", "dps": 30.0, "radius": 140.0, "self_dps": 0.80, "hit_cap": 24},
		],
	},
	{
		"id": "rebuild", "kind": KIND_WEAPON, "name": "全量重编译", "icon": "make",
		"sub": "// 整份作业重写一遍，慢，但很彻底",
		"max": 8,
		"levels": [
			{"desc": "蓄力 0.8s 后引发大爆炸（伤害 60，半径 150）", "dmg": 60.0, "cd": 9.0, "radius": 150.0, "charge": 0.80, "hit_cap": 25, "cd_kill": 0.0},
			{"desc": "伤害 +15，冷却 -0.6s，半径 +25", "dmg": 75.0, "cd": 8.4, "radius": 175.0, "charge": 0.76, "hit_cap": 30, "cd_kill": 0.0},
			{"desc": "伤害 +15，冷却 -0.5s，半径 +25", "dmg": 90.0, "cd": 7.9, "radius": 200.0, "charge": 0.72, "hit_cap": 34, "cd_kill": 0.0},
			{"desc": "伤害 +15，冷却 -0.5s，半径 +25", "dmg": 105.0, "cd": 7.4, "radius": 225.0, "charge": 0.68, "hit_cap": 38, "cd_kill": 0.0},
			{"desc": "伤害 +20，冷却 -0.5s，半径 +25", "dmg": 125.0, "cd": 6.9, "radius": 250.0, "charge": 0.64, "hit_cap": 42, "cd_kill": 0.0},
			{"desc": "伤害 +15，冷却 -0.5s，半径 +25", "dmg": 140.0, "cd": 6.4, "radius": 275.0, "charge": 0.60, "hit_cap": 46, "cd_kill": 0.0},
			{"desc": "伤害 +20，冷却 -0.5s，半径 +25", "dmg": 160.0, "cd": 5.9, "radius": 300.0, "charge": 0.55, "hit_cap": 52, "cd_kill": 0.0},
			{"desc": "伤害 +20，冷却 -0.4s，半径 +20，蓄力 0.5s；每次击杀减少剩余冷却 3%", "dmg": 180.0, "cd": 5.5, "radius": 320.0, "charge": 0.50, "hit_cap": 60, "cd_kill": 0.03},
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


## 这把武器的专属角色 id；不是专属武器时返回空串。
static func owner_of(id: String) -> String:
	return str(def_of(id).get("char", ""))


static func is_exclusive(id: String) -> bool:
	return owner_of(id) != ""


## 该角色能不能拿到这把武器。唯一过滤点 —— 升级三选一走它，
## 所以"别人拿不到专属武器"只需要在这一个地方成立，
## 不用在每个可能出现武器的地方各写一遍判断。
static func can_use(id: String, char_id: String) -> bool:
	var own := owner_of(id)
	return own == "" or own == char_id


static func def_of(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return HEAL_PICK
