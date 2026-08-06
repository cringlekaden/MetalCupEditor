#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <map>
#include <set>
#include <string>
#include <unordered_map>
#include <utility>
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

struct JointBuildRecord {
    FbxNode *node;
    int32_t parentIndex;
};

struct VertexInfluence {
    int32_t jointIndex;
    double weight;
};

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

static void WriteMatrixToArray(const FbxAMatrix &matrix, float *out16) {
    if (out16 == nullptr) {
        return;
    }
    for (int r = 0; r < 4; ++r) {
        for (int c = 0; c < 4; ++c) {
            out16[(r * 4) + c] = static_cast<float>(matrix.Get(r, c));
        }
    }
}

static bool NodeHasAnimatedCurves(FbxNode *node, FbxAnimLayer *layer) {
    if (node == nullptr || layer == nullptr) {
        return false;
    }
    auto hasCurve = [&](FbxAnimCurve *curve) -> bool {
        return curve != nullptr && curve->KeyGetCount() > 0;
    };
    return hasCurve(node->LclTranslation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_X)) ||
        hasCurve(node->LclTranslation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Y)) ||
        hasCurve(node->LclTranslation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Z)) ||
        hasCurve(node->LclRotation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_X)) ||
        hasCurve(node->LclRotation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Y)) ||
        hasCurve(node->LclRotation.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Z)) ||
        hasCurve(node->LclScaling.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_X)) ||
        hasCurve(node->LclScaling.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Y)) ||
        hasCurve(node->LclScaling.GetCurve(layer, FBXSDK_CURVENODE_COMPONENT_Z));
}

static void GatherAnimatedNodes(FbxNode *node, FbxAnimLayer *layer, std::set<FbxNode *> &animatedNodes) {
    if (node == nullptr) {
        return;
    }
    if (NodeHasAnimatedCurves(node, layer)) {
        animatedNodes.insert(node);
    }
    const int childCount = node->GetChildCount();
    for (int childIndex = 0; childIndex < childCount; ++childIndex) {
        GatherAnimatedNodes(node->GetChild(childIndex), layer, animatedNodes);
    }
}

static void BuildAnimatedNodeSet(FbxScene *scene, std::set<FbxNode *> &animatedNodes) {
    if (scene == nullptr) {
        return;
    }
    FbxNode *root = scene->GetRootNode();
    if (root == nullptr) {
        return;
    }
    const int stackCount = scene->GetSrcObjectCount<FbxAnimStack>();
    for (int stackIndex = 0; stackIndex < stackCount; ++stackIndex) {
        FbxAnimStack *stack = scene->GetSrcObject<FbxAnimStack>(stackIndex);
        if (stack == nullptr) {
            continue;
        }
        const int layerCount = stack->GetMemberCount<FbxAnimLayer>();
        for (int layerIndex = 0; layerIndex < layerCount; ++layerIndex) {
            FbxAnimLayer *layer = stack->GetMember<FbxAnimLayer>(layerIndex);
            if (layer == nullptr) {
                continue;
            }
            GatherAnimatedNodes(root, layer, animatedNodes);
        }
    }
}

static FbxVector4 ResolveTangent(FbxMesh *mesh,
                                 int polygonIndex,
                                 int polygonVertexIndex,
                                 int controlPointIndex) {
    if (mesh == nullptr || mesh->GetElementTangentCount() <= 0) {
        return FbxVector4(1.0, 0.0, 0.0, 0.0);
    }
    FbxGeometryElementTangent *tangentElement = mesh->GetElementTangent(0);
    if (tangentElement == nullptr) {
        return FbxVector4(1.0, 0.0, 0.0, 0.0);
    }
    int tangentIndex = 0;
    if (tangentElement->GetMappingMode() == FbxGeometryElement::eByControlPoint) {
        tangentIndex = controlPointIndex;
    } else if (tangentElement->GetMappingMode() == FbxGeometryElement::eByPolygonVertex) {
        tangentIndex = mesh->GetTextureUVIndex(polygonIndex, polygonVertexIndex);
    } else {
        return FbxVector4(1.0, 0.0, 0.0, 0.0);
    }
    if (tangentElement->GetReferenceMode() == FbxGeometryElement::eIndexToDirect) {
        const auto &indexArray = tangentElement->GetIndexArray();
        if (tangentIndex < 0 || tangentIndex >= indexArray.GetCount()) {
            return FbxVector4(1.0, 0.0, 0.0, 0.0);
        }
        tangentIndex = indexArray.GetAt(tangentIndex);
    }
    const auto &directArray = tangentElement->GetDirectArray();
    if (tangentIndex < 0 || tangentIndex >= directArray.GetCount()) {
        return FbxVector4(1.0, 0.0, 0.0, 0.0);
    }
    return directArray.GetAt(tangentIndex);
}

