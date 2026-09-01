//
//  TrackSearchItem.swift
//  Aidoku
//
//  Created by Skitty on 6/16/22.
//

import Foundation

/// A structure containing the necessary data to be returned from a tracker search.
struct TrackSearchItem: Equatable, Sendable {
    /// A unique identifier of the tracker item.
    let id: String
    /// The title of the tracker item.
    var title: String?
    /// Other titles the item is known by, used to match against a local manga title.
    var alternateTitles: [String]
    /// The URL for the cover image of the tracker item.
    var coverUrl: String?
    /// The description or summary of the tracker item.
    var description: String?
    /// The publishing status of the tracker item.
    var status: PublishingStatus?
    /// The type or format of the tracker item.
    var type: MediaType?
    /// The tracker community rating, normalized to a ten-point scale.
    var rating: Double?
    /// Whether the item is currently being tracked by the user, or nil if the tracker doesn't report it.
    var tracked: Bool?

    /// Every title the item is known by, most preferred first.
    var titles: [String] {
        (title.map { [$0] } ?? []) + alternateTitles
    }

    init(
        id: String,
        title: String? = nil,
        alternateTitles: [String] = [],
        coverUrl: String? = nil,
        description: String? = nil,
        status: PublishingStatus? = nil,
        type: MediaType? = nil,
        rating: Double? = nil,
        tracked: Bool?
    ) {
        self.id = id
        self.title = title
        self.alternateTitles = alternateTitles
        self.coverUrl = coverUrl
        self.description = description
        self.status = status
        self.type = type
        self.rating = rating
        self.tracked = tracked
    }
}
