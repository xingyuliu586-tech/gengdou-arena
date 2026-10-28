extends Node2D

# A playable first version. The art and ultimate presentation are deliberately
# separate from the combat rules so later sprite animation can replace them.
const IDS := ["naiwa", "niulai", "daishu", "doubao"]
const NAMES := ["奶蛙", "牛来", "袋鼠", "豆包"]
const ROLES := ["重型音波", "近身冲撞", "敏捷空战", "直线牵制"]
const MAX_HP := [1100, 1000, 950, 900]
const SPEED := [320.0, 350.0, 405.0, 365.0]
const JUMP := [-780.0, -850.0, -1020.0, -900.0]
const COLORS := [Color("#f8ca48"), Color("#dca629"), Color("#f6a41d"), Color("#373137")]
const STAGES := ["欢乐游乐园", "黄昏草原", "夜市街道", "数据空间"]
const FLOOR_Y := 600.0
const WORLD_WIDTH := 2560.0
const FONT: FontFile = preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")

var sprites: Dictionary = {}
var pose_textures: Dictionary = {}
var texture_foot_margins: Dictionary = {}
var effect_textures: Dictionary = {}
var stage_textures: Dictionary = {}
var sounds: Dictionary = {}
var music_player: AudioStreamPlayer
var screen := "title"
var menu_index := 0
var game_mode := 0 # 0 local, 1 CPU, 2 training
var difficulty := 1
var select_side := 0
var select_cursor := 0
var selections := [0, 1]
var stage_index := 0
var fighters: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var wins := [0, 0]
var round_number := 1
var round_ticks := 99 * 60
var phase := "intro"
var phase_ticks := 0
var winner := -1
var camera_x := 1280.0
var tick_count := 0
var ultimate: Dictionary = {}
var previous_buttons := [{}, {}]
var ai_memory: Dictionary = {}
var ai_opening_ticks := 0
var debug_boxes := false
var training_energy := true
var hit_counter := 0
var combo_timer := 0
var hitstop_ticks := 0
var camera_shake_ticks := 0
var camera_shake_strength := 0.0
var render_shake := Vector2.ZERO


func _ready() -> void:
	for id in IDS:
		var path := "res://assets/characters/%s/fighter.png" % id
		if ResourceLoader.exists(path):
			var fighter_tex: Texture2D = load(path)
			sprites[id] = fighter_tex
			_register_texture_foot_margin(fighter_tex)
		var poses := {}
		for pose_name in ["walk_contact_a", "walk_mid_back", "walk_lift_back", "walk_contact_b", "walk_mid_front", "walk_lift_front", "windup", "punch", "kick", "follow", "hurt", "laugh", "laugh_head", "laugh_fall", "after", "ultimate"]:
			var pose_path := "res://assets/characters/%s/%s.png" % [id, pose_name]
			if ResourceLoader.exists(pose_path):
				var pose_tex: Texture2D = load(pose_path)
				poses[pose_name] = pose_tex
				_register_texture_foot_margin(pose_tex)
		pose_textures[id] = poses
	for effect_name in ["sound_wave", "thunder", "impact", "rush", "beam"]:
		var effect_path := "res://assets/effects/%s.png" % effect_name
		if ResourceLoader.exists(effect_path):
			effect_textures[effect_name] = load(effect_path)
	for i in 4:
		var stage_path := "res://assets/stages/stage_%d.png" % i
		if ResourceLoader.exists(stage_path):
			stage_textures[i] = load(stage_path)
	for cue in ["attack_swing", "attack_hit", "block", "hurt", "skill", "niulai_ultimate", "naiwa_ultimate", "daishu_ultimate"]:
		var audio_path := "res://assets/audio/%s.wav" % cue
		if ResourceLoader.exists(audio_path):
			var player := AudioStreamPlayer.new()
			player.stream = load(audio_path)
			player.volume_db = -5.0 if cue.ends_with("ultimate") else -9.0
			add_child(player)
			sounds[cue] = player
	var theme_path := "res://assets/audio/battle_theme.wav"
	if ResourceLoader.exists(theme_path):
		music_player = AudioStreamPlayer.new()
		var theme: AudioStreamWAV = load(theme_path)
		theme.loop_begin = 0
		theme.loop_end = roundi(theme.get_length() * float(theme.mix_rate))
		theme.loop_mode = AudioStreamWAV.LOOP_FORWARD
		music_player.stream = theme
		music_player.volume_db = -20.0
		add_child(music_player)
		music_player.play()
	set_process_input(true)
	queue_redraw()


func _register_texture_foot_margin(tex: Texture2D) -> void:
	# Generated sprites include differing amounts of transparent space below the feet.
	# Inspect only a few columns of the bottom rows once during loading.
	var img: Image = tex.get_image()
	var image_width: int = img.get_width()
	var image_height: int = img.get_height()
	var column_step: int = maxi(1, image_width / 48)
	var found_y := image_height - 1
	var found := false
	for py in range(image_height - 1, maxi(-1, image_height - 240), -1):
		for px in range(0, image_width, column_step):
			if img.get_pixel(px, py).a >= 0.40:
				found_y = py
				found = true
				break
		if found:
			break
	texture_foot_margins[tex.resource_path] = float(image_height - 1 - found_y) / float(image_height)


func _play_sound(cue: String, pitch: float = 1.0) -> void:
	var player: AudioStreamPlayer = sounds.get(cue, null)
	if player != null:
		player.stop()
		player.pitch_scale = pitch
		player.play()


func _exit_tree() -> void:
	if music_player != null:
		music_player.stop()
	for cue in sounds:
		var player: AudioStreamPlayer = sounds[cue]
		player.stop()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = event.physical_keycode
	if screen == "battle":
		if key == KEY_ESCAPE:
			screen = "pause"
		elif key == KEY_F1:
			debug_boxes = not debug_boxes
		elif key == KEY_F3 and game_mode == 2:
			training_energy = not training_energy
		queue_redraw()
		return
	if screen == "pause":
		if key == KEY_ESCAPE or key == KEY_J or key == KEY_ENTER:
			screen = "battle"
		elif key == KEY_Q:
			screen = "title"
		queue_redraw()
		return
	if screen == "title":
		if _is_confirm(key):
			screen = "mode"
			menu_index = 0
	elif screen == "mode":
		if _is_up(key):
			menu_index = posmod(menu_index - 1, 3)
		elif _is_down(key):
			menu_index = (menu_index + 1) % 3
		elif _is_confirm(key):
			game_mode = menu_index
			screen = "select"
			select_side = 0
			select_cursor = 0
		elif key == KEY_ESCAPE:
			screen = "title"
	elif screen == "select":
		if _is_left(key) or _is_up(key):
			select_cursor = posmod(select_cursor - 1, 4)
		elif _is_right(key) or _is_down(key):
			select_cursor = (select_cursor + 1) % 4
		elif _is_confirm(key):
			selections[select_side] = select_cursor
			if select_side == 0:
				select_side = 1
				select_cursor = (select_cursor + 1) % 4
			else:
				screen = "difficulty" if game_mode == 1 else "stage"
				menu_index = 1
				stage_index = 0
		elif key == KEY_ESCAPE:
			if select_side == 1:
				select_side = 0
				select_cursor = selections[0]
			else:
				screen = "mode"
	elif screen == "stage":
		if _is_left(key) or _is_up(key):
			stage_index = posmod(stage_index - 1, 4)
		elif _is_right(key) or _is_down(key):
			stage_index = (stage_index + 1) % 4
		elif _is_confirm(key):
			_start_match()
		elif key == KEY_ESCAPE:
			screen = "select"
	elif screen == "difficulty":
		if _is_up(key):
			menu_index = posmod(menu_index - 1, 3)
		elif _is_down(key):
			menu_index = (menu_index + 1) % 3
		elif _is_confirm(key):
			difficulty = menu_index
			screen = "stage"
		elif key == KEY_ESCAPE:
			screen = "select"
	elif screen == "result":
		if _is_up(key) or _is_down(key):
			menu_index = 1 - menu_index
		elif _is_confirm(key):
			if menu_index == 0:
				_start_match()
			else:
				screen = "select"
				select_side = 0
				select_cursor = selections[0]
	queue_redraw()


func _is_confirm(key: Key) -> bool:
	return key == KEY_J or key == KEY_ENTER or key == KEY_SPACE or key == KEY_KP_1


func _is_left(key: Key) -> bool:
	return key == KEY_A or key == KEY_LEFT


func _is_right(key: Key) -> bool:
	return key == KEY_D or key == KEY_RIGHT


