# ==============================================================================
# Program: interface.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for interface.gd.
# ==============================================================================
## Heads-up display and menu overlay for the Omaha mission.
##
## A full-screen Control placed over the 3D view; same structure as the Ardennes overlay
## (hand-drawn title/HUD/menu panels in `_draw()`, real Buttons from `menu()`) with Omaha's own
## text, a simpler objective compass (inland direction plus the wave-two countdown) and a
## 'wire gaps' counter. Created and given `game` by the Omaha battle script.
extends Control

# The mission controller (phase, player, score counters, toast and subtitle text, objective helpers).
var game

# Container for the current phase's buttons; replaced by menu().
var panel:Control

# Phase for which the buttons were last built; set to "" to force a rebuild.
var last_phase:String=""

# Fonts: serif for headings, sans for body text, monospace for small-caps style labels.
var serif=preload("res://assets/fonts/DejaVuSerif.ttf")
var sans=preload("res://assets/fonts/DejaVuSans.ttf")
var mono=preload("res://assets/fonts/DejaVuSansMono.ttf")

# Palette: INK is the translucent panel colour, WHITE main text, GOLD accents, BLUE secondary text.
const INK=Color("10191f")
const WHITE=Color("e5e5d9")
const GOLD=Color("c8ae76")
const BLUE=Color("a7c5d1")

## Fill the screen, pass mouse clicks through and set the default font theme.
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Only the Button children accept the mouse; the overlay itself must not block the game.
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var theme=Theme.new()
	theme.default_font=sans
	theme.default_font_size=17
	self.theme=theme
	# A resize invalidates button positions, so clear last_phase to rebuild them in _process.
	resized.connect(func():last_phase="")

## Rebuild buttons when the game phase changes and redraw every frame.
func _process(_delta):
	if last_phase!=game.phase:
		last_phase=game.phase
		menu()
	queue_redraw()

## Draw a string with its baseline at `pos`.
## @param value Text. @param pos Baseline position in pixels. @param font Font (sans by default). @param points Size in points. @param color Colour (WHITE by default).
func text(value:String,pos:Vector2,font:Font=sans,points:int=17,color:Color=WHITE):
	draw_string(font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,points,color)

