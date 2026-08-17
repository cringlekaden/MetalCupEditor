# Install and interface tour

## Requirements and launch

Use an Apple-silicon Mac with macOS 26.2 and current Xcode. Clone MetalCupEditor beside MetalCupEngine, initialize the engine's required Jolt submodule (`git submodule update --init --recursive`), and install the editor package's macOS Assimp provider with `brew install assimp`. The Editor project expects both `MetalCupEngine.framework` and a locally installed Autodesk FBX SDK. The repository does not include a portable workspace/project-dependency definition for those paths, so configure them locally before opening `MetalCupEditor.xcodeproj`, selecting **MetalCupEditor**, and choosing Build/Run. There is no installer, standalone command-line build recipe, or supported packaged editor build on stable main.

On launch, use the startup modal or **File > New Project** / **File > Open Project**.

## Interface

The editor has a scene hierarchy for selecting entities, an inspector for component data, a viewport for visual editing, a content browser for project assets, and renderer controls for view/runtime settings. Animation graph assets open in their own graph workspace. Panels are ImGui-based and their visibility/state is editor-local; do not mistake panel state for project content.

## Rendering and environment

The renderer panel exposes scene renderer settings, debug targets and environment controls. Stable main includes sky, fog, cloud and IBL/reflection-probe settings, lighting and shadows; use them for iteration but see [limitations](troubleshooting.md#known-limitations). The physical celestial/exposure implementation remains experimental and is not part of this workflow.
