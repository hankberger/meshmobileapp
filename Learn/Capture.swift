// ⚠️ Info.plist Requirement:
// Add the following key to your Info.plist to avoid camera-access crashes:
// <key>NSCameraUsageDescription</key>
// <string>App requires camera access for depth capture.</string>

import ARKit
import UIKit
import CoreVideo
import SwiftUI
import RealityKit
import Metal
import MetalKit

/// Protocol to notify when frame data and coverage updates are available
protocol CaptureDepthManagerDelegate: AnyObject {
    func captureDepthManager(_ manager: CaptureDepthManager,
                              didCollectFrame depthData: ARDepthData,
                              cameraTransform: matrix_float4x4)
    func captureDepthManagerDidReachCoverageRequirement(_ manager: CaptureDepthManager)
    func captureDepthManager(_ manager: CaptureDepthManager,
                              didUpdateCoverage collected: Int,
                              threshold: Int)
}

/// Depth + Pose capture manager using ARKit SceneDepth
class CaptureDepthManager: NSObject {
    let session = ARSession()
    weak var delegate: CaptureDepthManagerDelegate?
    private var collectedPoses: [matrix_float4x4] = []
    let coverageThreshold: Int
     var didTriggerFusion = false

    init(coverageThreshold: Int = 30) {
        self.coverageThreshold = coverageThreshold
        super.init()
        session.delegate = self
    }

    func startSession() {
        // Note: Even on LiDAR devices, ARKit may log fallback warnings for depth linearization.
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.sceneDepth)
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopSession() {
        session.pause()
        collectedPoses.removeAll()
    }
}

// MARK: - ARSessionDelegate
extension CaptureDepthManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth,
              let confidenceMap = sceneDepth.confidenceMap else { return }
        let depthMap = sceneDepth.depthMap

        // Wrap into model
        let depthData = ARDepthData(
            depthMap: depthMap,
            confidenceMap: confidenceMap,
            cameraIntrinsics: frame.camera.intrinsics,
            resolution: (
                width: CVPixelBufferGetWidth(depthMap),
                height: CVPixelBufferGetHeight(depthMap)
            )
        )
        let transform = frame.camera.transform

        // Track coverage
        trackPose(transform)
        // Notify coverage progress
        delegate?.captureDepthManager(self,
                                       didUpdateCoverage: collectedPoses.count,
                                       threshold: coverageThreshold)

        // Notify delegates
        delegate?.captureDepthManager(self,
                                      didCollectFrame: depthData,
                                      cameraTransform: transform)
        if collectedPoses.count >= coverageThreshold {
            delegate?.captureDepthManagerDidReachCoverageRequirement(self)
        }
    }

    private func trackPose(_ pose: matrix_float4x4) {
        let pos = SIMD3<Float>(pose.columns.3.x,
                                 pose.columns.3.y,
                                 pose.columns.3.z)
        let isNew = !collectedPoses.contains { existing in
            let e = SIMD3<Float>(existing.columns.3.x,
                                  existing.columns.3.y,
                                  existing.columns.3.z)
            return simd_distance(e, pos) < 0.1
        }
        if isNew {
            collectedPoses.append(pose)
        }
    }
}

// MARK: - ARDepthData Model

struct ARDepthData {
    let depthMap: CVPixelBuffer
    let confidenceMap: CVPixelBuffer
    let cameraIntrinsics: simd_float3x3
    let resolution: (width: Int, height: Int)
}

// MARK: - SwiftUI Entry Point with Progress & Alert

struct DepthCaptureView: View {
    @StateObject private var wrapper = DepthWrapper()

    var body: some View {
        ZStack(alignment: .top) {
            ARContainer(session: wrapper.manager.session)
                .edgesIgnoringSafeArea(.all)

            ProgressView(value: wrapper.progress,
                         total: 1.0) {
                Text("Coverage: \(wrapper.collected) / \(wrapper.manager.coverageThreshold)")
            }
            .progressViewStyle(LinearProgressViewStyle())
            .padding()
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
            .padding([.top, .horizontal])
        }
        .alert(isPresented: $wrapper.coverageReached) {
            Alert(
                title: Text("Coverage Complete"),
                message: Text("Sufficient views collected for fusion."),
                dismissButton: .default(Text("OK")) {
                    wrapper.manager.stopSession()
                }
            )
        }
        .onAppear {
            wrapper.manager.delegate = wrapper
            wrapper.manager.startSession()
        }
        .onDisappear {
            wrapper.manager.stopSession()
        }
    }
}

struct ARContainer: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = session
        arView.automaticallyConfigureSession = false
        return arView
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

final class DepthWrapper: NSObject, ObservableObject {
    let manager = CaptureDepthManager(coverageThreshold: 20)
    @Published var collected: Int = 0
    @Published var progress: Double = 0.0
    @Published var coverageReached: Bool = false
    var extractedVertexBuffer: MTLBuffer?
    var extractedNormalBuffer: MTLBuffer?
    var extractedVertexCount: Int = 0
}

extension DepthWrapper: CaptureDepthManagerDelegate {
    func captureDepthManager(_ manager: CaptureDepthManager,
                              didUpdateCoverage collected: Int,
                              threshold: Int) {
        DispatchQueue.main.async {
            self.collected = collected
            self.progress = min(max(Double(collected) / Double(threshold), 0.0), 1.0)
        }
    }

    func captureDepthManager(_ manager: CaptureDepthManager,
                              didCollectFrame depthData: ARDepthData,
                              cameraTransform: matrix_float4x4) {
        let intrinsics = depthData.cameraIntrinsics
        FusionModule.shared.process(depthData: depthData,
                                    cameraTransform: cameraTransform, intrinsics: intrinsics)
    }

    func captureDepthManagerDidReachCoverageRequirement(_ manager: CaptureDepthManager) {
        DispatchQueue.main.async {
            self.coverageReached = true
            print("Coverage Reached!!")
        }

        // 2) Offload mesh extraction to a background queue,
           //    using the explicit `execute:` label so Swift picks the ()->Void overload.
       DispatchQueue.global(qos: .userInitiated).async(execute: {
           // 3) Only tsdfBuffer is optional—resolution is always there
           let tsdf = FusionModule.shared.tsdfVolume
           let resolution = FusionModule.shared.volumeResolution

           // 4) Configure + run Marching Cubes
           MeshExtractionModule.shared.configure(tsdfVolume: tsdf,
                                                 resolution: resolution)
           let (vBuf, nBuf, count) = MeshExtractionModule.shared.extractMesh()

           // 5) Hand results back to the main thread
           DispatchQueue.main.async {
               self.extractedVertexBuffer = vBuf
               self.extractedNormalBuffer = nBuf
               self.extractedVertexCount = count
               print("✅ Mesh extracted with \(count) verts")
               // e.g., trigger a redraw of your MTKView/SceneKit here
           }
       })
    }
}
