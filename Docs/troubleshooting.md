# Troubleshooting and current limitations

## Common problems

- **Framework not found:** build/open the sibling MetalCupEngine project, then rebuild the Editor scheme.
- **Project will not open:** select the project’s `Project.mcp`, not an individual scene; keep the full project folder together when moving it.
- **Asset is absent:** place it under the project `Assets` directory using a supported extension and allow the asset registry to scan it. Do not point scenes at machine-local paths.
- **Input does nothing in Play:** click/focus the viewport, verify the script is attached to the runtime entity, and verify a character controller exists before using controller calls.
- **Shaders do not change:** default projects intentionally use canonical engine resources. A project needs an explicit `Assets/Shaders` override selection.

## Known limitations

There is no supported installer, game packaging/export, public SDK compatibility guarantee, or stable interchange serialization. IBL/reflection probes rebuild but continuous scheduling is pending. Environment sky, fog and cloud controls exist, but the physically based celestial/night reconstruction and global exposure work remain unmerged because visible night sky and scene illumination do not yet agree. The editor’s source/validation projects are not a promise of a supported template.

## Media capture plan

When stable behavior is ready, capture an Apple-silicon/macOS-26.2 Editor build at the documented stable revision: (1) a clean project/startup screen, (2) hierarchy + inspector + viewport with a basic authored scene, and (3) renderer/environment controls. Record project/revision, avoid personal assets, and replace screenshots whenever the corresponding UI changes.
