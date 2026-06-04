import SwiftUI

struct StatisticsView: View {
    @ObservedObject var viewModel: GameLibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            LText("Statistiken")
                .font(.title2)
                .bold()
                .padding()

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Übersicht
                    VStack(spacing: 12) {
                        sectionTitle("Übersicht")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            statCard(value: "\(viewModel.games.count)", label: "Spiele", icon: "gamecontroller")
                            statCard(value: viewModel.favoriteCount > 0 ? "\(viewModel.favoriteCount)" : "0", label: "Favoriten", icon: "star.fill", color: .yellow)
                            statCard(value: "\(viewModel.gamesRated)", label: "Bewertet", icon: "star.leadinghalf.filled", color: .yellow)
                        }
                    }

                    // Spielzeit
                    VStack(spacing: 12) {
                        sectionTitle("Spielzeit")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            let hours = Int(viewModel.totalPlayTime) / 3600
                            let minutes = (Int(viewModel.totalPlayTime) % 3600) / 60
                            statCard(value: hours > 0 ? "\(hours) Std." : "\(minutes) Min", label: "Gesamt", icon: "clock")
                            if let game = viewModel.mostPlayedGame, game.playTime > 0 {
                                statCard(value: game.name, label: "Meiste Spielzeit", icon: "trophy.fill", color: .orange)
                            }
                        }
                    }

                    // Zuletzt gespielt
                    if let game = viewModel.lastPlayedGame {
                        VStack(spacing: 12) {
                            sectionTitle("Aktivität")
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.accentColor)
                                LText("Zuletzt gespielt: ")
                                    .foregroundColor(.secondary)
                                Text(game.name)
                                    .fontWeight(.medium)
                                Spacer()
                                if let last = game.lastPlayed {
                                    Text(last, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(10)
                        }
                    }

                    // Pro Plattform
                    if !viewModel.platformStats.isEmpty {
                        VStack(spacing: 12) {
                            sectionTitle("Plattformen")
                            ForEach(viewModel.platformStats, id: \.0) { platform, count in
                                statRow(label: platform, count: count, total: viewModel.games.count)
                            }
                        }
                    }

                    // Pro Kategorie
                    if !viewModel.categoryStats.isEmpty {
                        VStack(spacing: 12) {
                            sectionTitle("Kategorien")
                            ForEach(viewModel.categoryStats, id: \.0) { cat, count in
                                statRow(label: cat, count: count, total: viewModel.gamesWithCategory)
                            }
                        }
                    }

                    // Pro Runner
                    if !viewModel.runnerStats.isEmpty {
                        VStack(spacing: 12) {
                            sectionTitle("Runner")
                            ForEach(viewModel.runnerStats, id: \.0) { runner, count in
                                statRow(label: runner, count: count, total: viewModel.games.count)
                            }
                        }
                    }

                    // Bewertungsverteilung
                    if !viewModel.ratingStats.isEmpty {
                        VStack(spacing: 12) {
                            sectionTitle("Bewertungsverteilung")
                            ForEach((1...5).reversed(), id: \.self) { stars in
                                if let count = viewModel.ratingStats[stars] {
                                    HStack(spacing: 8) {
                                        HStack(spacing: 2) {
                                            ForEach(0..<stars, id: \.self) { _ in
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.yellow)
                                            }
                                        }
                                        .frame(width: 60)
                                        GeometryReader { geo in
                                            let maxCount = viewModel.ratingStats.values.max() ?? 1
                                            let ratio = CGFloat(count) / CGFloat(maxCount)
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.yellow.opacity(0.6))
                                                .frame(width: geo.size.width * ratio)
                                        }
                                        .frame(height: 14)
                                        Text("\(count)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 24)
                                    }
                                }
                            }
                        }
                    }

                    // Bewertungsdurchschnitt
                    if viewModel.averageRating > 0 {
                        VStack(spacing: 4) {
                            Divider()
                            HStack {
                                LText("Durchschnittliche Bewertung:")
                                    .foregroundColor(.secondary)
                                HStack(spacing: 1) {
                                    ForEach(0..<5, id: \.self) { i in
                                        Image(systemName: i < Int(viewModel.averageRating.rounded()) ? "star.fill" : "star")
                                            .font(.caption)
                                            .foregroundColor(.yellow)
                                    }
                                }
                                Text(String(format: "%.1f", viewModel.averageRating))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()
            Button { dismiss() } label: { LText("Schliessen") }
                .keyboardShortcut(.defaultAction)
                .padding()
        }
        .frame(width: 460, height: 560)
    }

    @ViewBuilder
    private func sectionTitle(_ key: String) -> some View {
        HStack {
            Text(verbatim: tr(key))
                .font(.headline)
            Spacer()
        }
    }

    @ViewBuilder
    private func statCard(value: String, label key: String, icon: String, color: Color = .accentColor) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: tr(key))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func statRow(label: String, count: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                let ratio = total > 0 ? CGFloat(count) / CGFloat(total) : 0
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: max(geo.size.width * ratio, ratio > 0 ? 4 : 0))
            }
            .frame(height: 14)
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 28)
        }
    }
}
