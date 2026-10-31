//
//  TrackerSeriesFormat.swift
//  Aidoku
//
//  Created by Amqx on 10/31/26.
//

import AidokuRunner

/// Whether a series is a novel or comic form.
enum TrackerSeriesFormat: Sendable, Equatable {
    case novel
    case comic

    private static let novelTags = Set([
        "novel", "light novel", "web novel", "ln", "wn",
        "小说", "小説", "轻小说", "ライトノベル", "ノベル", "소설", "라이트노벨", "웹소설"
    ].map(TrackerManager.normalizedTrackerTitle))

    private static let comicTags = Set([
        "manga", "manhwa", "manhua", "webtoon", "webtoons", "comic", "comics", "web comic", "long strip",
        "漫画", "漫畫", "マンガ", "만화", "웹툰"
    ].map(TrackerManager.normalizedTrackerTitle))

    /// Tries to guess the format of a local series, nil if it can't.
    init?(manga: AidokuRunner.Manga) {
        let tags = Set((manga.tags ?? []).map(TrackerManager.normalizedTrackerTitle))
        switch (!tags.isDisjoint(with: Self.novelTags), !tags.isDisjoint(with: Self.comicTags)) {
            case (true, true):
                return nil
            case (true, false):
                self = .novel
            case (false, true):
                self = .comic
            case (false, false):
                guard manga.viewer != .unknown else { return nil }
                self = .comic
        }
    }

    /// The format of a tracker catalog entry, or nil if the tracker didn't report a usable type.
    init?(mediaType: MediaType?) {
        switch mediaType {
            case .novel, .book:
                self = .novel
            case .manga, .manhwa, .manhua, .oneShot, .oel, .comic:
                self = .comic
            case .unknown, nil:
                return nil
        }
    }
}
