## Archived review snapshot (before-town-armor-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/omaha/layout.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
extends RefCounted
# Gameplay distances in metres. Troops, weapons and fortifications retain their scale.
const WIDTH:float=288.0
const DEPTH:float=528.0

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