## Draw the title screen, the in-game HUD, or a full-screen menu panel depending on the phase.
func _draw():
	# All positions are fractions of the window size so the layout scales.
	var w=size.x
	var h=size.y
	# Title: dark panel on the left half with a soft fade strip, headline, tagline and mission card on the right.
	if game.phase=="title":
		draw_rect(Rect2(0,0,w*0.50,h),Color(0.035,0.060,0.076,0.95))
		draw_rect(Rect2(w*0.50,0,w*0.04,h),Color(0.035,0.060,0.076,0.25))
		var x=w*0.052
		text("THE THIRD DISPLACEMENT",Vector2(x,h*0.11),mono,14,GOLD)
		text("HOLY",Vector2(x,h*0.23),serif,70)
		text("ORDER",Vector2(x,h*0.32),serif,70)
		draw_line(Vector2(x,h*0.36),Vector2(w*0.445,h*0.36),Color(GOLD,0.55))
		text("03 / THE LONGEST SHORE",Vector2(x,h*0.415),mono,20,GOLD)
		text("OMAHA  •  6 JUNE 1944",Vector2(x,h*0.455),mono,13,BLUE)
		var lines=["The ramp is the only way forward.","Two waves. Six hundred men. One long shore.","Keep low. Follow the engineers to the wire.","Take the bluff exits. Fight into the village."]
		for i in range(lines.size()):text(lines[i],Vector2(x,h*0.53+i*25),sans,16)
		text("A GARAND. A SWORD. THE LONGEST SHORE.",Vector2(x,h*0.88),mono,11,GOLD)
		text("AN AUTHORED OMAHA BEACH SECTOR",Vector2(x,h-27),mono,11,BLUE)
		draw_rect(Rect2(w*0.60,h*0.79,w*0.38,h*0.15),Color(INK,0.86))
		text("20 HIGGINS CRAFT / 32 DEFENSIVE MGs",Vector2(w*0.625,h*0.832),mono,15,GOLD)
		text("600 Americans including you / 100 Germans",Vector2(w*0.625,h*0.878),sans,14)
		text("Wave two lands four minutes after wave one.",Vector2(w*0.625,h*0.913),sans,12,BLUE)
		return
	# Playing: thin bars at the top and bottom, the objective panel, compass and counters.
	if game.phase=="playing":
		draw_rect(Rect2(0,0,w,10),Color(INK,0.9))
		draw_rect(Rect2(0,h-10,w,10),Color(INK,0.9))
		draw_rect(Rect2(25,29,390,75),Color(INK,0.82))
		text("OMAHA / THE LONGEST SHORE",Vector2(42,55),mono,12,GOLD)
		text(game.objective_text(),Vector2(42,84),sans,15)
		navigation()
		text("ALLIES %03d / ENEMY %02d"%[game.allies_alive+1,game.germans_alive],Vector2(w-306,52),mono,15,BLUE)
		text("WIRE GAPS %d • F6 GRAPHICS"%game.breaches+"",Vector2(w-306,76),mono,11,GOLD)
		# Crosshair ticks, hidden while seated in a truck or aiming down the sights (weapon 1 is the gun).
		var center=size/2
		if game.player.truck==null and (game.player.weapon!=1 or not game.player.aiming):
			for d in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:draw_line(center+d*5,center+d*10,Color(WHITE,0.8),1)
		# Hit marker: gold ticks when a shot connects.
		if game.hit_flash>0:
			for d in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:draw_line(center+d*9,center+d*14,GOLD,2)
		# Full-screen red tint scaled by the damage flash (fades with time).
		if game.damage_flash>0:draw_rect(Rect2(Vector2.ZERO,size),Color(0.55,0.05,0.02,game.damage_flash*0.18))
		# Bottom-left: health number and bars (health, stamina).
		draw_rect(Rect2(26,h-128,222,94),Color(INK,0.85))
		text("VITALITY / STAMINA",Vector2(42,h-103),mono,11,BLUE)
		text(str(ceili(game.player.health)),Vector2(42,h-61),serif,34)
		draw_rect(Rect2(112,h-79,115,6),Color("3b4b51"))
		draw_rect(Rect2(112,h-79,115*clampf(game.player.health/game.player.max_health,0,1),6),BLUE)
		draw_rect(Rect2(42,h-49,183*game.player.stamina/100,3),GOLD)
		# Bottom-right: weapon name, ammo state (loaded / reserve), grenades and key hints.
		draw_rect(Rect2(w-300,h-128,275,94),Color(INK,0.85))
		# Weapon name falls back to "M1918A2 BAR" if the player has no gun spec.
		var gun_name=game.player.gun_spec.name if game.player.get("gun_spec")!=null else "M1918A2 BAR"
		text(["ARMING SWORD",gun_name,"STEEL GAUNTLETS","ENTRENCHING TOOL"][mini(game.player.weapon,3)],Vector2(w-281,h-103),mono,12,GOLD)
		# Ammo text priority: broken, reloading, throwing, weapons safe (seated), else the normal count.
		var count="%02d / %03d"%[game.player.ammo,game.player.reserve] if game.player.weapon==1 else ("DIG / BREACH" if game.player.weapon==3 else "HOLD LMB / POWER")
		if game.player.weapon==1 and game.player.rifle_health<=0:count="BROKEN"
		if game.player.reload_time>0:count="RELOADING"
		if game.player.grenade_time>0:count="THROWING"
		if game.player.truck!=null:count="WEAPONS SAFE"
		text(count,Vector2(w-281,h-65),serif,26)
		text("G %d GRENADES • F INTERACT"%game.player.grenades,Vector2(w-281,h-45),mono,11,BLUE)
		text("1 SWORD  2 GUN  3 FISTS  4 SHOVEL • TAB KIT • J ORDERS",Vector2(w*0.5-232,h-28),mono,11,Color(WHITE,0.7))
		# Toast message box near the top, sized to the text.
		if game.toast_time>0:
			var tw=sans.get_string_size(game.toast_text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
			draw_rect(Rect2(w*0.5-tw/2-18,h*0.19-23,tw+36,36),Color(INK,0.84))
			text(game.toast_text,Vector2(w*0.5-tw/2,h*0.19),sans,14)
		# Subtitle box with speaker, at 78 % of the height.
		if game.subtitle_time>0:
			var sw=minf(w*0.82,1150)
			draw_rect(Rect2(w/2-sw/2,h*0.78,sw,66),Color(INK,0.91))
			text(game.speaker,Vector2(w/2-sw/2+19,h*0.78+23),mono,12,GOLD)
			text(game.subtitle,Vector2(w/2-sw/2+19,h*0.78+49),sans,16)
		return
	# Any other phase (paused, inventory, objectives, victory, defeat): dark full-screen panel with a title and text lines.
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.025,0.040,0.050,0.88))
	var x=w*0.17
	var title={"paused":"HOLD POSITION","inventory":"FIELD KIT","objectives":"ORDERS","defeat":"THE SHORE CLAIMED YOU","victory":"BEACHHEAD SECURED"}.get(game.phase,"HOLY ORDER")
	text(title,Vector2(x,h*0.22),serif,39)
	draw_line(Vector2(x,h*0.255),Vector2(w*0.84,h*0.255),GOLD)
	# Lines depend on the phase; the default (pause) shows the controls.
	var lines=[]
	match game.phase:
		"inventory":lines=["One carried firearm: %s"%game.player.gun_spec.name,"Loaded %d / %d • Spare %d • Grenades %d / 4"%[game.player.ammo,game.player.gun_spec.capacity,game.player.reserve,game.player.grenades],"Weapon condition: %d%%. A broken gun stays broken."%game.player.rifle_health,"F picks up a dropped gun you are looking at, swapping your current gun.","F searches bodies for their actual remaining ammunition and grenades.","Ammunition must match the firearm. Mounted Brownings stay on their boats."]
		"objectives":lines=["1. Ride in the first wave. Follow the file down the ramp.","2. Find prone cover. Engineers carry scarce Bangalore charges.","3. Cross three wire lines through local gaps. Cover the engineers.","4. Enter bunkers from the rear. Secure three exits and the village.","C toggles crouch; Z toggles prone. G starts a timed grenade throw.","Shovel: hold LMB to dig deeper; add RMB for a wider, shallower cut."]
		"defeat":lines=["The ramp, wire and bluff are all live combat.","%d allied soldiers and %d Germans were still alive."%[game.allies_alive,game.germans_alive],"Use prone cover, cross at a breach, and reach the bunker rear doors."]
		"victory":lines=["The beachhead is open. Your order remains several centuries late.","Allied survivors: %d of 599, plus you."%game.allies_alive,"Rounds fired: %d. Grenades detonated: %d."%[game.ammo_spent,game.grenade_detonations],"The village and at least three strongpoints are secured."]
		_:lines=["WASD move • Mouse aim • LMB attack • RMB sights","Shift sprint • C toggle crouch • Z toggle prone • Q/E lean • Space jump / mantle","R reload • G grenade • F dismount / pick up / loot • 1–4 equipment","J orders • Tab kit • F11 fullscreen • F6 graphics preset"]
	# Inventory shows the gun status plus the ammo pack contents.
	if game.phase=="inventory":
		lines=lines.slice(0,2)
		lines.append("Spare ammo pack: %.1f / 24 space • %.2f / 7.5 kg"%[game.player.ammo_pack.space_used(),game.player.ammo_pack.weight_used()])
		lines.append_array(game.player.ammo_pack.description())
		lines.append("Partial magazines still occupy their full space. Excess loot stays on the body.")
	# 30 px between text lines.
	for i in range(lines.size()):text(lines[i],Vector2(x,h*0.33+i*30),sans,15)

