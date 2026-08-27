//
//  CoreDataManager+History.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/14/22.
//

import AidokuRunner
import CoreData

extension CoreDataManager {
    /// Remove all history objects.
    func clearHistory(context: NSManagedObjectContext) {
        clear(request: HistoryObject.fetchRequest(), context: context)
        clearCachedManga(context: context)
        clearCachedChapters(context: context)
    }

    /// Remove all history objects from manga not in library
    func clearHistoryExcludingLibrary(context: NSManagedObjectContext) {
        let request = HistoryObject.fetchRequest()

        let pairPredicates = self.getLibraryManga(context: context).compactMap { mangaObj -> NSCompoundPredicate? in
            guard
                let mangaId = mangaObj.manga?.id,
                let sourceId = mangaObj.manga?.sourceId
            else {
                return nil
            }
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "mangaId == %@", mangaId),
                NSPredicate(format: "sourceId == %@", sourceId)
            ])
        }

        let excludePredicate: NSPredicate
        if pairPredicates.isEmpty {
            // if nothing in library, don't exclude anything
            excludePredicate = NSPredicate(value: true)
        } else {
            // NOT ((mangaId == a AND sourceId == b) OR (mangaId == c AND sourceId == d) OR ...)
            let orPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: pairPredicates)
            excludePredicate = NSCompoundPredicate(notPredicateWithSubpredicate: orPredicate)
        }

        request.predicate = excludePredicate
        clear(request: request, context: context)
        clearHistoryCacheExcludingLibrary(context: context)
    }

    /// Gets all history objects.
    func getHistory(context: NSManagedObjectContext) -> [HistoryObject] {
        (try? context.fetch(HistoryObject.fetchRequest())) ?? []
    }

    /// Get history objects for a source.
    func getHistory(
        sourceKey: String,
        context: NSManagedObjectContext
    ) -> [HistoryObject] {
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(format: "sourceId == %@", sourceKey)
        return (try? context.fetch(request)) ?? []
    }

    /// Get a particular history object.
    func getHistory(
        chapterId: ChapterIdentifier,
        context: NSManagedObjectContext
    ) -> HistoryObject? {
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "chapterId == %@ AND mangaId == %@ AND sourceId == %@",
            chapterId.chapterKey, chapterId.mangaKey, chapterId.sourceKey
        )
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Get the history objects for particular chapters of a manga.
    ///
    /// Uses a single fetch request (batched, to keep the `IN` list a reasonable size) rather than one
    /// request per chapter. Duplicate history objects for the same chapter are all returned.
    func getHistory(
        sourceId: String,
        mangaId: String,
        chapterIds: [String],
        context: NSManagedObjectContext
    ) -> [HistoryObject] {
        guard !chapterIds.isEmpty else { return [] }
        var result: [HistoryObject] = []
        for batch in chapterIds.chunked(into: Self.fetchBatchSize) {
            let request = HistoryObject.fetchRequest()
            request.predicate = NSPredicate(
                format: "sourceId == %@ AND mangaId == %@ AND chapterId IN %@",
                sourceId, mangaId, batch
            )
            result += (try? context.fetch(request)) ?? []
        }
        return result
    }

    /// Gets sorted history objects.
    func getRecentHistory(limit: Int, offset: Int, context: NSManagedObjectContext) -> [HistoryObject] {
        let request = HistoryObject.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "dateRead", ascending: false),
            NSSortDescriptor(key: "chapter.chapter", ascending: false)
        ]
        request.fetchLimit = limit
        request.fetchOffset = offset
        return (try? context.fetch(request)) ?? []
    }

    /// Check if history exists for a chapter.
    func hasHistory(
        chapterId: ChapterIdentifier,
        context: NSManagedObjectContext
    ) -> Bool {
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "chapterId == %@ AND mangaId == %@ AND sourceId == %@",
            chapterId.chapterKey, chapterId.mangaKey, chapterId.sourceKey
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Check if history exists for a manga.
    func hasHistory(
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> Bool {
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId.mangaKey, mangaId.sourceKey
        )
        request.fetchLimit = 1
        return (try? context.count(for: request)) ?? 0 > 0
    }

    /// Removes history for manga.
    func removeHistory(mangaId: MangaIdentifier, context: NSManagedObjectContext) {
        let history = getHistoryForManga(mangaId: mangaId, context: context)
        for item in history {
            context.delete(item)
        }
        removeHistoryCache(mangaId: mangaId, context: context)
    }

    func removeHistory(chapterIds: [ChapterIdentifier]) async {
        await container.performBackgroundTask { context in
            do {
                // fetch once per manga instead of once per chapter
                let groups = Dictionary(grouping: chapterIds) {
                    MangaIdentifier(sourceKey: $0.sourceKey, mangaKey: $0.mangaKey)
                }
                for (key, chapterIds) in groups {
                    let objects = self.getHistory(
                        sourceId: key.sourceKey,
                        mangaId: key.mangaKey,
                        chapterIds: chapterIds.map { $0.chapterKey },
                        context: context
                    )
                    for object in objects {
                        context.delete(object)
                    }
                    self.pruneHistoryCache(
                        mangaId: key,
                        removedChapterIds: chapterIds.map(\.chapterKey),
                        context: context
                    )
                }
                try context.save()
            } catch {
                LogManager.logger.error("CoreDataManager.removeHistory(sourceId:mangaId:chapterIds:): \(error.localizedDescription)")
            }
        }
    }

    func getOrCreateHistory(
        chapterId: ChapterIdentifier,
        context: NSManagedObjectContext
    ) -> HistoryObject {
        if let historyObject = getHistory(
            chapterId: chapterId,
            context: context
        ) {
            return historyObject
        }
        let historyObject = HistoryObject(context: context)
        historyObject.sourceId = chapterId.sourceKey
        historyObject.mangaId = chapterId.mangaKey
        historyObject.chapterId = chapterId.chapterKey
        if let chapterObject = self.getChapter(chapterId: chapterId, context: context) {
            historyObject.chapter = chapterObject
        }
        return historyObject
    }

    /// Get history objects for a manga.
    func getHistoryForManga(
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> [HistoryObject] {
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@",
            mangaId.mangaKey, mangaId.sourceKey
        )
        return (try? context.fetch(request)) ?? []
    }

    // format: [chapterId: (page (-1 if completed), read date)]
    func getReadingHistory(mangaId: MangaIdentifier) async -> [String: (page: Int, date: Int)] {
        await container.performBackgroundTask { context in
            let objects = self.getHistoryForManga(mangaId: mangaId, context: context)

            var needsSave = false
            var historyDict: [String: (page: Int, date: Int)] = [:]

            let inLibrary = self.hasLibraryManga(mangaId: mangaId, context: context)

            for history in objects {
                // remove duplicate read history objects for the same chapter
                if historyDict[history.chapterId] != nil {
                    needsSave = true
                    context.delete(history)
                    continue
                }
                // link history to chapter if link is missing
                if inLibrary && history.chapter == nil {
                    if let chapter = self.getChapter(
                        chapterId: .init(
                            sourceKey: mangaId.sourceKey,
                            mangaKey: mangaId.mangaKey,
                            chapterKey: history.chapterId
                        ),
                        context: context
                    ) {
                        history.chapter = chapter
                        needsSave = true
                    }
                }
                historyDict[history.chapterId] = (
                    history.completed ? -1 : Int(history.progress),
                    Int(history.dateRead?.timeIntervalSince1970 ?? -1)
                )
            }

            if needsSave {
                try? context.save()
            }

            return historyDict
        }
    }

    @MainActor
    func getProgress(chapterId: ChapterIdentifier) -> (completed: Bool, progress: Int?) {
        getProgress(chapterId: chapterId, context: context)
    }

    /// Get current completion status and page progress for chapter
    func getProgress(
        chapterId: ChapterIdentifier,
        context: NSManagedObjectContext
    ) -> (completed: Bool, progress: Int?) {
        let historyObject = getHistory(chapterId: chapterId, context: context)
        return (historyObject?.completed ?? false, (historyObject?.progress).flatMap(Int.init))
    }

    /// Set page progress for a chapter and creates a history object if it doesn't already exist.
    @discardableResult
    func setProgress(
        _ progress: Int,
        chapterId: ChapterIdentifier,
        totalPages: Int? = nil,
        scrollPosition: Double? = nil,
        dateRead: Date? = nil,
        completed: Bool? = nil,
        context: NSManagedObjectContext
    ) -> HistoryObject {
        let historyObject = self.getOrCreateHistory(
            chapterId: chapterId,
            context: context
        )
        historyObject.progress = Int16(progress)
        historyObject.dateRead = dateRead ?? Date()
        if let totalPages {
            historyObject.total = Int16(totalPages)
        }
        if let scrollPosition {
            historyObject.scrollPosition = NSNumber(value: scrollPosition)
        }
        if let completed {
            historyObject.completed = completed
        }
        return historyObject
    }

    /// Marks chapters as completed.
    @discardableResult
    func setCompleted(
        chapters: [Chapter],
        date: Date = Date(),
        context: NSManagedObjectContext
    ) -> Bool {
        setCompleted(
            chapterIds: chapters.map {
                ChapterIdentifier(sourceKey: $0.sourceId, mangaKey: $0.mangaId, chapterKey: $0.id)
            },
            date: date,
            context: context
        )
    }

    @discardableResult
    func setCompleted(
        chapterIds: [ChapterIdentifier],
        chapterMetadata: [ChapterIdentifier: AidokuRunner.Chapter] = [:],
        date: Date = Date(),
        context: NSManagedObjectContext
    ) -> Bool {
        guard !chapterIds.isEmpty else { return false }

        // fetch the existing history up front, so marking n chapters read doesn't take n requests
        var historyObjects: [ChapterIdentifier: HistoryObject] = [:]
        var chapterObjects: [ChapterIdentifier: ChapterObject] = [:]
        let groups = Dictionary(grouping: chapterIds) {
            MangaIdentifier(sourceKey: $0.sourceKey, mangaKey: $0.mangaKey)
        }
        for (key, groupChapterIds) in groups {
            let keys = groupChapterIds.map { $0.chapterKey }
            for object in getHistory(
                sourceId: key.sourceKey,
                mangaId: key.mangaKey,
                chapterIds: keys,
                context: context
            ) {
                let id = ChapterIdentifier(
                    sourceKey: key.sourceKey,
                    mangaKey: key.mangaKey,
                    chapterKey: object.chapterId
                )
                // duplicate history objects for a chapter: keep the first
                if historyObjects[id] == nil {
                    historyObjects[id] = object
                }
            }
            // chapter objects are only needed to link history that doesn't exist yet
            let missingKeys = groupChapterIds
                .filter { historyObjects[$0] == nil }
                .map { $0.chapterKey }
            for (chapterKey, object) in getChapters(
                sourceId: key.sourceKey,
                mangaId: key.mangaKey,
                chapterIds: missingKeys,
                context: context
            ) {
                chapterObjects[ChapterIdentifier(
                    sourceKey: key.sourceKey,
                    mangaKey: key.mangaKey,
                    chapterKey: chapterKey
                )] = object
            }
        }

        var success = false
        for chapterId in chapterIds {
            let historyObject: HistoryObject
            if let object = historyObjects[chapterId] {
                historyObject = object
            } else {
                historyObject = HistoryObject(context: context)
                historyObject.sourceId = chapterId.sourceKey
                historyObject.mangaId = chapterId.mangaKey
                historyObject.chapterId = chapterId.chapterKey
                historyObject.chapter = chapterObjects[chapterId]
                // track it, so duplicate ids don't create duplicate history
                historyObjects[chapterId] = historyObject
            }
            if let chapter = chapterMetadata[chapterId] {
                historyObject.loadChapterMetadata(from: chapter)
            }
            guard !historyObject.completed else { continue }
            historyObject.completed = true
            historyObject.dateRead = date
            success = true
        }
        return success
    }

    /// Check if history exists for a manga.
    func getEarliestReadDate(mangaId: MangaIdentifier, context: NSManagedObjectContext) -> Date? {
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ AND completed == true",
            mangaId.mangaKey, mangaId.sourceKey
        )
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "dateRead", ascending: true)]
        let result = (try? context.fetch(request))?.first
        return result?.dateRead
    }

    /// Get the highest read number (chapter or volume) based on forced mode for a manga.
    func getHighestReadNumber(
        mangaId: MangaIdentifier,
        context: NSManagedObjectContext
    ) -> Float? {
        let request = HistoryObject.fetchRequest()
        request.predicate = NSPredicate(
            format: "mangaId == %@ AND sourceId == %@ AND completed == true",
            mangaId.mangaKey, mangaId.sourceKey
        )
        request.fetchLimit = 1

        let key = "Manga.chapterDisplayMode.\(mangaId.description)"
        let displayMode: ChapterTitleDisplayMode = if mangaId.sourceKey.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
            UserDefaults.standard.bool(forKey: "\(mangaId.sourceKey).useChapters") ? .chapter : .volume
        } else {
            .init(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .default
        }
        switch displayMode {
            case .default:
                // Default mode: return highest chapter number
                request.sortDescriptors = [NSSortDescriptor(key: "chapter.chapter", ascending: false)]
                let result = (try? context.fetch(request))?.first
                return result?.chapter?.chapter?.floatValue
            case .chapter:
                // Forced chapter mode: return highest chapter number, fallback to volume as chapter
                request.sortDescriptors = [NSSortDescriptor(key: "chapter.chapter", ascending: false)]
                let result = (try? context.fetch(request))?.first
                if let chapter = result?.chapter?.chapter?.floatValue, chapter > 0 {
                    return chapter
                } else if let volume = result?.chapter?.volume?.floatValue {
                    return volume // Use volume number as chapter
                }
            case .volume:
                // Forced volume mode: return highest volume number, fallback to chapter as volume
                request.sortDescriptors = [NSSortDescriptor(key: "chapter.volume", ascending: false)]
                let result = (try? context.fetch(request))?.first
                if let volume = result?.chapter?.volume?.floatValue, volume > 0 {
                    return volume
                } else if let chapter = result?.chapter?.chapter?.floatValue {
                    return chapter // Use chapter number as volume
                }
        }

        return nil
    }
}
