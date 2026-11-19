# ==============================================================================
# Program: tactics.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for tactics.gd.
# ==============================================================================
## High-level squad AI ("tactics") for the Ardennes friendly forces.
##
## Splits dismounted friendlies into a LEFT and RIGHT wing (two groups of four
## squads), walks each wing along a route of hilltop gun areas and sets per-squad
## orders (support, flank, clear) from the JSON "book" of plans. Also handles
## leader succession when leaders die. Used by the battle script, which calls `update()`
## each tactics tick and `formation_goal()` per actor.
extends RefCounted

# Parsed tactical_plans.json: `plans` (order and approach_distance per plan) and `spacing` (squad_lateral, column, row).
var book:Dictionary

# Two dictionaries (LEFT/RIGHT): side (-1/1), name, squads (ids), leader, route (area ids), step (index into route), area (current target).
var groups:Array=[]

# Index of the current objective sector (0..3); advances when its areas are cleared.
var sector:int=0
var sector_names=["ROADBLOCK","FIR RIDGE","UPPER DUGOUTS"]
var sector_areas=[[0,1,2],[3,4,5],[6,7]]

# Overall commander; replaced automatically when he dies.
var commander

# Statistics counters used by tests and the debug report.
var orders_issued:int=0
var successions:int=0

## Load the tactical plan table from disk.
func _init():
	book=JSON.parse_string(FileAccess.get_file_as_string("res://scripts/ardennes/tactical_plans.json"))

## Create the two wing groups after the squads exist.
## @param game The battle controller (provides squads).
func initialize(game):
	# Squad 4's leader is the overall commander.
	commander=game.squads[4].leader
	for i in range(3):groups.append({"squads":[i*3,i*3+1,i*3+2],"leader":game.squads[i*3+1].leader,"area":i})

## Whether any member of an enemy gun-site squad (id 9 + area) is still alive.
## @param area Area index 0..7.
func area_alive(game,area:int)->bool:
	for actor in game.squads[9+area].members:
		if actor.alive:return true
	return false

## Run one tactics tick: assign soldiers, advance sector, pick leaders and issue squad orders.
## @param game The battle controller.
func update(game):
	while sector<2 and sector_areas[sector].all(func(i):return not area_alive(game,i)):
		sector+=1
		game.toast("SECTOR SECURED • Advance to "+sector_names[sector],7)
		game.say("Keep moving. Next defensive area is marked.",4,"SGT. HAYES")
	# Dead commander: choose the first living friendly.
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
			# Count an order change only when plan or area actually changed.
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

## Choose a formation slot for one soldier near his squad objective.
## @param game The battle controller.
## @param actor The soldier.
## @return A world position on the ground for the soldier's slot: columns of three, rows behind each other.
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
