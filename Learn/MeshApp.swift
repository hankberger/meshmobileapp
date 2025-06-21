//
//  MeshApp.swift
//  Learn
//
//  Created by Hank Berger on 6/20/25.
//

import SwiftUI

@main
struct MeshApp: App {
    var body: some Scene {
        WindowGroup {
            HomeScreenView()
        }
    }
}

struct HomeScreenView: View {
    @State private var showingCamera = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Meshify")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Create 3D models with LiDAR & Photogrammetry")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                Button(action: {
                    showingCamera = true
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text("Open Camera")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .cornerRadius(25)
                }
                
                Spacer()
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView()
        }
    }
}


#Preview {
    HomeScreenView()
}