func _is_up(key: Key) -> bool:
	return key == KEY_W or key == KEY_UP


func _is_down(key: Key) -> bool:
	return key == KEY_S or key == KEY_DOWN


func _start_match() -> void:
	wins = [0, 0]
	round_number = 1
	winner = -1
	fighters.clear()
	screen = "battle"
	_setup_round()


func _setup_round() -> void:
	var old_energy := [0, 0]
	if fighters.size() == 2:
		old_energy = [fighters[0]["energy"], fighters[1]["energy"]]
	fighters.clear()
	projectiles.clear()
	effects.clear()
	ultimate.clear()
	previous_buttons = [{}, {}]
	ai_memory.clear()
	ai_opening_ticks = 24
	for side in 2:
		var choice: int = selections[side]
		fighters.append({
			"id": IDS[choice], "choice": choice, "side": side,
			"x": 1040.0 if side == 0 else 1520.0,
			"y": FLOOR_Y, "vy": 0.0, "facing": 1 if side == 0 else -1,
			"hp": MAX_HP[choice], "energy": old_energy[side],
			"state": "idle", "attack": "", "attack_frame": 0,
			"attack_hit": false, "combo_index": 0, "combo_queued": false,
			"stun": 0, "dash": 0, "cooldown": 0,
			"air_jumps": 0, "guard": false, "blocked": false, "flash": 0,
			"last_attack_frame": -1, "walk_phase": 0.0
		})
	round_ticks = 99 * 60
	phase = "intro"
	phase_ticks = 75
	hit_counter = 0
	combo_timer = 0
	hitstop_ticks = 0
	camera_shake_ticks = 0
	camera_x = 1280.0
	queue_redraw()


func _physics_process(_delta: float) -> void:
	tick_count += 1
	if camera_shake_ticks > 0:
		camera_shake_ticks -= 1
	if music_player != null:
		var voice_playing := false
		for cue in ["naiwa_ultimate", "niulai_ultimate", "daishu_ultimate"]:
			if sounds.has(cue) and sounds[cue].playing:
				voice_playing = true
		music_player.volume_db = lerpf(music_player.volume_db, -32.0 if voice_playing else -20.0, 0.09)
	if screen != "battle":
		queue_redraw()
		return
	if phase == "intro":
		phase_ticks -= 1
		if phase_ticks <= 0:
			phase = "fight"
		queue_redraw()
		return
	if phase == "ending":
		phase_ticks -= 1
		if phase_ticks <= 0:
			if wins[0] >= 2 or wins[1] >= 2:
				winner = 0 if wins[0] >= 2 else 1
				menu_index = 0
				screen = "result"
			else:
				round_number += 1
				_setup_round()
		queue_redraw()
		return
	var inputs := [_read_input(0), _read_input(1)]
	if hitstop_ticks > 0:
		hitstop_ticks -= 1
		queue_redraw()
		return
	if not ultimate.is_empty():
		_tick_ultimate(inputs)
	else:
		for side in 2:
			_tick_fighter(side, inputs[side])
		_tick_projectiles()
		_separate_fighters()
		_update_camera()
		round_ticks -= 1
		if round_ticks <= 0:
			_finish_round(_time_winner())
	if combo_timer > 0:
		combo_timer -= 1
		if combo_timer == 0:
			hit_counter = 0
	for i in range(effects.size() - 1, -1, -1):
		effects[i]["life"] -= 1
		if effects[i]["life"] <= 0:
			effects.remove_at(i)
	queue_redraw()


func _read_input(side: int) -> Dictionary:
	if side == 1 and game_mode != 0:
		return _cpu_input() if game_mode == 1 else _training_input()
	var left := Input.is_physical_key_pressed(KEY_A if side == 0 else KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D if side == 0 else KEY_RIGHT)
	var up := Input.is_physical_key_pressed(KEY_W if side == 0 else KEY_UP)
	var down := Input.is_physical_key_pressed(KEY_S if side == 0 else KEY_DOWN)
	var attack := Input.is_physical_key_pressed(KEY_J if side == 0 else KEY_KP_1) or (side == 1 and Input.is_physical_key_pressed(KEY_1))
	var jump := Input.is_physical_key_pressed(KEY_K if side == 0 else KEY_KP_2) or (side == 1 and Input.is_physical_key_pressed(KEY_2))
	var dash := Input.is_physical_key_pressed(KEY_L if side == 0 else KEY_KP_3) or (side == 1 and Input.is_physical_key_pressed(KEY_3))
	var skill := Input.is_physical_key_pressed(KEY_U if side == 0 else KEY_KP_4) or (side == 1 and Input.is_physical_key_pressed(KEY_4))
	var ult := Input.is_physical_key_pressed(KEY_I if side == 0 else KEY_KP_5) or (side == 1 and Input.is_physical_key_pressed(KEY_5))
	var old: Dictionary = previous_buttons[side]
	var result := {
		"left": left, "right": right, "up": up, "down": down,
		"attack": attack and not old.get("attack", false),
		"jump": jump and not old.get("jump", false),
		"dash": dash and not old.get("dash", false),
		"skill": skill and not old.get("skill", false),
		"ult": ult and not old.get("ult", false)
	}
	previous_buttons[side] = {"attack": attack, "jump": jump, "dash": dash, "skill": skill, "ult": ult}
	return result


func _training_input() -> Dictionary:
	return {"left": false, "right": false, "up": false, "down": false,
		"attack": false, "jump": false, "dash": false, "skill": false, "ult": false}


func _cpu_input() -> Dictionary:
	var result := _training_input()
	if fighters.size() < 2:
		return result
	var self_f: Dictionary = fighters[1]
	var opponent: Dictionary = fighters[0]
	var dist: float = abs(self_f["x"] - opponent["x"])
	if ai_opening_ticks > 0:
		ai_opening_ticks -= 1
		return result
	if ai_memory.get("wait", 0) > 0:
		ai_memory["wait"] -= 1
		result["left"] = ai_memory.get("direction", 0) < 0
		result["right"] = ai_memory.get("direction", 0) > 0
		result["down"] = ai_memory.get("guard", false)
		return result
	var delay: int = [20, 13, 8][difficulty]
	var desired := 0
	if dist > 255.0:
		desired = 1 if opponent["x"] > self_f["x"] else -1
	elif dist < 105.0 and randf() < 0.30:
		desired = -1 if opponent["x"] > self_f["x"] else 1
	var should_guard: bool = opponent["attack"] != "" and dist < 170.0 and randf() < [0.2, 0.5, 0.8][difficulty]
	ai_memory = {"wait": delay, "direction": desired, "guard": should_guard}
	result["left"] = desired < 0
	result["right"] = desired > 0
	result["down"] = should_guard
	if not should_guard and self_f["stun"] <= 0:
		if self_f["energy"] >= 300 and dist < 340.0 and randf() < [0.16, 0.28, 0.42][difficulty]:
			result["ult"] = true
		elif dist < 225.0:
			result["attack"] = randf() < [0.55, 0.80, 0.95][difficulty]
		elif dist < 480.0 and randf() < 0.25:
			result["skill"] = true
		elif dist > 300.0 and self_f["choice"] == 2 and randf() < 0.2:
			result["jump"] = true
	return result


