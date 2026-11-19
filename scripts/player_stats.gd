## Shared player tuning constants. Kept in a tiny RefCounted script (never
## instantiated) so the player scripts and HUD code can read one source of
## truth for the health cap without depending on each other.
extends RefCounted

## Maximum player health in hit points. 300 is deliberately high so a single
## burst of rifle fire is survivable and armour/cover decisions matter.
const MAX_HEALTH:float=300.0
