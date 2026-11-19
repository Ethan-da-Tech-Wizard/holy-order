## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/ardennes/battle.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Battle controller for the Ardennes mission ("Road of Iron", scenes/ardennes.tscn).
##
## Story and flow: the player rides in a nine-truck US convoy that is
## ambushed on a snowy road. Two Panzerfaust strikes hit the lead and rear
## trucks, everyone dismounts, and the player's two sections (left/right) clear
## eight German gun positions on the ridges (80 Germans, 107 allies besides the
## player). Win by killing every German; lose if the player dies.
##
## Role: the root node; it creates the world, player, trucks, soldiers, HUD and
## sound, and provides every shared service actors call: target acquisition and
## friendly-fire-safe firing lines, bullets, grenades, rockets and explosions,
## noise, squad contact reports, spatial hashing, loot and weapon swapping, and
## the scripted ambush. Phases (`phase`): title, playing, paused/inventory/
## objectives, victory, defeat.
## Performance design (this scene has ~190 soldiers):
##   - AI "thinking" is not done every frame: think_budget() gives a credit that
##     lets at most 12 actors think per rendered frame, round-robin;
##   - neighbours are found with a 5 m grid (`spatial`) rebuilt 4 times a second;
##   - squads are updated once a second; many effects are capped at 64.
## Test hooks: `--battle-test` or tree meta "battle_test" enables test_mode
## (no auto pause); tree meta "battle_seed" fixes the random seed;
## `--battle-preview` skips the title; env HOLY_ORDER_PROFILE prints slow ticks.
## Collaborators: world.gd, player.gd, actor.gd, truck.gd, tactics.gd,
## weapons.gd, corpse.gd, dropped_weapon.gd, ammo_bundle.gd, interface.gd, audio.gd.
extends Node3D

const World=preload("res://scripts/ardennes/world.gd")
const Player=preload("res://scripts/ardennes/player.gd")
const Actor=preload("res://scripts/ardennes/actor.gd")
const Truck=preload("res://scripts/ardennes/truck.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")
const Art=preload("res://scripts/art.gd")
const Sounds=preload("res://scripts/ardennes/audio.gd")
const AmmoBundle=preload("res://scripts/ardennes/ammo_bundle.gd")
const Drop=preload("res://scripts/ardennes/dropped_weapon.gd")
const Corpse=preload("res://scripts/ardennes/corpse.gd")
const Tactics=preload("res://scripts/ardennes/tactics.gd")

## Squad commander AI (tactics.gd) for the dismounted phase.
var tactics=Tactics.new()

## Count of shots held back because an ally was in the line of fire (statistic).
var fire_checks_blocked:int=0
const HUD=preload("res://scripts/ardennes/interface.gd")

## The Ardennes world (terrain, road, hills, nests).
var world

## The player node.
var player

## The HUD/menu layer.
var hud

## The pooled audio service.
var sounds

## True while the player is on a mounted gun (not used in this mission; leave_mg is a no-op).
var player_mounted:bool=false

## Not used in this mission; present so shared UI code can test for it.
var demolition=null

## German soldiers (team 0).
var enemies:Array=[]

## American soldiers (team 1), not including the player.
var friendlies:Array=[]

## friendlies + enemies, used for thinking and noise.
var actors:Array=[]

## Squad dictionaries (team, order, temperament, anchor, objective, leader, members, contact, contact_age); ids 0-8 are the nine truck squads, 9+ the German positions.
var squads:Array=[]

## The nine CCKW trucks.
var trucks:Array=[]

## Dead actors in the order they died (looted by interact()).
var corpses:Array=[]

## Grenades in flight.
var grenades_live:Array=[]

## Panzerfaust rounds in flight.
var rockets:Array=[]

## Short-lived visual nodes {node, time}; freed when time runs out (cap 64).
var effects:Array=[]

## Per-truck engine-loop audio players.
var engines:Array=[]

## Current phase string (see class comment).
var phase:String="title"

## Seconds of play.
var elapsed:float=0

## Seconds including paused time, for UI animation.
var visual_elapsed:float=0

## True once every truck has been destroyed or unloaded.
var column_stopped:bool=false

## The scripted rocket at the lead truck has been fired.
var lead_strike:bool=false

## The scripted rocket at the rear truck has been fired.
var rear_strike:bool=false

## That rocket arrived (statistic for tests).
var lead_hit:bool=false

## The rear rocket arrived.
var rear_hit:bool=false

## Time (elapsed) when the rear strike is scheduled; -1 if none.
var rear_at:float=-1

## Time (elapsed) when the surviving trucks unload.
var dismount_at:float=-1

## True once the troops are on foot and tactics take over.
var dismounted:bool=false

## Round-robin index into `actors` for think_budget().
var think_cursor:int=0

## Countdown to the next spatial grid rebuild (0.25 s).
var sense_timer:float=0

## Countdown to the next squad update (1.0 s).
var squad_timer:float=0

## Spatial hash: Vector2i cell (5 m) -> actors in it.
var spatial:Dictionary={}

## Remaining allied soldiers (starts at 107 = 108 seats minus the player's).
var allies_alive:int=107

## Remaining Germans (8 positions x 10 men).
var germans_alive:int=80

## Rounds fired in total (also used to thin tracers to every 4th round).
var ammo_spent:int=0

## Statistic: shots or blasts that hurt the shooter's own side.
var friendly_fire_hits:int=0

## Statistic: near-miss events.
var near_misses:int=0

## Statistic: grenades that exploded.
var grenade_detonations:int=0

## Current banner message.
var toast_text:String=""

## Seconds left for the banner.
var toast_time:float=0

## Current dialogue line.
var subtitle:String=""

## Seconds left for it.
var subtitle_time:float=0

## Name shown with the subtitle.
var speaker:String="SGT. HAYES"

## HUD hit-marker timer.
var hit_flash:float=0

## Red-edge damage timer.
var damage_flash:float=0

## Direction of the last damage, for the HUD indicator.
var last_damage_direction=Vector3.ZERO

## Ensures the knight's wry line is said once, 9 s after dismount.
var winter_intro:bool=false

## The two German Panzerfaust soldiers positioned to ambush the convoy.
var staged_launchers:Array=[]

## "pending", "triggered" or "skipped" (no eligible truck arrived).
var ambush_outcome:String="pending"

## Trucks chosen for the scripted strikes (lead first).
var ambush_targets:Array=[]

## Same as column_stopped; kept for tests.
var convoy_settled:bool=false

## Statistic: shots at vehicles.
var vehicle_shots:int=0

