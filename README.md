# MetalCupEditor

MetalCupEditor is a macOS scene editor for [MetalCupEngine](https://github.com/cringlekaden/MetalCupEngine). It is the canonical handbook for creating projects, authoring scenes and assets, and testing a game with the MetalCup runtime.

> **Early development:** stable `main` is the public baseline, not a shipping game-development product. It is tested only on Apple-silicon Macs running macOS 26.2 with a current Xcode. Projects and APIs can change.

## What it includes

- An ImGui-based scene, viewport, inspector, content-browser, renderer and animation-graph workflow.
- `.mcp` projects, `.mcscene` scenes, project-local assets and metadata.
- Model, texture, environment, material, animation, Lua script and audio asset classification.
- Play-mode runtime sessions driven by MetalCupEngine, including physics, character controllers, animation and Lua hooks.

The Engine repository owns runtime architecture, renderer internals and contributor material; this repository owns the end-user workflow. Start with the [handbook](Docs/README.md).

## Quick start

Clone this repository next to a MetalCupEngine checkout initialized with `git submodule update --init --recursive`. The local SwiftAssimp package declares Assimp as a system library; on macOS its package manifest identifies Homebrew `assimp` as the provider (`brew install assimp`). The Editor project also references a locally installed Autodesk FBX SDK and an Engine framework product. Those workspace/framework paths are not self-contained in this repository, so there is no reproducible standalone Editor command-line build from a fresh clone yet. Configure those local dependencies, then open `MetalCupEditor.xcodeproj`, select **MetalCupEditor**, and Run.

Create or open a project with the startup dialog or **File > New Project** / **File > Open Project**. Default user projects live under `/Volumes/External/kadencringle/Library/Application Support/MetalCupEditor`.

## Documentation

- [End-user handbook](Docs/README.md)
- [First playable project](Docs/first-playable.md)
- [Projects, scenes and assets](Docs/projects-and-content.md)
- [Gameplay authoring](Docs/gameplay.md)
- [Troubleshooting and limitations](Docs/troubleshooting.md)
- [Engine technical documentation](https://github.com/cringlekaden/MetalCupEngine/tree/main/Docs)

## Limits, roadmap and license

Stable main has no supported packaging/export pipeline. Environment reconstruction work is intentionally unmerged; see [development status](Docs/development-status.md). No top-level license file is present, so this README does not claim one; third-party and repository asset provenance is recorded in [ASSET_ATTRIBUTION.md](ASSET_ATTRIBUTION.md). See [ROADMAP.md](ROADMAP.md), [CONTRIBUTING.md](CONTRIBUTING.md), and [SECURITY.md](SECURITY.md).

No current screenshot is published here because the repository has no clearly current, provenance-verified editor capture. See the capture plan in the handbook before adding media.