static void BuildDeformerNodeSet(FbxScene *scene, std::set<FbxNode *> &deformerNodes) {
    if (scene == nullptr) {
        return;
    }
    const int geometryCount = scene->GetGeometryCount();
    for (int geometryIndex = 0; geometryIndex < geometryCount; ++geometryIndex) {
        FbxGeometry *geometry = scene->GetGeometry(geometryIndex);
        if (geometry == nullptr) {
            continue;
        }
        const int skinCount = geometry->GetDeformerCount(FbxDeformer::eSkin);
        for (int skinIndex = 0; skinIndex < skinCount; ++skinIndex) {
            FbxSkin *skin = static_cast<FbxSkin *>(geometry->GetDeformer(skinIndex, FbxDeformer::eSkin));
            if (skin == nullptr) {
                continue;
            }
            const int clusterCount = skin->GetClusterCount();
            for (int clusterIndex = 0; clusterIndex < clusterCount; ++clusterIndex) {
                FbxCluster *cluster = skin->GetCluster(clusterIndex);
                if (cluster == nullptr) {
                    continue;
                }
                FbxNode *link = cluster->GetLink();
                if (link != nullptr) {
                    deformerNodes.insert(link);
                }
            }
        }
    }
}

static bool NodeShouldBeInSkeleton(FbxNode *node,
                                   const std::set<FbxNode *> &deformerNodes,
                                   const std::set<FbxNode *> &animatedNodes) {
    if (node == nullptr) {
        return false;
    }
    if (deformerNodes.find(node) != deformerNodes.end()) {
        return true;
    }
    if (animatedNodes.find(node) != animatedNodes.end()) {
        return true;
    }
    FbxNodeAttribute *attribute = node->GetNodeAttribute();
    if (attribute != nullptr && attribute->GetAttributeType() == FbxNodeAttribute::eSkeleton) {
        return true;
    }
    return false;
}

static bool MarkIncludedSkeletonNodes(FbxNode *node,
                                      const std::set<FbxNode *> &deformerNodes,
                                      const std::set<FbxNode *> &animatedNodes,
                                      std::set<FbxNode *> &includedNodes) {
    if (node == nullptr) {
        return false;
    }
    bool includeSelf = NodeShouldBeInSkeleton(node, deformerNodes, animatedNodes);
    const int childCount = node->GetChildCount();
    for (int childIndex = 0; childIndex < childCount; ++childIndex) {
        if (MarkIncludedSkeletonNodes(node->GetChild(childIndex), deformerNodes, animatedNodes, includedNodes)) {
            includeSelf = true;
        }
    }
    if (includeSelf) {
        includedNodes.insert(node);
    }
    return includeSelf;
}

static void BuildInverseBindByName(FbxScene *scene,
                                   std::unordered_map<std::string, FbxAMatrix> &inverseBindByName) {
    if (scene == nullptr) {
        return;
    }
    const int geometryCount = scene->GetGeometryCount();
    for (int geometryIndex = 0; geometryIndex < geometryCount; ++geometryIndex) {
        FbxGeometry *geometry = scene->GetGeometry(geometryIndex);
        if (geometry == nullptr) {
            continue;
        }
        const int skinCount = geometry->GetDeformerCount(FbxDeformer::eSkin);
        for (int skinIndex = 0; skinIndex < skinCount; ++skinIndex) {
            FbxSkin *skin = static_cast<FbxSkin *>(geometry->GetDeformer(skinIndex, FbxDeformer::eSkin));
            if (skin == nullptr) {
                continue;
            }
            const int clusterCount = skin->GetClusterCount();
            for (int clusterIndex = 0; clusterIndex < clusterCount; ++clusterIndex) {
                FbxCluster *cluster = skin->GetCluster(clusterIndex);
                if (cluster == nullptr) {
                    continue;
                }
                FbxNode *link = cluster->GetLink();
                if (link == nullptr) {
                    continue;
                }
                FbxAMatrix linkGlobal;
                if (!cluster->GetTransformLinkMatrix(linkGlobal)) {
                    continue;
                }
                inverseBindByName[NodeName(link)] = linkGlobal.Inverse();
            }
        }
    }
}

