class_name License
extends RefCounted
##
## 授权：把「哪款游戏 + 哪台电脑 + 多少天」编码成一串 20 个字符的激活码。
##
## 为什么不用非对称签名：Godot 4.7 的 Crypto 只提供 HMAC（对称），
## 没有 Ed25519，也没暴露公钥验签接口（已实测）。想自己手写 255 位大数
## 运算代价太大，所以走对称 HMAC —— 代价是密钥必须藏在客户端，
## 靠「绑定机器」把它拉回来：密钥就算被扒出来，也得先知道目标机器的
## 机器码才能造出可用的码，而机器码只在你发给学生的那一次才暴露。
##
## 激活码的构成（12 字节 → Base32 20 个字符）
##     game_id   1 字节   游戏编号，写在 core/license_key.gd 里
##     machine   5 字节   本机机器码原文
##     days      2 字节   授权天数，大端序；0 表示永久
##     mac       4 字节   HMAC-SHA256(secret, 前 8 字节) 的前 4 字节
##
## 四道关卡，按代价从低到高排：先验校验码（挡住自己编的码），
## 再看游戏编号（挡住买别的游戏的人），然后比对机器码（挡住转发给别人），
## 最后查「这张码本机用没用过」（挡住拿自己那一张码无限续期）。
## 顺序不能反 —— 校验码不过就没必要算机器码，那一步要读注册表，慢。
##

const GAME_ID := 1
const GAME_NAME := "代码幸存者"

const KEY_PATH := "res://core/license_key.gd"

const CODE_BYTES := 12        # game_id 1 + machine 5 + days 2 + mac 4
const MACHINE_BYTES := 5
const CODE_CHARS := 20
const MACHINE_CHARS := 8
const SECRET_BYTES := 32
const FINGERPRINT_BYTES := 4

## Base32 字母表。故意不含 0、1、8、9 —— 手抄时最容易被认错的那四个。
const B32 := "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
const HEX_CHARS := "0123456789abcdef"

static var _secret_cache := PackedByteArray()
static var _secret_ready := false
static var _machine_cache := PackedByteArray()


# ---------------------------------------------------------------- 字符串处理

## 统一用户输入：去分隔符、转大写、纠正手抄易混字符。
## Base32 里没有 0 和 1，所以出现它们一定是要写 O 和 I。
static func clean(text: String) -> String:
	var s: String = text.strip_edges().to_upper()
	var junk: Array[String] = ["-", " ", "_", "\t", "\r", "\n"]
	for j in junk:
		s = s.replace(j, "")
	return s.replace("0", "O").replace("1", "I")


## 每 4 个字符插一个连字符：方便念、方便抄。
static func group(text: String, n: int = 4) -> String:
	var parts := PackedStringArray()
	var i := 0
	while i < text.length():
		parts.append(text.substr(i, n))
		i += n
	return "-".join(parts)


# ---------------------------------------------------------------- Base32

static func _b32_encode(data: PackedByteArray) -> String:
	var out := ""
	var buf := 0
	var bits := 0
	for b in data:
		buf = (buf << 8) | int(b)
		bits += 8
		while bits >= 5:
			bits -= 5
			out += B32[(buf >> bits) & 31]
			buf &= (1 << bits) - 1
	if bits > 0:
		out += B32[(buf << (5 - bits)) & 31]
	return out


## 解码失败一律返回空数组（长度不对、有非法字符、填充位不是 0）。
## 最后那条「填充位必须为 0」是必须的：Base32 末尾几位是凑长度的填充，
## 不检查的话，改动末尾字符能解出同样的字节 —— 篡改检测会漏掉一个字符。
static func _b32_decode(text: String) -> PackedByteArray:
	var s := clean(text)
	var out := PackedByteArray()
	var buf := 0
	var bits := 0
	for i in s.length():
		var v := B32.find(s[i])
		if v < 0:
			return PackedByteArray()
		buf = (buf << 5) | v
		bits += 5
		while bits >= 8:
			bits -= 8
			out.append((buf >> bits) & 0xFF)
			buf &= (1 << bits) - 1
	if bits > 0 and buf != 0:
		return PackedByteArray()
	return out


# ---------------------------------------------------------------- 密钥

static func _hex_to_bytes(hex: String) -> PackedByteArray:
	var out := PackedByteArray()
	var h := hex.strip_edges().to_lower()
	if h.length() != SECRET_BYTES * 2:
		return out
	for i in range(0, h.length(), 2):
		var hi := HEX_CHARS.find(h[i])
		var lo := HEX_CHARS.find(h[i + 1])
		if hi < 0 or lo < 0:
			return out
		out.append((hi << 4) | lo)
	return out


