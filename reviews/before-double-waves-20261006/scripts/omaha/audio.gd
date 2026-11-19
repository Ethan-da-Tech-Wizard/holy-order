# ==============================================================================
# Program: audio.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for audio.gd.
# ==============================================================================
## Omaha-specific audio: same sounds as Ardennes but tuned for a very large, loud beach.
##
## Extends the Ardennes audio script. The difference is `at()`: with hundreds of
## soldiers firing, positional sounds create a fresh player per call (not the
## Ardennes voice pool) and are throttled by three limits (child count, per-frame
## count) so the mixer is not flooded.
extends "res://scripts/ardennes/audio.gd"
# Winter and Omaha share the bounded spatial sound pool.
