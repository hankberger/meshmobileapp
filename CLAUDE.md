# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Project Overview: "Meshify" - LiDAR 3D Scanning & Photogrammetry App
1. Executive Summary
"Meshify" is a professional-grade iOS application designed to empower users to create high-fidelity 3D models of objects and spaces using the integrated LiDAR scanner and advanced photogrammetry algorithms. The app will provide an intuitive user experience, from guided scanning to on-device editing and seamless export to various 3D file formats. Meshify aims to be the go-to tool for professionals and hobbyists in fields such as architecture, design, e-commerce, and digital art, offering a powerful and accessible solution for 3D content creation.

2. Problem Statement
The creation of detailed 3D models has traditionally been a complex and expensive process, requiring specialized hardware and desktop software with a steep learning curve. While modern smartphones have made 3D scanning more accessible, existing solutions often lack the precision, ease of use, or robust feature set required for professional applications. There is a growing demand for a mobile-first solution that can produce high-quality, textured 3D meshes with minimal effort and technical expertise.

3. Proposed Solution
Meshify will leverage the power of Apple's ARKit and RealityKit to provide a comprehensive 3D scanning solution. The app will utilize the LiDAR sensor for rapid and accurate spatial data acquisition, creating a precise point cloud of the environment. This data will be augmented with high-resolution images captured through a guided photogrammetry process. Our advanced algorithms will then process this data on-device to generate a detailed, textured 3D mesh.

4. Key Features
Hybrid LiDAR & Photogrammetry Scanning: Combines the speed and accuracy of LiDAR with the rich detail of photogrammetry for superior results.

Intuitive Guided Capture: An AR-powered interface will guide users through the scanning process, ensuring optimal coverage and image quality.

On-Device Processing: All processing is handled on the user's device, ensuring privacy and eliminating the need for a constant internet connection or cloud-based subscriptions for core functionality.

Advanced Editing Tools: A suite of on-device editing tools will allow users to crop, rotate, and clean up their 3D models.

High-Fidelity Texturing: The app will generate high-resolution, realistic textures for the 3D models.

Multiple Export Formats: Users will be able to export their models in a variety of popular formats, including OBJ, STL, and USDZ, for use in other 3D software.

Measurement Tools: An integrated measurement tool will allow users to take accurate measurements from their 3D scans.

Cloud Storage & Sharing (Pro Feature): An optional cloud-based service will allow users to store, share, and collaborate on their 3D models.

- **Language**: Swift 5.0
- **Framework**: SwiftUI
- **Platform**: iOS 18.1+
- **Development Team**: WY2FX658M4
- **Bundle ID**: hankberger.Learn

## Common Commands

### Building the Project
```bash
# Build the project in Xcode
xcodebuild -project Learn.xcodeproj -scheme Learn build

# Build for testing
xcodebuild -project Learn.xcodeproj -scheme Learn build-for-testing
```

### Running Tests
```bash
# Run unit tests
xcodebuild -project Learn.xcodeproj -scheme Learn test -destination 'platform=iOS Simulator,name=iPhone 15'

# Run UI tests
xcodebuild -project Learn.xcodeproj -scheme LearnUITests test -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Project Structure
- `Learn/` - Main app source code
  - `Notifications.swift` - Main app entry point (MeshApp struct)
  - `Assets.xcassets/` - App icons and assets
  - `Preview Content/` - SwiftUI preview assets
- `LearnTests/` - Unit test target (currently empty)
- `LearnUITests/` - UI test target (currently empty)

## Development Notes

- The main app struct is named `MeshApp` despite the project being called "Learn"
- Camera usage permission is required: "App requires camera access for depth capture"
- The project is configured for both iPhone and iPad
- SwiftUI previews are enabled
- Currently has minimal implementation - just the basic app structure