func _tick_fighter(side: int, command: Dictionary) -> void:
	var f: Dictionary = fighters[side]
	if f["flash"] > 0:
		f["flash"] -= 1
	if f["cooldown"] > 0:
		f["cooldown"] -= 1
	if game_mode == 2 and training_energy:
		f["energy"] = 300
	f["guard"] = command["down"] and f["y"] >= FLOOR_Y - 1.0 and f["attack"] == "" and f["stun"] == 0
	if f["stun"] > 0:
		f["stun"] -= 1
		f["state"] = "guard" if f["blocked"] else "hurt"
		f["guard"] = f["blocked"]
		_advance_vertical(f)
		return
	f["blocked"] = false
	if f["attack"] != "":
		if command["attack"] and f["attack"] == "jab" and f["combo_index"] < 3:
			f["combo_queued"] = true
		_tick_attack(side)
		_advance_vertical(f)
		return
	if f["dash"] > 0:
		f["dash"] -= 1
		f["x"] += f["facing"] * 9.5
		f["state"] = "dash"
		_advance_vertical(f)
		return
	if command["ult"] and f["energy"] >= 300 and ultimate.is_empty():
		_start_ultimate(side)
		return
	if command["attack"]:
		if f["y"] < FLOOR_Y - 5.0:
			_start_attack(side, "air")
		elif command["up"]:
			_start_attack(side, "upper")
		elif command["down"]:
			_start_attack(side, "low")
		else:
			f["combo_index"] = 1
			_start_attack(side, "jab")
		return
	if command["skill"] and f["cooldown"] <= 0:
		_start_attack(side, "skill_up" if command["up"] else ("skill_down" if command["down"] else "skill"))
		f["cooldown"] = 75
		return
	if command["dash"] and not f["guard"]:
		f["dash"] = 10
		f["state"] = "dash"
		_effect(f["x"], FLOOR_Y - 15.0, "dust", 20)
		return
	if command["jump"]:
		if f["y"] >= FLOOR_Y - 1.0:
			f["vy"] = JUMP[f["choice"]]
			f["air_jumps"] = 0
		elif f["choice"] == 2 and f["air_jumps"] < 1:
			f["vy"] = JUMP[f["choice"]] * 0.83
			f["air_jumps"] += 1
	if f["guard"]:
		f["state"] = "guard"
		var back_direction: int = -int(f["facing"])
		if (back_direction < 0 and command["left"]) or (back_direction > 0 and command["right"]):
			f["x"] += back_direction * SPEED[f["choice"]] * 0.42 / 60.0
	else:
		var direction := int(command["right"]) - int(command["left"])
		if direction != 0:
			var speed_scale := 0.88 if side == 1 and game_mode == 1 else 1.0
			var old_x: float = f["x"]
			f["x"] = clampf(old_x + direction * SPEED[f["choice"]] * speed_scale / 60.0, 65.0, WORLD_WIDTH - 65.0)
			# The frog uses two additional passing poses and an eight-frame cycle.
			# Reverse the frame order when moving backward relative to facing.
			var frog_walk: bool = f["choice"] == 0
			var phase_length: float = 8.0 if frog_walk else 4.0
			var step_distance: float = 17.5 if frog_walk else 35.0
			f["walk_phase"] = fposmod(float(f["walk_phase"]) + (f["x"] - old_x) * float(f["facing"]) / step_distance, phase_length)
			f["state"] = "walk" if f["y"] >= FLOOR_Y - 1.0 else "jump"
		else:
			f["state"] = "idle" if f["y"] >= FLOOR_Y - 1.0 else "jump"
	_advance_vertical(f)
	if f["y"] >= FLOOR_Y - 1.0 and f["state"] in ["idle", "walk", "guard"]:
		f["facing"] = 1 if fighters[1 - side]["x"] >= f["x"] else -1


func _advance_vertical(f: Dictionary) -> void:
	if f["y"] < FLOOR_Y or f["vy"] < 0.0:
		var was_airborne: bool = f["y"] < FLOOR_Y - 2.0
		f["vy"] += 2350.0 / 60.0
		f["y"] += f["vy"] / 60.0
		if f["y"] >= FLOOR_Y:
			f["y"] = FLOOR_Y
			f["vy"] = 0.0
			if was_airborne:
				_effect(f["x"], FLOOR_Y - 10.0, "dust", 19)
	f["x"] = clampf(f["x"], 65.0, WORLD_WIDTH - 65.0)


func _start_attack(side: int, kind: String) -> void:
	var f: Dictionary = fighters[side]
	f["attack"] = kind
	f["attack_frame"] = 0
	f["attack_hit"] = false
	f["combo_queued"] = false
	f["guard"] = false
	f["state"] = kind
	_play_sound("skill" if kind.begins_with("skill") else "attack_swing", [0.84, 0.92, 1.25, 1.08][f["choice"]])


func _attack_duration(kind: String, choice: int, combo_index: int) -> int:
	match kind:
		"jab":
			return [28, 25, 20, 22][choice] + maxi(0, combo_index - 1) * 2
		"upper":
			return [32, 30, 26, 27][choice]
		"low":
			return [30, 27, 23, 25][choice]
		"air":
			return [29, 27, 21, 24][choice]
		_:
			return 34


func _tick_attack(side: int) -> void:
	var f: Dictionary = fighters[side]
	f["attack_frame"] += 1
	var frame: int = f["attack_frame"]
	var kind: String = f["attack"]
	var choice: int = f["choice"]
	var duration: int = _attack_duration(kind, choice, f["combo_index"])
	var impact: int = [9, 7, 5, 6][choice]
	var reach: float = [218.0, 225.0, 238.0, 220.0][choice]
	var damage: int = [38, 45, 30, 33][choice]
	if kind == "jab":
		impact += f["combo_index"] - 1
		damage = roundi(float(damage) * [0.0, 1.0, 1.13, 1.45][f["combo_index"]])
	elif kind == "upper":
		impact += 2
		damage += 17
		reach -= 20.0
	elif kind == "low":
		impact += 1
		damage += 8
		reach += 12.0
	elif kind == "air":
		damage += 12
		reach += 15.0
	elif kind.begins_with("skill"):
		impact = 11
		damage = 70
	if frame == impact:
		if kind.begins_with("skill"):
			_do_skill(side, kind)
		else:
			var other: Dictionary = fighters[1 - side]
			var horizontal: float = (other["x"] - f["x"]) * f["facing"]
			var vertical: float = abs(other["y"] - f["y"])
			var hit := horizontal > -35.0 and horizontal < reach and vertical < (180.0 if kind == "upper" else 135.0)
			if hit:
				_deal_hit(side, damage, true, kind == "upper", kind == "low")
				f["attack_hit"] = true
	if choice == 2 and kind == "jab" and frame == roundi(float(duration) * 0.65) and f["attack_hit"]:
		var opponent: Dictionary = fighters[1 - side]
		var follow_distance: float = (opponent["x"] - f["x"]) * f["facing"]
		if follow_distance > -35.0 and follow_distance < reach + 25.0:
			_deal_hit(side, 16, true, false, false)
	if kind == "jab" and f["combo_queued"] and f["combo_index"] < 3 and frame >= duration - 8:
		f["combo_index"] += 1
		_start_attack(side, "jab")
	elif frame >= duration:
		f["attack"] = ""
		f["attack_frame"] = 0
		f["state"] = "idle"


func _do_skill(side: int, variant: String = "skill") -> void:
	var f: Dictionary = fighters[side]
	var choice: int = f["choice"]
	var other: Dictionary = fighters[1 - side]
	if variant == "skill_up":
		var reach: float = 130.0 if choice in [1, 2] else 190.0
		var target_x: float = f["x"] + f["facing"] * reach
		if choice in [1, 2]:
			f["x"] = clampf(target_x, 65.0, WORLD_WIDTH - 65.0)
			f["vy"] = -460.0 if choice == 1 else -560.0
		if abs(other["x"] - target_x) < 125.0 and abs(other["y"] - f["y"]) < 220.0:
			_deal_hit(side, 70, true, true, false)
		_effect(target_x, FLOOR_Y - 125.0, "pillar", 24)
		return
	if variant == "skill_down":
		projectiles.append({
			"owner": side, "x": f["x"] + f["facing"] * 70.0,
			"y": FLOOR_Y - 48.0, "vx": f["facing"] * 10.0,
			"life": 90, "damage": 58, "kind": "ground", "choice": choice
		})
		_effect(f["x"], FLOOR_Y - 20.0, "ground", 20)
		return
	if choice == 1 or choice == 2:
		f["x"] = clampf(f["x"] + f["facing"] * (115.0 if choice == 1 else 150.0), 65.0, WORLD_WIDTH - 65.0)
		if abs(other["x"] - f["x"]) < 125.0 and abs(other["y"] - f["y"]) < 125.0:
			_deal_hit(side, 75 if choice == 1 else 65, true, choice == 2, false)
		_effect(f["x"], f["y"] - 90.0, "rush" if choice == 1 else "shock", 18)
	elif choice == 3:
		projectiles.append({
			"owner": side, "x": f["x"] + f["facing"] * 105.0,
			"y": f["y"] - 184.0, "vx": f["facing"] * 16.0,
			"life": 80, "damage": 70, "kind": "verbal"
		})
		_directed_beam_effect(f["x"] + f["facing"] * 68.0, f["y"] - 184.0, f["facing"], 230.0, 21, "verbal")
	else:
		projectiles.append({
			"owner": side, "x": f["x"] + f["facing"] * 75.0,
			"y": f["y"] - 125.0, "vx": f["facing"] * (5.5 if choice == 0 else 9.0),
			"life": 115, "damage": 60 if choice == 0 else 48,
			"kind": "wave" if choice == 0 else "bubble"
		})
		_effect(f["x"], f["y"] - 115.0, "spark", 15)


