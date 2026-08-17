/// EditorExposureBridge.swift
/// C ABI for Project Render Settings, temporary viewport exposure, and diagnostics.

import Foundation
import MetalCupEngine

private func resolveExposureContext(_ contextPtr: UnsafeRawPointer?) -> MCEContext? {
    guard let contextPtr else { return nil }
    return Unmanaged<MCEContext>.fromOpaque(contextPtr).takeUnretainedValue()
}

private func resolveExposureEntity(_ entityId: UnsafePointer<CChar>?, context: MCEContext) -> Entity? {
    guard let entityId,
          let id = UUID(uuidString: String(cString: entityId)),
          let scene = context.bridgeServices.activeScene() else { return nil }
    return scene.ecs.entity(with: id)
}

private func writeExposureCString(_ value: String,
                                  to output: UnsafeMutablePointer<CChar>?,
                                  capacity: Int32) {
    guard let output, capacity > 0 else { return }
    let bytes = Array(value.utf8.prefix(Int(capacity - 1)))
    for (index, byte) in bytes.enumerated() { output[index] = CChar(bitPattern: byte) }
    output[bytes.count] = 0
}

private func writeExposure(_ settings: ExposureSettings,
                           _ mode: UnsafeMutablePointer<UInt32>?,
                           _ compensation: UnsafeMutablePointer<Float>?,
                           _ manualEV100: UnsafeMutablePointer<Float>?,
                           _ aperture: UnsafeMutablePointer<Float>?,
                           _ shutterSeconds: UnsafeMutablePointer<Float>?,
                           _ iso: UnsafeMutablePointer<Float>?,
                           _ meteringMode: UnsafeMutablePointer<UInt32>?,
                           _ histogramLogMin: UnsafeMutablePointer<Float>?,
                           _ histogramLogMax: UnsafeMutablePointer<Float>?,
                           _ lowPercentile: UnsafeMutablePointer<Float>?,
                           _ highPercentile: UnsafeMutablePointer<Float>?,
                           _ minimumEV100: UnsafeMutablePointer<Float>?,
                           _ maximumEV100: UnsafeMutablePointer<Float>?,
                           _ darkAdaptationRate: UnsafeMutablePointer<Float>?,
                           _ lightAdaptationRate: UnsafeMutablePointer<Float>?,
                           _ skyInfluenceCap: UnsafeMutablePointer<Float>?,
                           _ daylightKey: UnsafeMutablePointer<Float>?,
                           _ twilightKey: UnsafeMutablePointer<Float>?,
                           _ nightKey: UnsafeMutablePointer<Float>?,
                           _ useOutdoorPrior: UnsafeMutablePointer<UInt32>?) {
    mode?.pointee = settings.mode.rawValue
    compensation?.pointee = settings.compensation
    manualEV100?.pointee = settings.manualEV100
    aperture?.pointee = settings.aperture
    shutterSeconds?.pointee = settings.shutterSeconds
    iso?.pointee = settings.iso
    meteringMode?.pointee = settings.meteringMode.rawValue
    histogramLogMin?.pointee = settings.histogramLogMin
    histogramLogMax?.pointee = settings.histogramLogMax
    lowPercentile?.pointee = settings.lowPercentile
    highPercentile?.pointee = settings.highPercentile
    minimumEV100?.pointee = settings.minimumEV100
    maximumEV100?.pointee = settings.maximumEV100
    darkAdaptationRate?.pointee = settings.darkAdaptationRate
    lightAdaptationRate?.pointee = settings.lightAdaptationRate
    skyInfluenceCap?.pointee = settings.skyInfluenceCap
    daylightKey?.pointee = settings.targetKeyCurve.daylightKey
    twilightKey?.pointee = settings.targetKeyCurve.twilightKey
    nightKey?.pointee = settings.targetKeyCurve.nightKey
    useOutdoorPrior?.pointee = settings.useOutdoorPrior ? 1 : 0
}

