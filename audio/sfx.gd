extends Node
##
## 程序化音效引擎（autoload 名：Sfx）
##
## 全部音效用代码合成 PCM，项目里没有任何音频文件。选这条路的理由：
##   1. 零素材、零版权风险，也不用管导入参数 —— 和"广播波/落雷/血条都用代码画"一致
##   2. 8-bit/chiptune 的音色和创战纪电子风、编程主题本来就是一套语言
##   3. 幸存者类音效触发极密集（每秒几十次击杀），素材音重叠起来会糊，
##      合成的短音更好压，而且能按触发频率精细调音量
##
## 三个必须处理的工程问题：
##   · 节流 —— 同名音效设最小重触发间隔（MIN_GAP），否则每秒 40 次击杀
##     会把 16 个声道占满、变成一团噪音
##   · 复音上限 —— 播放池满了就丢弃新音，宁可少一声也不叠加
##   · 防爆音 —— Master 总线挂 limiter，密集音效叠加时不削波
##
## 音色合成用的是最朴素的"振荡器 + 包络"：方波/三角/锯齿/正弦/噪声，
## 加 attack/release 斜坡（没有斜坡的话每个音开头结尾都会"啪"一声）。
##

const MIX_RATE := 44100        # 音效采样率
const BGM_RATE := 22050        # BGM 用一半：chiptune 不需要高保真，省一半内存和生成时间
const VOICES := 16             # 同时发声上限

# 每个音效合成后统一归一化到这个峰值，让下面的 VOL 表成为音量的唯一控制点。
# 不归一化的话各音效原始峰值相差 13dB（0.18~0.89），音量表根本没法调。
const NORM_PEAK := 0.85

# BGM 压到 -19dB：它是一条连续的音床，反馈音是短促的瞬态。
# 音乐峰值必须明显低于瞬态峰值，否则"击杀/受伤"会被音乐糊住听不出来。
const BGM_VOL := -19.0
const SILENT := -80.0

enum W { SQUARE, TRI, SAW, SINE, NOISE }

# 同名音效的最小重触发间隔（毫秒）。
# 数值是被"每秒触发多少次"倒推出来的：击杀后期每秒 40+ 次，
# 42ms 的间隔把它压到每秒最多约 24 声，听上去是"密集的雨点"而不是"噪音墙"。
const MIN_GAP := {
	"kill": 42, "pickup": 38, "shoot": 55, "whip": 95,
	"wave": 260, "bolt": 220, "hurt": 220, "heal": 120,
}
# 没列进来的（升级 / 精英 / Boss / 通关 / 死亡）都是低频事件，每次都播
const DEFAULT_GAP := 0

# 各音效音量（dB）。触发越频繁压得越轻，稀有事件才允许响。
const VOL := {
	"kill": -17.0, "pickup": -18.0, "shoot": -18.5, "whip": -15.0,
	"wave": -12.5, "bolt": -12.5, "hurt": -10.5, "heal": -13.5,
	"chest": -11.5, "levelup": -10.5, "elite": -11.0,
	"boss": -8.0, "victory": -8.0, "death": -9.0, "ui": -17.0,
}

var _enabled := true
var _muted := false
var _boss_mode := false
# 独立的随机源：绝不能碰全局 randf()，那会把刷怪序列锁死成同一套
var _rng := RandomNumberGenerator.new()

var _streams: Dictionary = {}
# 保留浮点原始波形，只为 --sfxdump 导出与自检用；正常游玩不占额外开销
var _pcm: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _gate: Dictionary = {}          # 音效名 -> 上次播放的毫秒时间戳
var _p_norm: AudioStreamPlayer
var _p_boss: AudioStreamPlayer

# --sfxrec 专用
var _cap: AudioEffectCapture
var _rec_buf := PackedVector2Array()
var _rec_left := 0.0
var _rec_mix := 44100


