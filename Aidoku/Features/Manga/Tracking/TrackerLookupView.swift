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
    var lookup: (AidokuRunner.Manga) async -> [TrackerLookupResult] = {
        await TrackerManager.shared.lookupDetails(for: $0)
    }

    @State private var loading = true
    @State private var results: [TrackerLookupResult] = []
    @State private var safariUrl: URL?
    @State private var showSafari = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // no tracker returned anything usable, so the rows would all say the same thing
    private var unavailable: Bool {
        !loading && (results.isEmpty || results.allSatisfy { $0.failed })
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                if !loading && !unavailable {
                    ForEach(results) { result in
                        Section {
                            TrackerLookupRow(result: result, mangaTitle: manga.title, open: open)

                            if result.items.count > 1 {
                                NavigationLink {
                                    TrackerLookupAllResultsView(result: result, mangaTitle: manga.title, open: open)
                                } label: {
                                    Text(String(format: NSLocalizedString("VIEW_ALL_RESULTS_%i"), result.items.count))
                                }
                            }
                        } header: {
                            if result.id == results.first?.id {
                                Text(NSLocalizedString("TRACKER_LOOKUP_DESCRIPTION"))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.defaultMinListHeaderHeight, 1) // for ios 15
            .listSectionSpacingPlease(10)
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
            .sheet(isPresented: $showSafari) {
                SafariView(url: $safariUrl)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .task {
                results = await lookup(manga)
                withAnimation {
                    loading = false
                }
            }
        }
    }

    private func open(_ item: TrackSearchItem, on tracker: Tracker) {
        Task {
            guard let url = await tracker.getUrl(trackId: item.id) else { return }
            if AppSettings.tracking.openLookupLinksExternally.get() {
                openURL(url)
            } else {
                safariUrl = url
                showSafari = true
            }
        }
    }
}

private struct TrackerLookupRow: View {
    let result: TrackerLookupResult
    let mangaTitle: String
    let open: (TrackSearchItem, Tracker) -> Void

    var body: some View {
        switch result.state {
            case let .match(item), let .possibleMatch(item):
                Button {
                    open(item, result.tracker)
                } label: {
                    TrackerLookupResultView(result: result, mangaTitle: mangaTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offsetListSeparator()
                .accessibilityHint(NSLocalizedString("VIEW_ON_WEBSITE"))
            case .noMatch, .failed:
                TrackerLookupResultView(result: result, mangaTitle: mangaTitle)
                    .offsetListSeparator()
        }
    }
}

/// Everything a tracker's search returned, in the tracker's own order.
private struct TrackerLookupAllResultsView: View {
    let result: TrackerLookupResult
    let mangaTitle: String
    let open: (TrackSearchItem, Tracker) -> Void

    var body: some View {
        List {
            ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                Button {
                    open(item, result.tracker)
                } label: {
                    TrackerLookupItemView(item: item, mangaTitle: mangaTitle, exact: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offsetListSeparator()
                .accessibilityHint(NSLocalizedString("VIEW_ON_WEBSITE"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(result.tracker.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TrackerLookupResultView: View {
    let result: TrackerLookupResult
    let mangaTitle: String

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
                    TrackerLookupItemView(item: item, mangaTitle: mangaTitle, exact: true)
                case let .possibleMatch(item):
                    TrackerLookupItemView(item: item, mangaTitle: mangaTitle, exact: false)
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
}

private struct TrackerLookupItemView: View {
    let item: TrackSearchItem
    let mangaTitle: String
    let exact: Bool

    private static let ratingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter
    }()

    var body: some View {
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

#if DEBUG
private final class PreviewTracker: Tracker {
    let id: String
    let name: String
    let icon: PlatformImage?
    let isLoggedIn = true

    init(id: String, name: String, icon: String) {
        self.id = id
        self.name = name
        self.icon = PlatformImage(named: icon)
    }

    func getTrackerInfo() async throws -> TrackerInfo {
        TrackerInfo(supportedStatuses: [], scoreType: .tenPoint)
    }
    func register(trackId: String, highestChapterRead: Float?, earliestReadDate: Date?) async throws -> String? { nil }
    func update(trackId: String, update: TrackUpdate) async throws {}
    func getState(trackId: String) async throws -> TrackState { TrackState() }
    func getUrl(trackId: String) async -> URL? { URL(string: "https://example.com/\(trackId)") }
    func search(for manga: AidokuRunner.Manga, includeNsfw: Bool) async throws -> [TrackSearchItem] { [] }
    func search(title: String, includeNsfw: Bool) async throws -> [TrackSearchItem] { [] }
    func logout() async throws {}
}

private enum TrackerLookupPreviewData {
    static let manga = AidokuRunner.Manga(sourceKey: "preview", key: "preview", title: "Frieren")

    static let anilist = PreviewTracker(id: "anilist", name: "AniList", icon: "anilist")
    static let myAnimeList = PreviewTracker(id: "mal", name: "MyAnimeList", icon: "mal")
    static let bangumi = PreviewTracker(id: "bangumi", name: "Bangumi", icon: "bangumi")
    static let shikimori = PreviewTracker(id: "shikimori", name: "Shikimori", icon: "shikimori")

    static let items = [
        TrackSearchItem(id: "1", title: "Frieren", status: .ongoing, type: .manga, rating: 9.1, tracked: true),
        TrackSearchItem(id: "2", title: "Frieren: Beyond Journey's End", status: .hiatus, type: .novel, rating: 8.4, tracked: false),
        TrackSearchItem(id: "3", title: "Frieren Anthology", status: .completed, type: .oneShot, tracked: nil)
    ]

    static let results = [
        TrackerLookupResult(tracker: anilist, state: .match(items[0]), items: items),
        TrackerLookupResult(tracker: myAnimeList, state: .possibleMatch(items[1]), items: [items[1]]),
        TrackerLookupResult(tracker: bangumi, state: .noMatch),
        TrackerLookupResult(tracker: shikimori, state: .failed)
    ]
}

#Preview("Results") {
    TrackerLookupView(manga: TrackerLookupPreviewData.manga) { _ in
        TrackerLookupPreviewData.results
    }
}

#Preview("All Results") {
    PlatformNavigationStack {
        TrackerLookupAllResultsView(
            result: TrackerLookupPreviewData.results[0],
            mangaTitle: TrackerLookupPreviewData.manga.title,
            open: { _, _ in }
        )
    }
}

#Preview("Loading") {
    TrackerLookupView(manga: TrackerLookupPreviewData.manga) { _ in
        try? await Task.sleep(nanoseconds: .max)
        return []
    }
}

#Preview("No Trackers") {
    TrackerLookupView(manga: TrackerLookupPreviewData.manga) { _ in [] }
}

#Preview("Unavailable") {
    TrackerLookupView(manga: TrackerLookupPreviewData.manga) { _ in
        [TrackerLookupResult(tracker: TrackerLookupPreviewData.anilist, state: .failed)]
    }
}
#endif
