# Holy Order

A Godot game prototype following a displaced knight through desert, winter-convoy, and Omaha-inspired combat scenarios.

**Status:** Playable game prototype  
**Built with:** Godot 4, GDScript, procedural assets

[Project guide](docs/PROJECT_GUIDE.md) · [Every file explained](docs/FILE_GUIDE.md) · [Licenses and dependencies](docs/LICENSE_REVIEW.md)

## Start here

- [project.godot](project.godot) — Tracked project resource in .; 982 bytes.
- [START-HERE.txt](START-HERE.txt) — Reference notes for START HERE: HOLY ORDER — THE FIRST DISPLACEMENT Original desert mission / The village update.
- [scenes/menu.tscn](scenes/menu.tscn) — Godot scene for menu; declares nodes, scripts, and resource references.
- [scripts/menu.gd](scripts/menu.gd) — Source module for menu; defines `_ready`, `add_text`, `launch`.

The following commands are taken from this project’s source/configuration. Install its prerequisites first.

```sh
godot --path . --editor
```

## Repository layout

| Path | Role |
| --- | --- |
| [assets/](assets/) | Media and visual resources used by the project (66 tracked entries). |
| [reviews/](reviews/) | Historical reviews and development snapshots (685 tracked entries). |
| [scenes/](scenes/) | Godot scene definitions and resource references (4 tracked entries). |
| [scripts/](scripts/) | Build, launch, maintenance, and verification commands (103 tracked entries). |
| [tests/](tests/) | Automated checks and test fixtures (45 tracked entries). |
| [tools/](tools/) | Developer utilities and supporting automation (1 tracked entries). |

## Scope and current limits

Use the Godot version declared in project.godot. Audio has a local generator, Poly Haven texture credits are recorded, and DejaVu font notices are included. Scenario scale and performance figures in historical reviews are not a new benchmark.

## License

Original project code retains **MIT** terms in [LICENSE](LICENSE). Third-party libraries, media, data, models, and tools retain their own terms. See the [license review](docs/LICENSE_REVIEW.md) and [dependency inventory](docs/DEPENDENCIES.csv).