static void BuildJointList(FbxNode *node,
                           int32_t parentIndex,
                           const std::set<FbxNode *> &includedNodes,
                           std::vector<JointBuildRecord> &outRecords,
                           std::unordered_map<FbxNode *, int32_t> &outIndexByNode) {
    if (node == nullptr) {
        return;
    }

    int32_t nextParent = parentIndex;
    if (includedNodes.find(node) != includedNodes.end()) {
        JointBuildRecord record;
        record.node = node;
        record.parentIndex = parentIndex;
        outRecords.push_back(record);
        nextParent = static_cast<int32_t>(outRecords.size() - 1);
        outIndexByNode[node] = nextParent;
    }

    const int childCount = node->GetChildCount();
    for (int childIndex = 0; childIndex < childCount; ++childIndex) {
        BuildJointList(node->GetChild(childIndex), nextParent, includedNodes, outRecords, outIndexByNode);
    }
}

static void FillJointDTOs(const std::vector<JointBuildRecord> &jointRecords,
                          const std::unordered_map<std::string, FbxAMatrix> &inverseBindByName,
                          MCEFbxSceneDTO *outScene) {
    const size_t jointCount = jointRecords.size();
    outScene->jointCount = static_cast<int32_t>(jointCount);
    if (jointCount == 0) {
        outScene->joints = nullptr;
        return;
    }

    outScene->joints = static_cast<MCEFbxJointDTO *>(std::calloc(jointCount, sizeof(MCEFbxJointDTO)));
    for (size_t jointIndex = 0; jointIndex < jointCount; ++jointIndex) {
        const JointBuildRecord &record = jointRecords[jointIndex];
        MCEFbxJointDTO &joint = outScene->joints[jointIndex];
        joint.name = CopyCString(NodeName(record.node));
        joint.parentIndex = record.parentIndex;

        const FbxAMatrix local = record.node->EvaluateLocalTransform(FbxTime(0));
        const FbxVector4 localT = local.GetT();
        const FbxQuaternion localQ = local.GetQ();
        const FbxVector4 localS = local.GetS();

        joint.bindLocalPositionX = static_cast<float>(localT[0]);
        joint.bindLocalPositionY = static_cast<float>(localT[1]);
        joint.bindLocalPositionZ = static_cast<float>(localT[2]);

        joint.bindLocalRotationX = static_cast<float>(localQ[0]);
        joint.bindLocalRotationY = static_cast<float>(localQ[1]);
        joint.bindLocalRotationZ = static_cast<float>(localQ[2]);
        joint.bindLocalRotationW = static_cast<float>(localQ[3]);

        joint.bindLocalScaleX = static_cast<float>(localS[0]);
        joint.bindLocalScaleY = static_cast<float>(localS[1]);
        joint.bindLocalScaleZ = static_cast<float>(localS[2]);

        const std::string key = NodeName(record.node);
        auto inverseIt = inverseBindByName.find(key);
        FbxAMatrix inverseBind = inverseIt != inverseBindByName.end()
            ? inverseIt->second
            : record.node->EvaluateGlobalTransform(FbxTime(0)).Inverse();

        joint.hasInverseBindGlobal = true;
        joint.inverseBindGlobal = static_cast<float *>(std::malloc(sizeof(float) * 16));
        WriteMatrixToArray(inverseBind, joint.inverseBindGlobal);
    }
}

static FbxDouble ReadDoubleProperty(FbxSurfaceMaterial *material,
                                    const char *propertyName,
                                    FbxDouble fallbackValue) {
    if (material == nullptr || propertyName == nullptr) {
        return fallbackValue;
    }
    FbxProperty property = material->FindProperty(propertyName);
    if (!property.IsValid()) {
        return fallbackValue;
    }
    if (property.GetPropertyDataType().GetType() == eFbxDouble ||
        property.GetPropertyDataType().GetType() == eFbxFloat ||
        property.GetPropertyDataType().GetType() == eFbxDouble4 ||
        property.GetPropertyDataType().GetType() == eFbxDouble3 ||
        property.GetPropertyDataType().GetType() == eFbxDouble2) {
        return property.Get<FbxDouble>();
    }
    return fallbackValue;
}