func _tick_projectiles() -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		p["x"] += p["vx"]
		p["life"] -= 1
		var other: Dictionary = fighters[1 - p["owner"]]
		var ground: bool = p["kind"] == "ground"
		if abs(p["x"] - other["x"]) < 60.0 and abs(p["y"] - (other["y"] - 125.0)) < 120.0 and (not ground or other["y"] >= FLOOR_Y - 35.0):
			_deal_hit(p["owner"], p["damage"], true, false, ground)
			if p["kind"] != "verbal":
				_effect(p["x"], p["y"], "hit", 18)
			projectiles.remove_at(i)
		elif p["life"] <= 0 or p["x"] < 0.0 or p["x"] > WORLD_WIDTH:
			projectiles.remove_at(i)


func _deal_hit(attacker: int, amount: int, blockable: bool, launch: bool, knockdown: bool) -> void:
	if phase != "fight":
		return
	var defender := 1 - attacker
	var a: Dictionary = fighters[attacker]
	var d: Dictionary = fighters[defender]
	var blocked: bool = blockable and d["guard"] and d["y"] >= FLOOR_Y - 1.0
	var damage := maxi(1, roundi(float(amount) * (0.2 if blocked else 1.0)))
	d["hp"] = maxi(0, int(d["hp"]) - damage)
	d["flash"] = 7
	d["stun"] = 11 if blocked else (30 if knockdown else 18)
	d["blocked"] = blocked
	d["state"] = "guard" if blocked else "hurt"
	d["attack"] = ""
	d["dash"] = 0
	if not blocked:
		var push: float = 72.0 if knockdown else [34.0, 42.0, 22.0, 30.0][a["choice"]]
		d["x"] = clampf(d["x"] + a["facing"] * push, 65.0, WORLD_WIDTH - 65.0)
		if launch:
			d["vy"] = -510.0
		elif knockdown:
			d["vy"] = -270.0
	if not (game_mode == 2 and training_energy):
		a["energy"] = mini(300, int(a["energy"]) + roundi(amount * (0.25 if blocked else 0.5)))
		d["energy"] = mini(300, int(d["energy"]) + roundi(damage * 0.6))
	hit_counter += 1
	combo_timer = 85
	hitstop_ticks = 10 if amount >= 100 else (8 if amount >= 45 else 6)
	camera_shake_ticks = 12 if amount >= 100 else (9 if amount >= 45 else 6)
	camera_shake_strength = 8.0 if amount >= 100 else (5.5 if amount >= 45 else 3.5)
	_effect(d["x"], d["y"] - 125.0, "guard" if blocked else "hit", 15)
	if not blocked and amount >= 45:
		_effect(d["x"], FLOOR_Y - 28.0, "shock", 16)
	_play_sound("block" if blocked else "attack_hit")
	if not blocked:
		_play_sound("hurt")
	if d["hp"] <= 0:
		_finish_round(attacker)


func _effect(x: float, y: float, kind: String, life: int) -> void:
	effects.append({"x": x, "y": y, "kind": kind, "life": life, "max_life": life})


func _directed_beam_effect(x: float, y: float, facing: float, length: float, life: int, kind: String) -> void:
	effects.append({"x": x, "y": y, "kind": kind, "life": life, "max_life": life,
		"facing": facing, "length": length})


func _separate_fighters() -> void:
	if fighters.size() < 2:
		return
	var a: Dictionary = fighters[0]
	var b: Dictionary = fighters[1]
	var dx: float = b["x"] - a["x"]
	if absf(dx) < 94.0 and absf(a["y"] - b["y"]) < 140.0:
		var push: float = (94.0 - absf(dx)) * 0.5
		var direction := 1.0 if dx >= 0.0 else -1.0
		a["x"] = clampf(a["x"] - direction * push, 65.0, WORLD_WIDTH - 65.0)
		b["x"] = clampf(b["x"] + direction * push, 65.0, WORLD_WIDTH - 65.0)


func _update_camera() -> void:
	if fighters.size() < 2:
		return
	# Keep the camera still while both fighters remain inside a comfortable screen area.
	# Otherwise an approaching CPU makes an idle player appear to walk forward.
	var left_x: float = minf(fighters[0]["x"], fighters[1]["x"])
	var right_x: float = maxf(fighters[0]["x"], fighters[1]["x"])
	var margin := 150.0
	var minimum_camera: float = right_x - 640.0 + margin
	var maximum_camera: float = left_x + 640.0 - margin
	var target: float = clampf(camera_x, minimum_camera, maximum_camera) if minimum_camera <= maximum_camera else (left_x + right_x) * 0.5
	camera_x = lerpf(camera_x, clampf(target, 640.0, WORLD_WIDTH - 640.0), 0.18)


func _time_winner() -> int:
	var a_ratio: float = float(fighters[0]["hp"]) / float(MAX_HP[fighters[0]["choice"]])
	var b_ratio: float = float(fighters[1]["hp"]) / float(MAX_HP[fighters[1]["choice"]])
	if is_equal_approx(a_ratio, b_ratio):
		return -1
	return 0 if a_ratio > b_ratio else 1


func _finish_round(which: int) -> void:
	if phase == "ending":
		return
	phase = "ending"
	phase_ticks = 95
	winner = which
	if which >= 0:
		wins[which] += 1


func _start_ultimate(side: int) -> void:
	var f: Dictionary = fighters[side]
	f["energy"] = 0
	f["attack"] = ""
	f["state"] = "ultimate"
	ultimate = {"side": side, "t": 0, "hit": false, "lock_x": fighters[1 - side]["x"],
		"charge_start_x": f["x"], "charge_target_x": f["x"], "leap_start_x": f["x"]}
	_effect(f["x"], f["y"] - 140.0, "burst", 35)
	if f["choice"] == 0:
		_play_sound("naiwa_ultimate")
	elif f["choice"] == 1:
		_play_sound("niulai_ultimate")
	elif f["choice"] == 2:
		_play_sound("daishu_ultimate")


func _tick_ultimate(inputs: Array) -> void:
	var side: int = ultimate["side"]
	var defender := 1 - side
	var f: Dictionary = fighters[side]
	var d: Dictionary = fighters[defender]
	ultimate["t"] += 1
	var t: int = ultimate["t"]
	var choice: int = f["choice"]
	# The 0.6-second cut-in freezes both fighters, then the defender can react.
	if t > 36 and phase == "fight":
		_tick_fighter(defender, inputs[defender])
	if choice == 0:
		# Ten visible sound-wave hits and a stronger final pulse.
		if t >= 52 and t < 172 and (t - 52) % 12 == 0:
			_deal_hit(side, 25, true, false, false)
			_effect(f["x"], f["y"] - (80.0 if t >= 160 else 170.0), "wave", 24)
		if t == 177:
			_deal_hit(side, 100, true, true, true)
			_effect(f["x"], f["y"] - 170.0, "burst", 26)
		if t >= 204:
			_end_ultimate()
	elif choice == 1:
		if t == 76:
			f["facing"] = 1 if d["x"] >= f["x"] else -1
			ultimate["charge_start_x"] = f["x"]
			ultimate["charge_target_x"] = clampf(f["x"] + f["facing"] * maxf(absf(d["x"] - f["x"]) + 430.0, 1050.0), 65.0, WORLD_WIDTH - 65.0)
		if t >= 76 and t <= 156:
			var old_x: float = f["x"]
			var progress: float = _ease01(float(t - 76) / 80.0)
			f["x"] = lerpf(ultimate["charge_start_x"], ultimate["charge_target_x"], progress)
			if t % 5 == 0:
				_effect(f["x"] - f["facing"] * 65.0, FLOOR_Y - 105.0, "dash", 14)
			if not ultimate["hit"] and d["x"] >= minf(old_x, f["x"]) - 105.0 and d["x"] <= maxf(old_x, f["x"]) + 105.0 and d["y"] > FLOOR_Y - 125.0:
				ultimate["hit"] = true
				_deal_hit(side, 360, true, true, true)
				_effect(d["x"], d["y"] - 100.0, "rush", 26)
		if t >= 178:
			_end_ultimate()
	elif choice == 2:
		if t == 50:
			ultimate["leap_start_x"] = f["x"]
		if t >= 50 and t <= 118:
			var leap_progress: float = clampf(float(t - 50) / 68.0, 0.0, 1.0)
			f["x"] = lerpf(ultimate["leap_start_x"], d["x"], _ease01(leap_progress))
			f["y"] = FLOOR_Y - sin(leap_progress * PI) * 335.0
			f["vy"] = 0.0
			f["facing"] = 1 if d["x"] >= f["x"] else -1
		if t == 118:
			f["x"] = d["x"]
			f["y"] = FLOOR_Y - 52.0
			ultimate["hit"] = true
			_deal_hit(side, 380, false, true, true)
			_effect(d["x"], FLOOR_Y - 35.0, "slam", 30)
			_effect(d["x"], FLOOR_Y - 7.0, "dust", 26)
		if t >= 126:
			f["y"] = FLOOR_Y
		if t >= 155:
			_end_ultimate()
	else:
		if t == 110:
			f["facing"] = 1 if d["x"] >= f["x"] else -1
			var forward: float = (d["x"] - f["x"]) * f["facing"]
			var fist_x: float = f["x"] + f["facing"] * 68.0
			var beam_length: float = clampf(absf(d["x"] - fist_x) + 70.0, 180.0, 600.0)
			if forward > 0.0 and forward < 600.0 and d["y"] > FLOOR_Y - 145.0:
				ultimate["hit"] = true
				_deal_hit(side, 350, true, true, true)
			_directed_beam_effect(fist_x, f["y"] - 184.0, f["facing"], beam_length, 32, "beam")
		if t >= 145:
			_end_ultimate()
	if not (choice == 2 and t >= 50 and t < 126):
		_separate_fighters()
	_update_camera()


