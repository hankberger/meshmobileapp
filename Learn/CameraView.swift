//
//  CameraView.swift
//  Learn
//
//  Created by Hank Berger on 6/20/25.
//
//  Rewritten by Gemini on 6/20/25 to implement a more performant,
//  on-demand mesh generation architecture.
//

import SwiftUI
import ARKit
import RealityKit
import simd

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var arViewModel = ARViewModel()
    
    var body: some View {
        ZStack {
            ARViewContainer(arViewModel: arViewModel)
                .ignoresSafeArea()
            
            VStack {
                // Top control bar
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                        .padding()
                    
                    Spacer()
                    
                    Text("LiDAR Scanning")
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    Spacer()
                    
                    HStack {
                        Button("Reset") { arViewModel.resetMesh() }
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        Button(arViewModel.showDebugMesh ? "Hide Debug" : "Show Debug") {
                            arViewModel.toggleDebugMesh()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal)
                    }
                }
                .background(Color.black.opacity(0.3))
                
                Spacer()
                
                // Bottom control bar
                HStack(spacing: 20) {
                    VStack {
                        Text("Vertices")
                            .foregroundColor(.white)
                            .font(.caption)
                        Text("\(arViewModel.pointCount)")
                            .foregroundColor(.white)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    VStack {
                        Text("Meshes")
                            .foregroundColor(.white)
                            .font(.caption)
                        Text("\(arViewModel.meshCount)")
                            .foregroundColor(.white)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    // Start/Stop Scanning Button
                    Button {
                        if arViewModel.isScanning {
                            arViewModel.stopScanning()
                        } else {
                            arViewModel.startScanning()
                        }
                    } label: {
                        VStack {
                            Image(systemName: arViewModel.isScanning ? "stop.circle.fill" : "record.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(arViewModel.isScanning ? .red : .white)
                            Text(arViewModel.isScanning ? "Stop" : "Start")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                    }
                    
                    // Generate Final Mesh Button
                    Button("Generate Mesh") {
                        arViewModel.generateFinalMesh()
                    }
                    .font(.headline)
                    .disabled(!arViewModel.canGenerateMesh)
                    .foregroundColor(arViewModel.canGenerateMesh ? .black : .gray)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(arViewModel.canGenerateMesh ? Color.green : Color.gray.opacity(0.5))
                    .cornerRadius(10)
                }
                .padding()
                .padding(.bottom, 30)
                .background(Color.black.opacity(0.3))
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let arViewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arViewModel.setupARView(arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class ARViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties for UI
    @Published var isScanning = false
    @Published var pointCount = 0
    @Published var canGenerateMesh = false
    @Published var meshCount = 0
    @Published var showDebugMesh = true
    
    // MARK: - AR & RealityKit Properties
    private weak var arView: ARView?
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    
    // A single root entity to hold our final custom mesh.
    private var customMeshAnchor: AnchorEntity?

    // MARK: - Setup and Control
    
    func setupARView(_ arView: ARView) {
        self.arView = arView
        
        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            print("AR World Tracking with scene reconstruction is not supported on this device.")
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        
        arView.session.delegate = self
        arView.session.run(configuration)
        
        arView.environment.sceneUnderstanding.options = [.occlusion, .physics]
        arView.debugOptions.insert(.showSceneUnderstanding)
    }
    
    /// Starts the scanning process. This simply enables the state and clears any old custom mesh.
    /// The `ARSessionDelegate` will handle receiving mesh data from ARKit automatically.
    func startScanning() {
        // Clear any previously generated custom mesh
        customMeshAnchor?.removeFromParent()
        customMeshAnchor = nil
        
        isScanning = true
        canGenerateMesh = false
        
        // Ensure the debug wireframe is visible during scanning
        if !showDebugMesh {
           toggleDebugMesh()
        }
    }
    
    /// Stops the scanning process and allows the user to generate a final mesh.
    func stopScanning() {
        isScanning = false
        // Allow user to generate a mesh only if we have collected some anchors.
        canGenerateMesh = !meshAnchors.isEmpty
    }
    
    /// Clears all collected mesh data and resets the AR session.
    func resetMesh() {
        stopScanning()
        
        meshAnchors.removeAll()
        
        // Remove the custom mesh from the scene
        customMeshAnchor?.removeFromParent()
        customMeshAnchor = nil
        
        // Reset UI state
        updateCounts()
        
        // A full session reset is the most reliable way to clear ARKit's internal mesh data.
        if let configuration = arView?.session.configuration {
            arView?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction])
        }
        
        // Re-enable debug mesh if it was hidden
        if !showDebugMesh {
             arView?.debugOptions.insert(.showSceneUnderstanding)
             showDebugMesh = true
        }
    }
    
    /// Toggles the visibility of the real-time ARKit wireframe mesh.
    func toggleDebugMesh() {
        showDebugMesh.toggle()
        if showDebugMesh {
            arView?.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView?.debugOptions.remove(.showSceneUnderstanding)
        }
    }
    
    /// This function triggers the one-time, computationally intensive generation of the final mesh.
    func generateFinalMesh() {
        guard canGenerateMesh else { return }
        
        if isScanning { stopScanning() }
        
        // Perform the expensive mesh creation.
        createFinalMesh()
        
        // Hide the wireframe to only show our final, clean custom mesh
        if showDebugMesh { toggleDebugMesh() }
        
        // Disable the button after one successful generation to prevent re-computation.
        canGenerateMesh = false
    }
    
    // MARK: - Mesh Generation Logic
    
    /// Creates the final, visible RealityKit mesh from all captured ARMeshAnchors.
    /// This is computationally expensive and should only be called once when scanning is complete.
    private func createFinalMesh() {
        guard let arView = arView, !meshAnchors.isEmpty else { return }
        
        // 1. Remove any old custom mesh anchor.
        customMeshAnchor?.removeFromParent()
        customMeshAnchor = nil
        
        // 2. Define the material for our custom mesh.
        var material = SimpleMaterial(color: #colorLiteral(red: 0.2392156869, green: 0.6745098233, blue: 0.9686274529, alpha: 1), isMetallic: false)
        material.roughness = .float(0.7)
        material.metallic = .float(0.1)
        
        // 3. Combine all anchor geometries into a single mesh descriptor.
        var combinedDescriptor = MeshDescriptor(name: "final_custom_mesh")
        var allVertices: [SIMD3<Float>] = []
        var allIndices: [UInt32] = []

        for meshAnchor in meshAnchors.values {
            let geometry = meshAnchor.geometry
            let vertices = geometry.vertices
            let faces = geometry.faces
            
            // Get vertices from the buffer.
            let vertexPointer = vertices.buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: vertices.count)
            let vertexBuffer = UnsafeBufferPointer(start: vertexPointer, count: vertices.count)
            
            // Offset indices for the combined mesh.
            let currentVertexCount = UInt32(allVertices.count)
            let indicesCount = faces.count * faces.indexCountPerPrimitive
            let indicesPointer = faces.buffer.contents()
            
            if faces.bytesPerIndex == MemoryLayout<UInt16>.size {
                let typedPointer = indicesPointer.bindMemory(to: UInt16.self, capacity: indicesCount)
                allIndices.append(contentsOf: UnsafeBufferPointer(start: typedPointer, count: indicesCount).map { currentVertexCount + UInt32($0) })
            } else {
                let typedPointer = indicesPointer.bindMemory(to: UInt32.self, capacity: indicesCount)
                allIndices.append(contentsOf: UnsafeBufferPointer(start: typedPointer, count: indicesCount).map { currentVertexCount + $0 })
            }
            
            // Transform vertices to world space and add to the combined array.
            let transform = meshAnchor.transform
            allVertices.append(contentsOf: vertexBuffer.map { vertex in
                let worldPosition = transform * SIMD4<Float>(vertex, 1)
                return SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z)
            })
        }
        
        guard !allVertices.isEmpty, !allIndices.isEmpty else { return }

        // 4. Set the descriptor properties with the combined data.
        combinedDescriptor.positions = MeshBuffer(allVertices)
        combinedDescriptor.primitives = .triangles(allIndices)
        
        // 5. Generate the final MeshResource and create a single ModelEntity.
        do {
            if let meshResource = try? MeshResource.generate(from: [combinedDescriptor]) {
                let modelEntity = ModelEntity(mesh: meshResource, materials: [material])
                
                // Create a root anchor at the world origin to hold our combined model.
                let rootAnchor = AnchorEntity(world: .zero)
                rootAnchor.addChild(modelEntity)
                arView.scene.addAnchor(rootAnchor)
                
                // Store the anchor for future cleanup (e.g., reset).
                self.customMeshAnchor = rootAnchor
            }
        }
    }
    
    // MARK: - UI State Update
    
    private func updateCounts() {
        DispatchQueue.main.async {
            self.meshCount = self.meshAnchors.count
            self.pointCount = self.meshAnchors.values.reduce(0) { $0 + $1.geometry.vertices.count }
        }
    }
}

// MARK: - ARSessionDelegate

extension ARViewModel: ARSessionDelegate {
    // These delegate methods are called by ARKit on a background thread.
    // We simply store the latest mesh anchors.
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                meshAnchors[meshAnchor.identifier] = meshAnchor
            }
        }
        updateCounts()
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let meshAnchor = anchor as? ARMeshAnchor {
                 meshAnchors.removeValue(forKey: meshAnchor.identifier)
            }
        }
        updateCounts()
    }
}