func _ready() -> void:
	# 音频必须无视暂停：升级弹窗打开时 get_tree().paused = true，
	# 默认 PROCESS_MODE_INHERIT 会让 BGM 每次升级都断一下、刚播的升级音被掐掉。
	process_mode = Node.PROCESS_MODE_ALWAYS

	var args := OS.get_cmdline_user_args()
	var dump := args.has("--sfxdump")
	var headless := DisplayServer.get_name() == "headless"

	_rng.seed = 20260917
	var t0 := Time.get_ticks_msec()
	_build_sfx()
	_build_bgm()
	print("[Sfx] 合成完成 %d ms" % (Time.get_ticks_msec() - t0))

	# --sfxdump：把所有音效导出成 wav，headless 也能跑。
	# 用途一是听音色对不对（合成器调参只能靠耳朵），
	# 二是无头环境下验证"确实生成了声音"而不是一片静音。
	if dump:
		_dump_all()
		get_tree().quit()
		return

	# headless 下不发声：所有自动化测试都跑 headless，
	# Dummy 音频驱动没必要真的解码这些流。
	if headless:
		_enabled = false
		return

	_setup_voices()
	_setup_master_bus()
	_p_norm = _new_bgm_player(_streams["bgm"])
	_p_norm.play()

	# --sfxrec=<秒>：录制 Master 总线的真实输出。
	# 用途：验证"声音确实流出了音频总线"（不是合成完就扔在那儿），
	# 顺便能存一段实机试听样本。用 AudioEffectCapture 抓，不是抓流本身。
	for a in args:
		if a.begins_with("--sfxrec="):
			_start_rec(float(a.split("=")[-1]))


func _start_rec(secs: float) -> void:
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 8.0        # 每帧都会抽干，8 秒只是防意外堆积
	AudioServer.add_bus_effect(0, _cap)   # 0 = Master
	_rec_left = maxf(secs, 0.5)
	_rec_mix = AudioServer.get_mix_rate()
	print("[Sfx] 开始录音 %.1fs @ %d Hz" % [_rec_left, _rec_mix])


## 注意：_process 必须一直把 capture 缓冲抽干，不然它会写满后丢新数据。
func _process(delta: float) -> void:
	if _rec_left <= 0.0:
		return
	var avail := _cap.get_frames_available()
	if avail > 0:
		_rec_buf.append_array(_cap.get_buffer(avail))
	_rec_left -= delta
	if _rec_left <= 0.0:
		_dump_rec()
		get_tree().quit()


func _dump_rec() -> void:
	var n := _rec_buf.size()
	var dir := ProjectSettings.globalize_path("user://sfx")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/_capture.wav", FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(n * 4 + 36)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)                  # PCM
	f.store_16(2)                  # 立体声
	f.store_32(_rec_mix)
	f.store_32(_rec_mix * 4)
	f.store_16(4)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 4)
	for v in _rec_buf:
		f.store_16(int(clampf(v.x, -1.0, 1.0) * 32000.0))
		f.store_16(int(clampf(v.y, -1.0, 1.0) * 32000.0))
	f.close()
	print("[Sfx] 录音完成 %d 帧 (%.2fs) -> %s/_capture.wav" % [n, float(n) / float(_rec_mix), dir])


func _dump_all() -> void:
	var dir := ProjectSettings.globalize_path("user://sfx")
	DirAccess.make_dir_recursive_absolute(dir)
	print("[Sfx] 导出目录: " + ProjectSettings.globalize_path(dir))
	for k in _streams.keys():
		var pcm: PackedFloat32Array = _pcm.get(k, PackedFloat32Array())
		var rate: int = int((_streams[k] as AudioStreamWAV).mix_rate)
		var n := pcm.size()
		if n == 0:
			continue
		# 自检用的两个指标：peak 说明有没有削顶失真，rms 说明整体响不响。
		# 全是 0 就代表合成失败（静音），不用耳朵也能发现。
		var peak := 0.0
		var sq := 0.0
		for i in n:
			var a := absf(pcm[i])
			if a > peak:
				peak = a
			sq += pcm[i] * pcm[i]
		var rms := sqrt(sq / float(n))
		# 手写 WAV 头（16-bit 单声道，小端）：AudioStreamWAV.save_to_wav()
		# 在 headless 下会挂住进程，不能用。
		var f := FileAccess.open("%s/%s.wav" % [dir, k], FileAccess.WRITE)
		if f == null:
			print("[Sfx] 打开失败 " + k)
			continue
		f.store_buffer("RIFF".to_ascii_buffer())
		f.store_32(n * 2 + 36)
		f.store_buffer("WAVEfmt ".to_ascii_buffer())
		f.store_32(16)
		f.store_16(1)              # PCM
		f.store_16(1)              # 单声道
		f.store_32(rate)
		f.store_32(rate * 2)       # 字节率
		f.store_16(2)              # 块对齐
		f.store_16(16)             # 位深
		f.store_buffer("data".to_ascii_buffer())
		f.store_32(n * 2)
		for i in n:
			f.store_16(int(clampf(pcm[i], -1.0, 1.0) * 32000.0))
		f.close()
		print("[Sfx] %-9s %6.2fs  peak %.3f  rms %.3f" % [k, float(n) / float(rate), peak, rms])
	get_tree().quit()


