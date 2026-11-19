# ==============================================================================
# Program: player_stats.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Persistent player combat statistics and telemetry tracker. Accumulates shots fired, accuracy percentages, casualty counts, mission elapsed time, and objective completion states across campaign playthroughs.
# ==============================================================================
extends RefCounted
const MAX_HEALTH:float=300.0
