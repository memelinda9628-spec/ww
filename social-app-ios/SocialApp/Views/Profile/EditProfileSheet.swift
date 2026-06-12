import SwiftUI

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bio: String
    @State private var location: String
    let onSave: (String, String) async -> Void

    init(bio: String, location: String, onSave: @escaping (String, String) async -> Void) {
        self._bio = State(initialValue: bio)
        self._location = State(initialValue: location)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("简介") {
                    TextEditor(text: $bio)
                        .frame(minHeight: 80)
                }
                Section("所在地") {
                    TextField("输入所在地", text: $location)
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await onSave(bio, location)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}