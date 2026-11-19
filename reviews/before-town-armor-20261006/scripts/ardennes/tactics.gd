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

# Names of the sectors for HUD and messages.
var sector_names=["AMBUSH HILLS","MIDDLE RIDGE","LOWER RIDGE","ROAD GUNS"]

# Which enemy gun areas belong to each sector, from the ambush hills (6,7) down to the road guns (0,1).
var sector_areas=[[6,7],[4,5],[2,3],[0,1]]

# Overall commander; replaced automatically when he dies.
var commander

# Statistics counters used by tests and the debug report.
var orders_issued:int=0
var successions:int=0
var assigned_count:int=0

# True once both ambush-hill areas (6 and 7) are cleared.
var opening_secured:bool=false

## Load the tactical plan table from disk.
func _init():
	book=JSON.parse_string(FileAccess.get_file_as_string("res://scripts/ardennes/tactical_plans.json"))

## Create the two wing groups after the squads exist.
## @param game The battle controller (provides squads).
func initialize(game):
	# Squad 4's leader is the overall commander.
	commander=game.squads[4].leader
	# Each wing: squads 0-3 go left, 4-7 right; routes visit areas from the ambush hill back down the road (6,4,2,0 / 7,5,3,1).
	groups=[{"side":-1,"name":"LEFT","squads":[0,1,2,3],"leader":null,"route":[6,4,2,0],"step":0,"area":6},
		{"side":1,"name":"RIGHT","squads":[4,5,6,7],"leader":null,"route":[7,5,3,1],"step":0,"area":7}]

## Whether any member of an enemy gun-site squad (id 9 + area) is still alive.
## @param area Area index 0..7.
func area_alive(game,area:int)->bool:
	for actor in game.squads[9+area].members:
		if actor.alive:return true
	return false

## Put newly dismounted soldiers into a wing and squad.
##
## Soldiers who left their trucks have `wing == 0`. They are split so both wings stay
## roughly equal, then each joins the squad of its wing with the fewest living members.
func assign_dismounted(game):
	var fresh:Array=[]
	# Newly dismounted soldiers waiting for an assignment.
	var left=0
	# Counts of soldiers already assigned to each wing, for balancing.
	var right=0
	for actor in game.friendlies:
		if not actor.alive or actor.truck!=null:continue
		if actor.wing==0:fresh.append(actor)
		elif actor.wing<0:left+=1
		else:right+=1
	# Sorted by position relative to the road so the left half of the line goes to the left wing.
	if fresh.is_empty():return
	fresh.sort_custom(func(a,b):return a.position.x-game.world.road_x(a.position.z)<b.position.x-game.world.road_x(b.position.z))
	# Number of new soldiers to send left so the wings end up equal (rounded up).
	var to_left=clampi(int(ceil((left+right+fresh.size())/2.0))-left,0,fresh.size())
	for i in range(fresh.size()):
		var actor=fresh[i]
		actor.wing=-1 if i<to_left else 1
		var group=groups[0 if actor.wing<0 else 1]
		# Pick the squad with the fewest living, dismounted members of that wing.
		var selected=group.squads[0]
		var smallest=999
		for id in group.squads:
			var count=game.squads[id].members.filter(func(a):return a.alive and a.truck==null and a.wing==actor.wing).size()
			if count<smallest:
				smallest=count
				selected=id
		# Remove from the old (truck) squad, handing over leadership if needed.
		game.squads[actor.squad].members.erase(actor)
		if game.squads[actor.squad].leader==actor:game.squads[actor.squad].leader=null
		actor.squad=selected
		# New infantry orders: assault aggressively and advance toward the objective.
		actor.order="assault"
		actor.temperament="aggressive"
		actor.leader=false
		actor.state="advance"
		game.squads[selected].members.append(actor)
		assigned_count+=1

