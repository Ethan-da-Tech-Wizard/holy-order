# License review — Holy Order

Reviewed 2026-10-12. Original project code retains **MIT** terms in [LICENSE](../LICENSE).

The owner selected MIT for previously unlicensed original code. Existing licenses were preserved. This choice does not relicense copied code, dependencies, datasets, model weights, fonts, logos, or game assets.

## Preserved notices

- [LICENSE](../LICENSE)
- [assets/fonts/LICENSE.txt](../assets/fonts/LICENSE.txt)
- [tools/GODOT-LICENSE.txt](../tools/GODOT-LICENSE.txt)

## Dependency evidence

[DEPENDENCIES.csv](DEPENDENCIES.csv) lists 0 manifest and lockfile records. Repeated packages can appear under different manifests, versions, or development scopes. Registry metadata is evidence, not a replacement for the actual license text. For unpinned ranges, `metadata_version` is the version inspected and is not a claim about every install. Go and system/build tools can require notices beyond package-manager metadata.

## Project-specific considerations

Texture attribution is in assets/omaha/credits.json: the listed Poly Haven textures are CC0-1.0 ([publisher terms](https://polyhaven.com/license)). DejaVu/Bitstream/Arev font conditions remain in assets/fonts/LICENSE.txt. Preserve tools/GODOT-LICENSE.txt when distributing the engine. Audio generation is documented by assets/make_audio.py.

## Remaining work before binary distribution

No unresolved registry-license lookup remains in the listed package records. System packages, downloaded tools/models, optional plugins, release binaries, and externally obtained assets need a build-specific inventory. This source review is not a blanket legal certification or a claim that every release artifact has been audited.
