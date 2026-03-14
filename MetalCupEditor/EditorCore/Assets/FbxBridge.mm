#import "FbxBridge.h"

#include <cstring>
#include <string>

bool MCEFbxSkeletonExtractor_Extract(const char *path,
                                     MCEFbxSceneDTO *outScene,
                                     std::string &errorMessage);
bool MCEFbxAnimationExtractor_Extract(const char *path,
                                      MCEFbxSceneDTO *outScene,
                                      std::string &errorMessage);

static void MCEFbxWriteError(char *buffer, int32_t size, const std::string &error) {
    if (buffer == nullptr || size <= 0) {
        return;
    }
    const size_t maxLength = static_cast<size_t>(size - 1);
    const size_t copyLength = std::min(maxLength, error.size());
    if (copyLength > 0) {
        std::memcpy(buffer, error.data(), copyLength);
    }
    buffer[copyLength] = '\0';
}

bool MCEFbxExtractScene(const char *path,
                        MCEFbxSceneDTO *outScene,
                        char *errorBuffer,
                        int32_t errorBufferSize) {
    if (outScene == nullptr) {
        MCEFbxWriteError(errorBuffer, errorBufferSize, "FBX bridge received null scene output.");
        return false;
    }

    std::memset(outScene, 0, sizeof(MCEFbxSceneDTO));

    std::string errorMessage;
    if (!MCEFbxSkeletonExtractor_Extract(path, outScene, errorMessage)) {
        MCEFbxWriteError(errorBuffer, errorBufferSize, errorMessage);
        return false;
    }
    if (!MCEFbxAnimationExtractor_Extract(path, outScene, errorMessage)) {
        MCEFbxFreeScene(outScene);
        MCEFbxWriteError(errorBuffer, errorBufferSize, errorMessage);
        return false;
    }
    return true;
}

void MCEFbxFreeScene(MCEFbxSceneDTO *scene) {
    if (scene == nullptr) {
        return;
    }
    for (int32_t jointIndex = 0; jointIndex < scene->jointCount; ++jointIndex) {
        std::free(scene->joints[jointIndex].name);
        scene->joints[jointIndex].name = nullptr;
    }
    std::free(scene->joints);
    scene->joints = nullptr;
    scene->jointCount = 0;

    for (int32_t clipIndex = 0; clipIndex < scene->clipCount; ++clipIndex) {
        MCEFbxClipDTO &clip = scene->clips[clipIndex];
        std::free(clip.name);
        clip.name = nullptr;
        for (int32_t trackIndex = 0; trackIndex < clip.trackCount; ++trackIndex) {
            MCEFbxJointTrackDTO &track = clip.tracks[trackIndex];
            std::free(track.translations);
            std::free(track.rotations);
            std::free(track.scales);
            track.translations = nullptr;
            track.rotations = nullptr;
            track.scales = nullptr;
            track.translationCount = 0;
            track.rotationCount = 0;
            track.scaleCount = 0;
        }
        std::free(clip.tracks);
        clip.tracks = nullptr;
        clip.trackCount = 0;
    }
    std::free(scene->clips);
    scene->clips = nullptr;
    scene->clipCount = 0;
}
