extends SceneTree
##
## 生成 Input Map 并写回 project.godot。
## 运行方式：
##   godot --headless --path <项目目录> --script res://tools/setup_input_map.gd
##
## 两个坑（都已处理）：
## 1. InputMap.add_action() 只是运行时注册，不会自动持久化到 project.godot，
##    必须再显式 ProjectSettings.set_setting("input/<action>", dict)。
## 2. InputEvent 的序列化格式手写极易出错，交给引擎序列化最稳。
##

const KEYMAP := {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"pause": KEY_ESCAPE,
	"build_panel": KEY_TAB,
}

const DEADZONE := 0.2


func _init() -> void:
	for action: String in KEYMAP:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEYMAP[action]

		ProjectSettings.set_setting("input/" + action, {
			"deadzone": DEADZONE,
			"events": [ev],
		})

		if not InputMap.has_action(action):
			InputMap.add_action(action, DEADZONE)
		else:
			InputMap.action_erase_events(action)
		InputMap.action_add_event(action, ev)

		print("已绑定: %-12s -> %s" % [action, OS.get_keycode_string(KEYMAP[action])])

	var err := ProjectSettings.save()
	if err != OK:
		printerr("保存 project.godot 失败，错误码: ", err)
		quit(1)
		return

	print("Input Map 已写入 project.godot")
	quit(0)
