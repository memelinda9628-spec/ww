//
//  LocationShareView.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: SwiftUI view for LocationShare settings.

import SwiftUI
import MapKit

// MARK: - LocationShareView

struct LocationShareView: View {

    @StateObject private var viewModel = LocationShareViewModel()
    let roomId: String
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    var body: some View {
        VStack {
            if viewModel.isSharing {
                Text("正在共享位置...").font(.headline)
                Map(position: .constant(.region(region)))
                    .frame(height: 300)
                    .cornerRadius(12)
                Button("停止共享", role: .destructive) {
                    viewModel.stopSharing(roomId: roomId)
                }
                .padding()
            } else {
                Text("未在共享位置").foregroundColor(.secondary)
                Button("开始共享位置") {
                    viewModel.startSharing(geoUri: "geo:0,0", timeoutMs: 3600000, roomId: roomId)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("位置共享")
    }

}

#Preview {
    NavigationView { LocationShareView(roomId: "!test:example.com") }
}
