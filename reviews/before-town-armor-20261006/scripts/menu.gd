extends Control
const Graphics=preload("res://scripts/graphics.gd")
const MISSIONS={"ardennes":"res://scenes/ardennes.tscn","desert":"res://scenes/main.tscn","omaha":"res://scenes/omaha.tscn"}
var loading:bool=false
var status:Label
var choices:Dictionary={}
func _ready():
	Engine.max_fps=60
	Engine.physics_ticks_per_second=30
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_title("Holy Order — Winter · Desert · Omaha")
	var background=ColorRect.new()
	background.color=Color("111b20")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,60)
	add_child(margin)
	var center=CenterContainer.new()
	margin.add_child(center)
	var column=VBoxContainer.new()
	column.custom_minimum_size.x=660
	column.add_theme_constant_override("separation",14)
	center.add_child(column)
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
	var options=HBoxContainer.new()
	options.add_theme_constant_override("separation",16)
	column.add_child(options)
	add_text(options,"Graphics",18,Color("d1d9d8"))
	var graphics=OptionButton.new()
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
	var preferred="omaha"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preferred-mission="):preferred=arg.get_slice("=",1)
	choices.get(preferred,choices.omaha).grab_focus()
func add_text(parent:Node,value:String,points:int,color:Color)->Label:
	var label=Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",points)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label
func launch(mission:String):
	if loading or not MISSIONS.has(mission):return
	loading=true
	for button in choices.values():button.disabled=true
	status.text="Preparing the battlefield…"
	await get_tree().process_frame
	await get_tree().process_frame
	var error=get_tree().change_scene_to_file(MISSIONS[mission])
	if error!=OK:
		loading=false
		status.text="Unable to open this mission (%d)."%error
		for button in choices.values():button.disabled=false
