## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/ardennes/tactics.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Squad-level orders for the Ardennes friendly (player's) side: a small
## commander AI that sends the player's eight rifle squads up both ridges in
## sequence, clearing the German gun sites.
##
## Role: owned by the Ardennes battle controller (battle.gd), which calls
## initialize() once and update() periodically, and formation_goal() for each
## soldier's position. It writes orders to squads (game.squads[i]: plan, area,
## side, order, temperament, objective, leader, members) and to soldiers
## (wing, squad, order, state), which actor.gd then acts on.
## Data: tuning (plan names, approach distances, spacing) is read from
## tactical_plans.json beside this file, so it can be tweaked without code.
## Geography: eight numbered hill areas; the road runs down the valley and
## the left (-1) and right (+1) sections each work their ridge from the
## ambush hills back down toward the road guns.
extends RefCounted

## Parsed tactical_plans.json: `plans` (name -> order, approach_distance) and `spacing` (squad_lateral, column, row).
var book:Dictionary

## The two assault groups ("LEFT" and "RIGHT"): their squad ids, current
## leader, route (area ids in order) and the step along that route.
var groups:Array=[]

## Progress along the road (0..3): index into sector_names.
var sector:int=0

## Human names of the four stages, from the first ambush hills to the road guns.
var sector_names=["AMBUSH HILLS","MIDDLE RIDGE","LOWER RIDGE","ROAD GUNS"]

## Area ids belonging to each sector; a sector is finished when all are cleared.
var sector_areas=[[6,7],[4,5],[2,3],[0,1]]

## The soldier acting as overall commander: leader of squad 4 (the player's own truck squad, voiced as "SGT. HAYES") at start; falls to the next living soldier on death.
var commander

## Counter of orders changed; used by tests.
var orders_issued:int=0

## Counter of leader replacements after deaths; used by tests.
var successions:int=0

## Soldiers moved into a ridge group after leaving their truck.
var assigned_count:int=0

## True once both ambush-hill areas (6 and 7) are cleared; unlocks the backtrack phase.
var opening_secured:bool=false

## Loads the plan book from tactical_plans.json.
func _init():
	book=JSON.parse_string(FileAccess.get_file_as_string("res://scripts/ardennes/tactical_plans.json"))

## Builds the two groups and picks the commander. [param game] the battle controller.
## Group `route` lists the areas to take in order (left: 6,4,2,0; right: 7,5,3,1).
func initialize(game):
	commander=game.squads[4].leader
	groups=[{"side":-1,"name":"LEFT","squads":[0,1,2,3],"leader":null,"route":[6,4,2,0],"step":0,"area":6},
		{"side":1,"name":"RIGHT","squads":[4,5,6,7],"leader":null,"route":[7,5,3,1],"step":0,"area":7}]

## True if any German in guard area `area` is still alive (squads 9+area are the defenders).
## [param game] battle controller. [param area] area id 0..7.
func area_alive(game,area:int)->bool:
	for actor in game.squads[9+area].members:
		if actor.alive:return true
	return false

## Gives each newly dismounted soldier (wing 0, off a truck) to the left or
## right group: sorts them by how far they are from the road centre, sends the
## outer half left and the rest right so both groups stay balanced, then puts
## each in the group's smallest squad with the "assault" order.
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

	# Left-to-right by distance from the road line, so the split is spatial and
	# groups do not cross each other.
	fresh.sort_custom(func(a,b):return a.position.x-game.world.road_x(a.position.z)<b.position.x-game.world.road_x(b.position.z))

	# Number to send left so that left and right end up as equal as possible.
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

## Main command step (call about once per second): assigns new soldiers,
## announces the opening objective, advances the sector, replaces dead
## commanders and leaders, advances each group to its next uncleared area and
## writes the plan/objective for every squad in the group.
## Each squad alternates support / flank / clear roles: even-numbered squads
## give covering fire, odd ones flank to their side, and when the leader is
## within 28 m of the area they all switch to "clear".
func update(game):
	assign_dismounted(game)

	# First milestone: when both ambush hills are clear, announce the plan.
	if not opening_secured and not area_alive(game,6) and not area_alive(game,7):
		opening_secured=true
		game.toast("AMBUSH HILLS SECURED • Backtrack along both ridges",7)
		game.say("Left and right sections, work back down the road. Clear every gun site.",6,"SGT. HAYES")

	# Advance the displayed sector as soon as all its areas are cleared.
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

		# The backtrack phase starts only after the opening is secured; groups skip already-cleared areas.
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

			# Support squads stay back, flankers swing to their side; the order in
			# the squad list (j) decides the role so every group has a mix.
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

			# Lateral spacing so the four squads of one group arrive side by side
			# instead of stacking on one point.
			var flank=Vector3(group.side*float(j-1.5)*book.spacing.squad_lateral,0,0)
			sq.objective=game.world.on_ground(anchor-approach*book.plans[plan].approach_distance+flank)

## Position a soldier should walk to in its squad's formation around the squad objective.
## Soldiers fill slots in order (the alive, not-in-truck members before them);
## three per row, spaced by the plan book's column/row distances, with rows
## behind the objective along the direction of approach.
## [param game] battle controller. [param actor] the soldier.
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

## Areas still held by the Germans that a group is currently assigned to
## (used by the HUD and map). Returns an array of area ids.
func active_areas(game)->Array:
	var result:Array=[]
	for group in groups:
		if area_alive(game,group.area):result.append(group.area)
	return result
