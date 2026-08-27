//
//  HistoryObject.swift
//  Aidoku
//
//  Created by Skitty on 1/27/22.
//

import Foundation
import CoreData
import AidokuRunner

@objc(HistoryObject)
public class HistoryObject: NSManagedObject {
    var identifier: ChapterIdentifier {
        .init(sourceKey: sourceId, mangaKey: mangaId, chapterKey: chapterId)
    }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        dateRead = Date.distantPast
        progress = -1
        total = 0
        completed = false
    }

    func loadChapterMetadata(from chapter: AidokuRunner.Chapter) {
        chapterNumber = chapter.chapterNumber.map { NSNumber(value: $0) }
        volumeNumber = chapter.volumeNumber.map { NSNumber(value: $0) }
        chapterTitle = chapter.title
    }

    func metadataChapter() -> AidokuRunner.Chapter? {
        guard chapterNumber != nil || volumeNumber != nil || chapterTitle != nil else { return nil }
        return .init(
            key: chapterId,
            title: chapterTitle,
            chapterNumber: chapterNumber?.floatValue,
            volumeNumber: volumeNumber?.floatValue
        )
    }
}

extension HistoryObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HistoryObject> {
        NSFetchRequest<HistoryObject>(entityName: "History")
    }

    @NSManaged public var dateRead: Date?
    @NSManaged public var sourceId: String
    @NSManaged public var chapterId: String
    @NSManaged public var mangaId: String

    @NSManaged public var progress: Int16
    @NSManaged public var total: Int16
    @NSManaged public var completed: Bool
    @NSManaged public var scrollPosition: NSNumber?
    @NSManaged public var chapterNumber: NSNumber?
    @NSManaged public var volumeNumber: NSNumber?
    @NSManaged public var chapterTitle: String?

    @NSManaged public var chapter: ChapterObject?
    @NSManaged public var sessions: NSSet?
}

extension HistoryObject {
    @objc(addSessionsObject:)
    @NSManaged public func addToSessions(_ value: ReadingSessionObject)

    @objc(removeSessionsObject:)
    @NSManaged public func removeFromSessions(_ value: ReadingSessionObject)

    @objc(addSessions:)
    @NSManaged public func addToSessions(_ values: NSSet)

    @objc(removeSessions:)
    @NSManaged public func removeFromSessions(_ values: NSSet)
}

extension HistoryObject: Identifiable {

}
