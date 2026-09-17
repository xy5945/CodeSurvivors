class_name UiFont
extends RefCounted
##
## 中文字体。Godot 默认字体不含中文字形，不指定的话运行起来全是"□□□□"。
##
## 这里用 SystemFont 指向系统中文字体，只为让第一版跑通。
## 正式做 UI 时应换成项目内的字体文件（思源黑体 Noto Sans SC，SIL OFL 可商用）——
## 系统字体有版权风险，且打包到别的机器上可能缺失。
##

static var _cache: SystemFont = null


static func cjk() -> SystemFont:
	if _cache == null:
		var f := SystemFont.new()
		# 注意：PackedStringArray 没有 (String, String, ...) 构造函数，只能从数组字面量构造
		f.font_names = PackedStringArray([
			"Microsoft YaHei", "Noto Sans CJK SC", "SimHei", "sans-serif"
		])
		_cache = f
	return _cache


## 给任意 Control 套上中文字体 + 描边风格。暗底 UI 上不加阴影会糊成一团。
static func apply(ctrl: Control, size: int, color: Color) -> void:
	ctrl.add_theme_font_override("font", cjk())
	ctrl.add_theme_font_size_override("font_size", size)
	ctrl.add_theme_color_override("font_color", color)
	ctrl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	ctrl.add_theme_constant_override("shadow_offset_x", 1)
	ctrl.add_theme_constant_override("shadow_offset_y", 1)
