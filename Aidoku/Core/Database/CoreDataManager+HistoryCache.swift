//
//  CoreDataManager+HistoryCache.swift
//  Aidoku
//
//  Created by Amqx on 8/27/26.
//

import AidokuRunner
import CoreData

extension CoreDataManager {
    func getCachedManga(mangaId: MangaIdentifier, context: NSManagedObjectContext) -> CachedMangaObject? {
        let request = CachedMangaObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND id == %@",
            mangaId.sourceKey, mangaId.mangaKey
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func getCachedChapter(chapterId: ChapterIdentifier, context: NSManagedObjectContext) -> CachedChapterObject? {
        let request = CachedChapterObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "sourceId == %@ AND mangaId == %@ AND id == %@",
            chapterId.sourceKey, chapterId.mangaKey, chapterId.chapterKey
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get cached manga objects for a set of identifiers without issuing one fetch per manga.
    func getCachedManga(
        mangaIds: [MangaIdentifier],
        context: NSManagedObjectContext
    ) -> [MangaIdentifier: CachedMangaObject] {
        var result: [MangaIdentifier: CachedMangaObject] = [:]
        for batch in mangaIds.chunked(into: Self.fetchBatchSize) {
            let request = CachedMangaObject.fetchRequest()
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: batch.map {
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "sourceId == %@", $0.sourceKey),
                    NSPredicate(format: "id == %@", $0.mangaKey)
                ])
            })
            for object in (try? context.fetch(request)) ?? [] {
                let id = MangaIdentifier(sourceKey: object.sourceId, mangaKey: object.id)
                if result[id] == nil {
                    result[id] = object
                }
            }
        }
        return result
    }

    /// Get cached chapter objects for a set of identifiers without issuing one fetch per chapter.
    func getCachedChapters(
        chapterIds: [ChapterIdentifier],
        context: NSManagedObjectContext
    ) -> [ChapterIdentifier: CachedChapterObject] {
        var result: [ChapterIdentifier: CachedChapterObject] = [:]
        for batch in chapterIds.chunked(into: Self.fetchBatchSize) {
            let request = CachedChapterObject.fetchRequest()
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: batch.map {
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "sourceId == %@", $0.sourceKey),
                    NSPredicate(format: "mangaId == %@", $0.mangaKey),
                    NSPredicate(format: "id == %@", $0.chapterKey)
                ])
            })
            for object in (try? context.fetch(request)) ?? [] {
                let id = ChapterIdentifier(
                    sourceKey: object.sourceId,
                    mangaKey: object.mangaId,
                    chapterKey: object.id
                )
                if result[id] == nil {
                    result[id] = object
                }
            }
        }
        return result
    }

    func clearCachedManga(context: NSManagedObjectContext) {
        clear(request: CachedMangaObject.fetchRequest(), context: context)
    }

    func clearCachedChapters(context: NSManagedObjectContext) {
        clear(request: CachedChapterObject.fetchRequest(), context: context)
    }

    /// Clear cache entries for manga that are not currently in the library.
    func clearHistoryCacheExcludingLibrary(context: NSManagedObjectContext) {
        let libraryMangaIds = getLibraryManga(context: context).compactMap(\.manga?.identifier)
        let excludePredicate: NSPredicate
        if libraryMangaIds.isEmpty {
            excludePredicate = NSPredicate(value: true)
        } else {
            let pairPredicates = libraryMangaIds.map {
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "sourceId == %@", $0.sourceKey),
                    NSPredicate(format: "id == %@", $0.mangaKey)
                ])
            }
            excludePredicate = NSCompoundPredicate(
                notPredicateWithSubpredicate: NSCompoundPredicate(orPredicateWithSubpredicates: pairPredicates)
            )
        }

        let mangaRequest = CachedMangaObject.fetchRequest()
        mangaRequest.predicate = excludePredicate
        clear(request: mangaRequest, context: context)

        let chapterRequest = CachedChapterObject.fetchRequest()
        if libraryMangaIds.isEmpty {
            chapterRequest.predicate = NSPredicate(value: true)
        } else {
            let pairPredicates = libraryMangaIds.map {
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "sourceId == %@", $0.sourceKey),
                    NSPredicate(format: "mangaId == %@", $0.mangaKey)
                ])
            }
            chapterRequest.predicate = NSCompoundPredicate(
                notPredicateWithSubpredicate: NSCompoundPredicate(orPredicateWithSubpredicates: pairPredicates)
            )
        }
        clear(request: chapterRequest, context: context)
    }

    func removeHistoryCache(mangaId: MangaIdentifier, context: NSManagedObjectContext) {
        let mangaRequest = CachedMangaObject.fetchRequest()
        mangaRequest.predicate = NSPredicate(
            format: "sourceId == %@ AND id == %@",
            mangaId.sourceKey, mangaId.mangaKey
        )
        clear(request: mangaRequest, context: context)

        let chapterRequest = CachedChapterObject.fetchRequest()
        chapterRequest.predicate = NSPredicate(
            format: "sourceId == %@ AND mangaId == %@",
            mangaId.sourceKey, mangaId.mangaKey
        )
        clear(request: chapterRequest, context: context)
    }

    /// Remove chapter cache rows with deleted history and the manga row once no history remains.
    func pruneHistoryCache(
        mangaId: MangaIdentifier,
        removedChapterIds: [String],
        context: NSManagedObjectContext
    ) {
        guard !removedChapterIds.isEmpty else { return }
        for batch in removedChapterIds.chunked(into: Self.fetchBatchSize) {
            let request = CachedChapterObject.fetchRequest()
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND id IN %@",
                mangaId.sourceKey, mangaId.mangaKey, batch
            )
            clear(request: request, context: context)
        }
        if !getHistoryForManga(mangaId: mangaId, context: context).contains(where: { !$0.isDeleted }) {
            removeHistoryCache(mangaId: mangaId, context: context)
        }
    }

    /// Stores source results in the device-local history cache for the requested history chapters.
    func cacheHistoryData(
        manga: AidokuRunner.Manga,
        mangaId: MangaIdentifier,
        mangaDetails: AidokuRunner.Manga,
        chapterIds: Set<String>,
        context: NSManagedObjectContext
    ) {
        let requestedIdentifiers = chapterIds.map {
            ChapterIdentifier(
                sourceKey: mangaId.sourceKey,
                mangaKey: mangaId.mangaKey,
                chapterKey: $0
            )
        }
        let histories = Dictionary(grouping: getHistory(
            sourceId: mangaId.sourceKey,
            mangaId: mangaId.mangaKey,
            chapterIds: requestedIdentifiers.map(\.chapterKey),
            context: context
        ).filter { !$0.isDeleted }, by: \HistoryObject.chapterId)
        let identifiers = requestedIdentifiers.filter { histories[$0.chapterKey] != nil }

        // A source request can finish after its history was removed. Only recreate cache rows
        // for chapters whose history still exists in this context.
        guard !identifiers.isEmpty else { return }

        let mangaObject = getCachedManga(mangaId: mangaId, context: context)
            ?? CachedMangaObject(context: context)
        mangaObject.load(from: mangaDetails)
        // The lookup key is authoritative; sources may normalize keys in returned payloads.
        mangaObject.sourceId = mangaId.sourceKey
        mangaObject.id = mangaId.mangaKey

        let chapters = manga.chapters ?? []
        mangaObject.chaptersCached = !chapters.isEmpty
        let cachedChapters = getCachedChapters(chapterIds: identifiers, context: context)
        let chaptersByKey = Dictionary(chapters.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        for chapterId in identifiers {
            if let chapter = chaptersByKey[chapterId.chapterKey] {
                let chapterObject = cachedChapters[chapterId]
                    ?? CachedChapterObject(context: context)
                chapterObject.load(from: chapter, mangaId: mangaId)
                for historyObject in histories[chapter.key] ?? [] {
                    historyObject.loadChapterMetadata(from: chapter)
                }
            } else if !chapters.isEmpty && cachedChapters[chapterId] == nil {
                // Record that a non-empty source response did not contain this chapter, so a
                // dropped chapter does not trigger the same network request on every launch.
                let chapterObject = CachedChapterObject(context: context)
                chapterObject.sourceId = mangaId.sourceKey
                chapterObject.mangaId = mangaId.mangaKey
                chapterObject.id = chapterId.chapterKey
            }
        }
    }
}
