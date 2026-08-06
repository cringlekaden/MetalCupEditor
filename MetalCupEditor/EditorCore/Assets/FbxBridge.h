#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *name;
    int32_t parentIndex;
    float bindLocalPositionX;
    float bindLocalPositionY;
    float bindLocalPositionZ;
    float bindLocalRotationX;
    float bindLocalRotationY;
    float bindLocalRotationZ;
    float bindLocalRotationW;
    float bindLocalScaleX;
    float bindLocalScaleY;
    float bindLocalScaleZ;
    bool hasInverseBindGlobal;
    float *inverseBindGlobal;
} MCEFbxJointDTO;

typedef struct {
    float time;
    float valueX;
    float valueY;
    float valueZ;
} MCEFbxTranslationKeyDTO;

typedef struct {
    float time;
    float valueX;
    float valueY;
    float valueZ;
    float valueW;
} MCEFbxRotationKeyDTO;

typedef struct {
    float time;
    float valueX;
    float valueY;
    float valueZ;
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
    char *name;
    int32_t materialIndex;
    int32_t vertexCount;
    float *positions;
    float *normals;
    float *tangents;
    float *uv0;
    int32_t indexCount;
    uint32_t *indices;
    bool hasSkinning;
    uint16_t *jointIndices;
    float *jointWeights;
} MCEFbxMeshDTO;

typedef struct {
    char *name;
    float baseColorR;
    float baseColorG;
    float baseColorB;
    float emissiveColorR;
    float emissiveColorG;
    float emissiveColorB;
    float metallicFactor;
    float roughnessFactor;
    float alpha;
    float alphaCutoff;
    char *baseColorTexturePath;
    bool baseColorTextureEmbedded;
    char *normalTexturePath;
    bool normalTextureEmbedded;
    char *metallicTexturePath;
    bool metallicTextureEmbedded;
    char *roughnessTexturePath;
    bool roughnessTextureEmbedded;
    char *metallicRoughnessTexturePath;
    bool metallicRoughnessTextureEmbedded;
    char *occlusionTexturePath;
    bool occlusionTextureEmbedded;
    char *emissiveTexturePath;
    bool emissiveTextureEmbedded;
} MCEFbxMaterialDTO;

typedef struct {
    int32_t jointCount;
    MCEFbxJointDTO *joints;
    int32_t clipCount;
    MCEFbxClipDTO *clips;
    int32_t meshCount;
    MCEFbxMeshDTO *meshes;
    int32_t materialCount;
    MCEFbxMaterialDTO *materials;
    float importScaleFactor;
    char *importScaleSource;
} MCEFbxSceneDTO;

bool MCEFbxExtractScene(const char *path,
                        MCEFbxSceneDTO *outScene,
                        char *errorBuffer,
                        int32_t errorBufferSize);

void MCEFbxFreeScene(MCEFbxSceneDTO *scene);

#ifdef __cplusplus
} // extern "C"
#endif
