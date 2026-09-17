class_name KnowledgeDB
extends RefCounted
##
## 知识卡文案表。这是本作最重要的教学资产 —— 见武器设计文档第 9 节。
##
## 每张卡三行，分别解决三件事：
##   term + code   这个术语叫什么（中文 + 代码里的写法）
##   plain         白话怎么理解（一句孩子听得懂的话）
##   use           学了有什么用（真写代码时什么时候会碰上）
##
## 写文案的三条硬规矩（改动文案时必须守住）：
##   1. 不许出现孩子没见过的词。raycast、死锁、僵尸进程这类一律不用；
##      优先用弹窗、垃圾文件、回收站、蓝屏这些生活里的东西打比方。
##   2. plain 不超过 20 字，use 不超过 24 字 —— 卡片只有 250x130，
##      超了会换行撑爆排版（这个尺寸是照着 640x360 视口算的）。
##   3. 引号一律用「」，不要用 ASCII 双引号 —— GDScript 字符串里容易出事。
##
## id 的命名：武器的 id 与 UpgradeDefs 的 id 一致，敌人与 EnemyDB 的 id 一致，
## 这样触发时不用做任何映射。系统卡（gem / patch / chest）是额外加的。
##

const K_WEAPON := 0
const K_PASSIVE := 1
const K_ENEMY := 2
const K_SYSTEM := 3

const KIND_NAMES := ["武 器", "被 动", "Bug 与异常", "编程基础"]

const CARDS := [
	# ================= 武器（6）=================
	{
		"id": "whip", "kind": K_WEAPON, "term": "分支", "code": "if / else",
		"plain": "走不通，就换一条路走",
		"use": "判断成绩及不及格、密码对不对，都要用 if",
	},
	{
		"id": "orbit", "kind": K_WEAPON, "term": "循环", "code": "for / while",
		"plain": "同一件事让它重复做，不用写一百遍",
		"use": "重复的活交给它，比如算 1 加到 100",
	},
	{
		"id": "broadcast", "kind": K_WEAPON, "term": "广播", "code": "broadcast",
		"plain": "站中间喊一嗓子，周围全听见了",
		"use": "一个消息要通知很多地方，广播一次就够",
	},
	{
		"id": "judgment", "kind": K_WEAPON, "term": "随机数", "code": "rand()",
		"plain": "像掷骰子，出几全看运气",
		"use": "抽奖、洗牌、游戏里的暴击，都靠随机数",
	},
	{
		"id": "blade", "kind": K_WEAPON, "term": "递归", "code": "recursion",
		"plain": "自己调用自己，像一层层套娃",
		"use": "算阶乘、一层层翻文件夹，递归最好用",
	},
	{
		"id": "pointer", "kind": K_WEAPON, "term": "指针", "code": "pointer",
		"plain": "指针存的是地址，拿着地址就找得到本人",
		"use": "想改一个大东西，不用整个复制，给地址就行",
	},

	# ================= 被动（5）=================
	{
		"id": "malloc", "kind": K_PASSIVE, "term": "申请内存", "code": "malloc",
		"plain": "先向系统借一块地方放东西，用完要还",
		"use": "要存 100 个学生的成绩，先申请这么大地方",
	},
	{
		"id": "overclock", "kind": K_PASSIVE, "term": "超频", "code": "overclock",
		"plain": "让它跑得比标称的更快，代价是更烫",
		"use": "程序太慢要先优化代码，硬超频容易烧",
	},
	{
		"id": "ptr", "kind": K_PASSIVE, "term": "取地址与取值", "code": "& 和 *",
		"plain": "「&」问你住哪儿，「*」就按地址去找你",
		"use": "想让函数改外面的变量，就把地址传进去",
	},
	{
		"id": "optimize", "kind": K_PASSIVE, "term": "编译优化", "code": "-O2",
		"plain": "编译器悄悄把你的代码改写得更快",
		"use": "发布时开 -O2，一行代码不改也能快一截",
	},
	{
		"id": "thread", "kind": K_PASSIVE, "term": "多线程", "code": "thread",
		"plain": "一件事分给几个人同时干，就快了",
		"use": "一边下载一边显示进度条，就是两个线程",
	},

	# ================= 敌人：Bug 与异常（11）=================
	{
		"id": "error_red", "kind": K_ENEMY, "term": "报错", "code": "error",
		"plain": "程序发现不对就停下来，报告哪里错了",
		"use": "红色报错不可怕，它告诉你行号，照着找就行",
	},
	{
		"id": "popup", "kind": K_ENEMY, "term": "弹窗", "code": "dialog",
		"plain": "突然跳出来挡住你，不点掉就不走",
		"use": "弹窗要少用，谁都不喜欢被打断",
	},
	{
		"id": "junk_file", "kind": K_ENEMY, "term": "垃圾文件", "code": "temp file",
		"plain": "用完没删的临时文件，越堆电脑越慢",
		"use": "临时文件记得清理，别一直占着硬盘",
	},
	{
		"id": "trojan", "kind": K_ENEMY, "term": "木马", "code": "trojan",
		"plain": "伪装成好东西混进来，进门才露真面目",
		"use": "别乱装来路不明的软件，里面可能藏着东西",
	},
	{
		"id": "virus", "kind": K_ENEMY, "term": "病毒", "code": "virus",
		"plain": "会自己复制自己，一个变两个变四个",
		"use": "不乱点链接、装杀毒软件，就是为了挡它",
	},
	{
		"id": "mojibake", "kind": K_ENEMY, "term": "乱码", "code": "encoding",
		"plain": "打开方式不对，字就成了看不懂的符号",
		"use": "存和读要用同一种编码，最常用的是 UTF-8",
	},
	{
		"id": "infinite_loop", "kind": K_ENEMY, "term": "死循环", "code": "while(true)",
		"plain": "转圈转不出来，永远停不下来",
		"use": "while 循环一定要有能结束的条件，不然卡死",
	},
	{
		"id": "bluescreen", "kind": K_ENEMY, "term": "崩溃", "code": "crash",
		"plain": "系统实在撑不住，干脆整个停掉重来",
		"use": "崩溃说明写错了，看错误提示比重启有用",
	},
	{
		"id": "oom", "kind": K_ENEMY, "term": "内存不足", "code": "out of memory",
		"plain": "要的地方太多，系统没地方可分了",
		"use": "用完的内存要还回去，只借不还迟早爆",
	},
	{
		"id": "elite_skull", "kind": K_ENEMY, "term": "异常", "code": "try / catch",
		"plain": "碰到没想到的情况，程序会抛出一个异常",
		"use": "把可能出错的地方包起来抓住它，程序就不崩",
	},
	{
		"id": "boss_compiler", "kind": K_ENEMY, "term": "编译器", "code": "compiler",
		"plain": "把你的代码翻译成电脑能懂的话",
		"use": "写完代码要点编译，编译器会告诉你哪写错了",
	},

	# ================= 系统：编程基础（3）=================
	{
		"id": "gem", "kind": K_SYSTEM, "term": "变量", "code": "int x = 0",
		"plain": "一个装数字的盒子，里面的数能随时改",
		"use": "记分数、记血量、记个数，都要用变量",
	},
	{
		"id": "patch", "kind": K_SYSTEM, "term": "补丁", "code": "hotfix",
		"plain": "程序发出去后发现问题，打个补丁修一下",
		"use": "补丁只改出错的那一小块，不用整个重写",
	},
	{
		"id": "chest", "kind": K_SYSTEM, "term": "代码库", "code": "library",
		"plain": "别人写好的工具，拿过来就能用",
		"use": "想画图、想联网，先看看有没有现成的库",
	},
]


