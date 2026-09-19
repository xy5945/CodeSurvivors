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

## ---- 授权段 ----
## 只记「这一个有效期从哪天开始、总共多少天」，不记到期日 ——
## 记到期日的话，续期就得做加法，"再续一次"会把天数叠加起来；
## 记起算日则是「重置为今天」，重复输入同一个激活码结果不变（天然幂等）。
const SEC_LIC := "license"
const K_START_DAY := "start_day"        # 当前有效期的起算日（本地日序号）
const K_DAYS := "days"                  # 有效期天数，0 = 永久
const K_LICENSED := "licensed"          # 是否输入过激活码（只影响文案：试用/已授权）
const K_VIOLATIONS := "violations"      # 时钟回拨违规次数
const K_LAST_DAY := "last_seen_day"     # 最后一次运行的本地日序号
const K_LAST_TS := "last_seen_ts"       # 最后一次运行的 unix 秒

const TRIAL_DAYS := 7                   # 未激活时的试用天数
const MAX_VIOLATIONS := 3               # 回拨几次算恶意
const CLOCK_TOLERANCE := 3600           # 回拨容差（秒）：NTP 校时可能往回走几分钟
const MAX_SANE_DAYS := 3650             # 跨度超过十年 → 判定为时钟坏了，不拿它锁人

static var unlocked := 1                 # 已解锁的角色数（前 n 个可用）
static var cleared: Array[String] = []   # 通关过的角色 id
static var loaded := false

static var start_day := 0                # 0 = 还没定过，首次运行时才写
static var lic_days := TRIAL_DAYS
static var licensed := false
static var violations := 0
static var last_seen_day := 0
static var last_seen_ts := 0

## 测试用：写到别的文件去，别把玩家的真存档冲掉（--savetest 会设它）。
static var test_path := ""
## 测试用：关掉第二埋点，免得跑测试把开发机的用户目录写脏。
static var use_aux := true
## 测试用：把第二埋点的位置改到临时文件去。
static var aux_path_override := ""


static func path() -> String:
	return test_path if test_path != "" else FILE


## 读档。文件不存在（第一次玩）就保持默认值：只解锁第 1 个角色、试用从今天起算。
## 可以重复调用 —— 每次都从盘上重读，测试里靠它验证"真的写进去了"。
static func load_game() -> void:
	unlocked = 1
	cleared = []
	start_day = 0
	lic_days = TRIAL_DAYS
	licensed = false
	violations = 0
	last_seen_day = 0
	last_seen_ts = 0
	var cf := ConfigFile.new()
	if cf.load(path()) == OK:
		unlocked = clampi(int(cf.get_value(SEC, K_UNLOCKED, 1)), 1, CharDefs.CHARACTERS.size())
		cleared = []
		for s in (cf.get_value(SEC, K_CLEARED, []) as Array):
			cleared.append(str(s))
		start_day = int(cf.get_value(SEC_LIC, K_START_DAY, 0))
		lic_days = int(cf.get_value(SEC_LIC, K_DAYS, TRIAL_DAYS))
		licensed = bool(cf.get_value(SEC_LIC, K_LICENSED, false))
		violations = int(cf.get_value(SEC_LIC, K_VIOLATIONS, 0))
		last_seen_day = int(cf.get_value(SEC_LIC, K_LAST_DAY, 0))
		last_seen_ts = int(cf.get_value(SEC_LIC, K_LAST_TS, 0))
	loaded = true
	_bootstrap_license()


static func save_game() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SEC, K_UNLOCKED, unlocked)
	cf.set_value(SEC, K_CLEARED, cleared)
	cf.set_value(SEC_LIC, K_START_DAY, start_day)
	cf.set_value(SEC_LIC, K_DAYS, lic_days)
	cf.set_value(SEC_LIC, K_LICENSED, licensed)
	cf.set_value(SEC_LIC, K_VIOLATIONS, violations)
	cf.set_value(SEC_LIC, K_LAST_DAY, last_seen_day)
	cf.set_value(SEC_LIC, K_LAST_TS, last_seen_ts)
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


## ---------------------------------------------------------------- 时钟与授权
##
## 天数按「本地日历日」算，不按累计运行时长 —— 学生说"我玩了 7 天"时，
## 心里想的是日历上的 7 天。代价是它依赖系统时钟，所以下面这堆检测
## 全是围着"时钟可能被动手脚"转的。



