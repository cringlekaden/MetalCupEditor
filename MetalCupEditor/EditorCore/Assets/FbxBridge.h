#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *name;
    int32_t parentIndex;
    float bindLocalPosition[3];
    float bindLocalRotation[4];
    float bindLocalScale[3];
    bool hasInverseBindGlobal;
    float inverseBindGlobal[16];
} MCEFbxJointDTO;

typedef struct {
    float time;
    float value[3];
} MCEFbxTranslationKeyDTO;

typedef struct {
    float time;
    float value[4];
} MCEFbxRotationKeyDTO;

typedef struct {
    float time;
    float value[3];
} MCEFbxScaleKeyDTO;

typedef struct {
    int32_t jointIndex;
    int32_t translationCount;
    MCEFbxTranslationKeyDTO *translations;
    int32_t rotationCount;
    MCEFbxRotationKeyDTO *rotations;
    int32_t scaleCount;
    MCEFbxScaleKeyDTO *scales;
} MCEFbxJointTrackDTO;

typedef struct {
    char *name;
    float durationSeconds;
    int32_t trackCount;
    MCEFbxJointTrackDTO *tracks;
} MCEFbxClipDTO;

typedef struct {
    int32_t jointCount;
    MCEFbxJointDTO *joints;
    int32_t clipCount;
    MCEFbxClipDTO *clips;
} MCEFbxSceneDTO;

bool MCEFbxExtractScene(const char *path,
                        MCEFbxSceneDTO *outScene,
                        char *errorBuffer,
                        int32_t errorBufferSize);

void MCEFbxFreeScene(MCEFbxSceneDTO *scene);

#ifdef __cplusplus
} // extern "C"
#endif