## Cell -> actors claiming cover there; stops many soldiers taking the same spot.
var cover_reservations:Dictionary={}

## Rolling log of the last 600 frame times (ms) for performance tests.
var last_frame_ms:Array=[]

## True when running under tests: no auto pause on focus loss.
var test_mode:bool=false

## Fixed RNG seed when nonzero (reproducible battles).
var combat_seed:int=0

## Cause string -> count for all deaths.
var death_causes:Dictionary={}

## Same for team 1 only.
var friendly_death_causes:Dictionary={}

## Diagnostics for actors that died by falling out of the world.
var fall_events:Array=[]

## True when env HOLY_ORDER_PROFILE is set.
var profile_enabled:bool=OS.has_environment("HOLY_ORDER_PROFILE")

## Godot lifecycle hook: builds the whole battle in order (world, sound, player
## on the road start, convoy, Germans, tactics, spatial grid, HUD) and
## starts on the title camera. Honours test seed, retry and preview flags.
func _ready():
	Engine.max_fps=90
	test_mode="--battle-test" in OS.get_cmdline_user_args() or get_tree().has_meta("battle_test")
	combat_seed=int(get_tree().get_meta("battle_seed",0))
	if combat_seed!=0:seed(combat_seed)
	else:randomize()
	register_inputs()
	world=World.new()
	world.game=self
	add_child(world)
	sounds=Sounds.new()
	add_child(sounds)
	player=Player.new()
	player.game=self
	player.position=world.road_point(176)+Vector3(0,3,0)
	add_child(player)
	make_convoy()
	make_germans()
	actors=friendlies+enemies
	tactics.initialize(self)
	rebuild_spatial()
	var canvas=CanvasLayer.new()
	add_child(canvas)
	hud=HUD.new()
	hud.game=self
	canvas.add_child(hud)
	world.world_camera.current=true
	player.camera.current=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_title("Holy Order — Ardennes / Road of Iron")
	if get_tree().has_meta("ardennes_retry"):
		get_tree().remove_meta("ardennes_retry")
		begin()
	if "--battle-preview" in OS.get_cmdline_user_args():begin()