## 本地日序号。只用来做减法算天数，所以时区偏移无所谓 ——
## 同一个本地日期永远映射到同一个序号。
static func today_index() -> int:
	var d := Time.get_date_dict_from_system()
	var t := Time.get_unix_time_from_datetime_dict({
		"year": int(d["year"]), "month": int(d["month"]), "day": int(d["day"]),
		"hour": 0, "minute": 0, "second": 0,
	})
	return int(t / 86400.0)


static func now_ts() -> int:
	return int(Time.get_unix_time_from_system())


## 算天数时用的"今天"：和最后一次运行日取较大值。
## 学生把时钟拨回去之后，这里仍然停在他拨之前的那一天 —— 不给续命。
static func effective_today() -> int:
	return maxi(today_index(), last_seen_day)


static func days_used() -> int:
	if start_day == 0:
		return 0
	return maxi(0, effective_today() - start_day)


static func is_permanent() -> bool:
	return licensed and lic_days == 0


static func days_left() -> int:
	if is_permanent():
		return 9999
	return maxi(0, lic_days - days_used())


static func is_expired() -> bool:
	if is_permanent():
		return false
	return days_used() >= lic_days


## 标题页/激活页上显示的那一行。
static func status_text() -> String:
	if is_permanent():
		return "已授权　永久有效"
	var left := days_left()
	if left <= 0:
		return "授权已到期" if licensed else "试用已结束"
	var kind := "授权" if licensed else "试用"
	if left <= 2:
		return "%s剩余 %d 天　快到期了" % [kind, left]
	return "%s剩余 %d 天" % [kind, left]


## 激活 / 续期：起算日重置为今天，有效期换成 days（0 = 永久）。
## 故意不做加法 —— 同一个码输两次，结果和输一次一样。
static func activate(days: int) -> void:
	start_day = today_index()
	lic_days = days
	licensed = true
	violations = 0
	last_seen_day = start_day
	last_seen_ts = now_ts()
	save_game()
	_write_aux()


## 首次运行的初始化 + 每次启动的体检。
static func _bootstrap_license() -> void:
	var reg := _read_aux()
	if reg > 0 and (start_day == 0 or reg < start_day):
		start_day = reg          # 存档被删过？以更早的那份为准 —— 删档不能重置试用
	var today := today_index()
	if start_day == 0:
		start_day = today        # 第一次运行，试用从今天开始
	# 时钟明显不对劲时不拿它锁人（起算日在未来，或跨度超过十年）：
	# 主板电池没电、系统时间停在几年前，都会撞上这条，直接挪回今天。
	if start_day > today or today - start_day > MAX_SANE_DAYS:
		start_day = today
		violations = 0
	_clock_check()
	last_seen_day = maxi(last_seen_day, today)
	save_game()
	_write_aux()


## 回拨检测：这次运行的时间比上次还早（超过容差）→ 记一笔违规。
## 容差留 1 小时是给 NTP 校时的：正常机器往回走几秒到几分钟是常事。
static func _clock_check() -> void:
	var now := now_ts()
	if last_seen_ts > 0 and now < last_seen_ts - CLOCK_TOLERANCE:
		violations += 1
	last_seen_ts = maxi(last_seen_ts, now)


## 第二埋点：存档之外的另一份记录，专治「把 save.cfg 删了重新试用」。
##
## 本来打算写注册表（HKCU），但实测调用 reg.exe 这种外部程序会被安全策略
## 直接拦掉，也容易被杀软盯上 —— 而且埋点只是"多一道坎"，不值得为它引入
## 外部进程依赖。改成往用户目录下写一个不起眼的小文件：位置和 Godot 的
## user:// 不在一处，学生删了存档不会顺带把它删掉。
## 任何一步失败都只是少一道防线，绝不抛错、绝不影响游戏运行。
static func _aux_path() -> String:
	if aux_path_override != "":
		return aux_path_override
	var base := OS.get_environment("LOCALAPPDATA")
	if base.is_empty():
		base = OS.get_environment("USERPROFILE")
	if base.is_empty():
		return ""
	return base.path_join("CodeSurvivors").path_join(".state")


static func _write_aux() -> void:
	if not use_aux:
		return
	var p := _aux_path()
	if p.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(str(start_day))
	f.close()


static func _read_aux() -> int:
	if not use_aux:
		return 0
	var p := _aux_path()
	if p.is_empty() or not FileAccess.file_exists(p):
		return 0
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return 0
	var v := int(f.get_line().strip_edges())
	f.close()
	return v


## 测试用：把授权状态直接摆成想要的形状（不落盘）。
static func set_license_state(p_start: int, p_days: int, p_licensed: bool = true) -> void:
	start_day = p_start
	lic_days = p_days
	licensed = p_licensed
	loaded = true
