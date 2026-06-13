//
//  StorageSettingsView.swift
//  SocialApp
//
//  Created: 2026-06-08
//  Corresponding Rust API: matrix-rust-sdk FFI bindings
//  Description: SwiftUI view for StorageSettings settings.

import SwiftUI

// MARK: - StorageSettingsView

struct StorageSettingsView: View {

    @StateObject private var viewModel = StorageSettingsViewModel()

    var body: some View {
        Form {
            Section("缓存") {
                LabeledContent("缓存大小", value: viewModel.cacheSize)
                Button("清空缓存") { viewModel.clearCache() }
                    .disabled(viewModel.isLoading)
            }
            Section("媒体留存") {
                Stepper("保留天数: \(viewModel.mediaRetentionDays)", value: $viewModel.mediaRetentionDays, in: 1...365)
                    .onChange(of: viewModel.mediaRetentionDays) { newVal in
                        viewModel.setRetention(days: newVal)
                    }
            }
            Section("数据库") {
                Button("优化数据库") { viewModel.optimizeStorage() }
            }
        }
        .navigationTitle("存储设置")
        .onAppear { viewModel.loadStorageInfo() }
    }

}

#Preview {
    NavigationView { StorageSettingsView() }
}