static std::string ExtractTexturePath(FbxProperty property, bool &outEmbedded) {
    outEmbedded = false;
    if (!property.IsValid()) {
        return std::string();
    }

    const int layeredCount = property.GetSrcObjectCount<FbxLayeredTexture>();
    for (int layeredIndex = 0; layeredIndex < layeredCount; ++layeredIndex) {
        FbxLayeredTexture *layered = property.GetSrcObject<FbxLayeredTexture>(layeredIndex);
        if (layered == nullptr) {
            continue;
        }
        const int textureCount = layered->GetSrcObjectCount<FbxFileTexture>();
        for (int textureIndex = 0; textureIndex < textureCount; ++textureIndex) {
            FbxFileTexture *texture = layered->GetSrcObject<FbxFileTexture>(textureIndex);
            if (texture == nullptr) {
                continue;
            }
            const char *relative = texture->GetRelativeFileName();
            if (relative != nullptr && relative[0] != '\0') {
                return std::string(relative);
            }
            const char *fileName = texture->GetFileName();
            if (fileName != nullptr && fileName[0] != '\0') {
                return std::string(fileName);
            }
        }
    }

    const int textureCount = property.GetSrcObjectCount<FbxFileTexture>();
    for (int textureIndex = 0; textureIndex < textureCount; ++textureIndex) {
        FbxFileTexture *texture = property.GetSrcObject<FbxFileTexture>(textureIndex);
        if (texture == nullptr) {
            continue;
        }
        const char *relative = texture->GetRelativeFileName();
        if (relative != nullptr && relative[0] != '\0') {
            return std::string(relative);
        }
        const char *fileName = texture->GetFileName();
        if (fileName != nullptr && fileName[0] != '\0') {
            return std::string(fileName);
        }
    }

    const int videoCount = property.GetSrcObjectCount<FbxVideo>();
    if (videoCount > 0) {
        outEmbedded = true;
    }
    return std::string();
}

static void FillMaterialDTOs(FbxScene *scene, MCEFbxSceneDTO *outScene) {
    if (scene == nullptr) {
        outScene->materialCount = 0;
        outScene->materials = nullptr;
        return;
    }

    const int materialCount = scene->GetMaterialCount();
    outScene->materialCount = materialCount;
    if (materialCount <= 0) {
        outScene->materials = nullptr;
        return;
    }

    outScene->materials = static_cast<MCEFbxMaterialDTO *>(std::calloc(static_cast<size_t>(materialCount), sizeof(MCEFbxMaterialDTO)));
    for (int materialIndex = 0; materialIndex < materialCount; ++materialIndex) {
        FbxSurfaceMaterial *material = scene->GetMaterial(materialIndex);
        MCEFbxMaterialDTO &dto = outScene->materials[materialIndex];
        dto.name = CopyCString(material != nullptr && material->GetName() != nullptr ? material->GetName() : "Material");

        FbxDouble3 diffuse(1.0, 1.0, 1.0);
        FbxDouble3 emissive(0.0, 0.0, 0.0);
        FbxDouble transparencyFactor = 0.0;

        if (material != nullptr) {
            if (material->GetClassId().Is(FbxSurfacePhong::ClassId)) {
                FbxSurfacePhong *phong = static_cast<FbxSurfacePhong *>(material);
                diffuse = phong->Diffuse.Get();
                emissive = phong->Emissive.Get();
                transparencyFactor = phong->TransparencyFactor.Get();
            } else if (material->GetClassId().Is(FbxSurfaceLambert::ClassId)) {
                FbxSurfaceLambert *lambert = static_cast<FbxSurfaceLambert *>(material);
                diffuse = lambert->Diffuse.Get();
                emissive = lambert->Emissive.Get();
                transparencyFactor = lambert->TransparencyFactor.Get();
            }
        }

        dto.baseColorR = static_cast<float>(diffuse[0]);
        dto.baseColorG = static_cast<float>(diffuse[1]);
        dto.baseColorB = static_cast<float>(diffuse[2]);
        dto.emissiveColorR = static_cast<float>(emissive[0]);
        dto.emissiveColorG = static_cast<float>(emissive[1]);
        dto.emissiveColorB = static_cast<float>(emissive[2]);
        dto.alpha = static_cast<float>(std::max(0.0, std::min(1.0, 1.0 - transparencyFactor)));
        dto.alphaCutoff = 0.5f;

        dto.metallicFactor = static_cast<float>(ReadDoubleProperty(material, "Metalness", 1.0));
        if (std::abs(dto.metallicFactor - 1.0f) < 0.0001f) {
            dto.metallicFactor = static_cast<float>(ReadDoubleProperty(material, "Maya|metalness", 1.0));
        }
        dto.roughnessFactor = static_cast<float>(ReadDoubleProperty(material, "Roughness", 1.0));
        if (std::abs(dto.roughnessFactor - 1.0f) < 0.0001f) {
            dto.roughnessFactor = static_cast<float>(ReadDoubleProperty(material, "Maya|roughness", 1.0));
        }

        bool embedded = false;
        if (material != nullptr) {
            std::string path = ExtractTexturePath(material->FindProperty(FbxSurfaceMaterial::sDiffuse), embedded);
            dto.baseColorTexturePath = path.empty() ? nullptr : CopyCString(path);
            dto.baseColorTextureEmbedded = embedded;

            path = ExtractTexturePath(material->FindProperty(FbxSurfaceMaterial::sNormalMap), embedded);
            if (path.empty()) {
                path = ExtractTexturePath(material->FindProperty(FbxSurfaceMaterial::sBump), embedded);
            }
            dto.normalTexturePath = path.empty() ? nullptr : CopyCString(path);
            dto.normalTextureEmbedded = embedded;

            path = ExtractTexturePath(material->FindProperty("Metalness"), embedded);
            if (path.empty()) {
                path = ExtractTexturePath(material->FindProperty("Maya|metalness"), embedded);
            }
            dto.metallicTexturePath = path.empty() ? nullptr : CopyCString(path);
            dto.metallicTextureEmbedded = embedded;

            path = ExtractTexturePath(material->FindProperty("Roughness"), embedded);
            if (path.empty()) {
                path = ExtractTexturePath(material->FindProperty("Maya|roughness"), embedded);
            }
            dto.roughnessTexturePath = path.empty() ? nullptr : CopyCString(path);
            dto.roughnessTextureEmbedded = embedded;

            path = ExtractTexturePath(material->FindProperty("MetallicRoughness"), embedded);
            dto.metallicRoughnessTexturePath = path.empty() ? nullptr : CopyCString(path);
            dto.metallicRoughnessTextureEmbedded = embedded;

            path = ExtractTexturePath(material->FindProperty("Occlusion"), embedded);
            dto.occlusionTexturePath = path.empty() ? nullptr : CopyCString(path);
            dto.occlusionTextureEmbedded = embedded;

            path = ExtractTexturePath(material->FindProperty(FbxSurfaceMaterial::sEmissive), embedded);
            dto.emissiveTexturePath = path.empty() ? nullptr : CopyCString(path);
            dto.emissiveTextureEmbedded = embedded;
        }
    }
}

