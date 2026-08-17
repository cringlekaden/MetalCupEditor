# Renderer Validation

Open `Project.mcp` directly from the MetalCup Editor project chooser. The project opens in place, uses canonical Engine shaders, and intentionally contains no `Assets/Shaders` directory. Every camera is fixed at `0 EV` with automatic exposure disabled. MetalCup Filmic v1 and neutral legacy gamma state are explicit in every scene.

This is a deterministic numerical-regression lab, not a claim of calibrated visual correctness. Phase 1 intentionally invalidated older compensated brightness values. Phase 4 replaces the formerly weak procedural daytime source with one coupled sky/sun energy model. Phase 6 extends that frame-owned contract through dusk, night, and dawn.

## Phase 6 night and celestial reference

`Scenes/SkyTimeValidation.mcscene` is the deterministic day/dusk/night/dawn lab. It uses a full Moon (`moonPhase = 0.5`), physical lunar diameter `0.54 degrees`, effective lunar albedo `0.12`, the production star and Milky Way layers, one Environment-owned analytic key light, 4x MSAA, and the Phase 3 interactive/final IBL lifecycle. AO, clouds, bloom, and local fog are disabled for the primary celestial reference. Constant diffuse, dielectric, and metal objects plus fixed world-direction and shadow markers reveal lighting or orientation drift without relying on textures.

The checked-in camera remains `0 EV` as a numeric source reference. Useful fixed photographic viewing ranges are approximately Camera EV `+1` for day, `+3` to `+6` for dusk/dawn, and `+8` to `+12` for moonlit or deep night. Keep Environment Source EV at `0`: Camera EV changes only the output stage and must not rebuild IBL, while Source EV changes the physical sky/Sun/Moon source generation. Do not raise source radiance simply to make a night scene visible at daytime exposure.

- Fixed checkpoints: `06:00` dawn/horizon, `08:52` daylight, `12:00` noon, `17:34` golden hour, `18:00` sunset, `19:00` dusk, `22:00` moonlit night, `00:00` deep night, and `05:00` dawn transition.
- Phase checks: set Moon Phase to `0.0` (new), `0.25` (quarter), and `0.5` (full). The visible illuminated disk and analytic irradiance must vary together; only the selected Environment key light may own directional shadows.
- Direct only: disable global IBL and inspect the full-Moon highlight and shadow direction. IBL only: leave IBL enabled and use the Environment direct-light isolation control. Combined: enable both and verify additive pre-exposure HDR behavior.
- Stars and the Milky Way are visible sources but enter IBL through the documented bounded celestial-capture factor. They must not wash diffuse materials or produce implausibly dominant metal reflections.
- During the 60-second accelerated day, the visible Sun or Moon, analytic light, shadows, and active IBL direction must remain coherent. Interactive IBL may report lag; after time stops it must automatically become final/current without a black resource gap or an older generation replacing it.
- For the secondary fog check only, enable the already-authored Phase 5 local medium without changing its coefficients. Fog must consume the selected Sun/Moon frame irradiance without changing the celestial source, IBL resources, or exposure. Do not save this exploratory state over the source scene.

Deep-night calibration intentionally does not redesign clouds, cloud cards, night antialiasing, or gameplay. Existing 4x MSAA remains the accepted rasterization path.

## Phase 5 local fog and aerial perspective

`Scenes/FogReference.mcscene` is the numeric local-medium reference. Camera Exposure EV and
Environment Source EV are both `0`; AO, clouds, and bloom are disabled. Its neutral objects are
named for approximate camera distances `1`, `5`, `10`, `25`, `50`, and `100` world units, with
elevated and base-layer samples. Toggle only the Environment's Local Fog `Enabled` field for the
fog-off identity comparison. Inspect Optical Depth, Transmittance, In-scattered Radiance, Linear
Distance, Density, Ambient Scattering, Directional Scattering, and Pixel Classification debug views.

`Scenes/AerialPerspectiveValidation.mcscene` provides near/mid/far neutral geometry, an elevated
sample, a below-base sample, and a horizon-crossing silhouette. Use fixed high Sun first, then set
the Environment time to the existing golden-hour checkpoint. Compare direct-only, IBL-only, and
combined modes without changing exposure. For camera-height checks, use static checkpoints at
roughly `y = -2`, `5`, and `25`; do not save those runtime views into the canonical scene.

Expected behavior: fog-off is the Phase 4 image; enabled transmittance decreases monotonically with
distance/density; sky and geometry share the same boundary equation; upward background rays have a
finite integral; horizontal/downward infinite rays naturally approach opaque fog. The hard no-fog
horizon is still a presentation limitation, not a second atmosphere term. Local fog is not captured
into IBL or reflection probes. Live SAO remains unresolved and is intentionally disabled. Existing
MSAA is accepted; Phase 5 adds no AA work.

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

The fixed procedural environment provides controlled indirect illumination at Camera EV `0` and Environment Source EV `0`. The primary reference keeps local fog off and uses the normal 4x MSAA scene configuration while AO owns a coherent single-sample depth/normal pair. Entities cover an isolated elevated object, a touching pair, a wall/floor corner, a grazing wedge, a convex rounded edge, thin and isolated silhouettes, three camera-distance markers, and open background/no-sample pixels.