static func total() -> int:
	return CARDS.size()


static func card_of(id: String) -> Dictionary:
	for c in CARDS:
		if str(c["id"]) == id:
			return c
	return {}


static func has_card(id: String) -> bool:
	return card_of(id).size() > 0


## 表里第几张（图鉴里显示"第 N 张"，给收集进度用）
static func index_of(id: String) -> int:
	for i in CARDS.size():
		if str(CARDS[i]["id"]) == id:
			return i
	return -1


## 校验：把所有该有卡的地方过一遍，返回缺卡的 id 列表。
## 新增武器 / 新增敌人时忘了配卡，--cardtest 会直接报出来。
static func missing_cards() -> Array[String]:
	var out: Array[String] = []
	for u in UpgradeDefs.UPGRADES:
		if not has_card(str(u["id"])):
			out.append(str(u["id"]))
	for d in EnemyDB.DEFS:
		if not has_card(str(d["id"])):
			out.append(str(d["id"]))
	return out


## 导出成 Markdown：这套文案要能直接拿去做课件和宣传物料，
## 所以导出不是调试功能，是它的一部分价值。
static func to_markdown() -> String:
	var lines: Array[String] = []
	lines.append("# 《代码幸存者》知识卡 · 全 %d 张" % CARDS.size())
	lines.append("")
	lines.append("> 每张卡三行：术语是什么 → 白话怎么理解 → 学了有什么用。")
	lines.append("")
	var last_kind := -1
	for c in CARDS:
		var k: int = c["kind"]
		if k != last_kind:
			last_kind = k
			lines.append("")
			lines.append("## %s" % KIND_NAMES[k])
			lines.append("")
			lines.append("| 术语 | 代码里的写法 | 白话解释 | 学了有什么用 |")
			lines.append("|---|---|---|---|")
		lines.append("| **%s** | `%s` | %s | %s |" % [
			c["term"], c["code"], c["plain"], c["use"]
		])
	lines.append("")
	return "\n".join(lines)
