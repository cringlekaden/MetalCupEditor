#include <string>
#include "FbxBridge.h"

bool MCEFbxAnimationExtractor_Extract(const char *path,
                                      MCEFbxSceneDTO *outScene,
                                      std::string &errorMessage) {
    if (path == nullptr || outScene == nullptr) {
        errorMessage = "Invalid input for FBX animation extraction.";
        return false;
    }

#if __has_include(<fbxsdk.h>)
    // Stage 2 placeholder. This will be replaced with a full FBX SDK implementation
    // that evaluates stacks/layers and emits per-joint TRS keys in seconds.
    errorMessage = "FBX SDK animation extractor is not fully implemented.";
    return false;
#else
    errorMessage = "FBX SDK headers not available. Skipping FBX animation extraction.";
    return false;
#endif
}
