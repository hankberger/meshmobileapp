#include <metal_stdlib>
using namespace metal;

// a normalized linear sampler for your depth texture
constexpr sampler depthSampler(
    coord::normalized,
    filter::linear,
    address::clamp_to_edge
);

struct Uniforms {
    float4x4 cameraToVolume;   // transforms from volume‐space → camera‐space
    float3x3 intrinsics;       // [fx 0 cx; 0 fy cy; 0 0 1]
    float    truncation;       // truncation distance in meters
    float    voxelSize;        // side length of one voxel in meters
    uint3    volumeSize;       // number of voxels in X, Y, Z
};

kernel void tsdfFusionKernel(
    texture2d<float, access::sample> depthTex    [[texture(0)]],
    device       float             *tsdfVol      [[buffer(0)]],
    device       float             *weightVol    [[buffer(1)]],
    constant     Uniforms          &u            [[buffer(2)]],
    uint3                            gid          [[thread_position_in_grid]]
) {
    // 0) Bounds check
    uint x = gid.x;
    uint y = gid.y;
    uint z = gid.z;
    if (x >= u.volumeSize.x ||
        y >= u.volumeSize.y ||
        z >= u.volumeSize.z) {
        return;
    }

    // flatten (x,y,z) into 1D index
    uint idx = z * u.volumeSize.x * u.volumeSize.y
             + y * u.volumeSize.x
             + x;

    // 1) Voxel center in volume-space (meters)
    float3 volPos = (float3(x, y, z) + 0.5) * u.voxelSize;

    //    → camera-space
    float4 camPosHom = u.cameraToVolume * float4(volPos, 1.0);
    float3 camPos    = camPosHom.xyz / camPosHom.w;

    // only fuse voxels in front of the camera
    if (camPos.z <= 0.0) {
        return;
    }

    // 1) full 3D projection
    float3 proj3 = u.intrinsics * (camPos / camPos.z);

    // 2) grab x,y for uv coords
    float2 proj  = proj3.xy;
    float2 uv    = proj / float2(depthTex.get_width(),
                                 depthTex.get_height());

    // 2) Sample depth
    float depth = depthTex.sample(depthSampler, uv).r;
    if (depth <= 0.0) {
        return;
    }

    //    compute signed distance and truncate
    float sdf = depth - camPos.z;
    sdf = clamp(sdf, -u.truncation, u.truncation);

    //    normalize to [–1, +1]
    float tsdfNew = sdf / u.truncation;
    float wNew    = 1.0;    // constant weight per frame

    // 3) Fuse with previous TSDF + weight
    float tsdfOld = tsdfVol   [idx];
    float wOld    = weightVol [idx];
    float wFused  = wOld + wNew;
    float tsdfFused = (tsdfOld * wOld + tsdfNew * wNew) / wFused;

    tsdfVol   [idx] = tsdfFused;
    weightVol [idx] = wFused;
}
