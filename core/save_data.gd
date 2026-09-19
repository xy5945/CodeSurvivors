class_name SaveData
extends RefCounted
##
## 存档：目前只记两件事 —— **解锁到第几个角色**、**哪些角色通关过**。
##
## 为什么是静态的：解锁状态要跨"重载场景"存活（暂停退出回标题、结算重开
## 都是 reload_current_scene），而 static var 挂在类上，重载不会清掉它。
## 挂 autoload 也能做到，但为两个整数单开一个常驻节点没必要。
##
## 解锁规则：一开始只有第 1 个角色可用；**用第 n 个角色通关**才开第 n+1 个。
## 不是"通关任意角色开下一个" —— 那样一路用最简单的角色就能把全部刷开，
## 难度递增（0.8 → 1.2）也就失去意义了。
##
## 存档位置：user://save.cfg（Windows 下在 %APPDATA%/Godot/app_userdata/<项目名>/）。
## 用 ConfigFile 而不是 JSON：它是 Godot 自己的格式，读写都是两行，
## 也不用自己处理类型（JSON 会把 int 读成 float）。
##

const FILE := "user://save.cfg"
const SEC := "progress"
const K_UNLOCKED := "unlocked"
const K_CLEARED := "cleared"

static var unlocked := 1                 # 已解锁的角色数（前 n 个可用）
static var cleared: Array[String] = []   # 通关过的角色 id
static var loaded := false

## 测试用：写到别的文件去，别把玩家的真存档冲掉（--savetest 会设它）。
static var test_path := ""


static func path() -> String:
	return test_path if test_path != "" else FILE


## 读档。文件不存在（第一次玩）就保持默认值：只解锁第 1 个角色。
## 可以重复调用 —— 每次都从盘上重读，测试里靠它验证"真的写进去了"。
static func load_game() -> void:
	unlocked = 1
	cleared = []
	var cf := ConfigFile.new()
	if cf.load(path()) == OK:
		unlocked = clampi(int(cf.get_value(SEC, K_UNLOCKED, 1)), 1, CharDefs.CHARACTERS.size())
		cleared = []
		for s in (cf.get_value(SEC, K_CLEARED, []) as Array):
			cleared.append(str(s))
	loaded = true


static func save_game() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SEC, K_UNLOCKED, unlocked)
	cf.set_value(SEC, K_CLEARED, cleared)
	var err := cf.save(path())
	if err != OK:
		push_warning("[SaveData] 存档写入失败 %d" % err)


## 懒加载：场景里的子节点（选人界面）_ready 比 main._ready 早，
## 那时候还没人调 load_game —— 不兜这一下，卡片会按"只解锁 1 个"画出来。
static func _ensure() -> void:
	if not loaded:
		load_game()


static func unlocked_count() -> int:
	_ensure()
	return clampi(unlocked, 1, CharDefs.CHARACTERS.size())


static func is_unlocked(cid: String) -> bool:
	_ensure()
	var i := CharDefs.index_of(cid)
	return i >= 0 and i < unlocked_count()


static func has_cleared(cid: String) -> bool:
	_ensure()
	return cleared.has(cid)


## 通关记账：记一笔"这个角色通关了"，并开下一个角色。
## 返回新解锁的角色名（没有新解锁就返回空串），交给结算面板显示。
## 同一个角色第二次通关不会重复解锁，只是清掉了"新解锁"提示。
static func mark_cleared(cid: String) -> String:
	if not cleared.has(cid):
		cleared.append(cid)
	var i := CharDefs.index_of(cid)
	var next_i := i + 1
	if i >= 0 and next_i < CharDefs.CHARACTERS.size() and unlocked <= next_i:
		unlocked = next_i + 1
		save_game()
		return str(CharDefs.CHARACTERS[next_i]["name"])
	save_game()
	return ""


## 解锁下一个角色的条件说明，给选人界面用。
## 已经是最后一个（或已解锁）时返回空串。
static func unlock_hint(cid: String) -> String:
	if is_unlocked(cid):
		return ""
	var prev := CharDefs.def_at(CharDefs.index_of(cid) - 1)
	if prev.is_empty():
		return ""
	return "先用「%s」通关一次" % str(prev["name"])


## 清档：回到"只解锁第 1 个角色"的初始状态（--resetunlock）。
static func reset_all() -> void:
	unlocked = 1
	cleared = []
	save_game()


## 全解锁（--unlockall，开发用：想直接看后面的角色时不用重打一遍）。
static func unlock_all() -> void:
	unlocked = CharDefs.CHARACTERS.size()
	save_game()