- Inspect `AO Raw` (27), then `AO Filtered` (28).
- Inspect `AO Normals` (29), reconstructed view position (30), valid samples (48), obscurance (49), AO production depth (50), and the final indirect factor (51) to trace the production inputs.
- Background and no-valid-sample pixels must be visibility `1`.
- The isolated floor stays close to visibility `1`; touching objects and the wall/floor corner must fall below `1` locally without broad silhouette halos.
- More obscurance or greater intensity must not increase visibility.
- Bilateral blur averages visibility and uses `1` as the neutral fallback.
- To verify isolation, compare with AO on/off while direct-only: AO must not darken analytic direct lighting. Disable IBL and retain one analytic light in a disposable copy for this check.
- For the secondary fog interaction check, enable the existing scene-linear local fog temporarily: AO inputs and visibility must remain unchanged while the fogged composite changes. Do not save that runtime state over this source scene.
- Static-camera output must be deterministic. Small translations or rotations may move screen-space detail, but must not flash, invert, or erase the whole AO field.

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

The authoritative Phase 4 fixed-time lab uses the canonical procedural atmosphere at Environment Source EV `0`, Camera Exposure EV `0`, one Environment-owned analytic Sun, and no authored directional light. Source EV scales sky, Sun, and captured IBL energy together; Camera EV changes only final output. AO, fog, clouds, bloom, moonlight, and stars are disabled.

The primary row is deliberately texture-free and uses constant materials on the built-in smooth sphere: white diffuse (`roughness 0.80`), 18% gray diffuse (`0.80`), smooth dielectric (`0.06`), rough dielectric (`0.80`), smooth neutral metal (`0.06`), rough neutral metal (`0.80`), and copper-colored metal (`0.25`). The rounded neutral box behind the row uses roughness `0.25` to expose normal continuity on flat and curved regions. Smooth surfaces should show a localized environment reflection, increasing roughness should broaden it, metals must have no diffuse term but remain visible through environment specular, and dielectrics retain base-color diffuse plus neutral `0.04` F0. Small emissive direction markers sit outside the material row and are not calibration materials.

Do not judge PBR correctness using texture detail: these constant-material spheres are the authoritative chromaticity, energy, and BRDF references. Texture-based showcase materials belong to a later integration scene.

- High sun: `12:00` is the checked-in state and resolves to elevation `88 degrees`.
- Daylight reference: elevation `60 degrees` resolves to `08:51:57` or `15:08:03`.
- Mid elevation: `30 degrees` resolves to `07:19:44` or `16:40:16`.
- Golden hour: `10 degrees` resolves to `06:26:06` or `17:33:54`; direct sunlight should be warm while the opposite upper sky remains visibly cooler.
- Low golden hour: `5 degrees` resolves to `06:13:02` or `17:46:58`.
- Sunset/horizon: elevation `0 degrees` is `06:00:00` or `18:00:00`; confirm a continuous source transition.
- Civil twilight: inspect down to solar elevation `-6 degrees`; night calibration starts below this point in Phase 6.
- Direct only: disable global IBL while retaining the Environment-owned Sun.
- IBL only: leave IBL enabled and disable the generated analytic Sun through the Environment debug isolation control.
- Combined: enable both. Direct-only plus IBL-only must equal combined in pre-exposure HDR.

The visible view includes atmosphere, aureole, and the unscattered disk. IBL capture intentionally excludes the unscattered disk because its projected integral is represented by the analytic Sun. Never compensate source energy with global IBL gain, fog, material multipliers, or AO. Camera EV may be chosen photographically, but it must not be confused with Environment Source EV or used to alter IBL resources.

The calibrated lower hemisphere is a bounded neutral-ground response, but the background horizon has no camera-space fog or aerial perspective. A visibly hard presentation boundary remains a Phase 5 limitation, not a reason to tint or brighten the sky. Raw and filtered SAO still appear white everywhere in the live Editor; keep SAO disabled and do not compensate sky, IBL, Sun, exposure, or material values for that separate production-input defect.

### `SkyTimeValidation.mcscene`

The accelerated lab begins at `06:00` and advances a full day in 60 seconds. It has the same fixed source/output and disabled AO/fog/cloud/bloom state as `SkySunReference`, plus the Phase 6 reflected Moon, stars, and Milky Way. Stationary world-axis markers and the reflective material row reveal direction mismatch while the generated Sun-or-Moon key light and cascaded shadow owner follow the authoritative environment frame.

- Watch solar elevation/direction, analytic RGB irradiance, active IBL source time/direction, angular lag, and rebuild phase in Environment status.
- Visible disk, selected direct highlight, shadow ray, and current IBL marker should describe the same solar or lunar direction. Interactive IBL is allowed to lag visibly and must report that lag.
- During continuous motion, rebuilds are coalesced. When time stops, status must advance from interactive/lagging through rebuilding-final to final/current without a black resource gap.
- The source reference remains at Camera EV `0`; use the documented fixed viewing EV ranges without saving them. Camera exposure must not trigger an IBL rebuild.

Static checkpoints are authoritative. Do not save exploratory runtime state over these scenes. Phase 5 SSAO has passed manual acceptance, but AO remains disabled here so celestial energy can be inspected without an additional indirect-light factor.

## Static checkpoints and optional motion

The Engine has an existing `LightOrbitComponent`, so an orbit can be added manually for exploratory sweeps without a new scripting architecture. It depends on runtime time progression and is not serialized into these authoritative references. The checked-in static positions remain the reproducible checkpoints.

Do not save manual acceptance changes into these files. The Phase 1 manual shadow reproduction remains preserved outside Git at `.git-recovery/RendererValidation-manual-acceptance-2026-08-06`.
