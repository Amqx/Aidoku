//
//  MetadataCacheTests.swift
//  AidokuTests
//
//  Created by Amqx on 9/13/26.
//

import AidokuRunner
import CoreData
import Testing
@testable import Aidoku

@MainActor
struct MetadataCacheTests {
    private let manager = CoreDataManager.shared

    @Test func fullMetadataSurvivesReloadWithoutLibraryMembership() throws {
        let fixture = try StoreFixture()
        let manga = makeManga()
        manager.cacheMetadata(manga: manga, mangaId: manga.identifier, context: fixture.context)
        try fixture.context.save()
        fixture.context.reset()

        let object = try #require(manager.getManga(mangaId: manga.identifier, context: fixture.context))
        var restored = object.toNewManga()
        restored.chapters = manager.getChapters(mangaId: manga.identifier, context: fixture.context).map { $0.toNewChapter() }
        #expect(restored == manga)
        #expect(object.libraryObject == nil)
        #expect(manager.getLibraryManga(context: fixture.context).isEmpty)
        #expect(object.objectID.persistentStore?.configurationName == "Cloud")
        let chapter = try #require(manager.getChapter(chapterId: chapterId(manga), context: fixture.context))
        #expect(chapter.objectID.persistentStore?.configurationName == "Cloud")

        let reader = ReaderViewController(source: nil, manga: restored, chapter: try #require(restored.chapters?.first))
        #expect(reader.defaultReadingMode == .webtoon)
    }

    @Test func libraryMembershipDoesNotDuplicateOrDeleteMetadata() throws {
        let fixture = try StoreFixture()
        let manga = makeManga()
        manager.cacheMetadata(manga: manga, mangaId: manga.identifier, context: fixture.context)
        let original = try #require(manager.getManga(mangaId: manga.identifier, context: fixture.context))
        manager.addToLibrary(manga: manga, chapters: manga.chapters ?? [], context: fixture.context)
        let chapter = try #require(manager.getChapter(chapterId: chapterId(manga), context: fixture.context))
        manager.createMangaUpdate(mangaId: manga.identifier, chapterObject: chapter, context: fixture.context)
        _ = manager.getOrCreateHistory(chapterId: chapterId(manga), context: fixture.context)
        try fixture.context.save()
        #expect(manager.getManga(context: fixture.context).count == 1)
        #expect(manager.hasLibraryManga(mangaId: manga.identifier, context: fixture.context))

        manager.removeFromLibrary(ids: [manga.identifier], context: fixture.context)
        try fixture.context.save()
        #expect(!manager.hasLibraryManga(mangaId: manga.identifier, context: fixture.context))
        #expect(manager.getManga(mangaId: manga.identifier, context: fixture.context) === original)
        #expect(manager.getChapters(mangaId: manga.identifier, context: fixture.context).count == 2)
        #expect(manager.getUpdates(context: fixture.context).isEmpty)
    }

    @Test func removingUnreadLibraryMangaPrunesMetadata() throws {
        let fixture = try StoreFixture()
        let manga = makeManga()
        manager.addToLibrary(manga: manga, chapters: manga.chapters ?? [], context: fixture.context)
        try fixture.context.save()
        manager.removeFromLibrary(ids: [manga.identifier], context: fixture.context)
        try fixture.context.save()
        fixture.context.reset()
        #expect(manager.getManga(mangaId: manga.identifier, context: fixture.context) == nil)
        #expect(manager.getChapters(mangaId: manga.identifier, context: fixture.context).isEmpty)
    }

    @Test func readerStubDoesNotPreventFullMetadataCaching() throws {
        let fixture = try StoreFixture()
        let manga = makeManga()
        let stub = AidokuRunner.Manga(sourceKey: manga.sourceKey, key: manga.key, title: "")
        manager.cacheMetadataIfMissing(manga: stub, context: fixture.context)
        #expect(manager.getManga(mangaId: manga.identifier, context: fixture.context) == nil)
        manager.cacheMetadataIfMissing(manga: manga, context: fixture.context)
        try fixture.context.save()
        #expect(manager.getManga(mangaId: manga.identifier, context: fixture.context)?.title == manga.title)
    }

    @Test func emptyHistoryResponsePreservesChaptersAndRefreshesDetails() throws {
        let fixture = try StoreFixture()
        var manga = makeManga()
        manager.cacheMetadata(manga: manga, mangaId: manga.identifier, context: fixture.context)
        _ = manager.getOrCreateHistory(chapterId: chapterId(manga), context: fixture.context)
        try fixture.context.save()
        manga.title = "Updated title"
        manga.chapters = []
        manager.cacheHistoryData(
            manga: manga, mangaId: manga.identifier, mangaDetails: manga,
            chapterIds: ["one"], context: fixture.context
        )
        try fixture.context.save()
        fixture.context.reset()
        #expect(manager.getManga(mangaId: manga.identifier, context: fixture.context)?.title == "Updated title")
        #expect(manager.getChapters(mangaId: manga.identifier, context: fixture.context).count == 2)
    }

    @Test func restoreHistoryClearingPreservesUnattachedMetadata() throws {
        let fixture = try StoreFixture()
        let manga = makeManga()
        manager.cacheMetadata(manga: manga, mangaId: manga.identifier, context: fixture.context)
        _ = manager.getOrCreateHistory(chapterId: chapterId(manga), context: fixture.context)
        try fixture.context.save()
        manager.clearHistory(context: fixture.context, preservingMetadata: true)
        fixture.context.reset()
        #expect(manager.getHistory(context: fixture.context).isEmpty)
        #expect(manager.getManga(mangaId: manga.identifier, context: fixture.context) != nil)
        #expect(manager.getChapters(mangaId: manga.identifier, context: fixture.context).count == 2)
    }

    @Test func historyFetchStoresUnreadChaptersAndRetiresLegacyCache() throws {
        let fixture = try StoreFixture()
        let manga = makeManga()
        let legacy = CachedMangaObject(context: fixture.context)
        legacy.load(from: manga)
        let history = manager.getOrCreateHistory(chapterId: chapterId(manga), context: fixture.context)
        history.progress = 4
        try fixture.context.save()

        manager.cacheHistoryData(
            manga: manga, mangaId: manga.identifier, mangaDetails: manga,
            chapterIds: ["one"], context: fixture.context
        )
        try fixture.context.save()
        #expect(manager.getChapters(mangaId: manga.identifier, context: fixture.context).count == 2)
        #expect(history.progress == 4)
        #expect(history.chapter?.toNewChapter() == manga.chapters?.first)
        #expect(manager.getCachedManga(mangaId: manga.identifier, context: fixture.context) == nil)

        manager.removeHistory(mangaId: manga.identifier, context: fixture.context)
        try fixture.context.save()
        manager.cacheHistoryData(
            manga: manga, mangaId: manga.identifier, mangaDetails: manga,
            chapterIds: ["one"], context: fixture.context
        )
        #expect(manager.getManga(mangaId: manga.identifier, context: fixture.context) == nil)
    }

    @Test func cloudDeduplicationKeepsLibraryMembership() throws {
        let fixture = try StoreFixture()
        let manga = makeManga()
        manager.cacheMetadata(manga: manga, mangaId: manga.identifier, context: fixture.context)
        let cached = try #require(manager.getManga(mangaId: manga.identifier, context: fixture.context))
        let bookmarked = MangaObject(context: fixture.context)
        bookmarked.load(from: manga)
        bookmarked.title = "Edited title"
        let library = LibraryMangaObject(context: fixture.context)
        library.manga = bookmarked
        try fixture.context.save()

        manager.deduplicate(objectId: cached.objectID, context: fixture.context)
        try fixture.context.save()
        #expect(manager.getManga(context: fixture.context).count == 1)
        #expect(manager.getLibraryManga(context: fixture.context).first?.manga === bookmarked)
        #expect(bookmarked.title == "Edited title")
        #expect(bookmarked.chapters?.count == 2)
    }

    @Test func removingOneHistoryChapterKeepsTheFullChapterList() throws {
        let fixture = try StoreFixture()
        let manga = makeManga()
        manager.cacheMetadata(manga: manga, mangaId: manga.identifier, context: fixture.context)
        let first = manager.getOrCreateHistory(chapterId: chapterId(manga), context: fixture.context)
        _ = manager.getOrCreateHistory(chapterId: chapterId(manga, key: "two"), context: fixture.context)
        try fixture.context.save()
        fixture.context.delete(first)
        manager.pruneHistoryCache(mangaId: manga.identifier, removedChapterIds: ["one"], context: fixture.context)
        try fixture.context.save()
        #expect(manager.getChapters(mangaId: manga.identifier, context: fixture.context).count == 2)
    }

    @Test(arguments: [false, true])
    func clearingHistoryPreservesLibraryAndLocalFiles(excludingLibrary: Bool) throws {
        let fixture = try StoreFixture()
        let libraryManga = makeManga(key: "library")
        let historyManga = makeManga(key: "history")
        let localManga = makeManga(key: "local")
        manager.addToLibrary(manga: libraryManga, chapters: libraryManga.chapters ?? [], context: fixture.context)
        manager.cacheMetadata(manga: historyManga, mangaId: historyManga.identifier, context: fixture.context)
        manager.cacheMetadata(manga: localManga, mangaId: localManga.identifier, context: fixture.context)
        let local = try #require(manager.getManga(mangaId: localManga.identifier, context: fixture.context))
        let file = LocalFileInfoObject(context: fixture.context)
        file.manga = local
        _ = manager.getOrCreateHistory(chapterId: chapterId(libraryManga), context: fixture.context)
        _ = manager.getOrCreateHistory(chapterId: chapterId(historyManga), context: fixture.context)
        try fixture.context.save()

        if excludingLibrary {
            manager.clearHistoryExcludingLibrary(context: fixture.context)
        } else {
            manager.clearHistory(context: fixture.context)
        }
        try fixture.context.save()
        fixture.context.reset()
        #expect(manager.getManga(mangaId: libraryManga.identifier, context: fixture.context) != nil)
        #expect(manager.getManga(mangaId: localManga.identifier, context: fixture.context) != nil)
        #expect(manager.getManga(mangaId: historyManga.identifier, context: fixture.context) == nil)
        #expect(manager.getChapters(mangaId: libraryManga.identifier, context: fixture.context).count == 2)
        #expect(manager.getChapters(mangaId: historyManga.identifier, context: fixture.context).isEmpty)
        #expect(manager.hasHistory(mangaId: libraryManga.identifier, context: fixture.context) == excludingLibrary)
    }

    private func chapterId(_ manga: AidokuRunner.Manga, key: String = "one") -> ChapterIdentifier {
        .init(sourceKey: manga.sourceKey, mangaKey: manga.key, chapterKey: key)
    }

    private func makeManga(key: String = "series") -> AidokuRunner.Manga {
        .init(
            sourceKey: "test.source", key: key, title: "Series", cover: "https://example.com/cover.png",
            artists: ["Artist"], authors: ["Author"], description: "Description",
            url: URL(string: "https://example.com/series"), tags: ["Drama"], status: .ongoing,
            contentRating: .suggestive, viewer: .webtoon, updateStrategy: .never, nextUpdateTime: 123456,
            chapters: [
                .init(
                    key: "one", title: "First", chapterNumber: 1, volumeNumber: 2,
                    dateUploaded: Date(timeIntervalSince1970: 123456), scanlators: ["Group"],
                    url: URL(string: "https://example.com/chapter"), language: "en",
                    thumbnail: "https://example.com/thumbnail.png", locked: true
                ),
                .init(key: "two", title: "Second", chapterNumber: 2, language: "en")
            ]
        )
    }
}

private final class StoreFixture {
    let context: NSManagedObjectContext
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = CoreDataManager.shared.container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        for configuration in ["Cloud", "Local"] {
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType, configurationName: configuration,
                at: directory.appendingPathComponent("\(configuration).sqlite")
            )
        }
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