func _end_ultimate() -> void:
	if ultimate.is_empty():
		return
	var side: int = ultimate["side"]
	if fighters.size() == 2:
		fighters[side]["state"] = "idle"
	ultimate.clear()


func _draw() -> void:
	if screen == "battle" or screen == "pause":
		_draw_battle()
		if screen == "pause":
			_draw_panel(Rect2(390, 205, 500, 295), Color("#1e1a30"))
			_center_text("暂停", 640, 270, 48, Color.WHITE)
			_center_text("J / Enter / Esc 继续", 640, 352, 26, Color("#ffe997"))
			_center_text("Q 返回标题", 640, 405, 25, Color.WHITE)
	else:
		_draw_menu_background()
		match screen:
			"title": _draw_title()
			"mode": _draw_mode()
			"select": _draw_select()
			"difficulty": _draw_difficulty()
			"stage": _draw_stage_select()
			"result": _draw_result()


func _draw_menu_background() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#151927"))
	for i in 10:
		var x := float(i) * 170.0 - 90.0
		draw_line(Vector2(x, 720), Vector2(x + 420, 0), Color("#252c40"), 35.0)
	draw_circle(Vector2(1090, 160), 260, Color("#27354b"))
	draw_circle(Vector2(180, 600), 250, Color("#24223b"))
	draw_rect(Rect2(0, 0, 1280, 11), Color("#ffd34d"))
	draw_rect(Rect2(0, 709, 1280, 11), Color("#ffd34d"))


func _draw_title() -> void:
	_center_text("梗斗竞技场", 640, 165, 92, Color("#ffd04a"))
	_center_text("四人登场  ·  双人对战  ·  挑战人机", 640, 220, 26, Color("#e9e7e1"))
	for i in 4:
		_draw_card(Rect2(120 + i * 260, 295, 235, 270), i, false)
	_center_text("按 J / Enter 开始", 640, 648, 31, Color("#ffe7a1"))


func _draw_mode() -> void:
	_center_text("选择模式", 640, 152, 67, Color("#ffd04a"))
	var labels := ["本地双人 1 VS 1", "玩家 VS 人机", "训练模式"]
	for i in 3:
		var box := Rect2(350, 236 + i * 115, 580, 85)
		_draw_panel(box, Color("#6e4a22") if menu_index == i else Color("#24283b"))
		_center_text(labels[i], 640, 290 + i * 115, 30, Color.WHITE)
	_center_text("W / S 选择    J 确认    Esc 返回", 640, 660, 23, Color("#c8cbda"))


func _draw_select() -> void:
	_center_text("选择角色", 640, 91, 59, Color("#ffd04a"))
	var label := "1P 选择你的角色" if select_side == 0 else ("选择 CPU 对手" if game_mode != 0 else "2P 选择你的角色")
	_center_text(label, 640, 142, 27, Color("#f4f2e9"))
	for i in 4:
		var x := 122 + (i % 4) * 260
		_draw_card(Rect2(x, 205, 235, 315), i, select_cursor == i)
	_center_text("已选 1P：%s    2P：%s" % [NAMES[selections[0]], NAMES[selections[1]]], 640, 586, 25, Color.WHITE)
	_center_text("A / D 或方向键切换    J 确认    Esc 返回", 640, 652, 21, Color("#c8cbda"))


func _draw_card(rect: Rect2, choice: int, selected: bool) -> void:
	var inner: Color = COLORS[choice].darkened(0.64)
	_draw_panel(rect, inner)
	if selected:
		draw_rect(rect.grow(5), Color("#ffe27d"), false, 5)
	var tex: Texture2D = sprites.get(IDS[choice], null)
	if tex != null:
		var height := rect.size.y * 0.72
		var width := height * float(tex.get_width()) / float(tex.get_height())
		width = minf(width, rect.size.x - 20)
		draw_texture_rect(tex, Rect2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + 8, width, height), false)
	else:
		draw_circle(rect.position + Vector2(rect.size.x * 0.5, 104), 59, COLORS[choice])
		draw_circle(rect.position + Vector2(rect.size.x * 0.5, 202), 72, COLORS[choice])
	_center_text(NAMES[choice], rect.position.x + rect.size.x * 0.5, rect.end.y - 39, 30, Color.WHITE)
	if rect.size.y >= 300:
		_center_text(ROLES[choice], rect.position.x + rect.size.x * 0.5, rect.end.y - 12, 16, Color("#d9d9e6"))


func _draw_stage_select() -> void:
	_center_text("选择舞台", 640, 107, 64, Color("#ffd04a"))
	var main_rect := Rect2(70, 157, 760, 428)
	_draw_panel(main_rect.grow(6), Color("#222b3f"))
	if stage_textures.has(stage_index):
		draw_texture_rect(stage_textures[stage_index], main_rect, false)
	else:
		draw_rect(main_rect, Color("#7b93a7"))
	_draw_panel(Rect2(70, 585, 760, 53), Color("#20263a"))
	_center_text(STAGES[stage_index], 450, 620, 27, Color.WHITE)
	for i in 4:
		var row := Rect2(865, 157 + i * 119, 340, 103)
		_draw_panel(row, Color("#6e4a22") if stage_index == i else Color("#20263a"))
		var thumb := Rect2(row.position.x + 8, row.position.y + 8, 151, 87)
		if stage_textures.has(i):
			draw_texture_rect(stage_textures[i], thumb, false)
		else:
			draw_rect(thumb, Color("#7b93a7"))
		_text(STAGES[i], row.position.x + 172, row.position.y + 63, 21, Color.WHITE)
		if stage_index == i:
			draw_rect(row.grow(4), Color("#ffe27d"), false, 5)
	_center_text("A / D 或方向键切换    J 确认    Esc 返回", 640, 680, 23, Color.WHITE)


func _draw_difficulty() -> void:
	_center_text("选择人机难度", 640, 150, 61, Color("#ffd04a"))
	var labels := ["简单  ·  慢一些的反应", "普通  ·  标准对手", "困难  ·  积极攻防"]
	for i in 3:
		var box := Rect2(350, 236 + i * 110, 580, 82)
		_draw_panel(box, Color("#6e4a22") if menu_index == i else Color("#24283b"))
		_center_text(labels[i], 640, box.position.y + 53, 27, Color.WHITE)
	_center_text("W / S 选择    J 确认    Esc 返回", 640, 650, 23, Color("#c8cbda"))


func _draw_result() -> void:
	var label := "平局" if winner < 0 else ("1P 胜利！" if winner == 0 else ("CPU 胜利！" if game_mode == 1 else "2P 胜利！"))
	_center_text(label, 640, 145, 75, Color("#ffd04a"))
	if winner >= 0:
		_draw_card(Rect2(505, 208, 270, 290), selections[winner], true)
	for i in 2:
		var box := Rect2(385, 537 + i * 63, 510, 51)
		_draw_panel(box, Color("#6e4a22") if menu_index == i else Color("#24283b"))
		_center_text("再战" if i == 0 else "重新选角", 640, box.position.y + 35, 27, Color.WHITE)


func _draw_panel(rect: Rect2, bg: Color) -> void:
	draw_rect(rect, bg)
	draw_rect(rect, Color("#c2b7a9"), false, 2)


