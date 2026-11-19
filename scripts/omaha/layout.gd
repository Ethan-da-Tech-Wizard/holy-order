## Fixed layout constants for the Omaha Beach map and force sizes.
##
## Role: a constants-only class used by world.gd (builds the beach and town),
## battle.gd (spawns troops), boat.gd (landing craft) and wire.gd. Gathering
## them here keeps the geometry and the order of battle in one place.
## Axes: the sea is at +Z and the beach, bluffs and town at -Z (z = 0 is the waterline); X spans the beach width.
extends RefCounted
# Gameplay distances in metres. Troops, weapons and fortifications retain their scale.

## Nominal beach width in metres (288); streets, sectors and wire extend slightly beyond it.
const WIDTH:float=288.0

## Total playable depth in metres from the sea to the church.
const DEPTH:float=576.0

## German defenders on the beach and bluffs.
const BEACH_DEFENDERS:int=100

## German defenders in the village.
const TOWN_DEFENDERS:int=150

## All German defenders.
const GERMANS_TOTAL:int=BEACH_DEFENDERS+TOWN_DEFENDERS

## z of the town's front edge.
const TOWN_FRONT:float=-350.0

## z of the town's back edge.
const TOWN_BACK:float=-520.0

## Ground height (m) used for the town plateau.
const TOWN_GROUND:float=47.3

## x of the nine north-south streets in the town.
const ROAD_X=[-152.0,-114.0,-76.0,-38.0,0.0,38.0,76.0,114.0,152.0]

## z of the five east-west streets in the town.
const ROAD_Z=[-358.0,-408.0,-452.0,-498.0,-520.0]

## Landing craft in each wave.
const BOATS_PER_WAVE:int=20

## Riflemen carried in each craft.
const PASSENGERS_PER_BOAT:int=27

## Crew in each craft (coxswain and gunners).
const CREW_PER_BOAT:int=3

## Men per wave: boats x (passengers + crew) = 600.
const AMERICANS_PER_WAVE:int=BOATS_PER_WAVE*(PASSENGERS_PER_BOAT+CREW_PER_BOAT)

## Two waves = 1,200 Americans, the number shown on the menu.
const AMERICANS_TOTAL:int=AMERICANS_PER_WAVE*2

## Seat indexes in each boat reserved for engineers carrying bangalore torpedoes.
const ENGINEER_SEATS=[3,12,21]

## Distance (m) between adjacent landing craft in the line.
const FLEET_SPACING:float=12.0

## x of the three lanes the assault is organised into.
const ASSAULT_LANES=[-72.0,0.0,72.0]

## x centres of the eight 48 m-wide defence sectors.
const SECTORS=[-168.0,-120.0,-72.0,-24.0,24.0,72.0,120.0,168.0]

## z of the three barbed-wire rows on the beach.
const WIRE_ROWS=[-100.0,-138.0,-176.0]

## x extent (208 m) used when laying out the wire rows.
const WIRE_EDGE:int=208

## z of the sea wall.
const SEAWALL:float=-120.0

## z of the bunker line.
const BUNKER:float=-234.0

## z of the two trench lines.
const TRENCHES=[-284.0,-325.0]

## z of the village's first row.
const VILLAGE:float=-362.0

## z of the church at the far end.
const CHURCH:float=-494.0

## Returns the assault lane x nearest to `x` (rounds to the closest of -72, 0, 72).
static func assault_lane(x:float)->float:
	return ASSAULT_LANES[clampi(roundi(x/72.0)+1,0,2)]

## Returns the defence sector index 0..7 for a given x (sectors are 48 m wide starting at -168).
static func sector_for(x:float)->int:
	return clampi(roundi((x+168)/48),0,7)
