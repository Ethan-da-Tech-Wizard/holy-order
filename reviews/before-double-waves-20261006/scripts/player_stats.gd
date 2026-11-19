# ==============================================================================
# Program: player_stats.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for player_stats.gd.
# ==============================================================================
## Player tuning constants shared by the Ardennes and Omaha player controllers.
##
## This is a pure constants holder (RefCounted, never instantiated): other scripts
## read `PlayerStats.MAX_HEALTH` through a preload of this file so health is tuned
## in one place instead of being duplicated per theater.
extends RefCounted

# Hit points at spawn and the healing cap. 300 is deliberately well above the
# 100-point convention so rifle hits (tens of points) are survivable for a few shots.
const MAX_HEALTH:float=300.0
