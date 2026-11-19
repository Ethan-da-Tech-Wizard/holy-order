## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/ardennes/ammo_pack.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## The player's spare-ammunition inventory for the Ardennes and Omaha missions.
##
## Instead of a single number per weapon, ammunition is held as physical
## containers (magazines, clips, belts) with limited belt/pack space and weight,
## so carrying a belt of machine-gun ammunition leaves less room for
## rifle clips. player.gd owns one instance (`ammo_pack`); AmmoBundle.take(),
## reload code and the HUD call into it.
## A container is a Dictionary {kind: String, rounds: int} and `kind` is a key
## of FEEDS (the weapon family it feeds).
extends RefCounted
# Scenario carry limits: 24 space units / 7.5 kg of spare ammunition. These are
# a playable belt-and-pack allowance, not a claim that every soldier had this load.

## Total "space units" the pack holds (24); each feed type costs FEEDS[kind].space per container.
const SPACE_LIMIT:float=24.0

## Maximum weight in kg of spare ammunition (7.5) including empty containers.
const WEIGHT_LIMIT:float=7.5

## Feed catalogue, one row per weapon family. Columns: label (HUD text),
## rounds (capacity of one container), space (units one container takes),
## empty_kg (container weight), round_kg (weight per round, from the real
## cartridge mass: .30-06 about 27 g, 7.92 mm 26 g, 9 mm 12 g, .50 BMG 115 g),
## max (the most rounds of this kind the pack may hold, for balance), and
## caliber (rounds of the same caliber are interchangeable between weapons).
const FEEDS={
	"carbine":{"label":"15-round M1 Carbine magazine","rounds":15,"space":1.5,"empty_kg":0.09,"round_kg":0.013,"max":150,"caliber":"30carbine"},
	"m1919":{"label":"50-round .30-06 belt","rounds":50,"space":6.0,"empty_kg":0.15,"round_kg":0.027,"max":200,"caliber":"30-06"},
	"flamethrower":{"label":"Flamethrower fuel tank","rounds":100,"space":24.0,"empty_kg":4.0,"round_kg":0.03,"max":100,"caliber":"fuel"},
	"bar":{"label":"20-round BAR magazine","rounds":20,"space":3.0,"empty_kg":0.20,"round_kg":0.027,"max":160,"caliber":"30-06"},
	"garand":{"label":"8-round M1 en-bloc clip","rounds":8,"space":1.0,"empty_kg":0.025,"round_kg":0.027,"max":128,"caliber":"30-06"},
	"kar98":{"label":"5-round Mauser stripper clip","rounds":5,"space":0.5,"empty_kg":0.008,"round_kg":0.026,"max":120,"caliber":"792"},
	"g43":{"label":"10-round G43 magazine","rounds":10,"space":2.0,"empty_kg":0.16,"round_kg":0.026,"max":120,"caliber":"792"},
	"mp40":{"label":"32-round MP40 magazine","rounds":32,"space":3.0,"empty_kg":0.20,"round_kg":0.012,"max":192,"caliber":"9mm"},
	"mg34":{"label":"50-round 7.92 mm belt","rounds":50,"space":6.0,"empty_kg":0.15,"round_kg":0.026,"max":200,"caliber":"792"},
	"mg42":{"label":"50-round 7.92 mm belt","rounds":50,"space":6.0,"empty_kg":0.15,"round_kg":0.026,"max":200,"caliber":"792"},
	"m2":{"label":"100-round .50 belt","rounds":100,"space":15.0,"empty_kg":0.45,"round_kg":0.115,"max":100,"caliber":"50bmg"}
}

## Containers currently carried.
var containers:Array=[]

## Sum of the space units of all carried containers.
func space_used()->float:
	var n=0.0
	for item in containers:n+=FEEDS[item.kind].space
	return n

## Weight in kg of all containers plus their rounds.
func weight_used()->float:
	var n=0.0
	for item in containers:n+=FEEDS[item.kind].empty_kg+item.rounds*FEEDS[item.kind].round_kg
	return n

## Total rounds of one caliber (e.g. "30-06") across all containers.
## [param caliber] a FEEDS caliber string.
func rounds_for(caliber:String)->int:
	var n=0
	for item in containers:
		if FEEDS[item.kind].caliber==caliber:n+=item.rounds
	return n

## Total rounds in containers of one kind.
## [param kind] a FEEDS key.
func rounds_of(kind:String)->int:
	var n=0
	for item in containers:
		if item.kind==kind:n+=item.rounds
	return n

## Adds up to `requested` rounds of `kind` and returns how many were accepted.
## First tops up existing containers of that kind, then opens new ones while
## both space and weight limits allow. Rounds that do not fit are left out so
## the caller can leave them on the ground.
## [param kind] FEEDS key. [param requested] rounds offered (<= 0 returns 0).
func add_rounds(kind:String,requested:int)->int:
	if requested<=0:return 0
	var spec=FEEDS[kind]
	var remaining=mini(requested,spec.max-rounds_of(kind))
	var accepted=0
	for item in containers:
		if item.kind!=kind:continue

		# How many more rounds the weight allowance leaves (the tiny +0.0001
		# avoids a float rounding error losing one round).
		var by_weight=maxi(0,floori((WEIGHT_LIMIT-weight_used())/spec.round_kg+0.0001))
		var count=mini(remaining,mini(spec.rounds-item.rounds,by_weight))
		item.rounds+=count
		remaining-=count
		accepted+=count

	# Open new containers; a new one also adds its own empty weight.
	while remaining>0 and space_used()+spec.space<=SPACE_LIMIT:
		var by_weight=maxi(0,floori((WEIGHT_LIMIT-weight_used()-spec.empty_kg)/spec.round_kg+0.0001))
		var count=mini(remaining,mini(spec.rounds,by_weight))
		if count<=0:break
		containers.append({"kind":kind,"rounds":count})
		remaining-=count
		accepted+=count
	return accepted

## Removes up to `count` rounds of a caliber and returns how many were removed.
## [param caliber] caliber string. [param count] wanted rounds.
## [param preferred] container kind to empty first (the weapon in hand), so
## other weapons' ammunition is only used when needed. Emptied containers are discarded.
func take_rounds(caliber:String,count:int,preferred:String="")->int:
	var remaining=count
	var order=containers.duplicate()
	order.sort_custom(func(a,b):return int(a.kind==preferred)>int(b.kind==preferred))
	for item in order:
		if FEEDS[item.kind].caliber!=caliber:continue
		var n=mini(item.rounds,remaining)
		item.rounds-=n
		remaining-=n
		if item.rounds==0:containers.erase(item)
		if remaining==0:break
	return count-remaining

## Sets the total of a caliber to `value` by adding or removing rounds. Used
## by cheat/test code and scenario setup.
## [param kind] container type used when rounds must be added.
func adjust(caliber:String,value:int,kind:String):
	var existing=rounds_for(caliber)
	if value<existing:take_rounds(caliber,existing-maxi(0,value),kind)
	elif value>existing:add_rounds(kind,value-existing)

## Returns one HUD line per kind: "N x label: rounds / space".
func description()->Array[String]:
	var lines:Array[String]=[]
	var totals:Dictionary={}
	for item in containers:
		if not totals.has(item.kind):totals[item.kind]={"count":0,"rounds":0}
		totals[item.kind].count+=1
		totals[item.kind].rounds+=item.rounds
	for kind in totals:
		lines.append("%d × %s: %d rounds / %.1f space"%[totals[kind].count,FEEDS[kind].label,totals[kind].rounds,totals[kind].count*FEEDS[kind].space])
	return lines