## Registers the keyboard/mouse actions (like the desert version, but it
## first erases existing events so key rebinding at runtime never duplicates).
func register_inputs():
	var bindings={"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"sprint":KEY_SHIFT,"jump":KEY_SPACE,"crouch":KEY_C,"prone":KEY_Z,"objectives":KEY_J,"lean_left":KEY_Q,"lean_right":KEY_E,"reload":KEY_R,"interact":KEY_F,"grenade":KEY_G,"weapon_sword":KEY_1,"weapon_rifle":KEY_2,"weapon_fists":KEY_3,"weapon_shovel":KEY_4,"inventory":KEY_TAB,"pause":KEY_ESCAPE,"fullscreen":KEY_F11}
	for action in bindings:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event=InputEventKey.new()
		event.physical_keycode=bindings[action]
		InputMap.action_add_event(action,event)
	for action in ["attack","aim"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT if action=="attack" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action,event)

## Adds a squad record and returns its id. [param team] 0 German, 1 US.
## [param order] "assault"/"hold". [param temperament] "cautious"/"aggressive".
## [param anchor] home position.
func new_squad(team:int,order:String,temperament:String,anchor:Vector3)->int:
	var i=squads.size()
	squads.append({"team":team,"order":order,"temperament":temperament,"anchor":anchor,"objective":anchor,"leader":null,"members":[],"contact":Vector3.ZERO,"contact_age":999.0})
	return i

## Creates nine trucks (spaced 14 m along the road) with a 12-man squad each,
## and puts the player in truck 4's seat 10. Seat 0 is the leader, seat 2 carries
## a BAR, others an M1 Garand. Truck engine loops are created if audio is on.
func make_convoy():
	# One twelve-man rifle squad is the planned load in each CCKW, not its maximum capacity.
	# Nine loads = 108 seats; the player replaces one passenger. Seven central loads = 84 seats.
	for i in range(9):
		var vehicle=Truck.new()
		vehicle.game=self
		vehicle.index=i
		vehicle.progress=150-i*14
		add_child(vehicle)
		trucks.append(vehicle)
		var sq=new_squad(1,"assault","cautious" if i%3==0 else "aggressive",vehicle.position)
		squads[sq].objective=world.anchors[0]
		for seat in range(12):
			if i==4 and seat==10:
				player.truck=vehicle
				player.seat=seat
				player.rotation.y=vehicle.rotation.y+PI
				player.last_truck_yaw=vehicle.rotation.y
				player.position=vehicle.seat_transform(seat).origin
				continue
			var actor=Actor.new()
			actor.game=self
			actor.index=friendlies.size()
			actor.team=1
			actor.squad=sq
			actor.leader=seat==0
			actor.weapon_kind="bar" if seat==2 else "garand"
			actor.truck=vehicle
			actor.seat=seat
			actor.mounted=false
			actor.position=vehicle.seat_transform(seat).origin
			actor.order="assault"
			actor.temperament=squads[sq].temperament
			add_child(actor)
			friendlies.append(actor)
			vehicle.occupants.append(actor)
			squads[sq].members.append(actor)
			if actor.leader:squads[sq].leader=actor
		if sounds.enabled:
			var engine=AudioStreamPlayer3D.new()
			engine.stream=sounds.streams.engine
			engine.volume_db=-10
			engine.unit_size=5
			engine.max_distance=100
			vehicle.add_child(engine)
			vehicle.engine_loop=engine
			engine.finished.connect(func():if phase=="playing" and not vehicle.destroyed and not vehicle.unloaded:engine.play())
			engines.append(engine)

## Creates eight German positions of ten men each around the world's anchors:
## leader with MP40, a gunner on the main nest, a G43 marksman, riflemen with
## Kar98 and optionally a second MG42. Men are placed in a fixed slot pattern
## in front of the anchor; some carry a Panzerfaust, and two staged
## launchers stand by the road to ambush the column.
func make_germans():
	for i in range(8):
		var anchor=world.anchors[i]
		var sq=new_squad(0,"hold","cautious",anchor)
		for j in range(10):
			var actor=Actor.new()
			actor.game=self
			actor.index=enemies.size()+107
			actor.squad=sq
			actor.team=0
			actor.leader=j==0
			actor.weapon_kind="mp40" if j==0 else ("g43" if j==2 else "kar98")
			if j==1:
				actor.weapon_kind=world.nests[i].kind
				actor.mounted=true
				world.nests[i].operator=actor
			var facing=(Vector3(world.road_x(anchor.z),anchor.y,anchor.z+15)-anchor).normalized()
			var right=facing.cross(Vector3.UP)

			# Slot table (x = sideways, y = forward in metres relative to the position): a fixed fighting line.
			var slots=[Vector2(0,-6),Vector2(0,0),Vector2(-8,-2),Vector2(8,-2),Vector2(-5,-4),Vector2(5,-4),Vector2(-10,2),Vector2(10,2),Vector2(-13,-5),Vector2(13,-5)]
			if j==4 and world.secondary_nests.has(i):
				actor.weapon_kind="mg42"
				actor.mounted=true
				world.secondary_nests[i].operator=actor
			var offset=right*slots[j].x+facing*slots[j].y
			actor.position=world.on_ground(anchor+offset)+Vector3(0,0.1,0)
			if j==1:actor.position=anchor+Vector3(0,0.1,0)
			if j==4 and world.secondary_nests.has(i):actor.position=world.secondary_nests[i].position+Vector3(0,0.1,0)
			actor.order="hold" if actor.mounted else squads[sq].order
			actor.temperament=squads[sq].temperament
			if j==3 and i in [4,5,6,7]:actor.fausts=1
			add_child(actor)
			actor.home=anchor
			actor.guard_radius=27
			actor.rotation.y=atan2(anchor.x-world.road_x(anchor.z),-16.0)
			enemies.append(actor)
			squads[sq].members.append(actor)
			if actor.leader:squads[sq].leader=actor
			if j==3 and i in [6,7]:
				var z=-143.0 if i==6 else -238.0
				actor.position=world.on_ground(Vector3(world.road_x(z)+(-22 if i==6 else 22),0,z))+Vector3(0,0.1,0)
				actor.home=actor.position
				actor.guard_radius=13
				actor.reserved_faust=true
				staged_launchers.append(actor)

## Starts play from the title screen: switches to the player's camera,
## captures the mouse and starts engines and the first briefing line.
func begin():
	phase="playing"
	player.camera.current=true
	world.world_camera.current=false
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for engine in engines:engine.play()
	say("Stay seated. Weapons safe until we dismount. Watch the road behind us.",5,"SGT. HAYES")
	toast("COVERED TRANSPORT  •  LOOK OUT THE REAR  •  HOLD FIRE UNTIL DISMOUNT",7)

## Handles global hotkeys: fullscreen, pause, inventory, objectives and Enter on the title.
func _unhandled_input(event):
	if event.is_action_pressed("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if event.is_action_pressed("pause"):
		if phase=="playing":pause_game("paused")
		elif phase in ["paused","inventory","objectives"]:resume_game()
	for pair in [["inventory","inventory"],["objectives","objectives"]]:
		if event.is_action_pressed(pair[0]):
			if phase=="playing":pause_game(pair[1])
			elif phase==pair[1]:resume_game()
	if phase=="title" and event is InputEventKey and event.pressed and event.keycode==KEY_ENTER:begin()

## Freezes the simulation (phase) and mutes engine loops.
## [param menu] phase name to show.
func pause_game(menu:String="paused"):
	phase=menu
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for engine in engines:engine.stream_paused=true

## Resumes play.
func resume_game():
	phase="playing"
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for engine in engines:engine.stream_paused=false

## Pauses automatically when the window loses focus (except in tests).
func _notification(what):
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and phase=="playing" and not test_mode:pause_game()

## Per-frame work: AI thinking budget, frame-time log and HUD timers.
## [param delta] frame time in seconds.
func _process(delta):
	visual_elapsed+=delta
	if phase!="playing":return
	last_frame_ms.append(delta*1000)
	if last_frame_ms.size()>600:last_frame_ms.pop_front()
	toast_time=maxf(0,toast_time-delta)
	subtitle_time=maxf(0,subtitle_time-delta)
	hit_flash=maxf(0,hit_flash-delta)
	damage_flash=maxf(0,damage_flash-delta)

## Runs one battle step; optional profiling prints any tick over 8 ms.
## [param delta] fixed physics step in seconds.
func _physics_process(delta):
	var started=Time.get_ticks_usec() if profile_enabled else 0
	step_battle(delta)
	if profile_enabled and Time.get_ticks_usec()-started>8000:print("PROFILE battle_tick ",Time.get_ticks_usec()-started)

## One simulation tick: advances the convoy, schedules the knight's line,
## rebuilds the spatial grid (every 0.25 s), updates squads (every 1 s), ages
## squad contacts, moves projectiles and expires effects.
func step_battle(delta):
	if phase!="playing":return
	elapsed+=delta
	step_convoy(delta)
	if dismounted and not winter_intro and elapsed>dismount_at+9:
		winter_intro=true
		say("At last. A war with weather appropriate for this outfit.",5,"THE KNIGHT")
	sense_timer-=delta
	if sense_timer<=0:
		sense_timer=0.25
		rebuild_spatial()
	squad_timer-=delta
	if squad_timer<=0:
		squad_timer=1.0
		update_squads()
	# Six staggered decisions per physics tick keep each soldier's perception fresh
	# about twice a second; movement and firing still run at the full physics rate.
	if elapsed>3:
		for i in range(6):
			if actors.is_empty():break
			var actor=actors[think_cursor%actors.size()]
			think_cursor+=1
			if actor.alive:
				var started=Time.get_ticks_usec() if profile_enabled else 0
				actor.think(elapsed)
				if profile_enabled and Time.get_ticks_usec()-started>6000:print("PROFILE actor_think ",Time.get_ticks_usec()-started," ",actor.state)
	for sq in squads:sq.contact_age+=delta
	step_projectiles(delta)
	for effect in effects.duplicate():
		effect.time-=delta
		if effect.time<=0:
			effect.node.queue_free()
			effects.erase(effect)

## Replaces dead squad leaders with the first living member and runs tactics.update after dismount.
func update_squads():
	for sq in squads:
		if sq.leader==null or not sq.leader.alive:
			sq.leader=null
			for a in sq.members:
				if a.alive:
					sq.leader=a
					a.leader=true
					break
	if dismounted:tactics.update(self)

## An actor reports a sighting at `point` to its squad; a leader also shares it with allied squad leaders within 55 m.
## [param actor] the reporter. [param point] where the enemy was seen.
func report_contact(actor,point:Vector3):
	var sq=squads[actor.squad]
	sq.contact=point
	sq.contact_age=0
	# Leaders relay a location, never an unseen target object through terrain.
	if actor.leader:
		for other in squads:
			if other.team==actor.team and other.leader!=null and other.leader.alive and other.leader.global_position.distance_to(actor.global_position)<55 and other.contact_age>1:
				other.contact=point
				other.contact_age=1

## Rebuilds the 5 m spatial hash of living actors and the cover reservations (3 m cells).
func rebuild_spatial():
	spatial.clear()
	cover_reservations.clear()
	for actor in actors:
		if not actor.alive:continue
		var c=Vector2i(floori(actor.position.x/5),floori(actor.position.z/5))
		if not spatial.has(c):spatial[c]=[]
		spatial[c].append(actor)
		if actor.has_cover:
			var reservation=Vector3i(floori(actor.cover.x/3),actor.team,floori(actor.cover.z/3))
			if not cover_reservations.has(reservation):cover_reservations[reservation]=[]
			cover_reservations[reservation].append(actor)

## Returns a push-away vector (length at most 1) from nearby actors so soldiers
## do not stand inside each other; entrenched pairs may stand closer.
func separation_for(actor)->Vector3:
	var c=Vector2i(floori(actor.position.x/5),floori(actor.position.z/5))
	var result=Vector3.ZERO
	for dx in [-1,0,1]:
		for dz in [-1,0,1]:
			for other in spatial.get(c+Vector2i(dx,dz),[]):
				if other==actor or not other.alive or other.truck!=null:continue
				var v=actor.position-other.position
				v.y=0
				var d=v.length()
				var space=tactics.book.spacing.entrenched if actor.entrenched and other.entrenched else tactics.book.spacing.separation
				if d>0.01 and d<space:result+=v/d*(space-d)/space
	return result.limit_length(1.0)

## True for the player with health, or an actor that is alive and not "staged".
func actor_alive(actor)->bool:
	if actor==null or not is_instance_valid(actor):return false
	return actor.health>0 if actor==player else actor.alive and not actor.staged

## The point on `actor` that others aim at (its chest).
func actor_aim(actor)->Vector3:
	return actor.aim_point()

## Chooses a visible enemy for `actor`: candidates within weapon range (and
## not behind the actor when its contact is old), sorted by distance; the
## nearest five are tested with a sight ray and the first that is really visible is returned, or null.
func acquire_target(actor):
	var candidates=friendlies.duplicate() if actor.team==0 else enemies.duplicate()
	if actor.team==0:candidates.append(player)
	var nearest:Array=[]
	for other in candidates:
		if not actor_alive(other):continue
		var d=actor.global_position.distance_squared_to(other.global_position)
		if d>pow(actor.spec.range,2):continue
		if actor.contact_age>20:
			var toward=(other.global_position-actor.global_position).normalized()
			if (-actor.global_basis.z).dot(toward)<-0.20 and d>400:continue
		nearest.append({"actor":other,"d":d})
	nearest.sort_custom(func(a,b):return a.d<b.d)
	for entry in nearest.slice(0,5):
		var other=entry.actor
		var ray=PhysicsRayQueryParameters3D.create(actor.eye(),actor_aim(other),1|2|4|8)
		ray.exclude=[actor.get_rid()]
		var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and hit.collider==other:return other
	return null

## Friendly-fire check before shooting from `from` to `to`.
## Rejects if an ally (or the player for team 1) is near the line, widened by
## the weapon's spread and the ally's motion; then checks the first thing the ray hits and allows only enemies or enemy vehicles.
## Returns true when it is safe to fire.
func safe_fire_line(actor,from:Vector3,to:Vector3)->bool:
	# Check the likely dispersion cone and nearby allies' motion, not only the center ray.
	var length=from.distance_to(to)
	var axis=(to-from).normalized()
	var friends=friendlies if actor.team==1 else enemies
	for other in friends+([player] if actor.team==1 else []):
		if other==actor or not actor_alive(other):continue
		var point=actor_aim(other)+other.velocity*0.25
		var along=(point-from).dot(axis)
		if along<0.3 or along>length+2:continue
		var radius=0.65+actor.spec.spread*along*2.7
		if point.distance_to(from+axis*along)<radius:
			fire_checks_blocked+=1
			actor.fire_blocked+=1
			return false
	var direction=(to-from).normalized()
	var ray=PhysicsRayQueryParameters3D.create(from,to+direction*0.3,1|2|4|8)
	ray.exclude=[actor.get_rid()]
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():return true
	if hit.collider==player:return actor.team!=1
	if hit.collider is Actor:return hit.collider.team!=actor.team
	if hit.collider.get("truck_owner")!=null:return actor.team==0
	return false

## True if no ally (or the player for team 1) is within `radius` of `point`, now or 1.2 s ahead.
func safe_explosive_target(actor,point:Vector3,radius:float)->bool:
	var friends=friendlies if actor.team==1 else enemies
	for other in friends:
		if not other.alive:continue
		var future=other.global_position+other.velocity*1.2
		if other.global_position.distance_to(point)<radius or future.distance_to(point)<radius:return false
	if actor.team==1 and player.health>0 and player.position.distance_to(point)<radius:return false
	return true

## Tests a grenade arc (peak 5.5 m, six segments) for obstructions before throwing.
func can_lob(from:Vector3,to:Vector3)->bool:
	var last=from
	for i in range(1,7):
		var t=i/6.0
		var p=from.lerp(to,t)+Vector3(0,5.5*sin(t*PI),0)
		var hit=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(last,p,1))
		if not hit.is_empty() and i<6:return false
		last=p
	return true

## Fires one bullet with Gaussian spread and resolves penetration: up to four
## ray passes (layers world, player, both teams, props, equipment, pickups).
## Weapons in hands are damaged (80%), hit areas take damage, soldiers take it
## (headshots above 1.5 m deal 1.7x), props are damaged and thin wooden/cloth
## cargo panels let the bullet pass with 72% damage; armour and anything else stops it.
## Also draws a tracer, notifies near-miss and emits a 260 m gunshot noise.
## [param source] shooter. [param from] muzzle. [param aim] target. [param spread] standard deviation (radians). [param damage] hit points. [param kind] weapon kind ("m2" does extra environment damage).
func shoot(source,from:Vector3,aim:Vector3,spread:float,damage:float,kind:String):
	var direction=(aim-from).normalized()
	var right=direction.cross(Vector3.UP).normalized()
	var up=right.cross(direction).normalized()
	direction=(direction+right*randfn(0,spread)+up*randfn(0,spread)).normalized()
	var end=from+direction*430
	var origin=from
	var excludes:Array[RID]=[]
	excludes.assign(source.shot_exclusions() if source==player else [source.get_rid(),source.equipment.get_rid()])
	ammo_spent+=1
	for pass_index in range(4):
		var q=PhysicsRayQueryParameters3D.create(origin,end,1|2|4|8|16|32)
		q.collide_with_areas=true
		q.exclude=excludes
		var hit=get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():break
		var obj=hit.collider
		if obj.has_meta("wielder"):
			obj.get_meta("wielder").damage_weapon(damage*0.8)
			excludes.append(obj.get_rid())
			origin=hit.position+direction*0.04
			continue
		if obj.has_method("receive_hit"):
			obj.receive_hit(damage,hit.position)
			excludes.append(obj.get_rid())
			origin=hit.position+direction*0.04
			continue
		if obj==player or obj is Actor:
			var headshot=hit.position.y-obj.global_position.y>1.5
			hurt_actor(obj,damage*(1.7 if headshot else 1.0),source.global_position,"rifle")
			if obj.team==source.team:friendly_fire_hits+=1
			if source==player:hit_flash=0.18
			end=hit.position
			break
		damage_environment(hit,damage*(1.8 if kind=="m2" else 0.65),0.16)
		var armored=obj.has_method("stops_small_arms") and obj.stops_small_arms()
		if not armored and obj.has_method("damage_at") and (obj.material_kind in ["wood","cloth"] or obj.get("truck_owner")!=null) and pass_index<3:
			# Unarmored cargo panels can be penetrated. Passengers remain separate hitboxes.
			damage*=0.72
			excludes.append(obj.get_rid())
			origin=hit.position+direction*0.04
			continue
		end=hit.position
		break
	if ammo_spent%4==0 or source==player:tracer(from,end,Color("f2c88a") if source.team==1 else Color("eea473"))
	notify_projectile(from,end,source.team)
	if source!=player:sounds.at("rifle",from,-10,0.72 if kind=="m2" else randf_range(0.91,1.09))
	emit_noise(from,260,source.team,"gunshot")

## Applies damage to a soldier or the player, reduced by truck cover for passengers.
func hurt_actor(actor,damage:float,source:Vector3,kind:String):
	if not actor_alive(actor):return
	if actor.truck!=null and actor.truck.has_method("passenger_damage"):
		damage=actor.truck.passenger_damage(damage,kind)
	actor.take_damage(damage,source,kind)

## Tells soldiers whose eye is within 1.5 m of the path (and beyond 2 m from the start) that a bullet went past (near_miss).
func notify_projectile(from:Vector3,to:Vector3,_source_team:int):
	var line=to-from
	var sq_len=line.length_squared()
	if sq_len<0.001:return
	for actor in actors:
		if not actor.alive or actor.staged:continue
		var point=actor.eye()
		var t=clampf((point-from).dot(line)/sq_len,0,1)
		if point.distance_squared_to(from+line*t)<2.25 and point.distance_squared_to(from)>4:
			actor.near_miss(from)
			near_misses+=1

## Alerts all living actors of the other team with a noise of `radius`.
func emit_noise(point:Vector3,radius:float,team:int,kind:String):
	for actor in actors:
		if actor.team!=team and actor.alive:actor.hear_noise(point,radius,team,kind)

## Applies damage_at to the breakable that was hit.
func damage_environment(hit:Dictionary,amount:float,radius:float):
	if hit.collider.has_method("damage_at"):hit.collider.damage_at(amount,hit.position,radius)

## Draws a brief glowing streak up to 22 m long; nothing is drawn when 64 effects exist.
func tracer(from:Vector3,to:Vector3,color:Color):
	if effects.size()>64:return
	var root=Node3D.new()
	add_child(root)
	var mat=Art.material(color).duplicate()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var segment=to-from
	var length=minf(segment.length(),22)
	Art.segment(root,to-segment.normalized()*length,to,0.013,mat)
	effects.append({"node":root,"time":0.055})

## Draws a tiny sphere flash at the impact point.
func impact(point:Vector3,color:Color):
	if effects.size()>64:return
	var node=Art.sphere(self,0.055,point,Art.material(color))
	effects.append({"node":node,"time":0.15})

## Fires the scripted Panzerfaust at the lead or rear truck. Only a live
## launcher and a live truck qualify; nothing is spawned to stand in for a missing one.
func scripted_strike(vehicle,shooter,is_lead:bool):
	# Eligibility is evaluated against the live vehicle and launcher. No teleport,
	# invulnerable performer, or replacement target is created for a missing truck.
	shooter.fausts-=1
	launch_faust(shooter,vehicle.to_global(Vector3(0,1.4,-1.8)),vehicle,true)
	if is_lead:lead_strike=true
	else:rear_strike=true
	say("Panzerfaust! Front of the arriving column!" if is_lead else "They've hit the last truck in the kill zone!",4,"SGT. HAYES")

## Launches a Panzerfaust rocket from `source` toward `aim`.
## [param vehicle] truck being targeted. [param scripted] true for the ambush (no random miss; follows the truck).
## Unscripted rockets miss by a random amount that grows with range.
func launch_faust(source,aim:Vector3,vehicle=null,scripted:bool=false):
	var from=source.eye()+Vector3(0,0.12,0)
	var goal=aim
	if not scripted:
		var distance=from.distance_to(aim)
		goal+=Vector3(randfn(0,distance*0.055),randfn(0,distance*0.025),randfn(0,distance*0.045))
	var node=Art.sphere(self,0.075,from,Art.material(Color("c3a970")))
	rockets.append({"node":node,"from":from,"aim":goal,"age":0.0,"duration":maxf(0.35,from.distance_to(goal)/42.0),"vehicle":vehicle,"scripted":scripted,"source":source})
	emit_noise(from,260,source.team,"explosion")

## Player throws a grenade: 15 m/s forward and 5 m/s up.
func throw_grenade(from:Vector3,direction:Vector3):
	spawn_grenade(from,direction.normalized()*15.0+Vector3(0,5.0,0),1,player,player.last_grenade_type)

## AI throws a grenade at `target` with a computed lob (1.6 s flight).
func bot_grenade(actor,target:Vector3):
	var from=actor.eye()
	var flight=1.6
	var velocity=(target-from)/flight+Vector3(0,9.0*flight*0.5,0)
	spawn_grenade(from,velocity,actor.team,actor)

## Creates a grenade node: M24 stick grenade (German) or Mk 2 pineapple (US).
## Fuse is random 4.0-4.8 s.
func spawn_grenade(from:Vector3,velocity:Vector3,team:int,source,grenade_kind:String=""):
	if grenade_kind=="":grenade_kind="m24" if team==0 else "mk2"
	var node=Node3D.new()
	add_child(node)
	node.position=from
	var green=Art.material(Color("55573b"))
	if grenade_kind=="m24":
		Art.cylinder(node,0.019,0.21,Vector3.ZERO,Art.material(Color("8c7049")),-1,8)
		Art.cylinder(node,0.04,0.07,Vector3(0,0.12,0),green,-1,10)
	else:
		var mesh=Art.sphere(node,0.052,Vector3.ZERO,green)
		mesh.scale.y=1.3
	grenades_live.append({"node":node,"velocity":velocity,"age":0.0,"fuse":randf_range(4.0,4.8),"source":source,"team":team,"kind":grenade_kind})

## Moves grenades (gravity 9 m/s^2, bounce, 0.3 s safety so the thrower is not hit) and rockets along arcs; explodes them on fuse end, impact or arrival.
func step_projectiles(delta:float):
	for grenade in grenades_live.duplicate():
		grenade.age+=delta
		grenade.fuse-=delta
		grenade.velocity.y-=9.0*delta
		var from=grenade.node.position
		var to=from+grenade.velocity*delta
		var q=PhysicsRayQueryParameters3D.create(from,to,1|2|4|8)
		if grenade.age<0.3:q.exclude=[grenade.source.get_rid()]
		var hit=get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			to=hit.position+hit.normal*0.09
			grenade.velocity=grenade.velocity.bounce(hit.normal)*0.32
			if grenade.velocity.length()<0.65:grenade.velocity=Vector3.ZERO
		grenade.node.position=to
		grenade.node.rotate_x(delta*4)
		if grenade.fuse<=0:
			explode(to,5.8 if grenade.kind=="m24" else 7.0,125 if grenade.kind=="m24" else 115,grenade.source,"grenade")
			grenade_detonations+=1
			grenade.node.queue_free()
			grenades_live.erase(grenade)
	for rocket in rockets.duplicate():
		rocket.age+=delta
		var t=minf(1,rocket.age/rocket.duration)
		var goal=rocket.aim
		if rocket.scripted and is_instance_valid(rocket.vehicle):goal=rocket.vehicle.to_global(Vector3(0,1.4,-1.8))
		var pos=rocket.from.lerp(goal,t)+Vector3(0,1.1*sin(t*PI),0)
		var hit={}
		if not rocket.scripted:
			var q=PhysicsRayQueryParameters3D.create(rocket.node.position,pos,1|2|4|8)
			q.exclude=[rocket.source.get_rid()]
			hit=get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():pos=hit.position
		tracer(rocket.node.position,pos,Color("e8bc7b"))
		rocket.node.position=pos
		if t>=1 or not hit.is_empty():
			explode(pos,7.5,155,rocket.source,"rocket")
			if rocket.scripted and is_instance_valid(rocket.vehicle):
				rocket.vehicle.receive_ambush_strike(pos)
				if not ambush_targets.is_empty() and rocket.vehicle==ambush_targets[0]:lead_hit=true
				else:rear_hit=true
			rocket.node.queue_free()
			rockets.erase(rocket)

## Detonates at `point`: damages every actor within `radius` with a falloff
## (distance factor to the power 0.65) reduced by cover (18% behind hard cover, 55% behind other), throws corpses, damages dropped weapons, deforms the world, plays sound and noise, and draws a flash and dust.
## [param kind] "grenade" or "rocket".
func explode(point:Vector3,radius:float,damage:float,source,kind:String="grenade"):
	for actor in actors+[player]:
		if not actor_alive(actor):continue
		var aim=actor_aim(actor)
		var distance=point.distance_to(aim)
		if distance>radius:continue
		var cover=1.0
		var ray=PhysicsRayQueryParameters3D.create(point+Vector3(0,0.1,0),aim,1)
		var hit=get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():cover=0.18 if hit.collider.get("material_kind") in ["rock","soil","masonry","sandbag"] else 0.55
		var amount=damage*pow(1.0-distance/radius,0.65)*cover
		hurt_actor(actor,amount,point,"explosion")
		if source!=null and source.team==actor.team and amount>1:friendly_fire_hits+=1
	for corpse in get_tree().get_nodes_in_group("winter_corpses"):
		corpse.blast(point,radius,damage*1.4)
	for weapon in get_tree().get_nodes_in_group("dropped_weapons"):
		var d=weapon.global_position.distance_to(point)
		if d<radius:weapon.receive_hit(damage*(1-d/radius),point)
	world.blast(point,380,radius*0.7,1.15 if kind=="rocket" else 0.8,0.32 if kind=="rocket" else 0.12)
	sounds.at("explosion",point,-2,randf_range(0.85,1.05))
	emit_noise(point,300,-1,"explosion")
	var root=Node3D.new()
	add_child(root)
	root.position=point
	var mat=Art.material(Color("c88d42")).duplicate()
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var flash=Art.sphere(root,0.5,Vector3.ZERO,mat)
	var tween=create_tween()
	tween.tween_property(flash,"scale",Vector3.ONE*5,0.11)
	tween.tween_callback(flash.hide)
	for i in range(10):
		var dust=Art.sphere(root,randf_range(0.3,0.7),Vector3.ZERO,Art.material(Color("5c5c53")))
		var end=Vector3(randf_range(-3,3),randf_range(1,4),randf_range(-3,3))
		create_tween().tween_property(dust,"position",end,0.9)
	effects.append({"node":root,"time":1.1})

## Creates smoke particles and an orange glow at a burning wreck.
func add_wreck_fire(point:Vector3):
	var smoke=GPUParticles3D.new()
	add_child(smoke)
	smoke.position=point
	smoke.amount=35
	smoke.lifetime=6
	smoke.visibility_aabb=AABB(Vector3(-10,-2,-10),Vector3(20,28,20))
	var p=ParticleProcessMaterial.new()
	p.direction=Vector3(0.15,1,0)
	p.spread=12
	p.initial_velocity_min=2.0
	p.initial_velocity_max=3.4
	p.gravity=Vector3(0.04,0.2,0)
	p.scale_min=1.2
	p.scale_max=2.8
	var gradient=Gradient.new()
	gradient.set_color(0,Color(0.10,0.11,0.10,0.8))
	gradient.set_color(1,Color(0.20,0.22,0.23,0))
	var ramp=GradientTexture1D.new()
	ramp.gradient=gradient
	p.color_ramp=ramp
	smoke.process_material=p
	var quad=QuadMesh.new()
	quad.size=Vector2(3,3)
	var mat=StandardMaterial3D.new()
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo=true
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var texture=GradientTexture2D.new()
	var radial=Gradient.new()
	radial.set_color(0,Color(1,1,1,0.7))
	radial.set_color(1,Color(1,1,1,0))
	texture.gradient=radial
	texture.fill=GradientTexture2D.FILL_RADIAL
	texture.fill_from=Vector2(0.5,0.5)
	texture.fill_to=Vector2(1,0.5)
	mat.albedo_texture=texture
	quad.material=mat
	smoke.draw_pass_1=quad
	var light=OmniLight3D.new()
	add_child(light)
	light.position=point
	light.light_color=Color("ff943e")
	light.light_energy=2
	light.omni_range=7

## Stops the destroyed truck's engine; the others try to drive around it.
func vehicle_wrecked(vehicle,_scripted:bool):
	if vehicle.engine_loop!=null:vehicle.engine_loop.stop()
	# A local wreck is a traffic obstruction. Other trucks keep trying to pass it.

## First unloading starts the dismounted phase and the orders; tactics then assigns the new soldiers.
func truck_dismounted(vehicle):
	if vehicle.engine_loop!=null:vehicle.engine_loop.stop()
	if not dismounted:
		dismounted=true
		dismount_at=elapsed
		say("Dismount! Left and right sections: clear the ambush hills, then work back down the road!",7,"SGT. HAYES")
		toast("LEFT / RIGHT HILLTOPS MARKED • Choose either route • J orders",7)
	tactics.assign_dismounted(self)
	tactics.update(self)

## Records the death cause, creates the corpse, drops weapons and ammunition, updates counts and triggers victory when no German remains.
func actor_died(actor,kind:String):
	death_causes[kind]=int(death_causes.get(kind,0))+1
	if kind=="fall":
		fall_events.append({"index":actor.index,"position":str(actor.position),"surface":world.surface_height(actor.position.x,actor.position.z),"state":actor.state})
		print("FALL_DIAGNOSTIC ",JSON.stringify(fall_events.back()))
	if actor.team==1:friendly_death_causes[kind]=int(friendly_death_causes.get(kind,0))+1
	corpses.append(actor)
	var remains=Corpse.new()
	remains.game=self
	remains.soldier=actor
	remains.position=actor.position
	remains.rotation.y=actor.rotation.y
	add_child(remains)
	if not actor.dropped_broken:
		drop_weapon(actor.weapon_kind,actor.rounds,actor.weapon_health,actor.last_mount_position if actor.weapon_kind=="m2" else actor.position,actor.rotation.y,actor.weapon_kind=="m2")
		actor.rounds=0
	if actor.backup_rounds>0:
		drop_weapon("garand" if actor.team==1 else "kar98",actor.backup_rounds,100,actor.position+Vector3(0.5,0,0),actor.rotation.y)
		actor.backup_rounds=0
	if actor.team==0:germans_alive-=1
	else:allies_alive-=1
	if germans_alive<=0 and player.health>0:
		phase="victory"
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		sounds.play("victory",-10)

## F key: dismount orders in a truck, otherwise pick up ammunition, then the best-aimed weapon, then loot the nearest body.
func interact():
	if player.truck!=null:
		if player.truck.stopped:player.truck.dismount("orders")
		else:toast("Stay seated. Weapons remain safe until the truck stops and we dismount.",3)
		return
	for bundle in get_tree().get_nodes_in_group("ammo_bundles"):
		if bundle.position.distance_to(player.position)<2.6:
			bundle.take(player)
			return
	var pickup=null
	var closest_aim=0.62
	for item in get_tree().get_nodes_in_group("dropped_weapons"):
		if item.picked_up or item.mounted or item.global_position.distance_to(player.position)>3.4:continue
		var alignment=(-player.camera.global_basis.z).dot((item.global_position-player.camera.global_position).normalized())
		if alignment>closest_aim:
			closest_aim=alignment
			pickup=item
	if pickup!=null:
		pickup.take(player)
		return
	var nearest=null
	var best=3.2
	for actor in corpses:
		var distance=player.position.distance_to(actor.position)
		if not actor.looted and distance<best:
			nearest=actor
			best=distance
	if nearest==null:
		toast("F  •  Search a fallen soldier within reach.",2)
		return
	loot(nearest)

## Moves a dead soldier's grenades (up to 4 carried) and reserve ammunition into the player's pack.
func loot(actor)->Dictionary:
	if actor.looted:return {}
	var taken_grenades=mini(actor.grenades,maxi(0,4-player.grenades))
	var result={"rounds":0,"grenades":taken_grenades,"caliber":actor.spec.caliber}
	player.add_grenades("m24" if actor.team==0 else "mk2",taken_grenades)
	actor.grenades-=taken_grenades
	result.rounds=player.stash_ammo(actor.spec.caliber,actor.reserve,actor.weapon_kind)
	actor.reserve-=result.rounds
	if actor.backup_reserve>0:
		var n=player.stash_ammo("30-06" if actor.team==1 else "792",actor.backup_reserve,"garand" if actor.team==1 else "kar98")
		actor.backup_reserve-=n
	actor.looted=actor.reserve==0 and actor.grenades==0 and actor.backup_reserve==0
	toast("Recovered %d rounds, %d grenades. Pack %.1f / 24; grenades %d / 4."%[result.rounds,result.grenades,player.ammo_pack.space_used(),player.grenades],4)
	return result

## World point for the compass: the road end while seated, otherwise the nearest hilltop still held.
func objective_target()->Vector3:
	if player.truck!=null:return world.road_point(Truck.END_PROGRESS)
	var best=INF
	var goal=world.anchors[6]
	for area in tactics.active_areas(self):
		var d=player.position.distance_squared_to(world.anchors[area])
		if d<best:
			best=d
			goal=world.anchors[area]
	return goal

## HUD objective line, including how many of the eight hilltops are secured.
func objective_text()->String:
	if player.truck!=null:
		if player.truck.disabled:return "Wheels hit. Await dismount orders."
		return "Stay seated. Watch the road behind."
	var cleared=0
	for i in range(8):
		if not tactics.area_alive(self,i):cleared+=1
	return "Clear both ridges • %d / 8 hilltops secured"%cleared

## Shows a banner message for `duration` seconds.
func toast(text:String,duration:float=3):
	toast_text=text
	toast_time=duration

## Shows a subtitle line with its speaker.
func say(text:String,duration:float=5,who:String="THE KNIGHT"):
	subtitle=text
	subtitle_time=duration
	speaker=who

## Ends the mission on death and silences engines.
func defeat():
	if phase!="playing":return
	phase="defeat"
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for engine in engines:engine.stop()

## Restarts the mission, skipping the title screen.
func retry():
	get_tree().set_meta("ardennes_retry",true)
	get_tree().reload_current_scene()

## Stub (no mounted gun for the player here); keeps shared interface code working.
func leave_mg():pass

## Stops audio players so streams are released on scene change.
func _exit_tree():
	for engine in engines:
		if is_instance_valid(engine):
			engine.stop()
			engine.stream=null

## Puts a weapon on the ground as a DroppedWeapon.
## [param kind] weapon type. [param loaded] rounds in it. [param condition] durability.
## [param point] position. [param yaw] rotation. [param mounted] true for fixed guns.
func drop_weapon(kind:String,loaded:int,condition:float,point:Vector3,yaw:float,mounted:bool=false):
	var drop=Drop.new()
	drop.game=self
	drop.kind=kind
	drop.rounds=loaded
	drop.condition=condition
	drop.mounted=mounted
	drop.position=point if mounted else world.on_ground(point+Vector3(0.7,0,0.5))+Vector3(0,0.13,0)
	drop.rotation.y=yaw+0.4
	add_child(drop)
	return drop

## Swaps the player's firearm for the dropped one, dropping the old one; belt-fed MGs keep 50 rounds and put the surplus in a bundle.
func swap_weapon(drop):
	if player.has_rifle:drop_weapon(player.gun_kind,player.ammo,player.rifle_health,player.position,player.rotation.y)
	var loaded=drop.rounds
	if drop.kind in ["mg34","mg42"] and loaded>50:
		var bundle=AmmoBundle.new()
		bundle.game=self
		bundle.contents=[{"kind":drop.kind,"rounds":loaded-50}]
		bundle.position=drop.position+Vector3(0.5,0.1,0)
		add_child(bundle)
		loaded=50
	player.set_firearm(drop.kind,loaded,drop.condition)
	drop.rounds=0
	toast("Carrying %s%s. Previous firearm dropped."%[Kit.DATA[drop.kind].name," — BROKEN" if drop.condition<=0 else ""],3)

## True if another living actor on the same team is already using cover within about 2.3 m of `point`.
func cover_occupied(actor,point:Vector3)->bool:
	var cell=Vector3i(floori(point.x/3),actor.team,floori(point.z/3))
	for x in [-1,0,1]:
		for z in [-1,0,1]:
			for other in cover_reservations.get(cell+Vector3i(x,0,z),[]):
				if other!=actor and other.alive and other.has_cover and other.cover.distance_squared_to(point)<5.5:return true
	return false

## Puts the player's ammunition containers on the ground as a bundle.
func drop_pack():
	if player.ammo_pack.containers.is_empty():return
	var bundle=AmmoBundle.new()
	bundle.game=self
	bundle.contents=player.ammo_pack.containers.duplicate(true)
	player.ammo_pack.containers.clear()
	bundle.position=world.on_ground(player.position-player.global_basis.z*1.3)+Vector3(0,0.14,0)
	add_child(bundle)
	toast("Spare ammunition placed on the ground. F picks up what fits.",3)
	hud.last_phase=""

## Trucks that can still be struck: intact, loaded, between 540 m along the road and the end, nearest the front first.
func ambush_candidates()->Array:
	var candidates=trucks.filter(func(t):return not t.destroyed and not t.unloaded and not t.disabled and t.has_passengers() and t.progress>=540 and t.progress<=Truck.END_PROGRESS+1)
	candidates.sort_custom(func(a,b):return a.progress>b.progress)
	return candidates

## True if the shooter is alive, has a rocket, is within 78 m and has an unobstructed line to the truck.
func launcher_can_hit(shooter,vehicle)->bool:
	if shooter==null or not shooter.alive or shooter.fausts<=0:return false
	var point=vehicle.to_global(Vector3(0,1.4,-1.8))
	if shooter.eye().distance_to(point)>78:return false
	var q=PhysicsRayQueryParameters3D.create(shooter.eye(),point,1)
	var hit=get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider.get("truck_owner")==vehicle

## Decides once whether the ambush happens: the lead arriving truck is hit if the staged launcher can reach it, and the rear one 3.5 s later if possible. Sets ambush_outcome and the dismount time.
func decide_ambush(candidates:Array):
	if ambush_outcome!="pending":return
	ambush_outcome="skipped"
	if candidates.is_empty():return
	var front=candidates[0]
	var front_launcher=staged_launchers[1]
	if not launcher_can_hit(front_launcher,front):return
	ambush_outcome="triggered"
	ambush_targets=[front]
	scripted_strike(front,front_launcher,true)
	if candidates.size()>1:
		var rear=candidates.back()
		if rear!=front and launcher_can_hit(staged_launchers[0],rear):
			ambush_targets.append(rear)
			rear_at=elapsed+3.5
	# One arriving truck receives only one strike. Non-arrivals are never substituted.
	dismount_at=elapsed+5.5

## Advances trucks, triggers the ambush when the lead truck arrives, fires the rear strike, and orders the dismount.
func step_convoy(delta:float):
	for truck in trucks:truck.tick(delta)
	if ambush_outcome=="pending":
		var candidates=ambush_candidates()
		if not candidates.is_empty() and candidates[0].arrived:decide_ambush(candidates)
		elif trucks.all(func(t):return t.destroyed or t.unloaded):decide_ambush([])
	if rear_at>0 and elapsed>=rear_at and not rear_strike:
		rear_at=-1
		if ambush_targets.size()>1:
			var rear=ambush_targets[1]
			if not rear.destroyed and rear.has_passengers() and launcher_can_hit(staged_launchers[0],rear):scripted_strike(rear,staged_launchers[0],false)
	if ambush_outcome=="triggered" and dismount_at>0 and elapsed>=dismount_at:
		for truck in trucks:
			if not truck.destroyed and not truck.unloaded and truck.progress>=540:truck.dismount("ambush")
	convoy_settled=trucks.all(func(t):return t.destroyed or t.unloaded)
	column_stopped=convoy_settled

## Chooses the truck a German should shoot at: in range, visible, and preferred if recently hit, with a small deterministic spread so different gunners pick different trucks.
func acquire_vehicle(actor):
	if actor.team!=0:return null
	var best=null
	var score=INF
	for truck in trucks:
		if truck.destroyed or truck.unloaded or not truck.has_passengers():continue
		var point=truck.target_point(actor)
		var distance=actor.eye().distance_squared_to(point)
		if distance>actor.spec.range*actor.spec.range:continue
		var q=PhysicsRayQueryParameters3D.create(actor.eye(),point,1)
		var hit=get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.collider.get("truck_owner")!=truck:continue
		var value=distance+maxf(0,6-(elapsed-truck.last_hit_time))*700+float((truck.index+actor.index)%4)*100
		if value<score:
			score=value
			best=truck
	return best