# ------------------------------------------------------------ 对外接口

## 播放一个音效。节流和复音上限都在这里兜着，调用方不用操心密集触发。
func play(name: String) -> void:
	if not _enabled or _muted:
		return
	var st: AudioStreamWAV = _streams.get(name)
	if st == null:
		return

	var now := Time.get_ticks_msec()
	var gap := int(MIN_GAP.get(name, DEFAULT_GAP))
	if gap > 0 and now - int(_gate.get(name, -99999)) < gap:
		return
	_gate[name] = now

	var p := _voice()
	if p == null:
		return          # 声道全忙：丢弃。宁可少一声，也不要糊成一团
	p.stream = st
	p.volume_db = float(VOL.get(name, -8.0))
	p.play()


## Boss 出场切紧张版 BGM。用两个 player 交叉淡入淡出，避免硬切。
func set_boss_mode(on: bool) -> void:
	if not _enabled or on == _boss_mode:
		return
	_boss_mode = on
	var to_p := _p_boss if on else _p_norm
	var from_p := _p_norm if on else _p_boss
	if not to_p.playing:
		to_p.play()
	to_p.volume_db = SILENT
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(to_p, "volume_db", BGM_VOL, 0.8)
	tw.tween_property(from_p, "volume_db", SILENT, 0.8)


func stop_bgm() -> void:
	if not _enabled:
		return
	for p in [_p_norm, _p_boss]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", SILENT, 0.6)


func toggle_mute() -> bool:
	_muted = not _muted
	AudioServer.set_bus_mute(0, _muted)
	return _muted


func is_muted() -> bool:
	return _muted


## M 键静音。放在音频层而不是 main.gd：暂停中（升级弹窗打开）也要能静音，
## 而 main.gd 的 _process 此时是被暂停的，收不到。
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_M:
		print("[Sfx] 静音 %s" % ("开" if toggle_mute() else "关"))


# ------------------------------------------------------------ 播放池

func _setup_voices() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "v%d" % i
		add_child(p)
		_players.append(p)


func _voice() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return null


