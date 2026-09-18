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

static var _cache: Font = null


static func cjk() -> Font:
	if _cache == null:
		_cache = load(FONT_PATH)
	return _cache


## 给任意 Control 套上中文字体 + 描边风格。暗底 UI 上不加阴影会糊成一团。
static func apply(ctrl: Control, size: int, color: Color) -> void:
	ctrl.add_theme_font_override("font", cjk())
	ctrl.add_theme_font_size_override("font_size", size)
	ctrl.add_theme_color_override("font_color", color)
	ctrl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	ctrl.add_theme_constant_override("shadow_offset_x", 1)
	ctrl.add_theme_constant_override("shadow_offset_y", 1)