static void GatherControlPointInfluences(FbxMesh *mesh,
                                         const std::unordered_map<std::string, int32_t> &jointIndexByName,
                                         std::vector<std::vector<VertexInfluence>> &outInfluences) {
    if (mesh == nullptr) {
        return;
    }
    const int controlPointCount = mesh->GetControlPointsCount();
    outInfluences.clear();
    outInfluences.resize(static_cast<size_t>(std::max(controlPointCount, 0)));

    const int skinCount = mesh->GetDeformerCount(FbxDeformer::eSkin);
    for (int skinIndex = 0; skinIndex < skinCount; ++skinIndex) {
        FbxSkin *skin = static_cast<FbxSkin *>(mesh->GetDeformer(skinIndex, FbxDeformer::eSkin));
        if (skin == nullptr) {
            continue;
        }
        const int clusterCount = skin->GetClusterCount();
        for (int clusterIndex = 0; clusterIndex < clusterCount; ++clusterIndex) {
            FbxCluster *cluster = skin->GetCluster(clusterIndex);
            if (cluster == nullptr || cluster->GetLink() == nullptr) {
                continue;
            }
            auto jointIt = jointIndexByName.find(NodeName(cluster->GetLink()));
            if (jointIt == jointIndexByName.end()) {
                continue;
            }
            const int32_t jointIndex = jointIt->second;
            const int *cpIndices = cluster->GetControlPointIndices();
            const double *cpWeights = cluster->GetControlPointWeights();
            const int cpCount = cluster->GetControlPointIndicesCount();
            for (int cpOffset = 0; cpOffset < cpCount; ++cpOffset) {
                const int cpIndex = cpIndices[cpOffset];
                if (cpIndex < 0 || cpIndex >= controlPointCount) {
                    continue;
                }
                const double weight = cpWeights[cpOffset];
                if (weight <= 0.0) {
                    continue;
                }
                outInfluences[static_cast<size_t>(cpIndex)].push_back(VertexInfluence { jointIndex, weight });
            }
        }
    }

    for (size_t cpIndex = 0; cpIndex < outInfluences.size(); ++cpIndex) {
        std::vector<VertexInfluence> &influences = outInfluences[cpIndex];
        std::sort(influences.begin(), influences.end(), [](const VertexInfluence &lhs, const VertexInfluence &rhs) {
            return lhs.weight > rhs.weight;
        });
        if (influences.size() > 4) {
            influences.resize(4);
        }
        double weightSum = 0.0;
        for (const VertexInfluence &influence : influences) {
            weightSum += influence.weight;
        }
        if (weightSum > 0.0) {
            for (VertexInfluence &influence : influences) {
                influence.weight /= weightSum;
            }
        }
    }
}