func _new_bgm_player(st: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = BGM_VOL
	add_child(p)
	return p


## Master 挂 limiter：几十个音效叠在一起时总电平会冲过 0dBFS 削波爆音，
## limiter 把峰值按在 -1dB。
##
## 阈值必须贴近天花板（-3 → -1，只留 2dB 动作范围）：阈值压太低
## （比如 -10dB）会让正常战斗的每一秒都在压缩里，听感是音乐一直在"抽气"。
## 它只该在密集交火那一瞬间兜底。
func _setup_master_bus() -> void:
	if AudioServer.get_bus_effect_count(0) > 0:
		return
	var lim := AudioEffectLimiter.new()
	lim.threshold_db = -3.0
	lim.ceiling_db = -1.0
	lim.soft_clip_db = 2.0
	AudioServer.add_bus_effect(0, lim)


# ------------------------------------------------------------ 归一化

## 把一段波形整体缩放到统一峰值。只做等比例缩放，音效内部的强弱关系不变。
func _normalize(b: PackedFloat32Array) -> PackedFloat32Array:
	var pk := 0.0
	for i in b.size():
		var a := absf(b[i])
		if a > pk:
			pk = a
	if pk <= 0.0001:
		return b
	var k := NORM_PEAK / pk
	for i in b.size():
		b[i] *= k
	return b


# ------------------------------------------------------------ 音效库

func _build_sfx() -> void:
	var banks := {
		"kill": _make_kill(), "pickup": _make_pickup(), "levelup": _make_levelup(),
		"hurt": _make_hurt(), "heal": _make_heal(), "chest": _make_chest(),
		"wave": _make_wave(), "bolt": _make_bolt(), "shoot": _make_shoot(),
		"whip": _make_whip(), "elite": _make_elite(), "boss": _make_boss_appear(),
		"victory": _make_victory(), "death": _make_death(), "ui": _make_ui(),
	}
	for k in banks.keys():
		var nb: PackedFloat32Array = _normalize(banks[k])
		_pcm[k] = nb
		_streams[k] = _sfx(nb, MIX_RATE)


# 击杀：短促下滑"piu"。每秒可能响几十次，所以最轻、最短
func _make_kill() -> PackedFloat32Array:
	var b := _buf(0.07)
	_tone(b, 0.0, 0.055, 1150.0, 520.0, W.SQUARE, 0.30)
	_noise(b, 0.0, 0.025, 0.10)
	return b


# 拾取宝石：清脆上滑。触发频率全游戏最高，音量压到最轻
func _make_pickup() -> PackedFloat32Array:
	var b := _buf(0.055)
	_tone(b, 0.0, 0.045, 900.0, 1500.0, W.SQUARE, 0.22)
	return b


# 升级：C-E-G-C 上行琶音，全游戏最重要的正反馈，要明亮
func _make_levelup() -> PackedFloat32Array:
	var b := _buf(0.42)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		_tone(b, float(i) * 0.085, 0.16, notes[i], notes[i], W.SQUARE, 0.26)
	return b


# 受伤：低沉下坠 + 噪声撞击，和"屏幕边缘闪红"是同一件事的两种表达
func _make_hurt() -> PackedFloat32Array:
	var b := _buf(0.30)
	_tone(b, 0.0, 0.26, 330.0, 90.0, W.SAW, 0.36)
	_noise(b, 0.0, 0.10, 0.22)
	return b


# 回血（补丁包）：温暖的三音上行，和受伤的下坠形成对比
func _make_heal() -> PackedFloat32Array:
	var b := _buf(0.34)
	var notes := [392.0, 523.25, 659.25]
	for i in notes.size():
		_tone(b, float(i) * 0.09, 0.20, notes[i], notes[i], W.TRI, 0.30)
	return b


# 宝箱：比补丁包更华丽，加一颗高频"叮"
func _make_chest() -> PackedFloat32Array:
	var b := _buf(0.55)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		_tone(b, float(i) * 0.075, 0.22, notes[i], notes[i], W.SQUARE, 0.24)
	_tone(b, 0.30, 0.22, 2093.0, 2093.0, W.TRI, 0.16)
	return b


# 广播冲击波：低频扫频 + 噪声尾，表现一圈能量扩散出去
func _make_wave() -> PackedFloat32Array:
	var b := _buf(0.42)
	_tone(b, 0.0, 0.36, 240.0, 60.0, W.SAW, 0.30)
	_noise(b, 0.04, 0.30, 0.14)
	return b


# 落雷：高频劈下来 + 噪声炸开
func _make_bolt() -> PackedFloat32Array:
	var b := _buf(0.28)
	_noise(b, 0.0, 0.22, 0.32, 0.004, 0.10)
	_tone(b, 0.0, 0.11, 2000.0, 200.0, W.SQUARE, 0.26)
	return b


# 飞刃 / 指针发射：极短的高频"tsu"
func _make_shoot() -> PackedFloat32Array:
	var b := _buf(0.06)
	_tone(b, 0.0, 0.045, 1600.0, 800.0, W.SQUARE, 0.22)
	return b


# 长鞭挥击：一段带包络的噪声，像抽空气的"咻"
func _make_whip() -> PackedFloat32Array:
	var b := _buf(0.16)
	_noise(b, 0.0, 0.14, 0.26, 0.012, 0.09)
	return b


# 精英出场：两声高低警报，告诉玩家"这个不一样"
func _make_elite() -> PackedFloat32Array:
	var b := _buf(0.52)
	_tone(b, 0.0, 0.14, 740.0, 740.0, W.SQUARE, 0.26)
	_tone(b, 0.18, 0.14, 880.0, 880.0, W.SQUARE, 0.26)
	_tone(b, 0.36, 0.14, 740.0, 740.0, W.SQUARE, 0.26)
	return b


# Boss 出场：80Hz 三角 + 84Hz 锯齿制造 4Hz 拍频，低频轰鸣持续 1.2 秒
# 拍频（两个相近频率互相干涉产生的"抖动"）是制造不安感最省事的手段
func _make_boss_appear() -> PackedFloat32Array:
	var b := _buf(1.30)
	_tone(b, 0.0, 1.15, 80.0, 62.0, W.TRI, 0.38, 0.06, 0.25)
	_tone(b, 0.0, 1.15, 84.0, 66.0, W.SAW, 0.26, 0.06, 0.25)
	_noise(b, 0.0, 0.9, 0.14, 0.10, 0.35)
	_tone(b, 0.55, 0.30, 1200.0, 400.0, W.SQUARE, 0.18)
	return b


# 通关：六音上行琶音，最亮最长
func _make_victory() -> PackedFloat32Array:
	var b := _buf(0.95)
	var notes := [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98]
	for i in notes.size():
		_tone(b, float(i) * 0.11, 0.34, notes[i], notes[i], W.SQUARE, 0.26)
	_tone(b, 0.66, 0.30, 1046.5, 1046.5, W.TRI, 0.20)
	return b


# 死亡：长下坠，收在低音上
func _make_death() -> PackedFloat32Array:
	var b := _buf(0.95)
	_tone(b, 0.0, 0.60, 440.0, 110.0, W.SAW, 0.34)
	_tone(b, 0.30, 0.62, 220.0, 55.0, W.SQUARE, 0.26)
	_noise(b, 0.0, 0.25, 0.16)
	return b


# UI 点击：一下极短的"tick"
func _make_ui() -> PackedFloat32Array:
	var b := _buf(0.04)
	_tone(b, 0.0, 0.03, 1400.0, 1100.0, W.SQUARE, 0.18)
	return b


# ------------------------------------------------------------ BGM

func _build_bgm() -> void:
	_pcm["bgm"] = _normalize(_make_bgm(false))
	_pcm["bgm_boss"] = _normalize(_make_bgm(true))
	_streams["bgm"] = _sfx(_pcm["bgm"], BGM_RATE, true)
	_streams["bgm_boss"] = _sfx(_pcm["bgm_boss"], BGM_RATE, true)
	_p_boss = AudioStreamPlayer.new()
	_p_boss.stream = _streams["bgm_boss"]
	_p_boss.volume_db = SILENT
	add_child(_p_boss)


## 4 小节循环。结构：三角波贝斯 + 方波琶音 + 正弦底鼓 + 噪声踩镲。
## 正常版 Am-F-C-G（小调，冷峻）；Boss 版把后两小节换成 E（大三度）制造紧张，
## 速度也更快、底鼓更密。
func _make_bgm(boss: bool) -> PackedFloat32Array:
	var bpm := 138.0 if boss else 112.0
	var step := (60.0 / bpm) / 4.0        # 十六分音符
	var steps := 64                        # 4 小节
	var b := _buf(float(steps) * step, BGM_RATE)

	var roots := [110.0, 87.31, 130.81, 98.0]          # A2 F2 C3 G2
	var chords := [
		[220.0, 261.63, 329.63],                        # Am
		[174.61, 220.0, 261.63],                        # F
		[261.63, 329.63, 392.0],                        # C
		[196.0, 246.94, 293.66],                        # G
	]
	if boss:
		roots = [110.0, 87.31, 82.41, 82.41]           # A2 F2 E2 E2
		chords[2] = [164.81, 207.65, 246.94]           # E
		chords[3] = [164.81, 207.65, 246.94]           # E

	for s in steps:
		var t := float(s) * step
		var bar := s / 16
		var root: float = roots[bar]
		var chord: Array = chords[bar]

		# 贝斯：八分音符，撑住和声
		if s % 2 == 0:
			_tone(b, t, step * 1.8, root, root, W.TRI, 0.26, 0.004, 0.04, BGM_RATE)
		# 琶音：十六分音符，音量很轻，只负责"流动感"
		_tone(b, t, step * 0.9, chord[s % 3], chord[s % 3], W.SQUARE, 0.075,
			0.003, 0.03, BGM_RATE)
		# 底鼓：每拍（Boss 版加一个反拍）
		if s % 4 == 0 or (boss and s % 16 == 14):
			_tone(b, t, 0.11, 130.0, 45.0, W.SINE, 0.42, 0.002, 0.05, BGM_RATE)
		# 踩镲：八分反拍
		if s % 2 == 1:
			_noise(b, t, 0.03, 0.075, 0.001, 0.02, BGM_RATE)
	return b


# ------------------------------------------------------------ 合成内核

func _buf(dur: float, rate: int = MIX_RATE) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * float(rate)))
	return b