private func makeExposure(mode: UInt32,
                          compensation: Float,
                          manualEV100: Float,
                          aperture: Float,
                          shutterSeconds: Float,
                          iso: Float,
                          meteringMode: UInt32,
                          histogramLogMin: Float,
                          histogramLogMax: Float,
                          lowPercentile: Float,
                          highPercentile: Float,
                          minimumEV100: Float,
                          maximumEV100: Float,
                          darkAdaptationRate: Float,
                          lightAdaptationRate: Float,
                          skyInfluenceCap: Float,
                          daylightKey: Float,
                          twilightKey: Float,
                          nightKey: Float,
                          useOutdoorPrior: UInt32) -> ExposureSettings {
    ExposureSettings(
        mode: ExposureMode(rawValue: mode) ?? .automaticHistogram,
        compensation: compensation,
        manualEV100: manualEV100,
        aperture: aperture,
        shutterSeconds: shutterSeconds,
        iso: iso,
        meteringMode: ExposureMeteringMode(rawValue: meteringMode) ?? .centerWeighted,
        histogramLogMin: histogramLogMin,
        histogramLogMax: histogramLogMax,
        lowPercentile: lowPercentile,
        highPercentile: highPercentile,
        minimumEV100: minimumEV100,
        maximumEV100: maximumEV100,
        darkAdaptationRate: darkAdaptationRate,
        lightAdaptationRate: lightAdaptationRate,
        skyInfluenceCap: skyInfluenceCap,
        targetKeyCurve: ExposureTargetKeyCurve(daylightKey: daylightKey,
                                               twilightKey: twilightKey,
                                               nightKey: nightKey),
        useOutdoorPrior: useOutdoorPrior != 0
    )
}

@_cdecl("MCEProjectGetExposureSettings")
public func MCEProjectGetExposureSettings(_ contextPtr: UnsafeRawPointer?,
                                          _ mode: UnsafeMutablePointer<UInt32>?,
                                          _ compensation: UnsafeMutablePointer<Float>?,
                                          _ manualEV100: UnsafeMutablePointer<Float>?,
                                          _ aperture: UnsafeMutablePointer<Float>?,
                                          _ shutterSeconds: UnsafeMutablePointer<Float>?,
                                          _ iso: UnsafeMutablePointer<Float>?,
                                          _ meteringMode: UnsafeMutablePointer<UInt32>?,
                                          _ histogramLogMin: UnsafeMutablePointer<Float>?,
                                          _ histogramLogMax: UnsafeMutablePointer<Float>?,
                                          _ lowPercentile: UnsafeMutablePointer<Float>?,
                                          _ highPercentile: UnsafeMutablePointer<Float>?,
                                          _ minimumEV100: UnsafeMutablePointer<Float>?,
                                          _ maximumEV100: UnsafeMutablePointer<Float>?,
                                          _ darkAdaptationRate: UnsafeMutablePointer<Float>?,
                                          _ lightAdaptationRate: UnsafeMutablePointer<Float>?,
                                          _ skyInfluenceCap: UnsafeMutablePointer<Float>?,
                                          _ daylightKey: UnsafeMutablePointer<Float>?,
                                          _ twilightKey: UnsafeMutablePointer<Float>?,
                                          _ nightKey: UnsafeMutablePointer<Float>?,
                                          _ useOutdoorPrior: UnsafeMutablePointer<UInt32>?) -> UInt32 {
    guard let context = resolveExposureContext(contextPtr) else { return 0 }
    writeExposure(context.editorProjectManager.exposureDefaults(), mode, compensation, manualEV100,
                  aperture, shutterSeconds, iso, meteringMode, histogramLogMin, histogramLogMax,
                  lowPercentile, highPercentile, minimumEV100, maximumEV100, darkAdaptationRate,
                  lightAdaptationRate, skyInfluenceCap, daylightKey, twilightKey, nightKey, useOutdoorPrior)
    return 1
}