## Run one tactics tick: assign soldiers, advance sector, pick leaders and issue squad orders.
## @param game The battle controller.
func update(game):
	assign_dismounted(game)
	# Opening phase ends when both ambush hills are cleared; then the wings may march along their routes.
	if not opening_secured and not area_alive(game,6) and not area_alive(game,7):
		opening_secured=true
		game.toast("AMBUSH HILLS SECURED • Backtrack along both ridges",7)
		game.say("Left and right sections, work back down the road. Clear every gun site.",6,"SGT. HAYES")
	# Advance the current sector when all its areas are cleared.
	while sector<3 and sector_areas[sector].all(func(i):return not area_alive(game,i)):
		sector+=1
		orders_issued+=1
	# Dead commander: choose the first living friendly.
	if commander==null or not commander.alive:
		commander=null
		for actor in game.friendlies:
			if actor.alive:
				commander=actor
				successions+=1
				break
	for group in groups:
		# Group leader is lost if dead, mounted or no longer on this wing; replace him.
		if group.leader==null or not group.leader.alive or group.leader.truck!=null or group.leader.wing!=group.side:
			group.leader=null
			for actor in game.friendlies:
				if actor.alive and actor.wing==group.side and actor.truck==null:
					group.leader=actor
					successions+=1
					break
		# Advance along the route past cleared areas only after the opening is done.
		if opening_secured:
			while group.step<3 and not area_alive(game,group.route[group.step]):group.step+=1
		var previous=group.area
		group.area=group.route[group.step]
		if group.area!=previous:
			# Announce the next objective once.
			orders_issued+=1
			game.toast("%s SECTION • Next hilltop marked"%group.name,4)
		var anchor=game.world.anchors[group.area]
		for j in range(group.squads.size()):
			var sq=game.squads[group.squads[j]]
			# Only soldiers on foot and on this wing take part in squad orders.
			var living=sq.members.filter(func(a):return a.alive and a.truck==null and a.wing==group.side)
			if living.is_empty():continue
			# Make sure each squad has a valid living leader.
			if sq.leader==null or not sq.leader.alive or sq.leader.wing!=group.side or sq.leader.truck!=null:
				sq.leader=living[0]
				sq.leader.leader=true
			# Alternate squads support and flank: even squads support, odd ones flank toward their own side.
			var plan="support" if j%2==0 else ("flank_left" if group.side<0 else "flank_right")
			# Within 28 m of the objective the squad switches to clearing it.
			if sq.leader.position.distance_to(anchor)<28:plan="clear"
			# Count an order change only when plan or area actually changed.
			if sq.get("plan","")!=plan or sq.get("area",-1)!=group.area:orders_issued+=1
			sq.plan=plan
			sq.area=group.area
			sq.side=group.side
			sq.order=book.plans[plan].order
			sq.temperament="aggressive"
			# Objective sits the plan's approach_distance short of the target along the approach direction, offset sideways per squad so squads spread out.
			var approach=(anchor-sq.leader.position)
			approach.y=0
			# Fall back to forward when the leader is exactly on the anchor, avoiding a zero-length vector.
			if approach.length_squared()<0.01:approach=Vector3.FORWARD
			approach=approach.normalized()
			var flank=Vector3(group.side*float(j-1.5)*book.spacing.squad_lateral,0,0)
			sq.objective=game.world.on_ground(anchor-approach*book.plans[plan].approach_distance+flank)

## Choose a formation slot for one soldier near his squad objective.
## @param game The battle controller.
## @param actor The soldier.
## @return A world position on the ground for the soldier's slot: columns of three, rows behind each other.
func formation_goal(game,actor)->Vector3:
	var sq=game.squads[actor.squad]
	var goal:Vector3=sq.objective
	var slot=0
	# Slot = number of living, dismounted members listed before this actor.
	for other in sq.members:
		if other==actor:break
		if other.alive and other.truck==null:slot+=1
	# Direction the squad faces, flattened onto the ground plane.
	var toward=goal-actor.global_position
	toward.y=0
	if toward.length_squared()<0.01:toward=Vector3.FORWARD
	var right=toward.normalized().cross(Vector3.UP)
	# column: sideways spacing between slots; row: spacing between rows behind the front.
	return game.world.on_ground(goal+right*(slot%3-1)*book.spacing.column-toward.normalized()*float(slot/3)*book.spacing.row)

## Enemy areas still defended by someone and currently targeted by a wing.
## @return Area indices (0..7).
func active_areas(game)->Array:
	var result:Array=[]
	for group in groups:
		if area_alive(game,group.area):result.append(group.area)
	return result
