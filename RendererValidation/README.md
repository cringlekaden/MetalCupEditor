# Renderer Validation

Open `Project.mcp` directly from the MetalCup Editor project chooser. The project is opened in place and uses canonical Engine shaders; it intentionally has no `Assets/Shaders` directory.

The scene contains a fixed editor camera with automatic exposure disabled, a neutral diffuse cube, a neutral metallic cube, a neutral floor, a directional light, and a fixed procedural environment. It is a deterministic renderer-regression baseline, not a claim of calibrated visual correctness.

## Checks

1. **Direct-light only:** keep the `Validation Sun` enabled and disable IBL in Renderer settings.
2. **IBL only:** disable the `Validation Sun` light component and enable IBL.
3. **Combined:** enable both the light and IBL.

Keep the camera at manual exposure `1.0` for comparisons. Confirm the Renderer settings panel reports `Canonical Engine shaders` before recording results.