@_cdecl("MCEProjectSetExposureSettings")
public func MCEProjectSetExposureSettings(_ contextPtr: UnsafeRawPointer?,
                                          _ mode: UInt32, _ compensation: Float, _ manualEV100: Float,
                                          _ aperture: Float, _ shutterSeconds: Float, _ iso: Float,
                                          _ meteringMode: UInt32, _ histogramLogMin: Float, _ histogramLogMax: Float,
                                          _ lowPercentile: Float, _ highPercentile: Float,
                                          _ minimumEV100: Float, _ maximumEV100: Float,
                                          _ darkAdaptationRate: Float, _ lightAdaptationRate: Float,
                                          _ skyInfluenceCap: Float, _ daylightKey: Float, _ twilightKey: Float,
                                          _ nightKey: Float, _ useOutdoorPrior: UInt32) {
    guard let context = resolveExposureContext(contextPtr) else { return }
    var settings = makeExposure(
        mode: mode, compensation: compensation, manualEV100: manualEV100,
        aperture: aperture, shutterSeconds: shutterSeconds, iso: iso,
        meteringMode: meteringMode, histogramLogMin: histogramLogMin, histogramLogMax: histogramLogMax,
        lowPercentile: lowPercentile, highPercentile: highPercentile,
        minimumEV100: minimumEV100, maximumEV100: maximumEV100,
        darkAdaptationRate: darkAdaptationRate, lightAdaptationRate: lightAdaptationRate,
        skyInfluenceCap: skyInfluenceCap, daylightKey: daylightKey, twilightKey: twilightKey,
        nightKey: nightKey, useOutdoorPrior: useOutdoorPrior
    )
    // The ordinary panel intentionally does not expose asset picking. Preserve a
    // project-authored texture mask while editing the visible exposure fields.
    settings.meteringMaskHandle = context.editorProjectManager.exposureDefaults().meteringMaskHandle
    context.editorProjectManager.updateExposureDefaults(settings)
}

@_cdecl("MCEViewportSetExposureOverride")
public func MCEViewportSetExposureOverride(_ contextPtr: UnsafeRawPointer?,
                                           _ viewportID: UInt64,
                                           _ enabled: UInt32,
                                           _ mode: UInt32,
                                           _ compensation: Float,
                                           _ manualEV100: Float,
                                           _ locked: UInt32) {
    guard let context = resolveExposureContext(contextPtr), let renderer = context.engineContext.renderer else { return }
    let policy: ExposurePolicyOverride? = enabled == 0 ? nil : ExposurePolicyOverride(
        mode: ExposureMode(rawValue: mode),
        compensation: compensation,
        manualEV100: manualEV100
    )
    renderer.setViewportExposureOverride(policy, viewportID: viewportID, lockExposure: locked != 0)
}

@_cdecl("MCEViewportResetExposure")
public func MCEViewportResetExposure(_ contextPtr: UnsafeRawPointer?, _ viewportID: UInt64) {
    guard let context = resolveExposureContext(contextPtr) else { return }
    context.engineContext.renderer?.resetExposureHistory(viewportID: viewportID)
}