static int MaterialIndexForPolygon(FbxMesh *mesh, int polygonIndex) {
    if (mesh == nullptr) {
        return 0;
    }
    FbxLayerElementMaterial *materialLayer = mesh->GetElementMaterial();
    if (materialLayer == nullptr) {
        return 0;
    }
    if (materialLayer->GetMappingMode() == FbxLayerElement::eByPolygon) {
        const FbxLayerElementArrayTemplate<int> &indices = materialLayer->GetIndexArray();
        if (polygonIndex >= 0 && polygonIndex < indices.GetCount()) {
            return std::max(0, indices.GetAt(polygonIndex));
        }
    }
    if (materialLayer->GetMappingMode() == FbxLayerElement::eAllSame) {
        const FbxLayerElementArrayTemplate<int> &indices = materialLayer->GetIndexArray();
        if (indices.GetCount() > 0) {
            return std::max(0, indices.GetAt(0));
        }
    }
    return 0;
}

struct MeshBucket {
    std::string name;
    int materialIndex = 0;
    std::vector<float> positions;
    std::vector<float> normals;
    std::vector<float> tangents;
    std::vector<float> uv0;
    std::vector<uint32_t> indices;
    std::vector<uint16_t> jointIndices;
    std::vector<float> jointWeights;
    bool hasSkinning = false;
};

