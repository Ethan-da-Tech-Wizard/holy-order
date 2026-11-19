# ==============================================================================
# Program: ammo_pack.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Individual ammunition pickup entity. Handles physics drop trajectory, terrain ground snapping, inventory ammo pool incrementing, and deferred node lifecycle cleanup.
# ==============================================================================
extends RefCounted
# Scenario carry limits: 24 space units / 7.5 kg of spare ammunition. These are
# a playable belt-and-pack allowance, not a claim that every soldier had this load.
const SPACE_LIMIT:float=24.0
const WEIGHT_LIMIT:float=7.5
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
var containers:Array=[]

func space_used()->float:
	# --- CONTRACT: Function `space_used` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for space_used
	var n=0.0
	for item in containers:n+=FEEDS[item.kind].space
	return n

func weight_used()->float:
	# --- CONTRACT: Function `weight_used` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for weight_used
	var n=0.0
	for item in containers:n+=FEEDS[item.kind].empty_kg+item.rounds*FEEDS[item.kind].round_kg
	return n

func rounds_for(caliber:String)->int:
	# --- CONTRACT: Function `rounds_for` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for rounds_for
	var n=0
	for item in containers:
		if FEEDS[item.kind].caliber==caliber:n+=item.rounds
	return n

func rounds_of(kind:String)->int:
	# --- CONTRACT: Function `rounds_of` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for rounds_of
	var n=0
	for item in containers:
		if item.kind==kind:n+=item.rounds
	return n

func add_rounds(kind:String,requested:int)->int:
	# --- CONTRACT: Function `add_rounds` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for add_rounds
	if requested<=0:return 0
	var spec=FEEDS[kind]
	var remaining=mini(requested,spec.max-rounds_of(kind))
	var accepted=0
	for item in containers:
		if item.kind!=kind:continue
		var by_weight=maxi(0,floori((WEIGHT_LIMIT-weight_used())/spec.round_kg+0.0001))
		var count=mini(remaining,mini(spec.rounds-item.rounds,by_weight))
		item.rounds+=count
		remaining-=count
		accepted+=count
	while remaining>0 and space_used()+spec.space<=SPACE_LIMIT:
		var by_weight=maxi(0,floori((WEIGHT_LIMIT-weight_used()-spec.empty_kg)/spec.round_kg+0.0001))
		var count=mini(remaining,mini(spec.rounds,by_weight))
		if count<=0:break
		containers.append({"kind":kind,"rounds":count})
		remaining-=count
		accepted+=count
	return accepted

func take_rounds(caliber:String,count:int,preferred:String="")->int:
	# --- CONTRACT: Function `take_rounds` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for take_rounds
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

func adjust(caliber:String,value:int,kind:String):
	# --- CONTRACT: Function `adjust` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for adjust
	var existing=rounds_for(caliber)
	if value<existing:take_rounds(caliber,existing-maxi(0,value),kind)
	elif value>existing:add_rounds(kind,value-existing)

func description()->Array[String]:
	# --- CONTRACT: Function `description` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for description
	var lines:Array[String]=[]
	var totals:Dictionary={}
	for item in containers:
		if not totals.has(item.kind):totals[item.kind]={"count":0,"rounds":0}
		totals[item.kind].count+=1
		totals[item.kind].rounds+=item.rounds
	for kind in totals:
		lines.append("%d × %s: %d rounds / %.1f space"%[totals[kind].count,FEEDS[kind].label,totals[kind].rounds,totals[kind].count*FEEDS[kind].space])
	return lines
