extends Control

var game
var serif = preload("res://assets/fonts/DejaVuSerif.ttf")
var sans = preload("res://assets/fonts/DejaVuSans.ttf")
var mono = preload("res://assets/fonts/DejaVuSansMono.ttf")
const cream = Color("e7deca")
const muted = Color("aaa998")
const gold = Color("cbb47e")
var panel: Control
var menu_phase: String = ""

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	theme.default_font = sans
	theme.default_font_size = 17
	self.theme = theme
	resized.connect(func(): if is_instance_valid(panel): build_menu())

func _process(_delta):
	if game.phase != menu_phase:
		menu_phase = game.phase
		build_menu()
	queue_redraw()

func label_at(text: String, pos: Vector2, font: Font, font_size: int, color: Color = cream):
	draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw():
	var w = size.x
	var h = size.y
	if game.phase == "cinematic":
		draw_rect(Rect2(0,0,w,h*0.10),Color("081012"))
		draw_rect(Rect2(0,h*0.84,w,h*0.16),Color("081012"))
		draw_subtitles(h*0.88)
		return
	if game.phase == "title":
		draw_rect(Rect2(0,0,w*0.51,h),Color(0.035,0.058,0.058,0.93))
		draw_rect(Rect2(w*0.51,0,w*0.04,h),Color(0.035,0.058,0.058,0.3))
		var x = w*0.052
		label_at("THE FIRST DISPLACEMENT",Vector2(x,h*0.12),mono,14,gold)
		label_at("HOLY",Vector2(x,h*0.245),serif,76)
		label_at("ORDER",Vector2(x,h*0.34),serif,76)
		draw_line(Vector2(x,h*0.38),Vector2(w*0.44,h*0.38),Color(gold,0.55),1)
		label_at("CAPUZZO FRONTIER  /  LIBYA",Vector2(x,h*0.43),mono,14,gold)
		label_at("14 JUNE 1940",Vector2(x,h*0.465),mono,13,muted)
		var lines = ["Your order called it the Ark of the Covenant.","It was a machine. When it opened, your brothers", "were scattered across centuries.","", "You arrived alone. Steel on your back.","A sword at your side. A foreign war ahead."]
		for i in range(lines.size()):
			label_at(lines[i],Vector2(x,h*0.53+i*24),sans,16,cream)
		label_at("ONE KNIGHT. ANOTHER CENTURY. NO WAY HOME.",Vector2(x,h*0.90),mono,12,gold)
		draw_rect(Rect2(w*0.59,h*0.825,w*0.39,h*0.125),Color(0.025,0.045,0.045,0.78))
		label_at("01  /  FIRST CONTACT",Vector2(w*0.62,h*0.875),mono,16,cream)
		label_at("A fictional outpost in the opening desert campaign.",Vector2(w*0.62,h*0.915),sans,12,cream)
		label_at("PLAYABLE PROTOTYPE  •  v"+str(ProjectSettings.get_setting("application/config/version","0.1")),Vector2(x,h-28),mono,11,muted)
		return
	if game.phase == "playing":
		# A subtle helmet rim, kept clear of the sights and battlefield.
		draw_rect(Rect2(0,0,w,12),Color(0.02,0.03,0.03,0.80))
		draw_rect(Rect2(0,h-12,w,12),Color(0.02,0.03,0.03,0.65))
		draw_rect(Rect2(25,31,346,72),Color(0.06,0.085,0.08,0.78))
		label_at("CAPUZZO  /  FORWARD POSITION",Vector2(42,57),mono,12,gold)
		label_at(game.objective_text(),Vector2(42,86),sans,16)
		draw_navigation()
		var center = size/2
		var spread = 4 if game.player.aiming else 7
		if game.player.weapon != 1 or not game.player.aiming:
			for v in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				draw_line(center+v*spread,center+v*(spread+5),Color(cream,0.8),1.3)
		if game.hit_flash > 0:
			for v in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
				draw_line(center+v*9,center+v*15,gold,2)
		draw_rect(Rect2(28,h-135,220,100),Color(0.05,0.075,0.07,0.8))
		label_at("VITALITY",Vector2(44,h-108),mono,11,muted)
		label_at(str(int(ceil(game.player.health))),Vector2(44,h-66),serif,33,cream)
		draw_rect(Rect2(111,h-84,118,7),Color("44453b"))
		draw_rect(Rect2(111,h-84,118*clampf(game.player.health/game.player.max_health,0,1),7),Color("b2b68d"))
		draw_rect(Rect2(44,h-51,185,3),Color("42483b"))
		draw_rect(Rect2(44,h-51,185*game.player.stamina/100,3),gold)
		var name = ["ARMING SWORD","CARCANO M91","STEEL GAUNTLETS","ENTRENCHING TOOL","DEMOLITION SATCHEL"][game.player.weapon]
		if game.player_mounted:name="BREDA M37  /  8 mm"
		draw_rect(Rect2(w-284,h-135,255,100),Color(0.05,0.075,0.07,0.8))
		label_at(name,Vector2(w-265,h-108),mono,13,gold)
		var count = "%02d  /  %02d" % [game.player.ammo,game.player.reserve] if game.player.weapon == 1 else ("EDGE" if game.player.weapon == 0 else "FISTS")
		if game.player.weapon==3:count="DIG / BREACH"
		if game.player.weapon==4:
			count="%d SATCHEL"%game.demolition.carried
			if is_instance_valid(game.demolition.active):count="B  DETONATE" if not game.demolition.cable_broken else "LINE BROKEN"
		if game.player.reload_time>0: count="RELOADING"
		if game.player_mounted:
			count="%02d / %d TRAYS"%[game.mg_nest.rounds,game.mg_nest.spare_trays]
			if game.mg_nest.reload_time>0:count="CHANGING TRAY"
		label_at(count,Vector2(w-265,h-69),serif,28)
		label_at("G  %d     TAB  INVENTORY" % game.player.grenades,Vector2(w-265,h-47),mono,11,muted)
		label_at("1 SWORD   2 RIFLE   3 FISTS   4 DIG   5 SATCHEL",Vector2(w/2-218,h-36),mono,12,Color(cream,0.75))
		if game.player.is_charging:
			label_at("CHARGE",Vector2(w/2-37,h*0.62),mono,14,gold)
		if game.player.holding_attack:
			draw_rect(Rect2(w/2-40,h/2+37,80,4),Color("434d43"))
			draw_rect(Rect2(w/2-40,h/2+37,80*game.player.power_hold/1.2,4),gold)
		var prompt = game.interaction_prompt()
		if prompt != "":
			var width = sans.get_string_size(prompt,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
			draw_rect(Rect2(w/2-width/2-18,h*0.67-27,width+36,41),Color(0.05,0.08,0.08,0.88))
			label_at(prompt,Vector2(w/2-width/2,h*0.67),sans,17,gold)
		if game.toast_time > 0:
			var width = sans.get_string_size(game.toast_text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
			draw_rect(Rect2(w/2-width/2-20,171,width+40,42),Color(0.055,0.075,0.07,0.9))
			label_at(game.toast_text,Vector2(w/2-width/2,198),sans,16,cream)
		if game.damage_flash > 0:
			var a = game.damage_flash*0.45
			draw_rect(Rect2(0,0,w,h),Color(0.6,0.07,0.025,a*0.26))
			draw_rect(Rect2(0,0,13,h),Color(0.55,0.08,0.04,a))
			draw_rect(Rect2(w-13,0,13,h),Color(0.55,0.08,0.04,a))
		draw_subtitles(h*0.76)
		return
	# Paused, inventory, success and death all stop simulation, not just input.
	draw_rect(Rect2(0,0,w,h),Color(0.025,0.045,0.045,0.91))
	var x = w*0.15
	var title = {"paused":"A moment of stillness", "inventory":"What you carry", "victory":"THE LINE IS SILENT", "defeat":"STEEL IS NOT ENOUGH","briefing":"A stranger in the desert","objectives":"Your path through the desert"}.get(game.phase,"")
	label_at("HOLY ORDER  /  FIRST CONTACT",Vector2(x,h*0.19),mono,13,gold)
	label_at(title,Vector2(x,h*0.30),serif,43)
	draw_line(Vector2(x,h*0.35),Vector2(w*0.85,h*0.35),Color(gold,0.5),1)
	if game.phase == "inventory":
		var rows = ["ARMING SWORD                 Equipped" if game.player.weapon==0 else "ARMING SWORD                 Sheathed", "CARCANO M91                  %d loaded / %d reserve" % [game.player.ammo,game.player.reserve] if game.player.has_rifle else "CARCANO M91                  Not acquired", "STEEL HARNESS                Worn", "BREDA M35 GRENADES           %d" % game.player.grenades,"POCKET LINT                  %d" % game.lint,
			"ENTRENCHING TOOL             %s"%("Carried [4]" if game.player.has_shovel else "Not acquired"),
			"DEMOLITION SATCHEL           %d carried / %d in cache"%[game.demolition.carried,game.demolition.stock]]
		for i in range(rows.size()):
			label_at(rows[i],Vector2(x,h*0.40+i*33),mono,17,cream)
		label_at("Lint stacks. It has no use. Yet.",Vector2(x,h*0.72),serif,21,gold)
	elif game.phase == "briefing":
		var lines=["You begin behind a large rock. An isolated sentry stands ahead.","WASD to move. Shift to sprint. C to crouch. Z to go prone.","With sword or fists: hold Shift + right click to charge.","Left click to strike. Hold left click, then release for a heavy blow.","After the sentry, choose how to approach the five-man outpost.","F to loot. R to reload. Q/E to lean. Space to jump or mantle.","Follow the gold marker. J opens objectives; Tab opens inventory."]
		for i in range(lines.size()): label_at(lines[i],Vector2(x,h*0.42+i*31),sans,18,cream)
	elif game.phase == "objectives":
		var stages=["sentry","outpost","patrol","complete"]
		var current=stages.find(game.quest)
		if game.quest=="rifle": current=0
		var steps=["Defeat the lone sentry and recover his rifle.","Choose your approach. Clear the five-man Italian position.","Meet the British patrol on the road. Climb aboard.","Survive a ceremonial cup of British tea."]
		for i in range(steps.size()):
			var mark="✓" if i<current else ("→" if i==current else "·")
			label_at(mark+"  "+steps[i],Vector2(x,h*0.43+i*48),sans,19,gold if i==current else cream)
		label_at("Optional: loot ammunition, an entrenching tool, grenades and demolition supplies.",Vector2(x,h*0.70),sans,15,muted)
	elif game.phase == "paused":
		var lines = ["WASD Move   MOUSE Look   SHIFT Sprint   C Crouch   Z Prone", "LMB Attack / hold for power   RMB Aim / sprinting melee charge", "Q / E Lean   SPACE Jump / mantle   R Reload", "1 / 2 / 3 Sword / rifle / fists   4 Dig   5 Satchel", "F Doors / loot / mounted gun   G Grenade   B Detonate", "Satchel: LMB Place / RMB Lob   TAB Inventory   J Objectives", "F11 Fullscreen   ESC Pause / resume"]
		for i in range(lines.size()): label_at(lines[i],Vector2(x,h*0.42+i*32),mono,16,cream)
	elif game.phase == "victory":
		label_at("The position is cleared. Your first test ends here.",Vector2(x,h*0.44),sans,22,cream)
		label_at("Somewhere beyond the desert, another century is waiting.",Vector2(x,h*0.50),serif,21,gold)
		label_at("TIME  %02d:%02d     SHOTS  %d     LINT  %d" % [int(game.elapsed)/60,int(game.elapsed)%60,game.player.shot_count,game.lint],Vector2(x,h*0.62),mono,17,muted)
	elif game.phase == "defeat":
		label_at("Your armour was made for another war.",Vector2(x,h*0.45),serif,25,cream)
		label_at("Use cover, loot ammunition, and choose your moment to charge.",Vector2(x,h*0.53),sans,18,muted)

func draw_navigation():
	var center=Vector2(size.x/2,78)
	var radius=51.0
	draw_circle(center,radius,Color(0.035,0.065,0.06,0.89))
	draw_arc(center,radius,0,TAU,64,Color(gold,0.6),1)
	draw_line(center-Vector2(radius,0),center+Vector2(radius,0),Color(gold,0.16),1)
	draw_line(center-Vector2(0,radius),center+Vector2(0,radius),Color(gold,0.16),1)
	label_at("N",center+Vector2(-4,-55),mono,10,gold)
	var target=game.objective_target()
	var delta=Vector2(target.x-game.player.position.x,target.z-game.player.position.z)*0.62
	if delta.length()>radius-7: delta=delta.normalized()*(radius-7)
	draw_circle(center+delta,4,gold)
	var facing=Vector2(-sin(game.player.rotation.y),-cos(game.player.rotation.y))
	draw_colored_polygon(PackedVector2Array([center+facing*9,center+facing.rotated(2.5)*5,center+facing.rotated(-2.5)*5]),cream)
	for enemy in game.enemies:
		if not enemy.alive or enemy.position.distance_to(game.player.position)>24 or not game.player_can_see(enemy): continue
		var p=Vector2(enemy.position.x-game.player.position.x,enemy.position.z-game.player.position.z)*0.62
		draw_circle(center+p,2.5,Color("b8755c"))
	label_at("J  OBJECTIVES",center+Vector2(-52,72),mono,10,muted)
	var cam=game.player.camera
	if cam.is_position_behind(target): return
	var p=cam.unproject_position(target)
	p.x=clampf(p.x,38,size.x-38)
	p.y=clampf(p.y,230,size.y-190)
	var offset=5+sin(game.visual_elapsed*3)*1.5
	draw_polyline(PackedVector2Array([p+Vector2(0,-offset),p+Vector2(offset,0),p+Vector2(0,offset),p+Vector2(-offset,0),p+Vector2(0,-offset)]),gold,2)
	label_at("%dm" % int(game.player.position.distance_to(target)),p+Vector2(-13,25),mono,11,cream)

func draw_subtitles(y: float):
	if game.subtitle_time <= 0 or game.subtitle == "": return
	var lines: Array[String] = []
	var line = ""
	for word in game.subtitle.split(" "):
		if sans.get_string_size(line+" "+word,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x > size.x*0.75:
			lines.append(line)
			line = word
		else:
			line += (" " if line != "" else "")+word
	lines.append(line)
	var width = 0.0
	for text in lines: width = maxf(width,sans.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x)
	draw_rect(Rect2(size.x/2-width/2-22,y-24,width+44,lines.size()*26+39),Color(0.025,0.045,0.045,0.91))
	label_at(game.speaker,Vector2(size.x/2-width/2,y-5),mono,10,gold)
	for i in range(lines.size()):
		label_at(lines[i],Vector2(size.x/2-width/2,y+21+i*26),sans,18,cream)

func button(text: String, rect: Rect2, callback: Callable, primary: bool = false):
	var b = Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color("c7b182") if primary else Color("263836")
	normal.border_color = Color("897d60")
	normal.set_border_width_all(1)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	b.add_theme_stylebox_override("normal",normal)
	var hover = normal.duplicate()
	hover.bg_color = normal.bg_color.lightened(0.17)
	b.add_theme_stylebox_override("hover",hover)
	b.add_theme_stylebox_override("focus",hover)
	b.add_theme_color_override("font_color",Color("172525") if primary else cream)
	b.add_theme_color_override("font_hover_color",Color("172525") if primary else cream)
	b.pressed.connect(callback)
	panel.add_child(b)

func build_menu():
	if is_instance_valid(panel):
		remove_child(panel)
		panel.queue_free()
	panel = Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var w = size.x
	var h = size.y
	match game.phase:
		"title":
			button("BEGIN  →",Rect2(w*0.052,h*0.745,218,52),game.begin,true)
			button("QUIT",Rect2(w*0.052+232,h*0.745,110,52),game.quit_game)
			button("MISSION MENU",Rect2(w*0.052,h*0.812,342,36),func():preload("res://scripts/graphics.gd").menu(game))
		"paused", "inventory", "objectives":
			button("RETURN",Rect2(w*0.15,h*0.79,200,50),game.resume_game,true)
			button("MISSION MENU",Rect2(w*0.15+220,h*0.79,205,50),func():preload("res://scripts/graphics.gd").menu(game))
			button("QUIT",Rect2(w*0.15+445,h*0.79,120,50),game.quit_game)
		"briefing":
			button("READY  →",Rect2(w*0.15,h*0.79,210,52),game.resume_game,true)
		"victory", "defeat":
			button("PLAY AGAIN",Rect2(w*0.15,h*0.76,215,52),game.restart_game,true)
			button("MISSION MENU",Rect2(w*0.15+235,h*0.76,210,52),func():preload("res://scripts/graphics.gd").menu(game))
			button("QUIT",Rect2(w*0.15+465,h*0.76,120,52),game.quit_game)
