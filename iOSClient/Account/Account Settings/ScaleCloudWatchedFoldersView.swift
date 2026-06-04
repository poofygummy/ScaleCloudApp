// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct ScaleCloudWatchedFoldersView: View {
    let account: String
    @StateObject private var model: ScaleCloudWatchedFoldersModel
    @State private var showingPicker = false
    @Environment(\.presentationMode) var presentationMode

    init(account: String) {
        self.account = account
        _model = StateObject(wrappedValue: ScaleCloudWatchedFoldersModel(account: account))
    }

    var body: some View {
        Form {
            Section(header: Text("Watched Folders")) {
                if model.watchedFolders.isEmpty {
                    Text("No folders added yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.watchedFolders, id: \.self) { url in
                        HStack {
                            Image(systemName: "folder")
                                .font(.icon())
                                .frame(width: 26)
                                .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                        }
                    }
                    .onDelete(perform: model.removeFolder)
                }
            }

            Section {
                Button(action: {
                    showingPicker = true
                }, label: {
                    HStack {
                        Image(systemName: "plus")
                            .font(.icon())
                            .frame(width: 26)
                            .foregroundColor(Color(NCBrandColor.shared.iconImageColor))
                        Text("Add Watched Folder")
                            .font(.body)
                            .tint(.primary)
                    }
                })
            }
        }
        .navigationTitle("Watched Download Folders")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            DocumentPickerView(onPick: { url in
                model.addFolder(url: url)
            })
        }
    }
}

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}