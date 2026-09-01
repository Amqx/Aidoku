//
//  TrackerLookupResult.swift
//  Aidoku
//
//  Created by Amqx on 8/31/26.
//

import Foundation

struct TrackerLookupResult: Identifiable, Sendable {
    enum State: Sendable {
        /// A catalog entry whose title matches the local manga title.
        case match(TrackSearchItem)
        /// The tracker's top search result, which didn't match the local manga title.
        case possibleMatch(TrackSearchItem)
        case noMatch
        case failed
    }

    let tracker: Tracker
    let state: State

    var id: String { tracker.id }

    var failed: Bool {
        if case .failed = state { true } else { false }
    }
}