static void FillMeshDTOs(FbxScene *scene,
                         const std::unordered_map<std::string, int32_t> &jointIndexByName,
                         MCEFbxSceneDTO *outScene) {
    if (scene == nullptr) {
        outScene->meshCount = 0;
        outScene->meshes = nullptr;
        return;
    }

    std::vector<MeshBucket> buckets;
    FbxNode *root = scene->GetRootNode();
    if (root == nullptr) {
        outScene->meshCount = 0;
        outScene->meshes = nullptr;
        return;
    }

    std::function<void(FbxNode *)> traverse = [&](FbxNode *node) {
        if (node == nullptr) {
            return;
        }
        FbxMesh *mesh = node->GetMesh();
        if (mesh != nullptr) {
            const int polygonCount = mesh->GetPolygonCount();
            FbxStringList uvSetNames;
            mesh->GetUVSetNames(uvSetNames);
            const char *uvSetName = uvSetNames.GetCount() > 0 ? uvSetNames.GetStringAt(0) : nullptr;

            std::vector<std::vector<VertexInfluence>> influences;
            GatherControlPointInfluences(mesh, jointIndexByName, influences);

            std::map<int, MeshBucket> localBuckets;
            const FbxVector4 *controlPoints = mesh->GetControlPoints();

            for (int polygonIndex = 0; polygonIndex < polygonCount; ++polygonIndex) {
                const int polygonSize = mesh->GetPolygonSize(polygonIndex);
                if (polygonSize != 3) {
                    continue;
                }
                int materialIndex = MaterialIndexForPolygon(mesh, polygonIndex);
                MeshBucket &bucket = localBuckets[materialIndex];
                if (bucket.name.empty()) {
                    const std::string nodeName = NodeName(node);
                    bucket.name = nodeName.empty() ? "Mesh" : nodeName;
                    bucket.materialIndex = materialIndex;
                }

                for (int polygonVertex = 0; polygonVertex < 3; ++polygonVertex) {
                    const int controlPointIndex = mesh->GetPolygonVertex(polygonIndex, polygonVertex);
                    if (controlPointIndex < 0 || controlPoints == nullptr) {
                        continue;
                    }
                    const FbxVector4 p = controlPoints[controlPointIndex];
                    bucket.positions.push_back(static_cast<float>(p[0]));
                    bucket.positions.push_back(static_cast<float>(p[1]));
                    bucket.positions.push_back(static_cast<float>(p[2]));

                    FbxVector4 n(0.0, 1.0, 0.0, 0.0);
                    if (mesh->GetPolygonVertexNormal(polygonIndex, polygonVertex, n)) {
                        bucket.normals.push_back(static_cast<float>(n[0]));
                        bucket.normals.push_back(static_cast<float>(n[1]));
                        bucket.normals.push_back(static_cast<float>(n[2]));
                    } else {
                        bucket.normals.push_back(0.0f);
                        bucket.normals.push_back(1.0f);
                        bucket.normals.push_back(0.0f);
                    }

                    FbxVector4 t = ResolveTangent(mesh, polygonIndex, polygonVertex, controlPointIndex);
                    bucket.tangents.push_back(static_cast<float>(t[0]));
                    bucket.tangents.push_back(static_cast<float>(t[1]));
                    bucket.tangents.push_back(static_cast<float>(t[2]));

                    FbxVector2 uv(0.0, 0.0);
                    bool unmapped = false;
                    if (uvSetName != nullptr) {
                        mesh->GetPolygonVertexUV(polygonIndex, polygonVertex, uvSetName, uv, unmapped);
                    }
                    bucket.uv0.push_back(static_cast<float>(uv[0]));
                    bucket.uv0.push_back(static_cast<float>(uv[1]));

                    uint16_t jointIndices[4] = {0, 0, 0, 0};
                    float jointWeights[4] = {1.0f, 0.0f, 0.0f, 0.0f};
                    if (controlPointIndex >= 0 && controlPointIndex < static_cast<int>(influences.size())) {
                        const std::vector<VertexInfluence> &cpInfluences = influences[static_cast<size_t>(controlPointIndex)];
                        if (!cpInfluences.empty()) {
                            bucket.hasSkinning = true;
                            for (size_t influenceIndex = 0; influenceIndex < cpInfluences.size() && influenceIndex < 4; ++influenceIndex) {
                                jointIndices[influenceIndex] = static_cast<uint16_t>(std::max(0, cpInfluences[influenceIndex].jointIndex));
                                jointWeights[influenceIndex] = static_cast<float>(cpInfluences[influenceIndex].weight);
                            }
                        }
                    }
                    bucket.jointIndices.insert(bucket.jointIndices.end(), jointIndices, jointIndices + 4);
                    bucket.jointWeights.insert(bucket.jointWeights.end(), jointWeights, jointWeights + 4);

                    const uint32_t index = static_cast<uint32_t>(bucket.positions.size() / 3 - 1);
                    bucket.indices.push_back(index);
                }
            }

            for (auto &entry : localBuckets) {
                MeshBucket &bucket = entry.second;
                if (bucket.materialIndex > 0 || localBuckets.size() > 1) {
                    bucket.name += "_mat" + std::to_string(bucket.materialIndex);
                }
                buckets.push_back(bucket);
            }
        }

        const int childCount = node->GetChildCount();
        for (int childIndex = 0; childIndex < childCount; ++childIndex) {
            traverse(node->GetChild(childIndex));
        }
    };

    traverse(root);

    outScene->meshCount = static_cast<int32_t>(buckets.size());
    if (buckets.empty()) {
        outScene->meshes = nullptr;
        return;
    }

    outScene->meshes = static_cast<MCEFbxMeshDTO *>(std::calloc(buckets.size(), sizeof(MCEFbxMeshDTO)));
    for (size_t meshIndex = 0; meshIndex < buckets.size(); ++meshIndex) {
        const MeshBucket &bucket = buckets[meshIndex];
        MCEFbxMeshDTO &dto = outScene->meshes[meshIndex];
        dto.name = CopyCString(bucket.name);
        dto.materialIndex = bucket.materialIndex;
        dto.vertexCount = static_cast<int32_t>(bucket.positions.size() / 3);
        dto.indexCount = static_cast<int32_t>(bucket.indices.size());
        dto.hasSkinning = bucket.hasSkinning;

        if (!bucket.positions.empty()) {
            dto.positions = static_cast<float *>(std::malloc(sizeof(float) * bucket.positions.size()));
            std::memcpy(dto.positions, bucket.positions.data(), sizeof(float) * bucket.positions.size());
        }
        if (!bucket.normals.empty()) {
            dto.normals = static_cast<float *>(std::malloc(sizeof(float) * bucket.normals.size()));
            std::memcpy(dto.normals, bucket.normals.data(), sizeof(float) * bucket.normals.size());
        }
        if (!bucket.tangents.empty()) {
            dto.tangents = static_cast<float *>(std::malloc(sizeof(float) * bucket.tangents.size()));
            std::memcpy(dto.tangents, bucket.tangents.data(), sizeof(float) * bucket.tangents.size());
        }
        if (!bucket.uv0.empty()) {
            dto.uv0 = static_cast<float *>(std::malloc(sizeof(float) * bucket.uv0.size()));
            std::memcpy(dto.uv0, bucket.uv0.data(), sizeof(float) * bucket.uv0.size());
        }
        if (!bucket.indices.empty()) {
            dto.indices = static_cast<uint32_t *>(std::malloc(sizeof(uint32_t) * bucket.indices.size()));
            std::memcpy(dto.indices, bucket.indices.data(), sizeof(uint32_t) * bucket.indices.size());
        }
        if (!bucket.jointIndices.empty()) {
            dto.jointIndices = static_cast<uint16_t *>(std::malloc(sizeof(uint16_t) * bucket.jointIndices.size()));
            std::memcpy(dto.jointIndices, bucket.jointIndices.data(), sizeof(uint16_t) * bucket.jointIndices.size());
        }
        if (!bucket.jointWeights.empty()) {
            dto.jointWeights = static_cast<float *>(std::malloc(sizeof(float) * bucket.jointWeights.size()));
            std::memcpy(dto.jointWeights, bucket.jointWeights.data(), sizeof(float) * bucket.jointWeights.size());
        }
    }
}