## 读 core/license_key.gd 里的 SECRET_HEX。
## 用动态 load + 常量表，而不是 class_name 引用 —— 文件缺失时（公开仓库里
## 就是这个状态）游戏还能正常启动，只是激活功能不可用。
static func secret() -> PackedByteArray:
	if _secret_ready:
		return _secret_cache
	_secret_ready = true
	if not ResourceLoader.exists(KEY_PATH):
		return _secret_cache
	var scr: Variant = load(KEY_PATH)
	if scr == null:
		return _secret_cache
	var consts: Dictionary = scr.get_script_constant_map()
	_secret_cache = _hex_to_bytes(str(consts.get("SECRET_HEX", "")))
	return _secret_cache


static func has_secret() -> bool:
	return secret().size() == SECRET_BYTES


# ---------------------------------------------------------------- 机器码

## 机器指纹 → 5 字节。学生看到的 8 个字符就是它。
##
## 主要来源是 OS.get_unique_id()：Windows 上取自注册表 MachineGuid，
## 换硬件、重装驱动都不变，**只有重装系统才会变** —— 那之后学生要重新找你换码，
## 这是这套方案唯一需要人工兜底的地方。
## 万一拿不到唯一号（极少数环境），退回到「计算机名 + 用户名」，至少还能区分。
static func machine_bytes() -> PackedByteArray:
	if not _machine_cache.is_empty():
		return _machine_cache
	var uid := OS.get_unique_id()
	if uid.is_empty():
		uid = OS.get_environment("COMPUTERNAME") + OS.get_environment("USERNAME")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((uid + "|" + OS.get_processor_name()).to_utf8_buffer())
	var digest := ctx.finish()
	_machine_cache = digest.slice(0, MACHINE_BYTES)
	return _machine_cache


## 学生要发给你的「申请码」，形如 A3K7-M2XQ。只跟硬件有关，不含隐私。
static func machine_code() -> String:
	return group(_b32_encode(machine_bytes()))


# ---------------------------------------------------------------- 指纹

## 激活码指纹：存「这张码在本机用过了」，只留 4 字节。
## 哈希的是**归一化之后**的码 —— 带不带连字符、全小写、把 O 抄成 0
## 都算同一张，否则学生换个写法就能再用一次。
static func code_fingerprint(code: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(clean(code).to_utf8_buffer())
	var d := ctx.finish()
	var out := ""
	for i in FINGERPRINT_BYTES:
		out += HEX_CHARS[(int(d[i]) >> 4) & 0xF]
		out += HEX_CHARS[int(d[i]) & 0xF]
	return out


# ---------------------------------------------------------------- 验码

static func _hmac(key: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, data)


static func _payload(game_id: int, machine5: PackedByteArray, days: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.append(game_id)
	p.append_array(machine5)
	p.append((days >> 8) & 0xFF)
	p.append(days & 0xFF)
	return p


## 校验激活码。返回 {ok, reason, days, permanent}。
## reason 是给人看的一句话，UI 直接显示 —— 学生抄错、拿错码、用别人的码，
## 三种情况要能分清楚，否则你电话里没法判断问题出在哪。
static func verify(code: String) -> Dictionary:
	var res := {"ok": false, "reason": "", "days": 0, "permanent": false}
	var sec := secret()
	if sec.size() != SECRET_BYTES:
		res["reason"] = "本机没有配置激活密钥，请联系作者"
		return res

	var raw := _b32_decode(code)
	if raw.size() != CODE_BYTES:
		res["reason"] = "激活码应该是 20 个字符，请看看是不是抄漏了"
		return res

	var gid := int(raw[0])
	var m5 := raw.slice(1, 1 + MACHINE_BYTES)
	var days := (int(raw[6]) << 8) | int(raw[7])
	var mac := raw.slice(8, CODE_BYTES)

	if gid != GAME_ID:
		res["reason"] = "这个激活码属于另一款游戏（编号 %d），用不到《%s》上" % [gid, GAME_NAME]
		return res

	if _hmac(sec, _payload(gid, m5, days)).slice(0, 4) != mac:
		res["reason"] = "激活码校验不通过，多半是有字符抄错了"
		return res

	if m5 != machine_bytes():
		res["reason"] = "这个激活码是发给另一台电脑的，本机用不了"
		return res

	if SaveData.has_used_code(code_fingerprint(code)):
		res["reason"] = "这张激活码已经在本机用过了，请找老师要一张新的"
		return res

	res["ok"] = true
	res["days"] = days
	res["permanent"] = days == 0
	return res


## 把授权写进存档。days = 0 表示永久。返回 false = 这张码本机用过了，没生效。
## 起算日重置为今天（对天数幂等，不会累加），同时把这张码的指纹记下来 ——
## 记指纹是为了堵住「同一张码反复输入 = 每次重新装满天数」这个口子。
static func apply(days: int, code: String) -> bool:
	return SaveData.activate(days, code_fingerprint(code))


## 给自己看的诊断信息（--lictest 用）。
static func debug_info() -> Dictionary:
	return {
		"game_id": GAME_ID,
		"game_name": GAME_NAME,
		"machine_code": machine_code(),
		"machine_bytes": machine_bytes(),
		"has_secret": has_secret(),
		"secret_len": secret().size(),
	}
