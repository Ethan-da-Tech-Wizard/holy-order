extends RefCounted
# Gameplay distances in metres. Troops, weapons and fortifications retain their scale.
const WIDTH:float=576.0
const DEPTH:float=576.0
const FLEET_SPACING:float=40.0
const ASSAULT_LANES=[-120.0,0.0,120.0]
const SECTORS=[-280.0,-200.0,-120.0,-40.0,40.0,120.0,200.0,280.0]
const WIRE_ROWS=[-100.0,-138.0,-176.0]
const WIRE_EDGE:int=344
const SEAWALL:float=-120.0
const BUNKER:float=-234.0
const TRENCHES=[-284.0,-325.0]
const VILLAGE:float=-362.0
const CHURCH:float=-494.0

static func assault_lane(x:float)->float:
	return ASSAULT_LANES[clampi(roundi(x/120.0)+1,0,2)]

static func sector_for(x:float)->int:
	return clampi(roundi((x+280)/80),0,7)