#endif

} // namespace

bool MCEFbxSkeletonExtractor_Extract(const char *path,
                                     MCEFbxSceneDTO *outScene,
                                     std::string &errorMessage) {
    if (path == nullptr || outScene == nullptr) {
        errorMessage = "Invalid input for FBX skeleton extraction.";
        return false;
    }

#if MCE_HAS_FBXSDK
    outScene->jointCount = 0;
    outScene->joints = nullptr;
    outScene->clipCount = 0;
    outScene->clips = nullptr;
    outScene->meshCount = 0;
    outScene->meshes = nullptr;
    outScene->materialCount = 0;
    outScene->materials = nullptr;
    outScene->importScaleFactor = 1.0f;
    outScene->importScaleSource = nullptr;

    FbxManager *manager = FbxManager::Create();
    if (manager == nullptr) {
        errorMessage = "FBX SDK manager creation failed.";
        return false;
    }
    FbxIOSettings *ioSettings = FbxIOSettings::Create(manager, IOSROOT);
    manager->SetIOSettings(ioSettings);

    FbxImporter *importer = FbxImporter::Create(manager, "");
    if (importer == nullptr) {
        manager->Destroy();
        errorMessage = "FBX SDK importer creation failed.";
        return false;
    }

    if (!importer->Initialize(path, -1, manager->GetIOSettings())) {
        errorMessage = importer->GetStatus().GetErrorString();
        importer->Destroy();
        manager->Destroy();
        return false;
    }

    FbxScene *scene = FbxScene::Create(manager, "MetalCupScene");
    if (scene == nullptr) {
        importer->Destroy();
        manager->Destroy();
        errorMessage = "FBX SDK scene creation failed.";
        return false;
    }
    if (!importer->Import(scene)) {
        errorMessage = importer->GetStatus().GetErrorString();
        scene->Destroy();
        importer->Destroy();
        manager->Destroy();
        return false;
    }

    FbxGeometryConverter geometryConverter(manager);
    geometryConverter.Triangulate(scene, true);

    const FbxSystemUnit sceneUnit = scene->GetGlobalSettings().GetSystemUnit();
    double conversionFactor = sceneUnit.GetConversionFactorTo(FbxSystemUnit::m);
    if (!std::isfinite(conversionFactor) || conversionFactor <= 0.0) {
        conversionFactor = 1.0;
    }
    outScene->importScaleFactor = static_cast<float>(conversionFactor);
    outScene->importScaleSource = CopyCString(std::abs(conversionFactor - 1.0) > 1.0e-6 ? "fbxsdkSceneUnits" : "none");

    std::set<FbxNode *> deformerNodes;
    std::set<FbxNode *> animatedNodes;
    BuildDeformerNodeSet(scene, deformerNodes);
    BuildAnimatedNodeSet(scene, animatedNodes);

    std::set<FbxNode *> includedNodes;
    MarkIncludedSkeletonNodes(scene->GetRootNode(), deformerNodes, animatedNodes, includedNodes);

    std::vector<JointBuildRecord> jointRecords;
    std::unordered_map<FbxNode *, int32_t> jointIndexByNode;
    jointRecords.reserve(includedNodes.size());
    BuildJointList(scene->GetRootNode(), -1, includedNodes, jointRecords, jointIndexByNode);

    std::unordered_map<std::string, FbxAMatrix> inverseBindByName;
    BuildInverseBindByName(scene, inverseBindByName);
    FillJointDTOs(jointRecords, inverseBindByName, outScene);

    std::unordered_map<std::string, int32_t> jointIndexByName;
    jointIndexByName.reserve(jointRecords.size());
    for (size_t i = 0; i < jointRecords.size(); ++i) {
        jointIndexByName[NodeName(jointRecords[i].node)] = static_cast<int32_t>(i);
    }

    FillMaterialDTOs(scene, outScene);
    FillMeshDTOs(scene, jointIndexByName, outScene);

    scene->Destroy();
    importer->Destroy();
    manager->Destroy();
    return true;
#else
    errorMessage = "FBX SDK headers not available. Skipping FBX skeleton extraction.";
    return false;
#endif
}
