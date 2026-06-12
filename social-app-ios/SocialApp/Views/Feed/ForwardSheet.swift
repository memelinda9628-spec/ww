import SwiftUI

struct ForwardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isLoading = false
    let moment: Moment?
    let onSubmit: (String) async -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let moment {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            AvatarView(url: moment.authorAvatar, name: moment.authorName, size: 28)
                            Text(moment.authorName).font(.subheadline.weight(.semibold))
                        }
                        Text(moment.text)
                            .font(.callout)
                            .lineLimit(3)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(10)
                }

                TextEditor(text: $text)
                    .font(.body)
                    .padding(.horizontal)
            }
            .padding(.top, 8)
            .navigationTitle("转发")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        isLoading = true
                        Task {
                            await onSubmit(text)
                            isLoading = false
                            dismiss()
                        }
                    }
                    .disabled(isLoading)
                }
            }
        }
    }
}