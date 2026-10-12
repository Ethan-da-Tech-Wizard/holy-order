extends "res://scripts/ardennes/player.gd"
const Wire=preload("res://scripts/omaha/wire.gd")
var last_fired:float=-999
var deck_position=Vector3(0,0.27,1.99)

func _ready():
	super._ready()
	ammo_pack.containers.clear()
	set_firearm("garand",8,100)
	ammo_pack.add_rounds("garand",96)
	camera.far=750

func dismount():
	if truck==null or not truck.arrived or deck_position.z> -6.4:return
	var p=global_position
	truck=null
	prone=false
	crouched=false
	global_position=p
	velocity=Vector3(0,-1,-2.5)
	climbing=0
	game.toast("MOVE OFF THE RAMP • USE THE OBSTACLES • Z PRONE",6)

func _physics_process(delta):
	if truck!=null:
		step_on_deck(delta)
		return
	super._physics_process(delta)
	if game.phase!="playing" or truck!=null:return
	if position.z>0:
		# Cap wading speed instead of repeatedly cancelling the acceleration.
		var wading=Vector2(velocity.x,velocity.z).limit_length(4.4)
		velocity.x=wading.x
		velocity.z=wading.y
		if position.z>35:
			position.z=35
			game.toast("Deep water • head for the beach",2)

func step_on_deck(delta:float):
	ViewSmoothing.restore(self)
	if game.phase!="playing":return
	update_view(delta)
	if truck.arrived and not game.intro_active and truck.ramp.rotation.x< -1.2:
		var input=Input.get_vector("move_left","move_right","move_forward","move_back")
		var direction=truck.global_basis.inverse()*(global_basis*Vector3(input.x,0,input.y))
		var next=deck_position+direction*delta*3.2
		next.x=clampf(next.x,-1.12,1.12)
		next.z=clampf(next.z,-7.0,3.0)
		for other in truck.occupants:
			if not other.alive or other.truck!=truck:continue
			var p=truck.to_local(other.position)
			if absf(next.x-p.x)<0.53 and p.z<deck_position.z and next.z<p.z+0.56:next.z=maxf(next.z,p.z+0.56)
		deck_position=next
	deck_position.y=lerpf(0.27,-0.65,clampf((-deck_position.z-5.1)/1.8,0,1))
	global_position=truck.to_global(deck_position)
	rotation.y+=angle_difference(last_truck_yaw,truck.rotation.y)
	last_truck_yaw=truck.rotation.y
	eye_height=lerpf(eye_height,0.66 if prone else (1.02 if crouched else 1.55),delta*10)
	head.position.y=eye_height
	velocity=Vector3.ZERO
	stamina=100
	if deck_position.z< -6.5:dismount()

func _unhandled_input(event):
	if game.intro_active:return
	super._unhandled_input(event)

func dig_stroke():
	# Preserve digging; close shovel work can cut one wire segment if every engineer falls.
	if truck!=null or grenade_time>0 or cooldown>0 or not has_shovel:return
	var ray=PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3.1,1)
	ray.exclude=shot_exclusions()
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.collider is Wire:
		cooldown=0.65
		hit.collider.damage_at(100,hit.position)
		game.sounds.play("clang",-12)
		game.toast("CUTTING WIRE • %d / 16"%int(hit.collider.get_meta("cuts",0)),1)
		return
	super.dig_stroke()
