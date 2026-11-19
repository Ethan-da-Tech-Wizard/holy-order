# ==============================================================================
# Program: menu.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for menu.gd.
# ==============================================================================
## Main menu: lets the player choose a mission, graphics quality or quit.
##
## Scene script of scenes/menu.tscn. The UI is built entirely in code. Launching a
## mission changes scene to one of the three mission scenes. Command-line user args can
## pre-select a mission, e.g. `-- --preferred-mission=ardennes`, which is how tests and
## launchers focus a button.
extends Control

# Quality presets and their names.
const Graphics=preload("res://scripts/graphics.gd")

# Mission id -> scene path. Add a new mission here and in the button list in _ready.
const MISSIONS={"ardennes":"res://scenes/ardennes.tscn","desert":"res://scenes/main.tscn","omaha":"res://scenes/omaha.tscn"}

# Guards against double-clicks while the scene change is pending.
var loading:bool=false

# Label under the buttons that shows loading/error messages.
var status:Label

# Mission id -> its Button, so they can be disabled together and focused.
var choices:Dictionary={}

## Build the whole menu UI and focus the preferred mission.
func _ready():
	# The menu runs at the same caps as the missions so the first scene switch has no hitch.
	Engine.max_fps=60
	Engine.physics_ticks_per_second=30
	# Missions capture the mouse; the menu needs it visible.
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_title("Holy Order — Winter · Desert · Omaha")
	# Solid dark background fills the window regardless of aspect ratio.
	var background=ColorRect.new()
	background.color=Color("111b20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	# 60 px margin on every side keeps the column away from the window edge.
	var margin=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,60)
	add_child(margin)
	# Centre the 660 px wide column in the window.
	var center=CenterContainer.new()
	margin.add_child(center)
	var column=VBoxContainer.new()
	column.custom_minimum_size.x=660
	column.add_theme_constant_override("separation",14)
	center.add_child(column)
	add_text(column,"HOLY ORDER",44,Color("e8d5ac"))
	add_text(column,"THREE FRONTS. ONE KNIGHT.",18,Color("a5b3b8"))
	add_text(column,"Choose your mission",24,Color("ecf0ed"))
	# Each entry: [mission id, title, subtitle].
	for entry in [["ardennes","WINTER  /  Road of Iron","Armored convoy through the Ardennes"],["desert","DESERT  /  First Contact","The original desert mission"],["omaha","OMAHA  /  The Longest Shore","600 Americans · two waves · 100 entrenched defenders"]]:
		var button=Button.new()
		button.text=entry[1]+"\n"+entry[2]
		button.custom_minimum_size.y=76
		button.add_theme_font_size_override("font_size",20)
		# bind() passes the mission id into launch() when the button is pressed.
		button.pressed.connect(launch.bind(entry[0]))
		column.add_child(button)
		choices[entry[0]]=button
	var options=HBoxContainer.new()
	options.add_theme_constant_override("separation",16)
	column.add_child(options)
	add_text(options,"Graphics",18,Color("d1d9d8"))
	var graphics=OptionButton.new()
	# Selecting a preset stores it on the tree; missions read it when they start (graphics.gd).
	for name in Graphics.NAMES:graphics.add_item(name)
	graphics.select(Graphics.quality(get_tree()))
	graphics.item_selected.connect(func(q):get_tree().set_meta("graphics_quality",q))
	options.add_child(graphics)
	var quit_button=Button.new()
	quit_button.text="QUIT"
	quit_button.custom_minimum_size=Vector2(110,36)
	quit_button.pressed.connect(func():get_tree().quit())
	options.add_child(quit_button)
	status=add_text(column,"Low graphics is recommended for the largest battles.\nEsc pauses a mission; Mission Menu returns here.",16,Color("9fadb0"))
	# Omaha is the default highlighted mission; an override comes from the command line.
	var preferred="omaha"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preferred-mission="):preferred=arg.get_slice("=",1)
	choices.get(preferred,choices.omaha).grab_focus()

## Create a styled label.
## @param parent Container to add it to.
## @param value Text.
## @param points Font size in points.
## @param color Font colour.
## @return The new Label.
func add_text(parent:Node,value:String,points:int,color:Color)->Label:
	var label=Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",points)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

## Start a mission.
## @param mission Key in MISSIONS; unknown keys and repeat calls are ignored.
func launch(mission:String):
	if loading or not MISSIONS.has(mission):return
	# Lock the menu so a second click cannot start another scene change.
	loading=true
	for button in choices.values():button.disabled=true
	# Two frames let the status text actually render before the long scene load blocks the main thread.
	status.text="Preparing the battlefield…"
	await get_tree().process_frame
	await get_tree().process_frame
	var error=get_tree().change_scene_to_file(MISSIONS[mission])
	# On failure re-enable the buttons and show Godot's error code.
	if error!=OK:
		loading=false
		status.text="Unable to open this mission (%d)."%error
		for button in choices.values():button.disabled=false
