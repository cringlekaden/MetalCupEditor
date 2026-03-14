#include <string>
#include "FbxBridge.h"

bool MCEFbxSkeletonExtractor_Extract(const char *path,
                                     MCEFbxSceneDTO *outScene,
                                     std::string &errorMessage) {
    if (path == nullptr || outScene == nullptr) {
        errorMessage = "Invalid input for FBX skeleton extraction.";
        return false;
    }

#if __has_include(<fbxsdk.h>)
    // Stage 1 placeholder. This will be replaced with a full FBX SDK implementation
    // that preserves deform hierarchy, exact names, bind locals, and inverse binds.
    errorMessage = "FBX SDK skeleton extractor is not fully implemented.";
    return false;
#else
    errorMessage = "FBX SDK headers not available. Skipping FBX skeleton extraction.";
    return false;
#endif
}
