# ==============================================================================
# Program: ammo_pack.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for ammo_pack.gd.
# ==============================================================================
## The player's spare-ammunition inventory with space and weight limits.
##
## Ammunition is stored as containers (magazines, clips, belts), each a dict
## `{kind, rounds}`. `FEEDS` defines each container type. Adding rounds fills partial
## containers first, then opens new ones until either the space or the weight limit is hit.
## Used by the player (reloads, HUD) and by ammo_bundle.gd pickups.
extends RefCounted

# Scenario carry limits: 24 space units / 7.5 kg of spare ammunition. These are
# a playable belt-and-pack allowance, not a claim that every soldier had this load.
# Scenario carry limits: 24 space units / 7.5 kg of spare ammunition. These are
# a playable belt-and-pack allowance, not a claim that every soldier had this load.
const SPACE_LIMIT:float=24.0
const WEIGHT_LIMIT:float=7.5

# Per-kind container table. Fields: label (HUD text), rounds (capacity per container),
# space (pack units one container uses), empty_kg (container weight), round_kg (weight per
# round), max (most rounds of this kind that can be carried in total), caliber (rounds that
# share a caliber are interchangeable for reloading across weapons).
const FEEDS={
	"bar":{"label":"20-round BAR magazine","rounds":20,"space":3.0,"empty_kg":0.20,"round_kg":0.027,"max":160,"caliber":"30-06"},
	"garand":{"label":"8-round M1 en-bloc clip","rounds":8,"space":1.0,"empty_kg":0.025,"round_kg":0.027,"max":128,"caliber":"30-06"},
	"kar98":{"label":"5-round Mauser stripper clip","rounds":5,"space":0.5,"empty_kg":0.008,"round_kg":0.026,"max":120,"caliber":"792"},
	"g43":{"label":"10-round G43 magazine","rounds":10,"space":2.0,"empty_kg":0.16,"round_kg":0.026,"max":120,"caliber":"792"},
	"mp40":{"label":"32-round MP40 magazine","rounds":32,"space":3.0,"empty_kg":0.20,"round_kg":0.012,"max":192,"caliber":"9mm"},
	"mg34":{"label":"50-round 7.92 mm belt","rounds":50,"space":6.0,"empty_kg":0.15,"round_kg":0.026,"max":200,"caliber":"792"},
	"mg42":{"label":"50-round 7.92 mm belt","rounds":50,"space":6.0,"empty_kg":0.15,"round_kg":0.026,"max":200,"caliber":"792"},
	"m2":{"label":"100-round .50 belt","rounds":100,"space":15.0,"empty_kg":0.45,"round_kg":0.115,"max":100,"caliber":"50bmg"}
}

# Live containers; each entry is {"kind": FEEDS key, "rounds": int}.
var containers:Array=[]

## @return Pack space currently used, in the same units as SPACE_LIMIT.
func space_used()->float:
	var n=0.0
	for item in containers:n+=FEEDS[item.kind].space
	return n

## @return Total weight in kg: empty containers plus loaded rounds.
func weight_used()->float:
	var n=0.0
	for item in containers:n+=FEEDS[item.kind].empty_kg+item.rounds*FEEDS[item.kind].round_kg
	return n

## Count rounds of a caliber across weapon types.
## @param caliber FEEDS caliber string, e.g. "30-06".
func rounds_for(caliber:String)->int:
	var n=0
	for item in containers:
		if FEEDS[item.kind].caliber==caliber:n+=item.rounds
	return n

## Count rounds of exactly one container kind.
func rounds_of(kind:String)->int:
	var n=0
	for item in containers:
		if item.kind==kind:n+=item.rounds
	return n

## Add up to `requested` rounds of `kind`, respecting capacity, space and weight.
## @return The number of rounds actually accepted (may be less than requested or 0).
func add_rounds(kind:String,requested:int)->int:
	if requested<=0:return 0
	var spec=FEEDS[kind]
	# Per-kind cap first: the pack never carries more than `max` rounds of one kind.
	var remaining=mini(requested,spec.max-rounds_of(kind))
	var accepted=0
	# Top up existing partly-filled containers before opening new ones.
	for item in containers:
		if item.kind!=kind:continue
		# Rounds the remaining weight budget allows; the +0.0001 stops float error rounding down a whole round.
		var by_weight=maxi(0,floori((WEIGHT_LIMIT-weight_used())/spec.round_kg+0.0001))
		var count=mini(remaining,mini(spec.rounds-item.rounds,by_weight))
		item.rounds+=count
		remaining-=count
		accepted+=count
	# Open new containers while there is pack space; each costs its empty weight too.
	while remaining>0 and space_used()+spec.space<=SPACE_LIMIT:
		var by_weight=maxi(0,floori((WEIGHT_LIMIT-weight_used()-spec.empty_kg)/spec.round_kg+0.0001))
		var count=mini(remaining,mini(spec.rounds,by_weight))
		# Out of weight budget: stop instead of looping forever.
		if count<=0:break
		containers.append({"kind":kind,"rounds":count})
		remaining-=count
		accepted+=count
	return accepted

## Remove up to `count` rounds of a caliber, preferring one container kind.
## @param preferred Kind to drain first (usually the weapon in hand).
## @return Rounds removed.
func take_rounds(caliber:String,count:int,preferred:String="")->int:
	var remaining=count
	var order=containers.duplicate()
	# Sort so the preferred kind comes first; other compatible kinds supply the remainder.
	order.sort_custom(func(a,b):return int(a.kind==preferred)>int(b.kind==preferred))
	for item in order:
		if FEEDS[item.kind].caliber!=caliber:continue
		var n=mini(item.rounds,remaining)
		item.rounds-=n
		remaining-=n
		# Drop empty containers so they stop using space and weight.
		if item.rounds==0:containers.erase(item)
		if remaining==0:break
	return count-remaining

## Force the carried rounds of a caliber to `value` (used by tests and starting loadouts).
func adjust(caliber:String,value:int,kind:String):
	var existing=rounds_for(caliber)
	if value<existing:take_rounds(caliber,existing-maxi(0,value),kind)
	elif value>existing:add_rounds(kind,value-existing)

## Build HUD lines grouped by container kind.
## @return Strings like "3 × 8-round M1 en-bloc clip: 24 rounds / 3.0 space".
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
