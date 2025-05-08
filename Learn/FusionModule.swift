import Metal
import MetalKit
import ARKit

class FusionModule {
    static let shared = FusionModule()
    
    private init() {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()!
        
        // 1) Compile our TSDF-fusion kernel
        let kernel = library.makeFunction(name: "tsdfFusionKernel")!
        pipelineState = try! device.makeComputePipelineState(function: kernel)
        
        // 2) Allocate our 256³ TSDF + weight volumes
        let voxelCount = volumeResolution.x * volumeResolution.y * volumeResolution.z
        tsdfVolume = device.makeBuffer(length: MemoryLayout<Float>.stride * voxelCount, options: [])!
        weightVolume = device.makeBuffer(length: MemoryLayout<Float>.stride * voxelCount, options: [])!
        
        resetVolume()
        
        // 3) Set up a texture cache for CVPixelBuffer -> MTLTexture
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }
    
    // MARK: -- Parameters
    
    let volumeResolution = SIMD3<Int>(256, 256, 256)
    let voxelSize: Float = 0.004          // 4 mm per voxel
    let truncationDistance: Float = 0.02  // 2 cm
    
    // MARK: -- Metal objects
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary
    let pipelineState: MTLComputePipelineState
    var textureCache: CVMetalTextureCache?
    
    // The TSDF & weight volumes (flattened 1D arrays of length 256³)
    let tsdfVolume: MTLBuffer
    let weightVolume: MTLBuffer
    
    // MARK: -- Public API
    
    /// Zeroes out the TSDF & weight volumes.
    func resetVolume() {
        let ptr = tsdfVolume.contents().bindMemory(to: Float.self, capacity: tsdfVolume.length / MemoryLayout<Float>.stride)
        memset(ptr, 0, tsdfVolume.length)
        
        let wptr = weightVolume.contents().bindMemory(to: Float.self, capacity: weightVolume.length / MemoryLayout<Float>.stride)
        memset(wptr, 0, weightVolume.length)
    }
    
    /// Fuse one new depth frame into the TSDF volume.
    func process(depthData: ARDepthData,
                 cameraTransform: simd_float4x4,
                 intrinsics: simd_float3x3) {
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        // 1) Turn the ARDepthData’s CVPixelBuffer into a metal texture
        let depthPixelBuffer = depthData.depthMap
        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)
        
        var depthMTLTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil,
                                                  textureCache!,
                                                  depthPixelBuffer,
                                                  nil,
                                                  .r32Float,
                                                  width,
                                                  height,
                                                  0,
                                                  &depthMTLTexture)
        guard let dtex = depthMTLTexture,
              let depthTex = CVMetalTextureGetTexture(dtex) else {
            return
        }
        
        // 2) Set up our per-frame uniforms
        struct Uniforms {
            var cameraToVolume: simd_float4x4
            var intrinsics: simd_float3x3
            var truncation: Float
            var voxelSize: Float
            var volumeSize: SIMD3<UInt32>  // added for proper padding
        }
        
        // Compute the transform from camera space into volume-voxel space:
        let scale = SIMD3(1/voxelSize, 1/voxelSize, 1/voxelSize)
        let scaleMat = simd_float4x4(diagonal: SIMD4<Float>(scale, 1))
        let originTranslation = simd_float4x4(translation: SIMD3<Float>(
            -Float(volumeResolution.x) / 2,
            -Float(volumeResolution.y) / 2,
            -Float(volumeResolution.z) / 2
        ))
        let volumeOrigin = originTranslation * scaleMat
        
        let cameraToVolume = volumeOrigin * cameraTransform.inverse
        
        var uniforms = Uniforms(
            cameraToVolume: cameraToVolume,
            intrinsics: intrinsics,
            truncation: truncationDistance,
            voxelSize: voxelSize,
            volumeSize: SIMD3<UInt32>(UInt32(volumeResolution.x), UInt32(volumeResolution.y), UInt32(volumeResolution.z))
        )
        
        let uniformBuffer = device.makeBuffer(bytes: &uniforms,
                                              length: MemoryLayout<Uniforms>.stride,
                                              options: [])
        
        // 3) Bind everything and dispatch
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(depthTex, index: 0)
        encoder.setBuffer(tsdfVolume,     offset: 0, index: 0)
        encoder.setBuffer(weightVolume,   offset: 0, index: 1)
        encoder.setBuffer(uniformBuffer,  offset: 0, index: 2)
        
        let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 8)
        let threadgroups = MTLSize(width: (volumeResolution.x + 7) / 8,
                                   height: (volumeResolution.y + 7) / 8,
                                   depth: (volumeResolution.z + 7) / 8)
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        
        encoder.endEncoding()
        commandBuffer.commit()
    }
}

// MARK: - simd extension for translation convenience
extension simd_float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(t, 1)
    }
}
