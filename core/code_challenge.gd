class_name CodeChallenge
extends RefCounted
##
## 升级打码：出题 + 校验。
##
## 两个必须做对的设计：
##
## 1. 校验宽容的是「空格的数量」，不是「代码的内容」。
##    全角标点、多打少打空格、行尾空白都放过 —— 那是输入法问题，不是代码问题。
##    但行首缩进必须真的打出来（见 match_state 里那处 break），
##    否则孩子可以直接不打缩进，缩进这块就白练了。
##
## 2. 出题只存标准档，轻松/严格在运行时派生。同一段代码写三遍，
##    改一处就要同步三处，迟早对不上。
##

enum Mode { OFF, EASY, STD, HARD }

const MODE_NAMES := ["不打码", "轻松", "标准", "严格"]
const MODE_HINTS := [
	"升级直接生效",
	"只打核心那一行",
	"打完整代码段",
	"连 main 结构一起打",
]

## 全角空格不在 FF01-FF5E 区间里，单独处理
const IDEOGRAPHIC_SPACE := 0x3000
const TAB := 9

## 抽变体用的随机源。延迟创建 + 首次 randomize：
## RandomNumberGenerator 不 randomize 的话种子是固定的，每局出的题会一模一样。
static var _rng: RandomNumberGenerator = null


## 测试要可复现，就得能钉住种子（--codetest 用）
static func set_seed(s: int) -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	_rng.seed = s


## 测试钉完种子后要放开，否则正式开局出的题也固定了
static func randomize_seed() -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	_rng.randomize()


static func _pick(n: int) -> int:
	if n <= 1:
		return 0
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng.randi_range(0, n - 1)


# ---------------------------------------------------------------- 出题

## 生成一道题。is_evo（进化）走最难的满级题。
## variant 传 -1（默认）表示在这级的变体里随机抽一道 —— 同一个升级项反复升满级
## 不会永远打同一段代码；传具体下标则由调用方指定（测试用）。
static func build(upgrade_id: String, target_level: int, is_evo: bool, mode: int, variant: int = -1) -> Dictionary:
	var theme := CodeChallengeDB.theme_of(upgrade_id)
	var lv: int = 8 if is_evo else clampi(target_level, 1, 8)
	var vi := variant
	if vi < 0:
		vi = _pick(CodeChallengeDB.variants(theme, lv))
	var lines: Array = CodeChallengeDB.frag(theme, lv, vi)

	if mode == Mode.EASY:
		lines = _easy(lines)
	elif mode == Mode.HARD and lv >= 6:
		# Lv1-5 本身就是片段，套 main 反而不合语法，且会把梯度打乱
		lines = _wrap_main(lines)

	return {
		"theme": theme,
		"level": lv,
		"variant": vi,
		"lines": lines,
		"text": "\n".join(PackedStringArray(lines)),
		"tip": CodeChallengeDB.tip(theme, lv, vi),
	}


## 轻松档：取最长的一行（核心语句）。纯括号行和空行不算。
static func _easy(lines: Array) -> Array:
	var best := ""
	for l in lines:
		var s := str(l).strip_edges()
		if s.is_empty() or s == "{" or s.begins_with("}"):
			continue
		if s.length() > best.length():
			best = s
	if best.is_empty() and lines.size() > 0:
		best = str(lines[0]).strip_edges()
	return [best]


## 严格档：包一层能编译的完整程序。用了 rand() 就把 cstdlib 也带上。
static func _wrap_main(lines: Array) -> Array:
	var joined := "\n".join(PackedStringArray(lines))
	var out: Array = []
	out.append("#include <iostream>")
	if joined.contains("rand("):
		out.append("#include <cstdlib>")
	out.append("using namespace std;")
	out.append("int main() {")
	for l in lines:
		out.append("    " + str(l))
	out.append("    return 0;")
	out.append("}")
	return out


# ---------------------------------------------------------------- 校验

## 全角 -> 半角。FF01-FF5E 这一段整体偏移 0xFEE0 就是对应的半角字符，
## 比逐个查表省事，也不会漏（全角字母、数字、标点全在里面）。
static func normalize_char(c: String) -> String:
	if c.length() != 1:
		return c
	var v := c.unicode_at(0)
	if v == IDEOGRAPHIC_SPACE:
		return " "
	if v >= 0xFF01 and v <= 0xFF5E:
		return String.chr(v - 0xFEE0)
	if v == TAB:
		return " "
	return c


static func _is_space(c: String) -> bool:
	return c == " "


## 逐字符比对，返回高亮需要的一切：
##   tpos 目标已匹配到第几个字符 / ipos 输入已匹配到第几个 / err 是否打错 / done 是否通关
static func match_state(target: String, input: String) -> Dictionary:
	var i := 0
	var t := 0
	var ni := input.length()
	var nt := target.length()
	var err := false

	while i < ni and t < nt:
		var ic := normalize_char(input.substr(i, 1))
		var tc := normalize_char(target.substr(t, 1))
		if ic == tc:
			i += 1
			t += 1
			continue
		if _is_space(ic) and _is_space(tc):
			i += 1
			t += 1
			continue
		# 行首缩进不许跳过：放过去的话孩子永远不用按空格
		if _is_space(tc) and (t == 0 or target.substr(t - 1, 1) == "\n"):
			err = true
			break
		if _is_space(ic):
			i += 1
			continue
		if _is_space(tc):
			t += 1
			continue
		err = true
		break

	# 两头多余的空白不计较
	while i < ni and _is_space(normalize_char(input.substr(i, 1))):
		i += 1
	while t < nt and _is_space(normalize_char(target.substr(t, 1))):
		t += 1

	# 目标打完了但输入还有剩：那也是错，而且是最难受的一种 ——
	# 不算完成、也不报错，孩子只会看到进度条卡住不知道自己多打了。
	if t >= nt and i < ni:
		err = true

	return {
		"tpos": t,
		"ipos": i,
		"err": err,
		"done": (t >= nt and i >= ni),
	}


## 出错位置换算成「第几行第几列」，提示给孩子看
static func pos_to_line_col(target: String, pos: int) -> Vector2i:
	var line := 1
	var col := 1
	var i := 0
	while i < pos and i < target.length():
		if target.substr(i, 1) == "\n":
			line += 1
			col = 1
		else:
			col += 1
		i += 1
	return Vector2i(line, col)
