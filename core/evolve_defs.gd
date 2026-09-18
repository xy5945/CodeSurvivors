class_name EvolveDefs
extends RefCounted
##
## 进化（合体）纯数据：武器满级 + 指定被动满级 → 武器**机制质变**。
##
## 进化的原则（和数值升级的根本区别）：
##   进化改的是**行为**，不是数字。加伤害、加范围这类事交给 8 级数值表去做，
##   进化必须让玩家"换一种打法"—— 否则它只是一个更大的数字，玩家感知不到。
##
## 解锁条件：对应武器 Lv8（满级）+ 指定被动 Lv5（满级）。
## 两个都满级才会出现在三选一里，且**必占一席**（见 Loadout.roll_choices）——
## 随机池里等它出现的话，玩家可能连着七八次升级都看不到，那就等于没有。
##
## id 统一 "evo_<武器id>"，不进 Loadout.levels，单独记在 evolved 字典里。
##

## 取某条进化的数据
static func def_of(id: String) -> Dictionary:
	for e in EVOLUTIONS:
		if str(e["id"]) == id:
			return e
	return {}


## 某把武器对应的进化（没有则空字典）
static func for_weapon(base: String) -> Dictionary:
	for e in EVOLUTIONS:
		if str(e["base"]) == base:
			return e
	return {}


## 进化卡在 UI 里和升级卡共用一套结构，所以也要有 levels[0].desc
const EVOLUTIONS := [
	{
		"id": "evo_whip", "base": "whip", "passive": "optimize",
		"name": "三元表达式", "icon": "?:",
		"sub": "// 两边都算，总有一边成立",
		"levels": [{"desc": "长鞭改为四向十字挥击，背后和两侧都不再是死角"}],
	},
	{
		"id": "evo_orbit", "base": "orbit", "passive": "overclock",
		"name": "嵌套循环", "icon": "for{for}",
		"sub": "// 外层转一圈，内层转两圈",
		"levels": [{"desc": "环绕物变成内外双层，内圈反向旋转、伤害 60%"}],
	},
	{
		"id": "evo_broadcast", "base": "broadcast", "passive": "ptr",
		"name": "事件总线", "icon": "on()",
		"sub": "// 收到消息的人，继续往下发",
		"levels": [{"desc": "波命中的敌人会再发出一圈小广播（最多 3 处）"}],
	},
	{
		"id": "evo_judgment", "base": "judgment", "passive": "optimize",
		"name": "随机种子", "icon": "srand()",
		"sub": "// 同一个种子，连着摇三次",
		"levels": [{"desc": "每道落雷变成同点三连击，每一击单独计算命中上限"}],
	},
	{
		"id": "evo_blade", "base": "blade", "passive": "thread",
		"name": "尾递归", "icon": "tail rec",
		"sub": "// 不压栈，就能一直递归下去",
		"levels": [{"desc": "飞刃每次弹射不再衰减伤害，弹射次数 +3"}],
	},
	{
		"id": "evo_pointer", "base": "pointer", "passive": "ptr",
		"name": "引用计数", "icon": "shared_ptr",
		"sub": "// 引用还在，对象就还在",
		"levels": [{"desc": "追踪弹命中后分裂成两发，各自继续追下一个目标"}],
	},
	{
		"id": "evo_volley", "base": "volley", "passive": "thread",
		"name": "线程池", "icon": "pool",
		"sub": "// 排好队，一批一批地跑",
		"levels": [{"desc": "齐射改为两轮点射，第二轮重新锁定当前目标"}],
	},
	{
		"id": "evo_gc", "base": "gc", "passive": "optimize",
		"name": "全量回收", "icon": "gc -F",
		"sub": "// 别管在哪，用不上的都清掉",
		"levels": [{"desc": "回收不再限范围：全场残血敌人一起清（伤害仍限身边）"}],
	},
	{
		"id": "evo_buffer", "base": "buffer", "passive": "overclock",
		"name": "环形缓冲", "icon": "ring[]",
		"sub": "// 写满了就从头接着写，不丢",
		"levels": [{"desc": "叠层不再因停火清零，层数上限 +50%"}],
	},
	{
		"id": "evo_breakpoint", "base": "breakpoint", "passive": "malloc",
		"name": "断言", "icon": "assert()",
		"sub": "// 它一崩，周围一起停下来",
		"levels": [{"desc": "被冻结的敌人死亡时，会把周围敌人一起冻住"}],
	},
	{
		"id": "evo_forever", "base": "forever", "passive": "malloc",
		"name": "守护进程", "icon": "daemon",
		"sub": "// 一直在后台跑，不会自己停",
		"levels": [{"desc": "不再停机：血量低于 30% 时改为输出与自损一起减半"}],
	},
	{
		"id": "evo_rebuild", "base": "rebuild", "passive": "overclock",
		"name": "增量编译", "icon": "make -i",
		"sub": "// 只重新编译改动的那部分",
		"levels": [{"desc": "引爆后立刻追加一发（蓄力只要 60%），一轮两炸"}],
	},
]


## 是否进化卡（UI 用它决定金色描边和"进化"角标）
static func is_evo_id(id: String) -> bool:
	return id.begins_with("evo_")
