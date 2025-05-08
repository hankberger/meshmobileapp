//
//  LearnApp.swift
//  Learn
//
//  Created by Hank Berger on 5/5/25.
//

import SwiftUI

@main
struct LearnApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
               ContentView()
                   .tabItem {
                       Label("Journal", systemImage: "book")
                   }
                DepthCaptureView()
                    .tabItem {
                        Label("Settings", systemImage: "book")
                    }
              
            }
        }
    }
}
