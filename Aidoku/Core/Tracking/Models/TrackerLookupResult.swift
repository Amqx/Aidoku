//
//  TrackerLookupResult.swift
//  Aidoku
//
//  Created by Amqx on 8/31/26.
//

import Foundation

struct TrackerLookupResult: Identifiable, Sendable {
    enum State: Sendable {
        case match(TrackSearchItem)
        case possibleMatch(TrackSearchItem)
        case noMatch
        case failed
    }

    let tracker: Tracker
    let state: State
    var items: [TrackSearchItem] = []

    var id: String { tracker.id }

    var failed: Bool {
        if case .failed = state { true } else { false }
    }
}
