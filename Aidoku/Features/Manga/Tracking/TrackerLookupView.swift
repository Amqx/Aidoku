//
//  TrackerLookupView.swift
//  Aidoku
//
//  Created by Amqx on 8/31/26.
//

import AidokuRunner
import SwiftUI

struct TrackerLookupView: View {
    let manga: AidokuRunner.Manga

    @State private var loading = true
    @State private var results: [TrackerLookupResult] = []

    @Environment(\.dismiss) private var dismiss

    // no tracker returned anything usable, so the rows would all say the same thing
    private var unavailable: Bool {
        !loading && (results.isEmpty || results.allSatisfy { $0.failed })
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                if !loading && !unavailable {
                    Section {
                        ForEach(results) { result in
                            TrackerLookupResultView(result: result, mangaTitle: manga.title)
                        }
                    } header: {
                        Text(NSLocalizedString("TRACKER_LOOKUP_DESCRIPTION"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if loading {
                    ProgressView().progressViewStyle(.circular)
                } else if unavailable {
                    if results.isEmpty {
                        UnavailableView(
                            NSLocalizedString("NO_TRACKERS_AVAILABLE"),
                            systemImage: "magnifyingglass"
                        )
                        .padding()
                    } else {
                        UnavailableView(
                            NSLocalizedString("TRACKER_LOOKUP_UNAVAILABLE"),
                            systemImage: "exclamationmark.triangle",
                            description: Text(NSLocalizedString("TRACKER_LOOKUP_UNAVAILABLE_TEXT"))
                        )
                        .padding()
                    }
                }
            }
            .navigationTitle(NSLocalizedString("TRACKER_LOOKUP"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .task {
                results = await TrackerManager.shared.lookupDetails(for: manga)
                withAnimation {
                    loading = false
                }
            }
        }
    }
}

private struct TrackerLookupResultView: View {
    let result: TrackerLookupResult
    let mangaTitle: String

    private static let ratingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(uiImage: result.tracker.icon ?? UIImage(named: "MangaPlaceholder")!)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(result.tracker.name)
                    .font(.headline)
            }

            switch result.state {
                case let .match(item):
                    matchView(item, exact: true)
                case let .possibleMatch(item):
                    matchView(item, exact: false)
                case .noMatch:
                    Label(NSLocalizedString("NO_MATCH_FOUND"), systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                case .failed:
                    Label(NSLocalizedString("TRACKER_LOOKUP_FAILED"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    func matchView(_ item: TrackSearchItem, exact: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MangaCoverView(
                coverImage: item.coverUrl ?? "",
                width: 56,
                height: 56 * 3/2,
                downsampleWidth: 56
            )

            VStack(alignment: .leading, spacing: 5) {
                if !exact {
                    Text(NSLocalizedString("POSSIBLE_MATCH"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Text(item.title ?? mangaTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let rating = item.rating, rating > 0, let formatted = Self.formatted(rating: rating) {
                        Label(
                            String(format: NSLocalizedString("RATING_%@_OF_TEN"), formatted),
                            systemImage: "star.fill"
                        )
                    }
                    if item.tracked == true {
                        Label(NSLocalizedString("TRACKED"), systemImage: "checkmark.circle.fill")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if item.status != .unknown, let status = item.status?.toString() {
                    Text(String(format: NSLocalizedString("STATUS_COLON_%@"), status))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if item.type != .unknown, let type = item.type?.toString() {
                    Text(String(format: NSLocalizedString("TYPE_COLON_%@"), type))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func formatted(rating: Double) -> String? {
        ratingFormatter.string(from: rating as NSNumber)
    }
}
