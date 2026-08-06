# Renderer Validation

Open `Project.mcp` directly from the MetalCup Editor project chooser. The project is opened in place and uses canonical Engine shaders; it intentionally has no `Assets/Shaders` directory.

The scene contains a fixed editor camera with automatic exposure disabled and `exposureEV = 0`, a neutral diffuse cube, a neutral metallic cube, a neutral floor, a directional light, and a fixed procedural environment. It explicitly selects normal global IBL gain `1`, the fixed MetalCup Filmic v1 output transform, and neutral legacy gamma state. It is a deterministic renderer-regression baseline, not a claim of calibrated visual correctness.

Phase 1 intentionally invalidates older compensated brightness values. Do not retune this project to recreate the pre-Phase-1 appearance.

## Checks

1. **Direct-light only:** keep the `Validation Sun` enabled and disable IBL in Renderer settings.
2. **IBL only:** disable the `Validation Sun` light component and enable IBL.
3. **Combined:** enable both the light and IBL.

Keep the camera at `0 EV` for comparisons. Confirm the Renderer settings panel reports `Canonical Engine shaders` and `MetalCup Filmic v1` before recording results. Changing to `-1 EV` and `+1 EV` should halve and double the value entering the tonemapper without rebuilding IBL.
