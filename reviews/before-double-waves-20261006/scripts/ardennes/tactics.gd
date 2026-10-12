extends RefCounted
var book:Dictionary
var groups:Array=[]
var sector:int=0
var sector_names=["AMBUSH HILLS","MIDDLE RIDGE","LOWER RIDGE","ROAD GUNS"]
var sector_areas=[[6,7],[4,5],[2,3],[0,1]]
var commander
var orders_issued:int=0
var successions:int=0
var assigned_count:int=0
var opening_secured:bool=false

func _init():
	book=JSON.parse_string(FileAccess.get_file_as_string("res://scripts/ardennes/tactical_plans.json"))

func initialize(game):
	commander=game.squads[4].leader
	groups=[{"side":-1,"name":"LEFT","squads":[0,1,2,3],"leader":null,"route":[6,4,2,0],"step":0,"area":6},
		{"side":1,"name":"RIGHT","squads":[4,5,6,7],"leader":null,"route":[7,5,3,1],"step":0,"area":7}]

func area_alive(game,area:int)->bool:
	for actor in game.squads[9+area].members:
		if actor.alive:return true
	return false

func assign_dismounted(game):
	var fresh:Array=[]
	var left=0
	var right=0
	for actor in game.friendlies:
		if not actor.alive or actor.truck!=null:continue
		if actor.wing==0:fresh.append(actor)
		elif actor.wing<0:left+=1
		else:right+=1
	if fresh.is_empty():return
	fresh.sort_custom(func(a,b):return a.position.x-game.world.road_x(a.position.z)<b.position.x-game.world.road_x(b.position.z))
	var to_left=clampi(int(ceil((left+right+fresh.size())/2.0))-left,0,fresh.size())
	for i in range(fresh.size()):
		var actor=fresh[i]
		actor.wing=-1 if i<to_left else 1
		var group=groups[0 if actor.wing<0 else 1]
		var selected=group.squads[0]
		var smallest=999
		for id in group.squads:
			var count=game.squads[id].members.filter(func(a):return a.alive and a.truck==null and a.wing==actor.wing).size()
			if count<smallest:
				smallest=count
				selected=id
		game.squads[actor.squad].members.erase(actor)
		if game.squads[actor.squad].leader==actor:game.squads[actor.squad].leader=null
		actor.squad=selected
		actor.order="assault"
		actor.temperament="aggressive"
		actor.leader=false
		actor.state="advance"
		game.squads[selected].members.append(actor)
		assigned_count+=1

func update(game):
	assign_dismounted(game)
	if not opening_secured and not area_alive(game,6) and not area_alive(game,7):
		opening_secured=true
		game.toast("AMBUSH HILLS SECURED • Backtrack along both ridges",7)
		game.say("Left and right sections, work back down the road. Clear every gun site.",6,"SGT. HAYES")
	while sector<3 and sector_areas[sector].all(func(i):return not area_alive(game,i)):
		sector+=1
		orders_issued+=1
	if commander==null or not commander.alive:
		commander=null
		for actor in game.friendlies:
			if actor.alive:
				commander=actor
				successions+=1
				break
	for group in groups:
		if group.leader==null or not group.leader.alive or group.leader.truck!=null or group.leader.wing!=group.side:
			group.leader=null
			for actor in game.friendlies:
				if actor.alive and actor.wing==group.side and actor.truck==null:
					group.leader=actor
					successions+=1
					break
		if opening_secured:
			while group.step<3 and not area_alive(game,group.route[group.step]):group.step+=1
		var previous=group.area
		group.area=group.route[group.step]
		if group.area!=previous:
			orders_issued+=1
			game.toast("%s SECTION • Next hilltop marked"%group.name,4)
		var anchor=game.world.anchors[group.area]
		for j in range(group.squads.size()):
			var sq=game.squads[group.squads[j]]
			var living=sq.members.filter(func(a):return a.alive and a.truck==null and a.wing==group.side)
			if living.is_empty():continue
			if sq.leader==null or not sq.leader.alive or sq.leader.wing!=group.side or sq.leader.truck!=null:
				sq.leader=living[0]
				sq.leader.leader=true
			var plan="support" if j%2==0 else ("flank_left" if group.side<0 else "flank_right")
			if sq.leader.position.distance_to(anchor)<28:plan="clear"
			if sq.get("plan","")!=plan or sq.get("area",-1)!=group.area:orders_issued+=1
			sq.plan=plan
			sq.area=group.area
			sq.side=group.side
			sq.order=book.plans[plan].order
			sq.temperament="aggressive"
			var approach=(anchor-sq.leader.position)
			approach.y=0
			if approach.length_squared()<0.01:approach=Vector3.FORWARD
			approach=approach.normalized()
			var flank=Vector3(group.side*float(j-1.5)*book.spacing.squad_lateral,0,0)
			sq.objective=game.world.on_ground(anchor-approach*book.plans[plan].approach_distance+flank)

func formation_goal(game,actor)->Vector3:
	var sq=game.squads[actor.squad]
	var goal:Vector3=sq.objective
	var slot=0
	for other in sq.members:
		if other==actor:break
		if other.alive and other.truck==null:slot+=1
	var toward=goal-actor.global_position
	toward.y=0
	if toward.length_squared()<0.01:toward=Vector3.FORWARD
	var right=toward.normalized().cross(Vector3.UP)
	return game.world.on_ground(goal+right*(slot%3-1)*book.spacing.column-toward.normalized()*float(slot/3)*book.spacing.row)

func active_areas(game)->Array:
	var result:Array=[]
	for group in groups:
		if area_alive(game,group.area):result.append(group.area)
	return result
