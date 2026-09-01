//
//  TrackerLookupTests.swift
//  AidokuTests
//
//  Created by Amqx on 8/31/26.
//

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

    @Test func emptyResultsAreNoMatch() {
        let state = TrackerManager.bestMatch(in: [], title: "Anything")

        guard case .noMatch = state else {
            Issue.record("expected no match, got \(state)")
            return
        }
    }
}