## 一个音：从 f0 滑到 f1（f1<=0 表示不滑），带 attack/release 斜坡。
## 没有斜坡的话音的开头结尾是突变的方波沿，听上去就是"啪"的爆音。
func _tone(b: PackedFloat32Array, t0: float, dur: float,
		f0: float, f1: float, wave: int, gain: float,
		atk: float = 0.005, rel: float = 0.03, rate: int = MIX_RATE) -> void:
	var i0 := int(t0 * float(rate))
	var n := int(dur * float(rate))
	if n <= 0:
		return
	var atk_n := maxf(1.0, atk * float(rate))
	var rel_n := maxf(1.0, rel * float(rate))
	var slide := f1 > 0.0 and absf(f1 - f0) > 0.01
	var ph := 0.0
	for k in n:
		var i := i0 + k
		if i >= b.size():
			break
		var f := f0
		if slide:
			f = f0 + (f1 - f0) * (float(k) / float(n))
		ph += f / float(rate)
		if ph >= 1.0:
			ph -= 1.0
		var v := 0.0
		match wave:
			W.SQUARE: v = 1.0 if ph < 0.5 else -1.0
			W.TRI:    v = 4.0 * absf(ph - 0.5) - 1.0
			W.SAW:    v = 2.0 * ph - 1.0
			W.SINE:   v = sin(TAU * ph)
			_:        v = _rng.randf() * 2.0 - 1.0
		# 包络：开头斜坡淡入，结尾斜坡淡出，中间平台
		var e := 1.0
		if k < atk_n:
			e = float(k) / atk_n
		elif k > n - rel_n:
			e = float(n - k) / rel_n
		b[i] += v * gain * e


## 一段噪声。用来做打击乐、爆炸、挥击的空气声。
func _noise(b: PackedFloat32Array, t0: float, dur: float, gain: float,
		atk: float = 0.003, rel: float = 0.05, rate: int = MIX_RATE) -> void:
	var i0 := int(t0 * float(rate))
	var n := int(dur * float(rate))
	if n <= 0:
		return
	var atk_n := maxf(1.0, atk * float(rate))
	var rel_n := maxf(1.0, rel * float(rate))
	for k in n:
		var i := i0 + k
		if i >= b.size():
			break
		var e := 1.0
		if k < atk_n:
			e = float(k) / atk_n
		elif k > n - rel_n:
			e = float(n - k) / rel_n
		b[i] += (_rng.randf() * 2.0 - 1.0) * gain * e


func _sfx(b: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		# 先 clamp 再量化：叠加溢出不处理的话会绕回成刺耳的爆音
		var v := clampf(b[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = b.size()
	return s
