## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/ardennes/armored_panel.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
extends "res://scripts/ardennes/prop.gd"
var integrity:float=6500

## True while the panel is intact: rifle-class bullets are stopped by it, which
## AI line-of-fire checks use (destroyed panels become openings).
func stops_small_arms()->bool:return not destroyed

## Registers a hit: wear grows, a bullet mark is drawn, the owning vehicle is
## told, and integrity falls (50% of explosive damage, 4% of other damage).
## Destroyed at zero integrity. Returns false only if already destroyed.
## [param amount] damage points. [param point] world impact point.
## [param _radius] ignored here. [param explosive] true for blasts.
func damage_at(amount:float,point:Vector3,_radius:float=0.24,explosive:bool=false)->bool:
	if destroyed:return false
	wear+=amount
	bullet_mark(point)
	if truck_owner!=null:truck_owner.receive_part_damage(amount,point,explosive,self)
	integrity-=amount*(0.5 if explosive else 0.04)
	if integrity<=0:demolish()
	return true
