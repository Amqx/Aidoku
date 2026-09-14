//
//  CoreDataManager+Metadata.swift
//  Aidoku
//
//  Created by Amqx on 9/13/26.
//

import AidokuRunner
import CoreData

extension CoreDataManager {
    /// Store complete source metadata independently of library membership.
    /// Library refreshes own updates to bookmarked manga, including edited fields and update notifications.
    func cacheMetadata(
        manga: AidokuRunner.Manga,
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) {
        let object = getManga(mangaId: mangaId, context: context) ?? MangaObject(context: context)
        guard object.libraryObject == nil, object.fileInfo == nil else { return }
        object.load(from: manga)
        // The lookup identity wins if a source normalizes the key in its response.
        object.sourceId = mangaId.sourceKey
        object.id = mangaId.mangaKey
        if let chapters = manga.chapters {
            setChapters(chapters, mangaId: mangaId, context: context)
        }
        removeLegacyHistoryCache(mangaId: mangaId, context: context)
    }

    /// Cache reader metadata once, without rewriting the chapter list on every progress update.
    func cacheMetadataIfMissing(manga: AidokuRunner.Manga, context: NSManagedObjectContext) {
        guard getManga(mangaId: manga.identifier, context: context) == nil else { return }
        cacheMetadata(manga: manga, mangaId: manga.identifier, context: context)
    }

    /// Library and local-file records survive clearing the history cache.
    func removeCachedMetadata(mangaId: MangaIdentifier, context: NSManagedObjectContext) {
        guard let manga = getManga(mangaId: mangaId, context: context),
              manga.libraryObject == nil, manga.fileInfo == nil else { return }
        removeChapters(mangaId: mangaId, context: context)
        context.delete(manga)
    }

    func clearCachedMetadata(context: NSManagedObjectContext) {
        // History clearing uses batch deletes. Keep this cleanup in the store as well so it
        // doesn't try to save stale chapter snapshots after their history relationships changed.
        let chapters = ChapterObject.fetchRequest()
        chapters.predicate = NSPredicate(
            format: "manga != nil AND manga.libraryObject == nil AND manga.fileInfo == nil AND fileInfo == nil"
        )
        clear(request: chapters, context: context)
        let request = MangaObject.fetchRequest()
        request.predicate = NSPredicate(format: "libraryObject == nil AND fileInfo == nil")
        clear(request: request, context: context)
    }
}