## Draw the inland objective marker and the wave-two countdown.
func navigation():
	var center=Vector2(size.x/2,66)
	draw_rect(Rect2(center-Vector2(144,37),Vector2(288,87)),Color(INK,0.84))
	# Bearing to the objective relative to the player's facing, clamped to +/-1.1 rad so the marker stays in the box.
	var to=game.objective_target()-game.player.position
	var angle=wrapf(atan2(-to.x,-to.z)-game.player.rotation.y,-PI,PI)
	var p=center+Vector2(clampf(angle,-1.1,1.1)*110,0)
	draw_circle(p,4,GOLD)
	text("INLAND  /  %dm"%int(Vector2(to.x,to.z).length()),center+Vector2(-82,-13),mono,12,BLUE)
	# Seconds until the second wave lands, shown as mm:ss, or "WAVE 2 ASHORE" afterwards.
	var seconds=maxi(0,ceili(game.second_wave_at-game.elapsed))
	var line="WAVE 2 ASHORE" if game.second_wave_landed else "WAVE 2  %02d:%02d"%[seconds/60,seconds%60]
	text(line,center+Vector2(-75,34),mono,12,GOLD)

## Rebuild the phase's buttons (replaces the old panel).
func menu():
	# Free the old panel before creating the new one.
	if is_instance_valid(panel):panel.queue_free()
	panel=Control.new()
	add_child(panel)
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# No buttons during play.
	if game.phase=="playing":return
	var x=size.x*0.052 if game.phase=="title" else size.x*0.17
	var y=size.y*0.73
	# Title: deploy, plus a shortcut to the winter mission scene.
	if game.phase=="title":
		button("DEPLOY / ENTER",Vector2(x,y),Vector2(245,44),game.begin)
	# Victory or defeat offers another landing.
	elif game.phase in ["victory","defeat"]:button("LAND AGAIN",Vector2(x,y),Vector2(268,46),game.retry)
	else:button("RETURN TO BATTLE",Vector2(x,y),Vector2(268,46),game.resume_game)
	# The inventory screen also offers dropping the spare ammo pack.
	if game.phase=="inventory":button("DROP SPARE AMMO PACK",Vector2(x,y+52),Vector2(268,38),game.drop_pack)
	button("MISSION MENU",Vector2(x+280,y+51),Vector2(210,38),func():preload("res://scripts/graphics.gd").menu(game))
	button("QUIT",Vector2(x+280,y),Vector2(95,44),func():get_tree().quit())

## Add a styled Button to the current panel.
## @param caption Label. @param pos Position in pixels. @param dimensions Size in pixels. @param callback Called on press.
func button(caption:String,pos:Vector2,dimensions:Vector2,callback:Callable):
	var b=Button.new()
	b.text=caption
	b.position=pos
	b.size=dimensions
	var normal=StyleBoxFlat.new()
	normal.bg_color=Color("25373f")
	normal.border_color=Color(GOLD,0.6)
	normal.set_border_width_all(1)
	b.add_theme_stylebox_override("normal",normal)
	# Hover state is a lighter background.
	var hover=normal.duplicate()
	hover.bg_color=Color("3d5159")
	b.add_theme_stylebox_override("hover",hover)
	b.pressed.connect(callback)
	panel.add_child(b)
