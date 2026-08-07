# Renderer Validation

Open `Project.mcp` directly from the MetalCup Editor project chooser. The project opens in place, uses canonical Engine shaders, and intentionally contains no `Assets/Shaders` directory. Every camera is fixed at `0 EV` with automatic exposure disabled. MetalCup Filmic v1 and neutral legacy gamma state are explicit in every scene.

This is a deterministic numerical-regression lab, not a claim of calibrated visual correctness. Phase 1 intentionally invalidated older compensated brightness values. Phase 4 replaces the formerly weak procedural daytime source with one coupled sky/sun energy model. Night below civil twilight remains outside this lab.

## Scene index

### `RendererValidation.mcscene`

The general Phase 1 baseline. `Validation Sun` now uses schema 2 and a transform whose local `-Z` ray is `(-0.5050763, -0.8081220, -0.3030458)`. Its scene-relative directional illuminance is `pi`. `Validation Environment` owns the fixed procedural sky and global IBL.

- Direct only: keep `Validation Sun`, disable IBL.
- IBL only: disable `Validation Sun`, enable IBL.
- Combined: enable both.
- Exposure checks: compare `-1`, `0`, and `+1 EV`; exposure must not rebuild IBL.

### `MaterialReference.mcscene`

This source scene is direct-only by default: IBL, SAO, and shadows are disabled. It has exactly one analytic directional light at illuminance `pi` and no Environment component, so an environment-generated analytic Sun cannot contaminate the direct reference.

Left-to-right entities and numeric roles:

1. white dielectric, roughness `0.50`, metallic `0`;
2. 18% gray dielectric, roughness `0.50`, metallic `0`;
3. smooth dielectric, roughness `0.06`, metallic `0`;
4. rough dielectric, roughness `0.80`, metallic `0`;
5. neutral metal at the production roughness floor `0.06`;
6. neutral metal at roughness `0.25`;
7. neutral metal at roughness `0.80`;
8. copper-colored metal at roughness `0.25`.

Use the authored scene unchanged for the authoritative direct-only capture. For IBL-only and combined comparisons, use the general `RendererValidation.mcscene`, which has the same EV/output contract and a controlled procedural environment. Keep any environment-generated analytic Sun disabled when isolating IBL. Inspect pre-tonemap values for the narrow `0.06` highlight; do not judge its normalized peak only through the filmic output.

### `AnalyticLightLab.mcscene`

The directional rig is the only active rig initially. Its illuminance is `pi`. The point and spot rigs are deliberately represented with intensity `0`; activate one by setting its intensity to `16` and set the directional illuminance to `0`. Only one rig is authoritative for each capture.

- `Point Distance Marker 1`, `2`, and `4` are one, two, and four scene units from the point-light origin. Below 80% of range, irradiance ratios should be `1 : 1/4 : 1/16` before BRDF geometry.
- `Spot Axis and Cone Target Marker` lies on the transform-derived local `-Z` axis. Inspect center, inner cone, smooth transition, outer boundary, and outside.
- Point and spot shadows are unsupported in Phase 2. Their `castsShadows` fields remain false and the Inspector reports the limitation.
- Directional light values are scene-relative illuminance; point/spot values are scene-relative inverse-square intensity numerators. They are not calibrated lux or candela.

### `ShadowValidation.mcscene`

This scene has one and only one transform-authored diagonal directional shadow caster, hard filtering, IBL off, AO off, camera near `0.1`, and camera far `100`.

- `Near Large Caster`: camera depth approximately `5`.
- `Mid Medium Caster`: camera depth approximately `20`.
- `Far Thin Caster`: camera depth approximately `60`.
- `Grazing Bias Stress Caster`: sloped, thin geometry near depth `35`.
- `Receiver Plane`: spans the cascade range.

Validate hard shadows before PCF. Inspect Renderer debug modes `Shadow Cascade Index` (20), `Shadow Cascade Blend` (21), `Shadow Factor` (22), and `Shadow Bias Stress` (23). Repeat with one, three, and four cascades. For ownership checks use disposable copies: authored caster only; environment Sun only; authored caster plus a brighter noncasting Sun; and no caster. The debug factor describes only the selected map owner. Do not enable or tune experimental PCSS.

### `AOReference.mcscene`

The fixed procedural environment provides controlled indirect illumination. Entities cover an isolated elevated object, a touching pair, a wall/floor corner, a grazing wedge, an isolated silhouette, and open background/no-sample pixels.

- Inspect `AO Raw` (27), then `AO Filtered` (28).
- Background and no-valid-sample pixels must be visibility `1`.
- More obscurance or greater intensity must not increase visibility.
- Bilateral blur averages visibility and uses `1` as the neutral fallback.
- To verify isolation, compare with AO on/off while direct-only: AO must not darken analytic direct lighting. Disable IBL and retain one analytic light in a disposable copy for this check.
- Coplanar/lateral-contact response and evaluate-time normal rejection remain diagnostic follow-ups, not Phase 2 aesthetic tuning.

### `IBLOrientation.mcscene`

