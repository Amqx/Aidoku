//
//  CachedMangaObject.swift
//  Aidoku
//
//  Created by Amqx on 8/27/26.
//

import AidokuRunner
import CoreData

@objc(CachedMangaObject)
public class CachedMangaObject: NSManagedObject {
    func load(from manga: AidokuRunner.Manga) {
        sourceId = manga.sourceKey
        id = manga.key
        title = manga.title
        cover = manga.cover
    }

    func toManga() -> AidokuRunner.Manga {
        .init(sourceKey: sourceId, key: id, title: title, cover: cover)
    }
}

extension CachedMangaObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CachedMangaObject> {
        NSFetchRequest<CachedMangaObject>(entityName: "CachedManga")
    }

    @NSManaged public var sourceId: String
    @NSManaged public var id: String
    @NSManaged public var title: String
    @NSManaged public var cover: String?
    @NSManaged public var chaptersCached: Bool
}