func _text(label: String, x: float, y: float, size: int, color: Color = Color.WHITE) -> void:
	draw_string(FONT, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _center_text(label: String, x: float, y: float, size: int, color: Color = Color.WHITE) -> void:
	var width: float = FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(label, x - width * 0.5, y, size, color)


func _draw_battle() -> void:
	_draw_world_stage()
	if fighters.size() != 2:
		return
	var shake_amount: float = camera_shake_strength * float(camera_shake_ticks) / 12.0
	render_shake = Vector2(sin(float(tick_count) * 2.3), cos(float(tick_count) * 3.1)) * shake_amount
	var offset := Vector2(640.0 - camera_x, 0) + render_shake
	draw_set_transform(offset)
	for p in projectiles:
		_draw_projectile(p)
	for e in effects:
		if e["kind"] == "thunder":
			_draw_effect(e)
	for side in 2:
		_draw_fighter(fighters[side])
	for e in effects:
		if e["kind"] != "thunder":
			_draw_effect(e)
	draw_set_transform(Vector2.ZERO)
	_draw_hud()
	if phase == "intro":
		_center_text("ROUND %d" % round_number, 640, 310, 73, Color("#fff0a9"))
		_center_text("FIGHT!", 640, 386, 64, Color.WHITE)
	elif phase == "ending":
		_center_text("KO!" if winner >= 0 else "DRAW!", 640, 360, 100, Color("#ffde69"))


func _draw_world_stage() -> void:
	if stage_textures.has(stage_index):
		draw_texture_rect(stage_textures[stage_index], Rect2(0, 0, 1280, 720), false)
		return
	var sky: Color = [Color("#9bd7e5"), Color("#f1bd81"), Color("#343551"), Color("#293c70")][stage_index]
	draw_rect(Rect2(0, 0, 1280, 720), sky)
	if stage_index == 0:
		draw_circle(Vector2(1020, 190), 103, Color("#fff1b2"))
		for j in 8:
			draw_circle(Vector2(120 + j * 180 - fmod(camera_x * 0.08, 80.0), 515), 140, Color("#7bc5ae"))
		for j in 5:
			draw_line(Vector2(150 + j * 300, 485), Vector2(150 + j * 300, 260), Color("#f7d48b"), 9)
			draw_circle(Vector2(150 + j * 300, 260), 30, Color("#f0a3a1"))
	elif stage_index == 1:
		draw_circle(Vector2(920, 210), 90, Color("#ffe0a0"))
		for j in 7:
			draw_circle(Vector2(j * 250 - fmod(camera_x * 0.06, 150.0), 555), 210, Color("#b0bb7e"))
	elif stage_index == 2:
		for j in 14:
			var h := 160 + (j * 53) % 150
			draw_rect(Rect2(j * 115 - fmod(camera_x * 0.06, 120.0), 600 - h, 85, h), Color("#494b72"))
			draw_rect(Rect2(j * 115 - fmod(camera_x * 0.06, 120.0) + 16, 600 - h + 20, 18, 31), Color("#efc972"))
	else:
		for j in 12:
			draw_line(Vector2(j * 130, 100), Vector2(j * 130, 600), Color("#5368a6"), 2)
		for j in 7:
			draw_line(Vector2(0, j * 85 + 70), Vector2(1280, j * 85 + 70), Color("#5368a6"), 2)
	draw_rect(Rect2(0, FLOOR_Y, 1280, 120), [Color("#d49d6f"), Color("#957e55"), Color("#57516a"), Color("#293b64")][stage_index])
	draw_rect(Rect2(0, FLOOR_Y, 1280, 8), Color("#ffecac"))
	if stage_index == 3:
		for j in 14:
			draw_line(Vector2(j * 100, FLOOR_Y), Vector2(j * 100 - 100, 720), Color("#466bc0"), 1)
		for j in 4:
			draw_line(Vector2(0, FLOOR_Y + j * 32), Vector2(1280, FLOOR_Y + j * 32), Color("#466bc0"), 1)


func _draw_fighter(f: Dictionary) -> void:
	var choice: int = f["choice"]
	var bob := 0.0
	var x: float = f["x"]
	var y: float = f["y"] + bob
	var own_ultimate: bool = f["state"] == "ultimate" and not ultimate.is_empty() and f["side"] == ultimate["side"]
	var ult_t: int = ultimate["t"] if own_ultimate else 0
	if own_ultimate and choice == 0 and ult_t < 178:
		if ult_t < 160:
			y += sin(float(ult_t) * 0.45) * 4.0
	_draw_fighter_shadow(f, x)
	var facing: float = f["facing"]
	var length: int = _attack_duration(f["attack"], choice, f["combo_index"])
	var attack_progress: float = clampf(float(f["attack_frame"]) / float(length), 0.0, 1.0)
	var kicking: bool = f["attack"] in ["low", "air", "skill_down"] or (f["attack"] == "jab" and f["combo_index"] == 3) or (f["attack"] == "skill" and choice == 2)
	var attack_motion := _attack_motion(attack_progress, kicking, choice) if f["attack"] != "" else {}
	var lunge: float = attack_motion.get("x", 0.0)
	y += attack_motion.get("y", 0.0)
	var squash_x := 1.0
	var squash_y := 1.0
	var tilt := 0.0
	if f["attack"] != "":
		squash_x = attack_motion["sx"]
		squash_y = attack_motion["sy"]
		tilt = attack_motion["tilt"]
	elif f["state"] == "walk":
		# The walk sprites already contain real lifted and planted feet.
		tilt = sin(float(f["walk_phase"]) * TAU / (8.0 if choice == 0 else 4.0)) * 0.012
	elif f["state"] == "dash":
		squash_x = 1.13
		squash_y = 0.91
		tilt = -0.10
	elif f["state"] == "guard":
		squash_x = 1.03
		squash_y = 0.94
		y += 9.0
		tilt = 0.025
	elif f["state"] == "hurt":
		squash_x = 0.91
		squash_y = 1.06
		tilt = 0.07
	elif own_ultimate and choice == 1 and ult_t >= 76 and ult_t <= 156:
		squash_x = 1.16
		squash_y = 0.90
		tilt = -0.10
	elif own_ultimate and choice == 2 and ult_t >= 50 and ult_t < 118:
		tilt = -0.12 + 0.30 * clampf(float(ult_t - 50) / 68.0, 0.0, 1.0)
		squash_x = 1.07
	elif own_ultimate and choice == 0 and ult_t < 160:
		squash_x = 1.0 + sin(float(ult_t) * 0.45) * 0.035
		squash_y = 1.0 - sin(float(ult_t) * 0.45) * 0.035
		tilt = sin(float(ult_t) * 0.22) * 0.045
	elif f["y"] < FLOOR_Y - 5.0:
		squash_x = 0.95
		squash_y = 1.06
	draw_set_transform(Vector2(x + 640.0 - camera_x + facing * lunge, y) + render_shake, tilt, Vector2(facing * squash_x, squash_y))
	var tex: Texture2D = sprites.get(f["id"], null)
	if f["state"] == "walk":
		var walk_names := ["walk_contact_a", "walk_mid_back", "walk_lift_back", "walk_mid_back", "walk_contact_b", "walk_mid_front", "walk_lift_front", "walk_mid_front"] if choice == 0 else ["walk_contact_a", "walk_lift_back", "walk_contact_b", "walk_lift_front"]
		var walk_frame := clampi(floori(float(f["walk_phase"])), 0, walk_names.size() - 1)
		var walk_poses: Dictionary = pose_textures.get(f["id"], {})
		tex = walk_poses.get(walk_names[walk_frame], tex)
	if tex != null:
		var height: float = [266.0, 250.0, 271.0, 260.0][choice]
		var tint := Color("#fff7c2") if f["flash"] > 0 and f["flash"] % 2 == 0 else Color.WHITE
		if selections[0] == selections[1] and f["side"] == 1:
			tint = tint * Color(0.72, 0.89, 1.0)
		var pose_name := "punch"
		if f["attack"] != "":
			if attack_progress < 0.25:
				pose_name = "windup"
			elif attack_progress < 0.60:
				pose_name = "kick" if kicking else "punch"
			else:
				pose_name = "follow"
		elif f["state"] == "hurt":
			pose_name = "hurt"
		elif own_ultimate:
			if choice == 0:
				if ult_t >= 178:
					pose_name = "after"
				elif ult_t >= 160:
					pose_name = "laugh_fall"
				elif ult_t >= 76 and ult_t < 100:
					pose_name = "laugh_head"
				else:
					pose_name = "laugh"
			else:
				pose_name = "ultimate"
		var available: Dictionary = pose_textures.get(f["id"], {})
		var pose: Texture2D = available.get(pose_name, available.get("laugh", null) if choice == 0 and own_ultimate else null)
		var old_pose: Texture2D = null
		var pose_blend := 1.0
		if f["attack"] != "":
			if attack_progress >= 0.25 and attack_progress < 0.34:
				old_pose = available.get("windup", null)
				pose_blend = _ease01((attack_progress - 0.25) / 0.09)
			elif attack_progress >= 0.60 and attack_progress < 0.69:
				old_pose = available.get("kick" if kicking else "punch", null)
				pose_blend = _ease01((attack_progress - 0.60) / 0.09)
		if choice == 0 and own_ultimate:
			for change in [[76, "laugh"], [100, "laugh_head"], [160, "laugh"], [178, "laugh_fall"]]:
				if ult_t >= change[0] and ult_t < change[0] + 7:
					old_pose = available.get(change[1], null)
					pose_blend = _ease01(float(ult_t - change[0]) / 7.0)
					break
		var pose_alpha := 0.0
		if pose != null and f["attack"] != "":
			pose_alpha = _ease01(attack_progress / 0.11) * (1.0 - _ease01((attack_progress - 0.84) / 0.16))
		elif pose != null and f["state"] == "hurt":
			pose_alpha = 0.9
		elif pose != null and own_ultimate:
			pose_alpha = _ease01(clampf(float(ult_t - 70) / 12.0, 0.0, 1.0)) if choice == 3 else 1.0
		if f["state"] == "dash" and f["dash"] > 0:
			for ghost in 2:
				var ghost_width: float = height * float(tex.get_width()) / float(tex.get_height())
				var ghost_rect := Rect2(-ghost_width * 0.5 - 23.0 * float(ghost + 1), -height, ghost_width, height)
				draw_texture_rect(tex, ghost_rect, false, Color(0.73, 0.92, 1.0, 0.19 - ghost * 0.07))
		_draw_character_image(tex, height, tint, 1.0 - pose_alpha)
		if pose != null and pose_alpha > 0.0:
			if old_pose != null:
				_draw_character_image(old_pose, height, tint, pose_alpha * (1.0 - pose_blend))
			_draw_character_image(pose, height, tint, pose_alpha * pose_blend)
	else:
		_draw_fighter_placeholder(choice, f)
	draw_set_transform(Vector2(640.0 - camera_x, 0) + render_shake)
	if debug_boxes:
		draw_rect(Rect2(x - 47, y - 240, 94, 240), Color.GREEN, false, 2)
		if f["attack"] != "" and f["attack_frame"] >= 5 and f["attack_frame"] <= 12:
			draw_rect(Rect2(x + f["facing"] * 30.0 - 50.0, y - 190.0, 120, 90), Color.RED, false, 2)


func _draw_fighter_shadow(f: Dictionary, world_x: float) -> void:
	var air_height: float = maxf(0.0, FLOOR_Y - float(f["y"]))
	var ground_strength: float = clampf(1.0 - air_height / 360.0, 0.20, 1.0)
	var width_scale: float = clampf(1.0 - air_height / 700.0, 0.55, 1.0)
	var screen_x: float = world_x + 640.0 - camera_x + render_shake.x
	# A soft cast silhouette follows the stage light; night stages keep it subtle.
	var cast_length: float = [105.0, 135.0, 55.0, 35.0][stage_index] * ground_strength
	var cast_direction: float = -1.0 if stage_index < 2 else 1.0
	draw_set_transform(Vector2(screen_x, FLOOR_Y + 3.0 + render_shake.y))
	for layer in range(4):
		var spread: float = 13.0 - float(layer) * 3.0
		var cast_points := PackedVector2Array([
			Vector2(-39.0 - spread, 0.0), Vector2(39.0 + spread, 0.0),
			Vector2(cast_direction * cast_length + 36.0 + spread, 43.0 + spread),
			Vector2(cast_direction * cast_length - 43.0 - spread, 43.0 + spread)
		])
		draw_colored_polygon(cast_points, Color(0.10, 0.065, 0.07, (0.012 + float(layer) * 0.011) * ground_strength))
	# Broad penumbra and two contact patches anchor the actual feet.
	draw_set_transform(Vector2(screen_x, FLOOR_Y + 4.0 + render_shake.y), 0.0, Vector2(width_scale, 0.27))
	for layer in range(6):
		var radius: float = 86.0 - float(layer) * 9.0
		var opacity: float = (0.018 + float(layer) * 0.012) * ground_strength
		draw_circle(Vector2.ZERO, radius, Color(0.12, 0.085, 0.075, opacity))
	draw_set_transform(Vector2(screen_x, FLOOR_Y + 2.0 + render_shake.y), 0.0, Vector2(width_scale, 0.23))
	for foot in [-1.0, 1.0]:
		draw_circle(Vector2(foot * 33.0, 0.0), 31.0, Color(0.10, 0.07, 0.06, 0.20 * ground_strength))


func _draw_character_image(tex: Texture2D, height: float, tint: Color, opacity: float) -> void:
	var width: float = height * float(tex.get_width()) / float(tex.get_height())
	var foot_shift: float = height * float(texture_foot_margins.get(tex.resource_path, 0.0))
	var color := Color(tint.r, tint.g, tint.b, tint.a * opacity)
	draw_texture_rect(tex, Rect2(-width * 0.5, -height + foot_shift, width, height), false, color)


func _ease01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _attack_motion(progress: float, kicking: bool, choice: int = 0) -> Dictionary:
	# Character-specific anticipation, drive, impact and recoil are sampled every frame.
	var drive: float = [0.90, 1.30, 1.48, 1.12][choice]
	var lift: float = [0.78, 0.72, 1.55, 1.00][choice]
	var coil: float = [8.0, 4.0, 13.0, 6.0][choice]
	var attack_tilt: float = [-0.06, -0.16, -0.19, -0.09][choice]
	var keys: Array = [
		[0.00, 0.0, 0.0, 1.00, 1.00, 0.00, 0.0],
		[0.16, -15.0 * drive, coil, 1.05, 0.92, 0.07, 0.35],
		[0.34, 38.0 * drive, -45.0 * lift if kicking else -4.0, 1.14, 0.94, attack_tilt, 1.0],
		[0.58, 25.0 * drive, -32.0 * lift if kicking else -2.0, 1.08, 0.97, attack_tilt * 0.70, 1.0],
		[0.78, 5.0 * drive, -6.0 if kicking else 3.0, 0.97, 1.04, 0.04, 0.7],
		[1.00, 0.0, 0.0, 1.00, 1.00, 0.00, 0.0]
	]
	var left: Array = keys[0]
	var right: Array = keys[keys.size() - 1]
	for i in range(keys.size() - 1):
		if progress <= keys[i + 1][0]:
			left = keys[i]
			right = keys[i + 1]
			break
	var t := _ease01((progress - left[0]) / maxf(right[0] - left[0], 0.001))
	return {
		"x": lerpf(left[1], right[1], t),
		"y": lerpf(left[2], right[2], t),
		"sx": lerpf(left[3], right[3], t),
		"sy": lerpf(left[4], right[4], t),
		"tilt": lerpf(left[5], right[5], t),
		"alpha": lerpf(left[6], right[6], t)
	}


func _draw_fighter_placeholder(choice: int, f: Dictionary) -> void:
	var body: Color = COLORS[choice]
	if f["flash"] > 0 and f["flash"] % 2 == 0:
		body = Color.WHITE
	if choice == 0:
		draw_circle(Vector2(0, -97), 88, body)
		draw_circle(Vector2(-8, -205), 61, body)
		draw_circle(Vector2(0, -88), 65, Color("#f6e4ae"))
		draw_circle(Vector2(38, -237), 17, Color("#72a365"))
		draw_circle(Vector2(40, -237), 9, Color.BLACK)
		draw_line(Vector2(42, -190), Vector2(75, -190), Color("#53463c"), 3)
	elif choice == 1:
		draw_circle(Vector2(0, -105), 74, body)
		draw_circle(Vector2(0, -218), 52, body)
		draw_line(Vector2(-38, -259), Vector2(-55, -302), Color("#686465"), 13)
		draw_line(Vector2(38, -259), Vector2(55, -302), Color("#686465"), 13)
		draw_circle(Vector2(30, -205), 27, Color("#eabcbc"))
		draw_circle(Vector2(17, -233), 5, Color.BLACK)
	elif choice == 2:
		draw_circle(Vector2(0, -100), 82, body)
		draw_circle(Vector2(-12, -218), 58, body)
		draw_line(Vector2(-42, -258), Vector2(-52, -324), body, 33)
		draw_line(Vector2(20, -267), Vector2(75, -326), body, 34)
		draw_circle(Vector2(38, -205), 25, Color("#884827"))
		draw_circle(Vector2(5, -238), 7, Color.BLACK)
		draw_circle(Vector2(0, -92), 61, Color("#f7e3a1"))
	else:
		draw_rect(Rect2(-55, -171, 110, 139), body)
		draw_circle(Vector2(0, -218), 51, Color("#f3c5b5"))
		draw_arc(Vector2(0, -226), 55, PI, TAU, 22, Color("#3c2826"), 27)
		draw_line(Vector2(-5, -167), Vector2(14, -85), Color("#ba3c39"), 23)
		draw_circle(Vector2(20, -229), 6, Color.BLACK)
	draw_rect(Rect2(-54, -33, 45, 29), Color("#3a342b"))
	draw_rect(Rect2(12, -33, 45, 29), Color("#3a342b"))


func _draw_projectile(p: Dictionary) -> void:
	var pos := Vector2(p["x"], p["y"])
	if p["kind"] == "wave":
		_draw_effect_texture("sound_wave", Rect2(pos.x - 58, pos.y - 63, 116, 126), 0.85)
	elif p["kind"] == "verbal":
		var direction: float = signf(p["vx"])
		_draw_directed_beam(Vector2(pos.x - direction * 92.0, pos.y), direction, 184.0, 84.0, 0.90)
	elif p["kind"] == "ground":
		var ground_color: Color = [Color("#fbe684"), Color("#dcae69"), Color("#f6b872"), Color("#9bdbff")][p.get("choice", 0)]
		for trail in 3:
			draw_circle(pos + Vector2(-signf(p["vx"]) * (trail * 26.0), -trail * 2.0), 25.0 - trail * 5.0, Color(ground_color.r, ground_color.g, ground_color.b, 0.72 - trail * 0.18))
	else:
		draw_circle(pos, 25, Color("#91d5ff"))


func _draw_effect(e: Dictionary) -> void:
	var pos := Vector2(e["x"], e["y"])
	var progress: float = 1.0 - float(e["life"]) / float(e["max_life"])
	var alpha: float = 1.0 - progress
	match e["kind"]:
		"dust":
			for puff in 3:
				var drift: float = (float(puff) - 1.0) * (24.0 + progress * 60.0)
				draw_circle(pos + Vector2(drift, -progress * 18.0), 13.0 + progress * 22.0, Color(0.96, 0.86, 0.68, alpha * 0.55))
		"wave":
			var radius := 20.0 + progress * 560.0
			_draw_effect_texture("sound_wave", Rect2(pos.x - radius, pos.y - radius * 0.68, radius * 2.0, radius * 1.36), alpha * 0.88)
		"thunder":
			_draw_effect_texture("thunder", Rect2(pos.x - 135.0, pos.y - 650.0, 270.0, 660.0), alpha)
			draw_line(pos + Vector2(-35, -700), pos + Vector2(10, -420), Color(0.85, 0.95, 1.0, alpha), 16.0)
			draw_line(pos + Vector2(10, -420), pos + Vector2(-20, -210), Color(0.85, 0.95, 1.0, alpha), 16.0)
			draw_line(pos + Vector2(-20, -210), pos, Color(0.85, 0.95, 1.0, alpha), 18.0)
		"beam":
			_draw_directed_beam(pos, float(e["facing"]), float(e["length"]), 120.0, alpha)
		"verbal":
			_draw_directed_beam(pos, float(e["facing"]), float(e["length"]) + progress * 65.0, 90.0, alpha)
		"dash":
			_draw_effect_texture("rush", Rect2(pos.x - 95, pos.y - 75, 190, 150), alpha * 0.7)
		"rush":
			_draw_effect_texture("rush", Rect2(pos.x - 120 - progress * 60, pos.y - 90, 240 + progress * 110, 180), alpha)
		"shock", "ground":
			_draw_effect_texture("impact", Rect2(pos.x - 95 - progress * 80, pos.y - 80, 190 + progress * 160, 150), alpha)
		"slam":
			_draw_effect_texture("impact", Rect2(pos.x - 120.0 - progress * 180.0, pos.y - 75.0 - progress * 60.0, 240.0 + progress * 360.0, 150.0 + progress * 120.0), alpha)
			for puff in 6:
				var drift: float = (float(puff) - 2.5) * (31.0 + progress * 48.0)
				draw_circle(pos + Vector2(drift, 42.0 - progress * 33.0), 14.0 + progress * 18.0, Color(0.84, 0.69, 0.47, alpha * 0.32))
		"pillar":
			_draw_effect_texture("thunder", Rect2(pos.x - 75, pos.y - 165, 150, 290), alpha * 0.75)
		"guard":
			_draw_effect_texture("impact", Rect2(pos.x - 45, pos.y - 45, 90, 90), alpha * 0.45)
		"hit":
			_draw_effect_texture("impact", Rect2(pos.x - 64 - progress * 40, pos.y - 64 - progress * 40, 128 + progress * 80, 128 + progress * 80), alpha)
			draw_circle(pos, 18.0 + progress * 52.0, Color(1.0, 0.91, 0.48, alpha * 0.45))
			for ray in 8:
				var angle: float = float(ray) * TAU / 8.0
				var origin := pos + Vector2.from_angle(angle) * (18.0 + progress * 18.0)
				var end := pos + Vector2.from_angle(angle) * (45.0 + progress * 58.0)
				draw_line(origin, end, Color(1.0, 1.0, 0.88, alpha), 5.0)
		_:
			_draw_effect_texture("impact", Rect2(pos.x - 55, pos.y - 55, 110, 110), alpha * 0.6)


func _draw_effect_texture(name: String, rect: Rect2, opacity: float) -> void:
	var tex: Texture2D = effect_textures.get(name, null)
	if tex != null:
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, opacity))


