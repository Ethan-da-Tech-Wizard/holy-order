extends RefCounted
var book:Dictionary
var groups:Array=[]
var sector:int=0
var sector_names=["ROADBLOCK","FIR RIDGE","UPPER DUGOUTS"]
var sector_areas=[[0,1,2],[3,4,5],[6,7]]
var commander
var orders_issued:int=0
var successions:int=0

func _init():
	book=JSON.parse_string(FileAccess.get_file_as_string("res://scripts/ardennes/tactical_plans.json"))

func initialize(game):
	commander=game.squads[4].leader
	for i in range(3):groups.append({"squads":[i*3,i*3+1,i*3+2],"leader":game.squads[i*3+1].leader,"area":i})

func area_alive(game,area:int)->bool:
	for actor in game.squads[9+area].members:
		if actor.alive:return true
	return false

func update(game):
	while sector<2 and sector_areas[sector].all(func(i):return not area_alive(game,i)):
		sector+=1
		game.toast("SECTOR SECURED • Advance to "+sector_names[sector],7)
		game.say("Keep moving. Next defensive area is marked.",4,"SGT. HAYES")
	if commander==null or not commander.alive:
		commander=null
		for sq in game.squads.slice(0,9):
			if sq.leader!=null and sq.leader.alive:
				commander=sq.leader
				successions+=1
				break
	var assigned:Array=[]
	for group in groups:
		if group.leader==null or not group.leader.alive:
			group.leader=null
			for index in group.squads:
				var leader=game.squads[index].leader
				if leader!=null and leader.alive:
					group.leader=leader
					successions+=1
					break
		if group.leader==null:continue
		if not area_alive(game,group.area) or group.area in assigned or group.area not in sector_areas[sector]:
			var best=INF
			for area in sector_areas[sector]:
				if not area_alive(game,area):continue
				var score=group.leader.position.distance_squared_to(game.world.anchors[area])+(50000 if area in assigned else 0)
				if score<best:
					best=score
					group.area=area
		assigned.append(group.area)
		var anchor=game.world.anchors[group.area]
		for j in range(group.squads.size()):
			var sq=game.squads[group.squads[j]]
			var plan=["support","flank_left","flank_right"][j]
			if sq.leader!=null and sq.leader.position.distance_to(anchor)<32:plan="clear"
			if sq.get("plan","")!=plan or sq.get("area",-1)!=group.area:orders_issued+=1
			sq.plan=plan
			sq.area=group.area
			sq.order=book.plans[plan].order
			sq.temperament="cautious" if plan=="support" else "aggressive"
			var direction=(anchor-sq.anchor).normalized()
			direction.y=0
			direction=direction.normalized()
			var right=direction.cross(Vector3.UP)
			var offset=book.plans[plan].offset
			sq.objective=game.world.on_ground(anchor+right*float(offset[0])+direction*float(offset[1]))

func formation_goal(game,actor)->Vector3:
	var sq=game.squads[actor.squad]
	var goal:Vector3=sq.objective
	var members:Array=sq.members
	var slot=members.find(actor)
	var toward=(goal-sq.anchor).normalized()
	toward.y=0
	var right=toward.cross(Vector3.UP).normalized()
	var spacing=4.5 if sq.get("plan","")=="support" else 3.8
	return game.world.on_ground(goal+right*(slot%4-1.5)*spacing-toward*float(slot/4)*spacing)