@_cdecl("MCEExposureGetDiagnostics")
public func MCEExposureGetDiagnostics(_ contextPtr: UnsafeRawPointer?,
                                      _ viewportID: UInt64,
                                      _ meteredLuminance: UnsafeMutablePointer<Float>?,
                                      _ targetEV100: UnsafeMutablePointer<Float>?,
                                      _ currentEV100: UnsafeMutablePointer<Float>?,
                                      _ gain: UnsafeMutablePointer<Float>?,
                                      _ compensation: UnsafeMutablePointer<Float>?,
                                      _ minimumEV100: UnsafeMutablePointer<Float>?,
                                      _ maximumEV100: UnsafeMutablePointer<Float>?,
                                      _ preExposure: UnsafeMutablePointer<Float>?,
                                      _ maximumStoredHDR: UnsafeMutablePointer<Float>?,
                                      _ saturationCount: UnsafeMutablePointer<UInt32>?,
                                      _ outdoorPriorStops: UnsafeMutablePointer<Float>?,
                                      _ adaptationState: UnsafeMutablePointer<CChar>?,
                                      _ adaptationStateCapacity: Int32,
                                      _ viewIdentity: UnsafeMutablePointer<CChar>?,
                                      _ viewIdentityCapacity: Int32,
                                      _ histogram128: UnsafeMutablePointer<UInt32>?,
                                      _ source: UnsafeMutablePointer<CChar>?,
                                      _ sourceCapacity: Int32) -> UInt32 {
    guard let context = resolveExposureContext(contextPtr),
          let diagnostics = context.engineContext.rendererDiagnostics.allExposureViews().last(where: {
              $0.identity.viewportInstanceID == viewportID
          }) else { return 0 }
    meteredLuminance?.pointee = diagnostics.meteredLuminance
    targetEV100?.pointee = diagnostics.targetEV100
    currentEV100?.pointee = diagnostics.currentEV100
    gain?.pointee = diagnostics.effectiveGain
    compensation?.pointee = diagnostics.compensation
    minimumEV100?.pointee = diagnostics.minimumEV100
    maximumEV100?.pointee = diagnostics.maximumEV100
    preExposure?.pointee = diagnostics.renderPreExposure
    maximumStoredHDR?.pointee = diagnostics.maximumStoredHDR
    saturationCount?.pointee = diagnostics.fp16SaturationCount
    outdoorPriorStops?.pointee = diagnostics.outdoorPriorContribution
    if let histogram128 {
        for index in 0..<min(128, diagnostics.histogram.count) { histogram128[index] = diagnostics.histogram[index] }
    }
    writeExposureCString(diagnostics.adaptationState, to: adaptationState, capacity: adaptationStateCapacity)
    let identity = diagnostics.identity
    writeExposureCString("scene=\(identity.sceneID.uuidString) camera=\(identity.cameraID.uuidString) viewport=\(identity.viewportInstanceID) kind=\(identity.viewKind.rawValue)",
                         to: viewIdentity,
                         capacity: viewIdentityCapacity)
    writeExposureCString(diagnostics.resolvedSource, to: source, capacity: sourceCapacity)
    return 1
}

@_cdecl("MCEEditorGetPostProcessExposureVolume")
public func MCEEditorGetPostProcessExposureVolume(_ contextPtr: UnsafeRawPointer?,
                                                   _ entityId: UnsafePointer<CChar>?,
                                                   _ enabled: UnsafeMutablePointer<UInt32>?,
                                                   _ isGlobal: UnsafeMutablePointer<UInt32>?,
                                                   _ priority: UnsafeMutablePointer<Int32>?,
                                                   _ blendDistance: UnsafeMutablePointer<Float>?,
                                                   _ weight: UnsafeMutablePointer<Float>?,
                                                   _ overrideMask: UnsafeMutablePointer<UInt64>?,
                                                   _ mode: UnsafeMutablePointer<UInt32>?,
                                                   _ compensation: UnsafeMutablePointer<Float>?,
                                                   _ manualEV100: UnsafeMutablePointer<Float>?,
                                                   _ aperture: UnsafeMutablePointer<Float>?,
                                                   _ shutterSeconds: UnsafeMutablePointer<Float>?,
                                                   _ iso: UnsafeMutablePointer<Float>?,
                                                   _ meteringMode: UnsafeMutablePointer<UInt32>?,
                                                   _ lowPercentile: UnsafeMutablePointer<Float>?,
                                                   _ highPercentile: UnsafeMutablePointer<Float>?,
                                                   _ minimumEV100: UnsafeMutablePointer<Float>?,
                                                   _ maximumEV100: UnsafeMutablePointer<Float>?,
                                                   _ darkAdaptationRate: UnsafeMutablePointer<Float>?,
                                                   _ lightAdaptationRate: UnsafeMutablePointer<Float>?) -> UInt32 {
    guard let context = resolveExposureContext(contextPtr),
          let scene = context.bridgeServices.activeScene(),
          let entity = resolveExposureEntity(entityId, context: context),
          let volume = scene.ecs.get(PostProcessVolumeComponent.self, for: entity) else { return 0 }
    let resolved = ExposurePolicyResolver.resolve(project: context.engineContext.projectExposureDefaults,
                                                  volumes: [ExposureOverrideLayer(policy: volume.exposure,
                                                                                 source: "Post Process Volume")]).settings
    enabled?.pointee = volume.enabled ? 1 : 0
    isGlobal?.pointee = volume.isGlobal ? 1 : 0
    priority?.pointee = Int32(clamping: volume.priority)
    blendDistance?.pointee = volume.blendDistance
    weight?.pointee = volume.weight
    overrideMask?.pointee = ExposureOverrideFieldMask.fields(in: volume.exposure).rawValue
    writeExposure(resolved, mode, compensation, manualEV100, aperture, shutterSeconds, iso,
                  meteringMode, nil, nil, lowPercentile, highPercentile, minimumEV100, maximumEV100,
                  darkAdaptationRate, lightAdaptationRate, nil, nil, nil, nil, nil)
    return 1
}