func _draw_directed_beam(origin: Vector2, facing: float, length: float, height: float, opacity: float) -> void:
	# The texture starts with a flare and ends at the tip. Anchor the flare to the fist.
	var camera_offset := Vector2(640.0 - camera_x, 0.0) + render_shake
	draw_set_transform(camera_offset + origin, 0.0, Vector2(facing, 1.0))
	_draw_effect_texture("beam", Rect2(0.0, -height * 0.5, length, height), opacity)
	draw_set_transform(camera_offset)


func _draw_hud() -> void:
	draw_rect(Rect2(0, 0, 1280, 122), Color(0.08, 0.09, 0.16, 0.85))
	for side in 2:
		var f: Dictionary = fighters[side]
		var choice: int = f["choice"]
		var left: float = 80.0 if side == 0 else 762.0
		_draw_panel(Rect2(left, 26, 445, 43), Color("#342f3a"))
		var hp_ratio: float = float(f["hp"]) / float(MAX_HP[choice])
		var bar_x: float = left + 4.0 + (1.0 - hp_ratio) * 437.0 if side == 1 else left + 4.0
		draw_rect(Rect2(bar_x, 30, hp_ratio * 437.0, 35), Color("#e95f58") if hp_ratio < 0.28 else COLORS[choice])
		_text("%s  %d/%d" % [NAMES[choice], f["hp"], MAX_HP[choice]], left + 7, 57, 23, Color.WHITE)
		for cell in 3:
			var energy_x: float = left + cell * 139.0
			draw_rect(Rect2(energy_x, 79, 128, 19), Color("#33394e"))
			var fill: float = clampf((float(f["energy"]) - cell * 100.0) / 100.0, 0.0, 1.0)
			draw_rect(Rect2(energy_x + 3, 82, fill * 122.0, 13), Color("#71ccef"))
		for win_dot in 2:
			draw_circle(Vector2(left + win_dot * 27 + 5, 112), 8, Color("#ffd64e") if wins[side] > win_dot else Color("#5d6272"))
	_center_text("%02d" % ceili(float(round_ticks) / 60.0), 640, 70, 51, Color.WHITE)
	if hit_counter >= 2 and combo_timer > 0:
		_center_text("%d HITS!" % hit_counter, 640, 173, 39, Color("#ffe384"))
	if game_mode == 2:
		_text("训练  F1 判定框  F3 无限能量: %s" % ("开" if training_energy else "关"), 22, 690, 20, Color.WHITE)
	else:
		_text("1P  A/D 移动  K 跳  S 防御  J 攻击  U 技能  I 大招", 22, 666, 18, Color.WHITE)
		_text("2P  ←/→ 移动  数字2 跳  ↓ 防御  数字1 攻击  4 技能  5 大招     Esc 暂停", 22, 693, 18, Color.WHITE)
	if fighters[0]["energy"] >= 300 or fighters[1]["energy"] >= 300:
		_center_text("大招就绪！", 640, 113, 18, Color("#ffe384"))


