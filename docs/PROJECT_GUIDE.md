# Holy Order

A Godot game prototype following a displaced knight through desert, winter-convoy, and Omaha-inspired combat scenarios.

**Status:** Playable game prototype  
**Built with:** Godot 4, GDScript, procedural assets

## Reading order

1. Read the root README for project purpose and setup navigation.
2. Follow the entry points below to find the implementation.
3. Use the file guide to locate individual modules, tests, assets, and configuration.
4. Check component licenses before redistributing dependencies or assets.

## Important paths

- [project.godot](../project.godot) — Godot project settings: main scene, engine feature level, window size, rendering, audio, and physics configuration.
- [START-HERE.txt](../START-HERE.txt) — Reference notes for START HERE: HOLY ORDER — THE FIRST DISPLACEMENT Original desert mission / The village update.
- [scenes/menu.tscn](../scenes/menu.tscn) — Godot scene for menu; declares nodes, scripts, and resource references.
- [scripts/menu.gd](../scripts/menu.gd) — Source module for menu; defines `_ready`, `add_text`, `launch`.

## Structure

| Path | Role |
| --- | --- |
| [assets/](../assets/) | Media and visual resources used by the project (66 tracked entries). |
| [docs/](../docs/) | Project documentation, decisions, and reference material (10 tracked entries). |
| [reviews/](../reviews/) | Historical reviews and development snapshots (685 tracked entries). |
| [scenes/](../scenes/) | Godot scene definitions and resource references (4 tracked entries). |
| [scripts/](../scripts/) | Game logic, actors, interactions, UI, and world behavior (103 tracked entries). |
| [tests/](../tests/) | Automated checks and test fixtures (45 tracked entries). |
| [tools/](../tools/) | Developer utilities and supporting automation (1 tracked entries). |

## Useful commands

Run from the repository root after following the documented prerequisites.

```sh
godot --path . --editor
```

## Scope

Use the Godot version declared in project.godot. Audio has a local generator, Poly Haven texture credits are recorded, and DejaVu font notices are included. Scenario scale and performance figures in historical reviews are not a new benchmark.

## Maintaining the guide

The file catalog is a source-inspection snapshot, not proof that every runtime path works. Update it when moving files or changing module responsibilities. The 2026-10-12 documentation review did not run every application, deploy services, or validate all historical performance claims.
