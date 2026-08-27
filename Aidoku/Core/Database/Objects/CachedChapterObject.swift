//
//  CachedChapterObject.swift
//  Aidoku
//
//  Created by Amqx on 8/27/26.
//

import AidokuRunner
import CoreData

@objc(CachedChapterObject)
public class CachedChapterObject: NSManagedObject {
    func load(from chapter: AidokuRunner.Chapter, mangaId: MangaIdentifier) {
        sourceId = mangaId.sourceKey
        self.mangaId = mangaId.mangaKey
        id = chapter.key
        title = chapter.title
        self.chapter = chapter.chapterNumber.map(NSNumber.init(value:))
        volume = chapter.volumeNumber.map(NSNumber.init(value:))
    }

    func toChapter() -> AidokuRunner.Chapter {
        .init(
            key: id,
            title: title,
            chapterNumber: chapter?.floatValue,
            volumeNumber: volume?.floatValue
        )
    }
}

extension CachedChapterObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CachedChapterObject> {
        NSFetchRequest<CachedChapterObject>(entityName: "CachedChapter")
    }

    @NSManaged public var sourceId: String
    @NSManaged public var mangaId: String
    @NSManaged public var id: String
    @NSManaged public var title: String?
    @NSManaged public var chapter: NSNumber?
    @NSManaged public var volume: NSNumber?
}
