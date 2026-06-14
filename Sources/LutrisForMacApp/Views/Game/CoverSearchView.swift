import SwiftUI

struct CoverSearchView: View {
    let gameName: String
    let gameID: String
    let onSelect: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searcher = SteamGridDBSearcher()
    @State private var selectedURL: String = ""
    @State private var searchText: String = ""
    @State private var previewImage: NSImage?
    @State private var isLoadingPreview = false

    var body: some View {
        VStack(spacing: 0) {
            LText("Cover suchen")
                .font(.title2)
                .bold()
                .padding()

            HStack {
                TextField(tr("Spielname..."), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }
                Button { runSearch() } label: { LText("Suchen") }
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || searcher.isSearching)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if searcher.isSearching {
                ProgressView("Suche...")
                    .padding()
            } else if let error = searcher.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(verbatim: trf("Fehler: %@", error))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if searcher.results.isEmpty && !searchText.isEmpty {
                LText("Keine Cover gefunden")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(searcher.results) { cover in
                            Button {
                                selectedURL = cover.url
                                loadPreview(from: cover.url)
                            } label: {
                                AsyncImage(url: URL(string: cover.url)) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    case .failure:
                                        Image(systemName: "photo")
                                            .foregroundColor(.secondary)
                                    case .empty:
                                        ProgressView()
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .frame(width: 130, height: 195)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedURL == cover.url ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }

            if let preview = previewImage {
                Divider()
                HStack {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .cornerRadius(6)
                    VStack(alignment: .leading, spacing: 4) {
                        LText("Ausgewählt")
                            .font(.headline)
                        Button {
                            onSelect?(selectedURL)
                            dismiss()
                        } label: { LText("Übernehmen") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }

            HStack {
                Button { dismiss() } label: { LText("Abbrechen") }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
        .onAppear {
            searchText = gameName
            runSearch()
        }
    }

    private func runSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task { await searcher.searchGame(searchText.trimmingCharacters(in: .whitespaces)) }
    }

    private func loadPreview(from url: String) {
        guard let url = URL(string: url) else { return }
        isLoadingPreview = true
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let img = NSImage(data: data) {
                previewImage = img
            }
            isLoadingPreview = false
        }
    }
}
