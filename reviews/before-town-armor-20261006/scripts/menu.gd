## Archived review snapshot (before-town-armor-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/menu.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Main menu for Holy Order: the first scene the player sees, and the scene
## every mission's "Mission Menu" button returns to.
##
## Role in the app: lets the player pick one of three campaigns and a graphics
## quality, then hands off to that mission's scene via change_scene_to_file.
##   desert   -> scenes/main.tscn     (scripts/game.gd and the village/enemy scripts)
##   ardennes -> scenes/ardennes.tscn (scripts/ardennes/*)
##   omaha    -> scenes/omaha.tscn    (scripts/omaha/*)
## Uses graphics.gd for the quality names; the chosen level is stored as tree
## meta ("graphics_quality") so the mission scenes can read it after the switch.
##
## Command line: `-- --preferred-mission=<key>` pre-focuses that button (the
## test and review harnesses use this); the default focus is omaha.
## Limits: the UI is built entirely in code, so there is no .tscn layout to edit.
## Run: open the project in Godot 4 and press Play.
extends Control
const Graphics=preload("res://scripts/graphics.gd")

## Mission key -> scene path. The keys double as the button ids in `choices`
## and as the values accepted by --preferred-mission.
const MISSIONS={"ardennes":"res://scenes/ardennes.tscn","desert":"res://scenes/main.tscn","omaha":"res://scenes/omaha.tscn"}

## Guards against double-clicks: once a launch begins every mission button is
## disabled and further launch() calls return immediately.
var loading:bool=false

## Label under the buttons; shows hints, then "Preparing..." or an error.
var status:Label

## Mission key -> its Button, so launch() can disable them all and the
## command-line preference can grab focus on one of them.
var choices:Dictionary={}

## Godot lifecycle hook: builds the whole menu in code and applies engine-wide
## frame settings. Called once by the engine when the scene enters the tree.
func _ready():
	# Engine-wide pacing set here because the menu is always the first scene:
	# 60 render fps with a 30 Hz physics tick keeps the large Omaha battle
	# (hundreds of actors) affordable on laptops; missions inherit these values.
	Engine.max_fps=60
	Engine.physics_ticks_per_second=30
	# Mission scenes capture or hide the mouse, so make it usable again
	# whenever the player returns to the menu.
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	# Title names all three fronts; shown in the OS window bar and task switcher.
	DisplayServer.window_set_title("Holy Order — Winter · Desert · Omaha")
	# Dark slate backdrop drawn first so it sits behind every other control.
	var background=ColorRect.new()
	background.color=Color("111b20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	# 60 px of padding on every side keeps the column off the screen edge at any
	# window size; the loop avoids four near-identical override calls.
	var margin=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,60)
	add_child(margin)
	# Margin -> Center -> VBox centres the column both ways; the fixed 660 px
	# minimum width stops the long mission titles from wrapping.
	var center=CenterContainer.new()
	margin.add_child(center)
	var column=VBoxContainer.new()
	column.custom_minimum_size.x=660
	column.add_theme_constant_override("separation",14)
	center.add_child(column)
	# Title block: parchment gold for the game name, muted grey-blue for the
	# tagline, so the mission buttons are the brightest items on screen.
	add_text(column,"HOLY ORDER",44,Color("e8d5ac"))
	add_text(column,"THREE FRONTS. ONE KNIGHT.",18,Color("a5b3b8"))
	add_text(column,"Choose your mission",24,Color("ecf0ed"))
	for entry in [["ardennes","WINTER  /  Road of Iron","Armored convoy through the Ardennes"],["desert","DESERT  /  First Contact","The original desert mission"],["omaha","OMAHA  /  The Longest Shore","1,200 Americans · two waves · 100 entrenched defenders"]]:
		var button=Button.new()
		button.text=entry[1]+"\n"+entry[2]
		button.custom_minimum_size.y=76
		button.add_theme_font_size_override("font_size",20)
		button.pressed.connect(launch.bind(entry[0]))
		column.add_child(button)
		choices[entry[0]]=button
	# Bottom row: graphics quality dropdown plus Quit.
	var options=HBoxContainer.new()
	options.add_theme_constant_override("separation",16)
	column.add_child(options)
	add_text(options,"Graphics",18,Color("d1d9d8"))
	var graphics=OptionButton.new()
	for name in Graphics.NAMES:graphics.add_item(name)
	# Preselect the current level (kept on the SceneTree so it survives scene
	# changes) and write any change back as tree meta for the missions to read.
	graphics.select(Graphics.quality(get_tree()))
	graphics.item_selected.connect(func(q):get_tree().set_meta("graphics_quality",q))
	options.add_child(graphics)
	# No confirmation on Quit: the menu holds no unsaved state.
	var quit_button=Button.new()
	quit_button.text="QUIT"
	quit_button.custom_minimum_size=Vector2(110,36)
	quit_button.pressed.connect(func():get_tree().quit())
	options.add_child(quit_button)
	# Hint text lives in `status` so launch() can later reuse the same label.
	status=add_text(column,"Low graphics is recommended for the largest battles.\nEsc pauses a mission; Mission Menu returns here.",16,Color("9fadb0"))
	# Default focus is the Omaha button for keyboard/gamepad users; an automated
	# run can override it with --preferred-mission=<key>. Unknown keys fall back
	# to omaha through choices.get().
	var preferred="omaha"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preferred-mission="):preferred=arg.get_slice("=",1)
	choices.get(preferred,choices.omaha).grab_focus()

## Creates a Label, applies size and colour, adds it to `parent` and returns it.
## [param parent] container that receives the label.
## [param value] text to show.
## [param points] font size in points.
## [param color] font colour.
## Returns the new Label (the caller only keeps the one used as status line).
func add_text(parent:Node,value:String,points:int,color:Color)->Label:
	var label=Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",points)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

## Starts the chosen mission. Bound to each mission button, so `mission` is one
## of the MISSIONS keys. Awaits two frames before the blocking scene load so
## the "Preparing" text and disabled buttons are actually drawn first; on
## failure it re-enables the menu and shows the Godot error code.
## [param mission] key into MISSIONS; unknown keys are ignored.
func launch(mission:String):
	# Ignore re-entrant presses and bad keys: a double-click would otherwise
	# queue two scene changes.
	if loading or not MISSIONS.has(mission):return
	loading=true
	for button in choices.values():button.disabled=true
	status.text="Preparing the battlefield…"
	# Two frames: the first applies the disabled/status changes, the second lets
	# the renderer present them before change_scene_to_file stalls the main thread.
	await get_tree().process_frame
	await get_tree().process_frame
	var error=get_tree().change_scene_to_file(MISSIONS[mission])
	# Load failed (missing or broken scene): restore the menu so the player can
	# retry or pick another mission.
	if error!=OK:
		loading=false
		status.text="Unable to open this mission (%d)."%error
		for button in choices.values():button.disabled=false
