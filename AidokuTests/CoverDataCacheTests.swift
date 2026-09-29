@testable import Aidoku
import Foundation
import Nuke
import Testing
import UIKit

struct CoverDataCacheTests {
    @MainActor
    @Test func coverDataStaysSeparateAndClearRemovesBothCaches() async throws {
        let pipeline = ImagePipeline.shared
        let readerCache = try #require(pipeline.configuration.dataCache as? DataCache)
        let coverCache = try #require(CoverDataCache.cache)
        let identifier = UUID().uuidString
        let cover = ImageRequest(
            url: URL(string: "https://example.invalid/\(identifier)/cover.jpg"),
            userInfo: [.isMangaCover: true]
        )
        let reader = ImageRequest(url: URL(string: "https://example.invalid/\(identifier)/page.jpg"))
        let coverData = try #require(UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }.pngData())
        let readerData = Data("page".utf8)

        pipeline.cache.storeCachedData(coverData, for: cover)
        pipeline.cache.storeCachedData(readerData, for: reader)
        coverCache.flush()
        readerCache.flush()

        let coverKey = pipeline.cache.makeDataCacheKey(for: cover)
        let readerKey = pipeline.cache.makeDataCacheKey(for: reader)
        #expect(coverCache.cachedData(for: coverKey) == coverData)
        #expect(readerCache.cachedData(for: coverKey) == nil)
        #expect(readerCache.cachedData(for: readerKey) == readerData)
        #expect(coverCache.cachedData(for: readerKey) == nil)

        pipeline.configuration.imageCache?.removeAll()
        let diskImage = try await pipeline.image(for: cover)
        #expect(diskImage.size == CGSize(width: 1, height: 1))

        readerCache.removeAll()
        readerCache.flush()
        #expect(pipeline.cache.cachedData(for: cover) == coverData)

        pipeline.cache.storeCachedData(readerData, for: reader)
        await SettingsView().clearNetworkCache()
        readerCache.flush()
        coverCache.flush()
        #expect(pipeline.cache.cachedData(for: reader) == nil)
        #expect(pipeline.cache.cachedData(for: cover) == nil)
    }
}
