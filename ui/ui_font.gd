class_name UiFont
extends RefCounted
##
## 中文字体。Godot 默认字体不含中文字形，不指定的话运行起来全是"□□□□"。
##
## 字体文件内嵌在项目里（fonts/NotoSansSC-Regular.ttf，思源黑体 SIL OFL 可商用）。
## 早期用 SystemFont 指向微软雅黑只为让第一版跑通 —— 那有两个硬伤：
##   1. 换台机器（尤其导出 exe 之后）没有这个字体就整屏方框
##   2. 系统字体不能随包分发，有版权风险
## 内嵌这份是子集：项目用到的字符 + GB2312 常用汉字（3.4MB，全量 17.7MB）。
## 新增中文文案后重新生成，见 tools/font/gen_font_subset.py。
##

const FONT_PATH := "res://fonts/NotoSansSC-Regular.ttf"
## 代码题用的等宽字体。Cascadia Mono（微软开源，SIL OFL 1.1，可合法内嵌分发），
## 已钉 wght=400 并子集到 ASCII —— 代码块只有 ASCII，中文走 CJK 字体。
## 别换成 Consolas / Courier New：那是专有字体，不能随包分发。
const MONO_PATH := "res://fonts/CascadiaMono-Regular.ttf"

static var _cache: Font = null
static var _mono_cache: Font = null


static func cjk() -> Font:
	if _cache == null:
		_cache = load(FONT_PATH)
	return _cache


## 等宽字体（代码块专用）。不等宽的话 C++ 代码的缩进对不齐，照着打就没意义了。
static func mono() -> Font:
	if _mono_cache == null:
		_mono_cache = load(MONO_PATH)
	return _mono_cache


## 统一风格的按钮。标题/选人/说明/暂停四处都要用，各写一遍的话
## 四处的 hover 色、圆角、字号迟早会飘 —— 集中在这一处改。
static func make_button(text: String, size: int = 12,
		color: Color = Color(0.88, 0.93, 1.0, 1.0)) -> Button:
	var b := Button.new()
	b.text = text
	apply(b, size, color)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.55, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.90, 0.55, 1.0))
	b.add_theme_stylebox_override("normal", _btn_box(Color(0.10, 0.13, 0.20, 0.96), Color(0.32, 0.40, 0.55, 1.0)))
	b.add_theme_stylebox_override("hover", _btn_box(Color(0.18, 0.24, 0.36, 0.98), Color(1.0, 0.86, 0.42, 1.0)))
	b.add_theme_stylebox_override("pressed", _btn_box(Color(0.26, 0.32, 0.46, 0.98), Color(1.0, 0.86, 0.42, 1.0)))
	# 不做 focus 样式的话，点过一次按钮后 Godot 会留一圈默认焦点框，很碍眼
	b.add_theme_stylebox_override("focus", _btn_box(Color(0.10, 0.13, 0.20, 0.96), Color(0.32, 0.40, 0.55, 1.0)))
	return b


static func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	return sb


## 给任意 Control 套上中文字体 + 描边风格。暗底 UI 上不加阴影会糊成一团。
static func apply(ctrl: Control, size: int, color: Color) -> void:
	ctrl.add_theme_font_override("font", cjk())
	ctrl.add_theme_font_size_override("font_size", size)
	ctrl.add_theme_color_override("font_color", color)
	ctrl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	ctrl.add_theme_constant_override("shadow_offset_x", 1)
	ctrl.add_theme_constant_override("shadow_offset_y", 1)

## 给代码块套等宽字体。不带描边 —— 代码要的是锐利，描边会让小字号糊掉。
static func apply_mono(ctrl: Control, size: int, color: Color) -> void:
	ctrl.add_theme_font_override("font", mono())
	ctrl.add_theme_font_size_override("font_size", size)
	ctrl.add_theme_color_override("font_color", color)
