//
//  TrackerLookupTests.swift
//  AidokuTests
//
//  Created by Amqx on 8/31/26.
//

import AidokuRunner
import Testing
@testable import Aidoku

struct TrackerLookupTests {
    @Test func publicCatalogTrackersSupportAnonymousSearch() {
        let trackerIds = TrackerManager.trackers
            .filter { $0.supportsAnonymousSearch }
            .map { $0.id }

        #expect(trackerIds == ["anilist", "myanimelist", "mangabaka", "shikimori", "bangumi"])
    }

    @Test func prefersNormalizedExactTitle() {
        let results = [
            TrackSearchItem(id: "first", title: "Hero Academia", tracked: false),
            TrackSearchItem(id: "exact", title: "My Hero Academia!", tracked: false)
        ]

        let state = TrackerManager.bestMatch(in: results, title: "My Hero Academia")

        guard case let .match(item) = state else {
            Issue.record("expected an exact match, got \(state)")
            return
        }
        #expect(item.id == "exact")
    }

    @Test func matchesAlternateTitle() {
        let results = [
            TrackSearchItem(id: "first", title: "Unrelated", tracked: false),
            TrackSearchItem(
                id: "alternate",
                title: "Oyasumi Punpun",
                alternateTitles: ["Goodnight Punpun"],
                tracked: false
            )
        ]

        let state = TrackerManager.bestMatch(in: results, title: "Goodnight Punpun")

        guard case let .match(item) = state else {
            Issue.record("expected an exact match, got \(state)")
            return
        }
        #expect(item.id == "alternate")
    }

    @Test func unmatchedTopResultIsOnlyAPossibleMatch() {
        let results = [
            TrackSearchItem(id: "first", title: "First Result", tracked: false),
            TrackSearchItem(id: "second", title: "Second Result", tracked: false)
        ]

        let state = TrackerManager.bestMatch(in: results, title: "Unrelated Title")

        guard case let .possibleMatch(item) = state else {
            Issue.record("expected a possible match, got \(state)")
            return
        }
        #expect(item.id == "first")
    }

    @Test func comicPrefersComicEntryWithSameTitle() {
        let results = [
            TrackSearchItem(id: "novel", title: "Solo Leveling", type: .novel, tracked: false),
            TrackSearchItem(id: "webtoon", title: "Solo Leveling", type: .manhwa, tracked: false)
        ]

        let state = TrackerManager.bestMatch(in: results, title: "Solo Leveling", format: .comic)

        guard case let .match(item) = state else {
            Issue.record("expected an exact match, got \(state)")
            return
        }
        #expect(item.id == "webtoon")
    }

    @Test func novelPrefersNovelEntryWithSameTitle() {
        let results = [
            TrackSearchItem(id: "webtoon", title: "Solo Leveling", type: .manga, tracked: false),
            TrackSearchItem(id: "novel", title: "Solo Leveling", type: .novel, tracked: false)
        ]

        let state = TrackerManager.bestMatch(in: results, title: "Solo Leveling", format: .novel)

        guard case let .match(item) = state else {
            Issue.record("expected an exact match, got \(state)")
            return
        }
        #expect(item.id == "novel")
    }

    @Test func confirmedFormatBeatsUnreportedFormat() {
        let results = [
            TrackSearchItem(id: "unknown", title: "Solo Leveling", type: .unknown, tracked: false),
            TrackSearchItem(id: "webtoon", title: "Solo Leveling", type: .manga, tracked: false)
        ]

        let state = TrackerManager.bestMatch(in: results, title: "Solo Leveling", format: .comic)

        guard case let .match(item) = state else {
            Issue.record("expected an exact match, got \(state)")
            return
        }
        #expect(item.id == "webtoon")
    }

    @Test func unreportedFormatCanStillMatch() {
        let results = [TrackSearchItem(id: "unknown", title: "Solo Leveling", tracked: false)]

        let state = TrackerManager.bestMatch(in: results, title: "Solo Leveling", format: .novel)

        guard case let .match(item) = state else {
            Issue.record("expected an exact match, got \(state)")
            return
        }
        #expect(item.id == "unknown")
    }

    @Test func wrongFormatTitleIsNotAConfirmedMatch() {
        let results = [
            TrackSearchItem(id: "novel", title: "Solo Leveling", type: .novel, tracked: false),
            TrackSearchItem(id: "other", title: "Solo Leveling: Ragnarok", type: .manhwa, tracked: false)
        ]

        let state = TrackerManager.bestMatch(in: results, title: "Solo Leveling", format: .comic)

        guard case let .possibleMatch(item) = state else {
            Issue.record("expected a possible match, got \(state)")
            return
        }
        #expect(item.id == "other")
    }

    @Test func onlyWrongFormatResultsArePossibleMatches() {
        let results = [TrackSearchItem(id: "novel", title: "Solo Leveling", type: .novel, tracked: false)]

        let state = TrackerManager.bestMatch(in: results, title: "Solo Leveling", format: .comic)

        guard case let .possibleMatch(item) = state else {
            Issue.record("expected a possible match, got \(state)")
            return
        }
        #expect(item.id == "novel")
    }

    @Test func unknownSeriesFormatKeepsResultOrder() {
        let results = [
            TrackSearchItem(id: "novel", title: "Solo Leveling", type: .novel, tracked: false),
            TrackSearchItem(id: "webtoon", title: "Solo Leveling", type: .manhwa, tracked: false)
        ]

        let state = TrackerManager.bestMatch(in: results, title: "Solo Leveling")

        guard case let .match(item) = state else {
            Issue.record("expected an exact match, got \(state)")
            return
        }
        #expect(item.id == "novel")
    }

    @Test(arguments: [
        (["Action", "Light Novel"], AidokuRunner.Viewer.unknown, TrackerSeriesFormat?.some(.novel)),
        (["小说"], .unknown, .novel),
        // a scrolling text series can still report a page-based viewer
        (["Web Novel"], .webtoon, .novel),
        (["Long Strip"], .unknown, .comic),
        (["WEBTOON"], .unknown, .comic),
        (["Action"], .webtoon, .comic),
        (["Action"], .rightToLeft, .comic),
        ([], .unknown, nil),
        (["Action"], .unknown, nil),
        // an adaptation's tags can name both formats, so neither can be trusted
        (["Manga", "Novel"], .rightToLeft, nil),
        // only the whole tag counts, not one that merely mentions a format
        (["Novel Adaptation"], .unknown, nil)
    ]) func infersSeriesFormat(tags: [String], viewer: AidokuRunner.Viewer, expected: TrackerSeriesFormat?) {
        let manga = AidokuRunner.Manga(sourceKey: "source", key: "key", title: "Title", tags: tags, viewer: viewer)

        #expect(TrackerSeriesFormat(manga: manga) == expected)
    }

    @Test func allFormatsResolveFromTrackerMediaTypes() {
        #expect(TrackerSeriesFormat(mediaType: .novel) == .novel)
        #expect(TrackerSeriesFormat(mediaType: .manhwa) == .comic)
        #expect(TrackerSeriesFormat(mediaType: .oneShot) == .comic)
        #expect(TrackerSeriesFormat(mediaType: .unknown) == nil)
        #expect(TrackerSeriesFormat(mediaType: nil) == nil)
    }

    @Test func emptyResultsAreNoMatch() {
        let state = TrackerManager.bestMatch(in: [], title: "Anything")

        guard case .noMatch = state else {
            Issue.record("expected no match, got \(state)")
            return
        }
    }
}
