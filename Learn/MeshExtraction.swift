//
//  MeshExtraction.swift
//  Learn
//
//  Created by Hank Berger on 5/7/25.
//
import Metal
import MetalKit

/// Module for extracting a triangle mesh from a TSDF volume using GPU Marching Cubes
/// Performance target: sub-5 s extraction on modern phone GPUs
class MeshExtractionModule {
    static let shared = MeshExtractionModule()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    private var volumeResolution: SIMD3<Int> = SIMD3(256, 256, 256)
    private var tsdfVolume: MTLBuffer?

    private var vertexBuffer: MTLBuffer?
    private var normalBuffer: MTLBuffer?
    private var meshCountBuffer: MTLBuffer?

    private init() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue(),
              let library = dev.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "marchingCubesKernel") else {
            fatalError("Metal setup failed")
        }
        device = dev
        commandQueue = queue
        pipelineState = try! dev.makeComputePipelineState(function: kernel)
    }

    /// Configure the module with an existing TSDF volume buffer
    /// - Parameters:
    ///   - tsdfVolume: GPU buffer containing float TSDF values
    ///   - resolution: Dimensions of the volume (e.g. 256³)
    func configure(tsdfVolume: MTLBuffer, resolution: SIMD3<Int>) {
        self.tsdfVolume = tsdfVolume
        self.volumeResolution = resolution

        // Estimate maximum triangles: ~5 per voxel
        let maxTriangles = resolution.x * resolution.y * resolution.z * 5 / 3
        let maxVertices = maxTriangles * 3

        vertexBuffer = device.makeBuffer(
            length: MemoryLayout<SIMD3<Float>>.stride * maxVertices,
            options: .storageModeShared
        )
        normalBuffer = device.makeBuffer(
            length: MemoryLayout<SIMD3<Float>>.stride * maxVertices,
            options: .storageModeShared
        )
        meshCountBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )
    }

    /// Run GPU Marching Cubes and return the generated mesh
    /// - Returns: tuple of (vertices, normals, vertexCount)
    func extractMesh() -> (vertices: MTLBuffer, normals: MTLBuffer, count: Int) {
        guard let tsdf = tsdfVolume,
              let vertBuf = vertexBuffer,
              let normBuf = normalBuffer,
              let countBuf = meshCountBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Mesh extraction not configured or Metal failure")
        }

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(tsdf, offset: 0, index: 0)
        encoder.setBytes(&volumeResolution, length: MemoryLayout<SIMD3<Int>>.stride, index: 1)
        encoder.setBuffer(vertBuf, offset: 0, index: 2)
        encoder.setBuffer(normBuf, offset: 0, index: 3)
        encoder.setBuffer(countBuf, offset: 0, index: 4)

        // Dispatch threads over (resolution - 1) cubes
        let tgSize = MTLSize(width: 8, height: 8, depth: 8)
        let tgCount = MTLSize(
            width: (volumeResolution.x - 1 + tgSize.width) / tgSize.width,
            height: (volumeResolution.y - 1 + tgSize.height) / tgSize.height,
            depth: (volumeResolution.z - 1 + tgSize.depth) / tgSize.depth
        )
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let countPtr = countBuf.contents().bindMemory(to: UInt32.self, capacity: 1)
        let triCount = Int(countPtr.pointee)
        let vertexCount = triCount * 3

        return (vertices: vertBuf, normals: normBuf, count: vertexCount)
    }
}


