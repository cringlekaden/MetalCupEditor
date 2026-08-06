#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>

#include "FbxBridge.h"

#if __has_include(<fbxsdk.h>)
#include <fbxsdk.h>
#define MCE_HAS_FBXSDK 1
#else
#define MCE_HAS_FBXSDK 0
#endif

namespace {

#if MCE_HAS_FBXSDK

static char *CopyCString(const std::string &value) {
    char *memory = static_cast<char *>(std::malloc(value.size() + 1));
    if (memory == nullptr) {
        return nullptr;
    }
    std::memcpy(memory, value.c_str(), value.size() + 1);
    return memory;
}

static std::string NodeName(FbxNode *node) {
    if (node == nullptr || node->GetName() == nullptr) {
        return std::string();
    }
    return std::string(node->GetName());
}

static void CollectNodesByName(FbxNode *node, std::unordered_map<std::string, FbxNode *> &outByName) {
    if (node == nullptr) {
        return;
    }
    outByName[NodeName(node)] = node;
    const int childCount = node->GetChildCount();
    for (int childIndex = 0; childIndex < childCount; ++childIndex) {
        CollectNodesByName(node->GetChild(childIndex), outByName);
    }
}

static void CollectKeyTimes(FbxNode *node,
                            FbxAnimLayer *layer,
                            std::set<FbxLongLong> &outTicks) {
    if (node == nullptr || layer == nullptr) {
        return;
    }

    auto collectCurve = [&](FbxAnimCurve *curve) {
        if (curve == nullptr) {
            return;
        }
        const int keyCount = curve->KeyGetCount();
        for (int keyIndex = 0; keyIndex < keyCount; ++keyIndex) {
            outTicks.insert(curve->KeyGetTime(keyIndex).Get());
        }
    };

    collectCurve(node->LclTranslation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_X));
    collectCurve(node->LclTranslation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Y));
    collectCurve(node->LclTranslation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Z));

    collectCurve(node->LclRotation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_X));
    collectCurve(node->LclRotation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Y));
    collectCurve(node->LclRotation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Z));

    collectCurve(node->LclScaling.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_X));
    collectCurve(node->LclScaling.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Y));
    collectCurve(node->LclScaling.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Z));
}

static void FillTrackForJoint(FbxNode *node,
                              FbxAnimLayer *layer,
                              const FbxTime &startTime,
                              const FbxTime &endTime,
                              int32_t jointIndex,
                              MCEFbxJointTrackDTO &outTrack) {
    std::set<FbxLongLong> ticks;
    CollectKeyTimes(node, layer, ticks);
    ticks.insert(startTime.Get());
    ticks.insert(endTime.Get());

    if (ticks.empty()) {
        ticks.insert(startTime.Get());
    }

    const size_t keyCount = ticks.size();
    outTrack.jointIndex = jointIndex;
    outTrack.translationCount = static_cast<int32_t>(keyCount);
    outTrack.rotationCount = static_cast<int32_t>(keyCount);
    outTrack.scaleCount = static_cast<int32_t>(keyCount);
    outTrack.translations = static_cast<MCEFbxTranslationKeyDTO *>(std::calloc(keyCount, sizeof(MCEFbxTranslationKeyDTO)));
    outTrack.rotations = static_cast<MCEFbxRotationKeyDTO *>(std::calloc(keyCount, sizeof(MCEFbxRotationKeyDTO)));
    outTrack.scales = static_cast<MCEFbxScaleKeyDTO *>(std::calloc(keyCount, sizeof(MCEFbxScaleKeyDTO)));

    size_t writeIndex = 0;
    for (FbxLongLong tick : ticks) {
        FbxTime sampleTime;
        sampleTime.Set(tick);

        const FbxAMatrix local = node->EvaluateLocalTransform(sampleTime);
        const FbxVector4 t = local.GetT();
        const FbxQuaternion q = local.GetQ();
        const FbxVector4 s = local.GetS();

        const float seconds = static_cast<float>((sampleTime - startTime).GetSecondDouble());

        MCEFbxTranslationKeyDTO &translation = outTrack.translations[writeIndex];
        translation.time = seconds;
        translation.valueX = static_cast<float>(t[0]);
        translation.valueY = static_cast<float>(t[1]);
        translation.valueZ = static_cast<float>(t[2]);

        MCEFbxRotationKeyDTO &rotation = outTrack.rotations[writeIndex];
        rotation.time = seconds;
        rotation.valueX = static_cast<float>(q[0]);
        rotation.valueY = static_cast<float>(q[1]);
        rotation.valueZ = static_cast<float>(q[2]);
        rotation.valueW = static_cast<float>(q[3]);

        MCEFbxScaleKeyDTO &scale = outTrack.scales[writeIndex];
        scale.time = seconds;
        scale.valueX = static_cast<float>(s[0]);
        scale.valueY = static_cast<float>(s[1]);
        scale.valueZ = static_cast<float>(s[2]);

        ++writeIndex;
    }
}

#endif

} // namespace

