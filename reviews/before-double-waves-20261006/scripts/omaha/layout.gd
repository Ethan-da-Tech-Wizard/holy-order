# ==============================================================================
# Program: layout.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for layout.gd.
# ==============================================================================
## Fixed coordinate layout of the Omaha beach assault map.
##
## Pure constants plus two lookup helpers, used by the boat, wire, village and
## test scripts so every object agrees on where the beach, seawall, bunker,
## trenches and village sit. The z axis runs inland from the landing fleet:
## the waterline is near 0 and defences sit at increasingly negative z.
## x is across the beach, centred on 0. Nothing here is instantiated.
extends RefCounted

# Gameplay distances in metres. Troops, weapons and fortifications retain their scale.
# Beach footprint: WIDTH across the shore, DEPTH from the sea to the church.
# Gameplay distances in metres. Troops, weapons and fortifications retain their scale.
const WIDTH:float=288.0
const DEPTH:float=528.0

# Metres between landing craft in the fleet line, so boats do not overlap on spawn.
const FLEET_SPACING:float=24.0

# x positions of the three landing lanes (left, centre, right), 72 m apart.
const ASSAULT_LANES=[-72.0,0.0,72.0]

# Eight defence sectors of 48 m centred on these x values (see sector_for()).
const SECTORS=[-168.0,-120.0,-72.0,-24.0,24.0,72.0,120.0,168.0]

# z of each barbed wire row on the beach, nearest to the sea first.
const WIRE_ROWS=[-100.0,-138.0,-176.0]

# Half-width of the wire fields in metres (wire stops this far from the centre line).
const WIRE_EDGE:int=208

# z of the seawall that troops shelter behind after crossing the open beach.
const SEAWALL:float=-120.0

# z of the main concrete bunker on the bluff.
const BUNKER:float=-234.0

# z of the two trench lines behind the bunker.
const TRENCHES=[-284.0,-325.0]

# z where the village begins, and z of the church that anchors its far end.
const VILLAGE:float=-362.0
const CHURCH:float=-494.0

## Snap an x position to the nearest of the three assault lanes.
##
## @param x World x in metres.
## @return The lane centre x (-72, 0 or 72).
static func assault_lane(x:float)->float:
	# Lanes are 72 m apart, so rounding x/72 gives -1/0/1; +1 turns it into an array index.
	return ASSAULT_LANES[clampi(roundi(x/72.0)+1,0,2)]

## Map an x position to one of the 8 defence sectors.
##
## @param x World x in metres.
## @return Sector index 0..7 from the left edge, clamped for positions beyond the map.
static func sector_for(x:float)->int:
	# Sector centres run -168..168 in 48 m steps: shifting by 168 and dividing by 48 gives the index.
	return clampi(roundi((x+168)/48),0,7)
