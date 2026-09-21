# Getting CS2 assets in

Not wired up yet. This is the plan, recorded so the eventual extraction script
has something to implement.

## Tool

[Source 2 Viewer / ValveResourceFormat](https://github.com/ValveResourceFormat/ValveResourceFormat),
which browses VPK archives and decompiles Source 2 assets. It has a
[command line utility](https://s2v.app/ValveResourceFormat/guides/command-line.html)
suitable for scripting, which is what `scripts/extract_assets.sh` should use so
extraction is repeatable rather than a manual chore.

## What comes out

| Asset | Exports? | Notes |
|---|---|---|
| Weapon and player models | Yes, glTF 2.0 / GLB | Geometry, materials, textures and the skeleton. Animations export automatically. |
| dust2 world geometry | Yes, glTF | Brushes, meshes, props, textures as PNG. |
| dust2 collision | Partially | Merged into a single mesh on export, not preserved as editable shapes. |
| dust2 lighting | No | Relight it ourselves. |
| dust2 nav mesh | No | Bake our own for bots. |
| Sounds | Yes | |
| Weapon tuning numbers | **No** | See below. |

Docs: [models](https://s2v.app/ValveResourceFormat/guides/exporting-models.html),
[maps](https://s2v.app/ValveResourceFormat/guides/exporting-maps.html).

Two things to expect when dust2 arrives:

- The merged collision mesh works as a trimesh static body, but CS maps use
  player-clip brushes to smooth awkward corners and those do not survive the
  export. A hand-authored clip layer will be needed, and it will matter for how
  movement feels around corners.
- Geometry comes back mostly triangulated and merged by material.

## The weapon numbers are not extractable

Damage, armour ratio, penetration, recoil seeds and the inaccuracy/spread model
live in `scripts/weapons.vdata_c`, and no published artifact carries the
values: the entity schema has the field names with zeroed templates, the item
definitions hold only presentation metadata, and demo streams never carry
static game data.

Source: <https://github.com/CS2OpenDev/CS2OpenDev-SchemaTracker/issues/16>

So making the AK feel right is a measurement job, not an import job:

1. Start from the CS:GO-era weapon scripts, which were plain text and carried
   the recoil and inaccuracy fields. CS2 inherited most of this model.
2. Use published spray patterns as the target to match, e.g.
   [op.gg](https://op.gg/cs2/spray-patterns) and
   [csdb](https://csdb.gg/recoil-patterns/).
3. Fire 30-round sprays at a wall in our build, plot the impacts, and tune
   until the plot overlays the reference.

That means a spray-pattern test range with impact plotting is an early build,
not a late one. It is the same tuning loop the movement HUD provides, pointed
at ballistics instead.

## Licensing

Extracting from your own CS2 installation for a private build is normal modding
practice. Valve's models, textures, sounds and map geometry cannot be
redistributed, and that includes committing them to a public repository, so
`assets/` is gitignored and stays that way.
