## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/omaha/layout.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
extends RefCounted
# Gameplay distances in metres. Troops, weapons and fortifications retain their scale.
const WIDTH:float=576.0
const DEPTH:float=576.0
const FLEET_SPACING:float=40.0
const ASSAULT_LANES=[-120.0,0.0,120.0]
const SECTORS=[-280.0,-200.0,-120.0,-40.0,40.0,120.0,200.0,280.0]
const WIRE_ROWS=[-100.0,-138.0,-176.0]
const WIRE_EDGE:int=344

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
	return ASSAULT_LANES[clampi(roundi(x/120.0)+1,0,2)]

static func sector_for(x:float)->int:
	return clampi(roundi((x+280)/80),0,7)
