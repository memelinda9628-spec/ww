import SwiftUI

struct PostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isLoading = false
    let onSubmit: (String) async -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(.horizontal)
                    .padding(.top, 8)
                Spacer()
            }
            .navigationTitle("发动态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发布") {
                        isLoading = true
                        Task {
                            await onSubmit(text)
                            isLoading = false
                            dismiss()
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
        }
    }
}