extends CharacterBody3D

const Art = preload("res://scripts/art.gd")
var game
var model: Dictionary
var health: float = 100.0
var alive: bool = true
var sentry: bool = false
var index: int = 0
var anchor: Vector3
var clock: float = 0
var cooldown: float = 3
var windup: float = 0
var alerted: bool = false
var stagger: float = 0
var shots_fired: int = 0
var muzzle: MeshInstance3D
var rng = RandomNumberGenerator.new()

func _ready():
	rng.seed = 740 + index*39
	collision_layer = 4
	collision_mask = 1|2|4
	var c = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.85
	c.shape = capsule
	c.position.y = 0.93
	add_child(c)
	model = Art.soldier(self)
	anchor = position
	cooldown = 2.5 + index*0.43
	var mat = Art.material(Color("ffe2a1")).duplicate()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle = Art.sphere(model.gun,0.06,model.gun.get_node("Muzzle").position,mat)
	muzzle.visible = false

func _physics_process(delta):
	if not alive or game.phase != "playing":
		return
	clock += delta
	stagger = maxf(0, stagger-delta)
	cooldown -= delta
	var player = game.player
	var target = player.global_position
	var distance = global_position.distance_to(target)
	var facing = Vector3(target.x,global_position.y,target.z)
	if alerted and global_position.distance_to(facing) > 0.1:
		look_at(facing)
	var visible_player = can_see_player()
	var notice_range = 26.0 if sentry else 25.0
	if player.crouched: notice_range *= 0.55
	if player.prone: notice_range *= 0.31
	var toward = (target-global_position).normalized()
	var in_view = (-global_basis.z).dot(toward) > 0.25
	if distance < notice_range and visible_player and (in_view or distance < 3.5):
		alerted = true
	if not alerted:
		rotation.y = PI + sin(clock*0.25+index)*0.28
	model.gun.rotation.x = lerpf(model.gun.rotation.x,0.0 if alerted else -0.48,delta*3)
	if alerted and sentry:
		game.has_seen_rifle = true
	# Defenders hold the line. Flankers move between nearby clear firing points.
	var desired = Vector3.ZERO
	if alerted and not sentry and index % 2 == 0 and distance > 8 and distance < 43:
		var patrol = anchor + Vector3(sin(clock*0.35+index)*2.0,0,0)
		desired = (patrol - global_position)
		desired.y = 0
		if desired.length() > 0.35:
			desired = desired.normalized()*1.05
		else:
			desired = Vector3.ZERO
	velocity.x = desired.x
	velocity.z = desired.z
	if not is_on_floor():
		velocity.y -= 20*delta
	move_and_slide()
	var moving = Vector2(velocity.x,velocity.z).length()
	model.legs[0].rotation.x = sin(clock*9)*0.4*minf(moving,1)
	model.legs[1].rotation.x = -model.legs[0].rotation.x
	model.body.rotation.x = -stagger*0.45
	if stagger > 0:
		windup = 0
		return
	if windup > 0:
		windup -= delta
		if windup <= 0:
			shoot()
	elif alerted and visible_player and distance < 62 and cooldown <= 0:
		windup = 0.60 if sentry else 0.44
		cooldown = rng.randf_range(3.2,4.9) if not sentry else 4.8
		game.sounds.at("bolt",global_position,-7)
	if distance < 1.75 and cooldown > 1 and clock > 2:
		if int(clock*2) % 5 == 0 and windup == 0:
			cooldown = minf(cooldown,0.5)

func can_see_player() -> bool:
	var start = global_position + Vector3(0,1.52,0)
	var target = game.player.global_position+Vector3(0,game.player.eye_height*0.86,0)
	var q = PhysicsRayQueryParameters3D.create(start,target,1|2)
	q.exclude = [get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider == game.player

func shoot():
	if not alive or not can_see_player():
		return
	shots_fired += 1
	var origin = global_position+Vector3(0,1.42,0)
	var target = game.player.global_position + Vector3(0,1.12,0)
	var distance = origin.distance_to(target)
	var accuracy = clampf(0.78 - distance*0.009,0.20,0.68)
	if game.player.is_sprinting:
		accuracy *= 0.65
	if sentry and shots_fired == 1:
		accuracy = 0 # The first report is an authored warning shot, not a hidden death trap.
	var hits = rng.randf() < accuracy
	if not hits:
		target += Vector3(rng.randf_range(0.8,1.5)*(1 if rng.randf()>0.5 else -1),rng.randf_range(-0.4,0.5),0)
	game.tracer(origin,target,Color("e9bb70"))
	game.sounds.at("rifle",origin,-2)
	muzzle.visible = true
	get_tree().create_timer(0.07).timeout.connect(func(): if is_instance_valid(muzzle): muzzle.visible = false)
	if hits:
		game.player.take_damage(11 if sentry else 13,global_position,"rifle")
	model.gun.position.z = -0.38
	var tw = create_tween()
	tw.tween_property(model.gun,"position:z",-0.43,0.28)

func take_damage(amount: float, headshot: bool = false):
	if not alive:
		return
	health -= amount * (2.0 if headshot else 1.0)
	stagger = 0.55
	alerted = true
	game.sounds.at("hit",global_position,-7)
	if health <= 0:
		die()

func die():
	alive = false
	set_collision_layer_value(3,false)
	collision_mask = 0
	velocity = Vector3.ZERO
	muzzle.visible = false
	var tw = create_tween().set_parallel(true)
	tw.tween_property(model.root,"rotation:x",-PI/2,0.45).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(model.root,"position:y",0.18,0.45)
	game.enemy_down(self)