This scene has no analytic lights, fog, AO, or clouds. Enable `Orientation Pattern Global IBL` in Renderer diagnostics to replace the procedural source with the deterministic six-face production diagnostic. Face identity is `+X` red, `-X` cyan, `+Y` green, `-Y` magenta, `+Z` blue, and `-Z` yellow. White borders, the upper stripe, corner dot, equator, and narrow HDR marker distinguish face orientation from a solid-color false positive.

- Inspect the diffuse, rough/smooth dielectric, and rough/smooth metal references at fixed `0 EV`.
- Global sky, diffuse irradiance, and prefiltered specular must agree on the marker direction.
- The physical axis markers are capture references for `ReflectionProbeValidation`; they do not replace the generated global diagnostic.
- Face edges must remain continuous. A mirrored stripe, swapped color, or marker on the opposite side is a convention failure.

### `IBLRoughness.mcscene`

The top dielectric row and bottom metal row use roughness `0.06`, `0.10`, `0.20`, `0.25`, `0.50`, `0.80`, and `1.00` from left to right. The scene is global-IBL-only at fixed `0 EV`.

- Enable `Orientation Pattern Global IBL` for the directional marker sweep.
- The marker must broaden monotonically as roughness increases without rotating, mirroring, or collapsing to black.
- Disable the diagnostic for the uniform/procedural reference. Uniform-radiance numeric truth is automated because the procedural sky is not uniform.
- Do not compensate weak procedural-sky IBL here; source-radiance calibration remains Phase 4 work.

### `ReflectionProbeValidation.mcscene`

`Canonical Local Reflection Probe` is the sole selected local probe. Six emissive axis markers and a narrow `+Z` up-right marker surround its capture origin. The `+Z` and `-Z` metal references deliberately expose the former probe-only Z flip; the `Global Only Smooth Metal Reference` lies outside the authored influence box.

1. Rebuild the local probe explicitly and wait for `ready`.
2. Compare the same reflection direction with local-probe contribution enabled and disabled.
3. Enable the local-probe orientation diagnostic to inspect the canonical generated cube, then disable it to inspect the scene capture.
4. The marker color, side, and within-face up/right placement must match the global convention. Probe intensity is compatibility-only and must not rescale captured energy.

Phase 3 retains one selected probe, the existing opaque-geometry/sky capture policy, and current blend-shell selection. Overlapping-probe redesign and parallax-corrected box projection remain later quality work.

### `SkySunReference.mcscene`

The authoritative Phase 4 fixed-time lab uses the canonical procedural atmosphere at source `0 EV`, camera `0 EV`, one Environment-owned analytic Sun, and no authored directional light. AO, fog, clouds, bloom, moonlight, and stars are disabled. Its references are white and 18% gray diffuse, smooth/rough dielectric, and smooth/rough metal; fixed axis markers expose solar and shadow direction.

- Noon: set fixed time to `12:00` (checked-in state).
- Mid-elevation daylight: set fixed time to `09:00` or `15:00`.
- Golden hour: set fixed time to `07:00` or `17:00`.
- Sunset/horizon: use approximately `06:00` or `18:00` and confirm a continuous fade.
- Civil twilight: inspect down to solar elevation `-6 degrees`; night calibration starts below this point in Phase 6.
- Direct only: disable global IBL while retaining the Environment-owned Sun.
- IBL only: leave IBL enabled and disable the generated analytic Sun through the Environment debug isolation control.
- Combined: enable both. Direct-only plus IBL-only must equal combined in pre-exposure HDR.

The visible view includes atmosphere, aureole, and the unscattered disk. IBL capture intentionally excludes the unscattered disk because its projected integral is represented by the analytic Sun. Never compensate this scene with global IBL gain, camera exposure, fog, or AO.

### `SkyTimeValidation.mcscene`

The accelerated lab begins at `06:00` and advances a full day in 60 seconds. It has the same fixed camera/output and disabled AO/fog/cloud/bloom state as `SkySunReference`. Stationary world-axis markers and the reflective material row reveal direction mismatch while the generated Sun and cascaded shadow owner follow the authoritative environment frame.

- Watch solar elevation/direction, analytic RGB irradiance, active IBL source time/direction, angular lag, and rebuild phase in Environment status.
- Visible disk, direct highlight, shadow ray, and current IBL marker should describe the same solar direction. Interactive IBL is allowed to lag visibly and must report that lag.
- During continuous motion, rebuilds are coalesced. When time stops, status must advance from interactive/lagging through rebuilding-final to final/current without a black resource gap.
- Exposure must remain `0 EV` and must not trigger an IBL rebuild.

Static checkpoints are authoritative. Do not save exploratory runtime state over these scenes. Raw and filtered SAO currently appear white everywhere in the live Editor; Phase 4 deliberately leaves AO disabled and does not compensate sky or material energy for that separate defect.

## Static checkpoints and optional motion

The Engine has an existing `LightOrbitComponent`, so an orbit can be added manually for exploratory sweeps without a new scripting architecture. It depends on runtime time progression and is not serialized into these authoritative references. The checked-in static positions remain the reproducible checkpoints.

Do not save manual acceptance changes into these files. The Phase 1 manual shadow reproduction remains preserved outside Git at `.git-recovery/RendererValidation-manual-acceptance-2026-08-06`.