@_cdecl("MCEEditorSetPostProcessExposureVolume")
public func MCEEditorSetPostProcessExposureVolume(_ contextPtr: UnsafeRawPointer?,
                                                   _ entityId: UnsafePointer<CChar>?,
                                                   _ enabled: UInt32, _ isGlobal: UInt32,
                                                   _ priority: Int32, _ blendDistance: Float, _ weight: Float,
                                                   _ overrideMask: UInt64, _ mode: UInt32, _ compensation: Float,
                                                   _ manualEV100: Float, _ aperture: Float, _ shutterSeconds: Float,
                                                   _ iso: Float, _ meteringMode: UInt32,
                                                   _ lowPercentile: Float, _ highPercentile: Float,
                                                   _ minimumEV100: Float, _ maximumEV100: Float,
                                                   _ darkAdaptationRate: Float, _ lightAdaptationRate: Float) {
    guard let context = resolveExposureContext(contextPtr),
          !context.bridgeServices.isPlaying, !context.bridgeServices.isSimulating,
          let scene = context.bridgeServices.activeScene(),
          let entity = resolveExposureEntity(entityId, context: context),
          var volume = scene.ecs.get(PostProcessVolumeComponent.self, for: entity) else { return }
    let mask = ExposureOverrideFieldMask(rawValue: overrideMask)
    var policy = volume.exposure
    policy.mode = mask.contains(.mode) ? (ExposureMode(rawValue: mode) ?? .automaticHistogram) : nil
    policy.compensation = mask.contains(.compensation) ? compensation : nil
    policy.manualEV100 = mask.contains(.manualEV100) ? manualEV100 : nil
    policy.aperture = mask.contains(.aperture) ? aperture : nil
    policy.shutterSeconds = mask.contains(.shutterSeconds) ? shutterSeconds : nil
    policy.iso = mask.contains(.iso) ? iso : nil
    policy.meteringMode = mask.contains(.meteringMode) ? (ExposureMeteringMode(rawValue: meteringMode) ?? .centerWeighted) : nil
    policy.lowPercentile = mask.contains(.percentiles) ? lowPercentile : nil
    policy.highPercentile = mask.contains(.percentiles) ? highPercentile : nil
    policy.minimumEV100 = mask.contains(.limits) ? minimumEV100 : nil
    policy.maximumEV100 = mask.contains(.limits) ? maximumEV100 : nil
    policy.darkAdaptationRate = mask.contains(.adaptation) ? darkAdaptationRate : nil
    policy.lightAdaptationRate = mask.contains(.adaptation) ? lightAdaptationRate : nil
    volume = PostProcessVolumeComponent(enabled: enabled != 0,
                                        isGlobal: isGlobal != 0,
                                        priority: Int(priority),
                                        blendDistance: blendDistance,
                                        weight: weight,
                                        exposure: policy)
    scene.ecs.add(volume, to: entity)
    context.bridgeServices.notifySceneMutation()
}
