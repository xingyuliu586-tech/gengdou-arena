extends Node2D

# Visual-only handoff point for the later Opus ultimate animation pass.
# Combat timing, hit tests and damage remain in main.gd::_tick_ultimate().
const FONT: FontFile = preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const NAMES := ["奶蛙", "牛来", "袋鼠", "豆包"]
const COLORS := [Color("#f8ca48"), Color("#dca629"), Color("#f6a41d"), Color("#4b719a")]
const TITLES := ["捧腹大笑·音波攻击", "妈妈！冲撞", "雷霆大坐", "最直白的一击"]
const LINES := ["哈哈哈哈！", "妈妈！", "你的胆子真是肥嘟嘟的！", "我将用最直白最不绕弯子的办法干掉你"]
const IDS := ["naiwa", "niulai", "daishu", "doubao"]


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var game: Variant = get_parent()
	if game.screen != "battle" or game.ultimate.is_empty():
		return
	var side: int = game.ultimate["side"]
	var choice: int = game.fighters[side]["choice"]
	var t: int = game.ultimate["t"]
	if t < 36:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.08, 0.79))
		draw_rect(Rect2(0, 211, 1280, 311), COLORS[choice].darkened(0.62))
		for streak in 5:
			var dx := float((t * 29 + streak * 320) % 1800) - 300.0
			draw_line(Vector2(dx, 520), Vector2(dx + 320, 210), Color(1, 1, 1, 0.08), 13.0)
		var poses: Dictionary = game.pose_textures.get(IDS[choice], {})
		var pose_name := "laugh" if choice == 0 else "ultimate"
		var portrait: Texture2D = poses.get(pose_name, null)
		if portrait != null:
			var h := 615.0
			var w := h * float(portrait.get_width()) / float(portrait.get_height())
			if w > 560.0:
				w = 560.0
				h = w * float(portrait.get_height()) / float(portrait.get_width())
			draw_texture_rect(portrait, Rect2(990.0 - w * 0.5, 675.0 - h, w, h), false, Color.WHITE)
		_center_text(NAMES[choice] + "  ·  " + TITLES[choice], 432, 324, 44, Color.WHITE)
		_center_text(LINES[choice], 432, 394, 24 if choice == 3 else 31, Color("#ffedaa"))
	else:
		if choice == 0:
			_center_text("捧腹大笑！" if t < 178 else "笑声过后！", 640, 215, 39, Color("#ffea91"))
		elif choice == 1 and t < 76:
			_center_text("妈妈——！", 640, 215, 53, Color("#ffea91"))
		elif choice == 2:
			_center_text("你的胆子真是肥嘟嘟的！", 640, 205, 38, Color("#ffea91"))
		elif choice == 3 and t < 112:
			_center_text(LINES[3], 640, 205, 36, Color("#cbe9ff"))


func _center_text(label: String, x: float, y: float, size: int, color: Color) -> void:
	var width: float = FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(FONT, Vector2(x - width * 0.5, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
