extends RefCounted
# Gameplay distances in metres. Troops, weapons and fortifications retain their scale.
const WIDTH:float=288.0
const DEPTH:float=576.0
const BEACH_DEFENDERS:int=100
const TOWN_DEFENDERS:int=150
const GERMANS_TOTAL:int=BEACH_DEFENDERS+TOWN_DEFENDERS
const TOWN_FRONT:float=-350.0
const TOWN_BACK:float=-520.0
const TOWN_GROUND:float=47.3
const ROAD_X=[-152.0,-114.0,-76.0,-38.0,0.0,38.0,76.0,114.0,152.0]
const ROAD_Z=[-358.0,-408.0,-452.0,-498.0,-520.0]
const BOATS_PER_WAVE:int=20
const PASSENGERS_PER_BOAT:int=27
const CREW_PER_BOAT:int=3
const AMERICANS_PER_WAVE:int=BOATS_PER_WAVE*(PASSENGERS_PER_BOAT+CREW_PER_BOAT)
const AMERICANS_TOTAL:int=AMERICANS_PER_WAVE*2
const ENGINEER_SEATS=[3,12,21]
const FLEET_SPACING:float=12.0
const ASSAULT_LANES=[-72.0,0.0,72.0]
const SECTORS=[-168.0,-120.0,-72.0,-24.0,24.0,72.0,120.0,168.0]
const WIRE_ROWS=[-100.0,-138.0,-176.0]
const WIRE_EDGE:int=208
const SEAWALL:float=-120.0
const BUNKER:float=-234.0
const TRENCHES=[-284.0,-325.0]
const VILLAGE:float=-362.0
const CHURCH:float=-494.0

static func assault_lane(x:float)->float:
	return ASSAULT_LANES[clampi(roundi(x/72.0)+1,0,2)]

static func sector_for(x:float)->int:
	return clampi(roundi((x+168)/48),0,7)