bool MCEFbxAnimationExtractor_Extract(const char *path,
                                      MCEFbxSceneDTO *outScene,
                                      std::string &errorMessage) {
    if (path == nullptr || outScene == nullptr) {
        errorMessage = "Invalid input for FBX animation extraction.";
        return false;
    }

#if MCE_HAS_FBXSDK
    outScene->clipCount = 0;
    outScene->clips = nullptr;

    FbxManager *manager = FbxManager::Create();
    if (manager == nullptr) {
        errorMessage = "FBX SDK animation extractor failed to create manager.";
        return false;
    }
    FbxIOSettings *ioSettings = FbxIOSettings::Create(manager, IOSROOT);
    manager->SetIOSettings(ioSettings);

    FbxImporter *importer = FbxImporter::Create(manager, "");
    if (importer == nullptr) {
        manager->Destroy();
        errorMessage = "FBX SDK animation extractor failed to create importer.";
        return false;
    }
    if (!importer->Initialize(path, -1, manager->GetIOSettings())) {
        errorMessage = importer->GetStatus().GetErrorString();
        importer->Destroy();
        manager->Destroy();
        return false;
    }

    FbxScene *scene = FbxScene::Create(manager, "MetalCupAnimationScene");
    if (scene == nullptr) {
        importer->Destroy();
        manager->Destroy();
        errorMessage = "FBX SDK animation extractor failed to create scene.";
        return false;
    }
    if (!importer->Import(scene)) {
        errorMessage = importer->GetStatus().GetErrorString();
        scene->Destroy();
        importer->Destroy();
        manager->Destroy();
        return false;
    }

    std::unordered_map<std::string, FbxNode *> nodesByName;
    CollectNodesByName(scene->GetRootNode(), nodesByName);

    std::vector<FbxAnimStack *> animStacks;
    const int stackCount = scene->GetSrcObjectCount<FbxAnimStack>();
    animStacks.reserve(static_cast<size_t>(std::max(stackCount, 0)));
    for (int stackIndex = 0; stackIndex < stackCount; ++stackIndex) {
        FbxAnimStack *stack = scene->GetSrcObject<FbxAnimStack>(stackIndex);
        if (stack != nullptr) {
            animStacks.push_back(stack);
        }
    }

    if (animStacks.empty()) {
        scene->Destroy();
        importer->Destroy();
        manager->Destroy();
        return true;
    }

    outScene->clipCount = static_cast<int32_t>(animStacks.size());
    outScene->clips = static_cast<MCEFbxClipDTO *>(std::calloc(animStacks.size(), sizeof(MCEFbxClipDTO)));

    for (size_t clipIndex = 0; clipIndex < animStacks.size(); ++clipIndex) {
        FbxAnimStack *stack = animStacks[clipIndex];
        scene->SetCurrentAnimationStack(stack);

        FbxTime startTime;
        FbxTime endTime;
        FbxTakeInfo *takeInfo = scene->GetTakeInfo(stack->GetName());
        if (takeInfo != nullptr) {
            startTime = takeInfo->mLocalTimeSpan.GetStart();
            endTime = takeInfo->mLocalTimeSpan.GetStop();
        } else {
            FbxTimeSpan timeline;
            scene->GetGlobalSettings().GetTimelineDefaultTimeSpan(timeline);
            startTime = timeline.GetStart();
            endTime = timeline.GetStop();
        }
        if (endTime < startTime) {
            endTime = startTime;
        }

        MCEFbxClipDTO &clip = outScene->clips[clipIndex];
        clip.name = CopyCString(stack->GetName() != nullptr ? stack->GetName() : "Clip");
        clip.durationSeconds = static_cast<float>((endTime - startTime).GetSecondDouble());
        clip.trackCount = outScene->jointCount;

        if (outScene->jointCount > 0) {
            clip.tracks = static_cast<MCEFbxJointTrackDTO *>(std::calloc(static_cast<size_t>(outScene->jointCount), sizeof(MCEFbxJointTrackDTO)));
            for (int32_t jointIndex = 0; jointIndex < outScene->jointCount; ++jointIndex) {
                const MCEFbxJointDTO &joint = outScene->joints[jointIndex];
                std::string jointName = joint.name != nullptr ? std::string(joint.name) : std::string();
                auto nodeIt = nodesByName.find(jointName);
                if (nodeIt == nodesByName.end() || nodeIt->second == nullptr) {
                    FbxNode *fallbackNode = scene->FindNodeByName(FbxString(jointName.c_str()));
                    if (fallbackNode != nullptr) {
                        FillTrackForJoint(fallbackNode,
                                          stack->GetMemberCount<FbxAnimLayer>() > 0 ? stack->GetMember<FbxAnimLayer>(0) : nullptr,
                                          startTime,
                                          endTime,
                                          jointIndex,
                                          clip.tracks[jointIndex]);
                    }
                    continue;
                }

                FbxAnimLayer *layer = stack->GetMemberCount<FbxAnimLayer>() > 0 ? stack->GetMember<FbxAnimLayer>(0) : nullptr;
                FillTrackForJoint(nodeIt->second, layer, startTime, endTime, jointIndex, clip.tracks[jointIndex]);
            }
        }
    }

    scene->Destroy();
    importer->Destroy();
    manager->Destroy();
    return true;
#else
    errorMessage = "FBX SDK headers not available. Skipping FBX animation extraction.";
    return false;
#endif
}
