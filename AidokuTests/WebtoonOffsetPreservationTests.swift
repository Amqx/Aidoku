//
//  WebtoonOffsetPreservationTests.swift
//  Aidoku
//
// Created by Amqx on 9/7/26
//

import Testing
import UIKit
import AsyncDisplayKit
@testable import Aidoku

@MainActor
@Suite struct WebtoonOffsetPreservationTests {
    @Test("Texture node identity and the overlay offset survive chapter insertion and removal")
    func textureIntegration() async {
        let layout = VerticalContentOffsetPreservingLayout()
        let zoomView = ZoomableCollectionView(layout: layout)
        let dataSource = TexturePageDataSource()
        let collectionNode = zoomView.collectionNode
        collectionNode.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        zoomView.scrollNode.frame = collectionNode.frame
        collectionNode.dataSource = dataSource
        // Texture does not invoke the reload completion until its view has loaded.
        _ = collectionNode.view
        await collectionNode.reloadData()
        collectionNode.view.layoutIfNeeded()
        layout.prepare()
        zoomView.adjustContentSize()
        zoomView.scrollNode.view.contentOffset.y = 1100

        layout.preserveOffsetAcrossChangeAbove()
        dataSource.sections[0][0].height += 100
        dataSource.sections[0][2].height += 900
        layout.prepare()
        #expect(collectionNode.contentOffset.y == 1200)
        #expect(zoomView.scrollNode.view.contentOffset.y == 1200)
        #expect(zoomView.scrollNode.view.contentSize.height == 4200)

        layout.preserveOffsetAcrossChangeAbove()
        dataSource.sections.insert([FixedHeightNode(height: 700)], at: 0)
        await collectionNode.performBatch(animated: false) {
            collectionNode.insertSections(IndexSet(integer: 0))
        }
        collectionNode.view.layoutIfNeeded()
        #expect(collectionNode.contentOffset.y == 1900)
        #expect(zoomView.scrollNode.view.contentOffset.y == 1900)

        layout.preserveOffsetAcrossChangeAbove()
        dataSource.sections.removeFirst()
        await collectionNode.performBatch(animated: false) {
            collectionNode.deleteSections(IndexSet(integer: 0))
        }
        collectionNode.view.layoutIfNeeded()
        #expect(collectionNode.contentOffset.y == 1200)
        #expect(zoomView.scrollNode.view.contentOffset.y == 1200)
    }

    @Test("Only growth above the visible page changes the offset", arguments: [0, 900])
    func simultaneousHeightChanges(growthBelow: CGFloat) throws {
        let fixture = LayoutFixture()
        let page = IndexPath(item: 1, section: 0)
        let oldFrame = try #require(fixture.layout.layoutAttributesForItem(at: page)?.frame)
        let oldScreenY = oldFrame.minY - fixture.collectionView.contentOffset.y

        fixture.layout.preserveOffsetAcrossChangeAbove()
        fixture.layout.sections[0][0].height += 100
        fixture.layout.sections[0][2].height += growthBelow
        fixture.layout.prepare()

        let newFrame = try #require(fixture.layout.layoutAttributesForItem(at: page)?.frame)
        let offset = fixture.collectionView.contentOffset.y
        #expect(offset == 1200)
        #expect(newFrame.minY - offset == oldScreenY)
        #expect(newFrame.contains(CGPoint(x: 200, y: offset + 400)))
    }

    @Test("Repeated transitions do not count growth below the viewport")
    func unchangedPageAbove() {
        let fixture = LayoutFixture()
        fixture.layout.preserveOffsetAcrossChangeAbove()
        fixture.layout.preserveOffsetAcrossChangeAbove()
        fixture.layout.sections[0][2].height += 900
        fixture.layout.prepare()
        #expect(fixture.collectionView.contentOffset.y == 1100)
    }

    @Test("Resizing a partly visible page preserves the distance from its top", arguments: [600, 1600])
    func partlyVisiblePage(height: CGFloat) {
        let fixture = LayoutFixture()
        fixture.layout.preserveOffsetAcrossChangeAbove()
        fixture.layout.sections[0][1].height = height
        fixture.layout.prepare()
        #expect(fixture.collectionView.contentOffset.y == 1100)
    }

    @Test("Scrolling before layout uses the page visible at layout time")
    func scrollingBeforeLayout() {
        let fixture = LayoutFixture()
        fixture.layout.preserveOffsetAcrossChangeAbove()
        fixture.collectionView.contentOffset.y = 2100
        fixture.layout.sections[0][1].height += 100
        fixture.layout.sections[0][3].height += 900
        fixture.layout.prepare()
        #expect(fixture.collectionView.contentOffset.y == 2200)
    }

    @Test("Preservation respects zoom and leaves horizontal panning unchanged")
    func zoomedPage() {
        let fixture = LayoutFixture()
        fixture.layout.setScale(2)
        fixture.layout.prepare()
        fixture.collectionView.contentOffset = CGPoint(x: 75, y: 2200)
        fixture.layout.preserveOffsetAcrossChangeAbove()
        fixture.layout.sections[0][0].height += 100
        fixture.layout.sections[0][2].height += 900
        fixture.layout.prepare()
        #expect(fixture.collectionView.contentOffset == CGPoint(x: 75, y: 2400))
    }

    @Test("Chapter prepend and removal preserve identity across section changes")
    func chapterWindowChanges() throws {
        let fixture = LayoutFixture()
        fixture.layout.preserveOffsetAcrossChangeAbove()
        fixture.layout.sections.insert([LayoutPage(id: 10, height: 700)], at: 0)
        // A loading image below the visible page must not contribute to the prepend.
        fixture.layout.sections[1][2].height += 900
        fixture.reload()
        #expect(fixture.collectionView.contentOffset.y == 1800)
        let insertedFrame = try #require(fixture.layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 1))?.frame)
        #expect(insertedFrame.minY - fixture.collectionView.contentOffset.y == -100)

        fixture.layout.preserveOffsetAcrossChangeAbove()
        fixture.layout.sections.removeFirst()
        fixture.layout.sections[0][3].height += 300
        fixture.reload()
        #expect(fixture.collectionView.contentOffset.y == 1100)
        let trimmedFrame = try #require(fixture.layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))?.frame)
        #expect(trimmedFrame.minY - fixture.collectionView.contentOffset.y == -100)
    }

    @Test("Offset notification is synchronous and preservation is consumed once")
    func offsetNotification() {
        let fixture = LayoutFixture()
        var offsets: [CGPoint] = []
        fixture.layout.onOffsetPreserved = { offset in
            #expect(fixture.collectionView.contentOffset == offset)
            #expect(fixture.layout.collectionViewContentSize.height == 4200)
            offsets.append(offset)
        }
        fixture.layout.preserveOffsetAcrossChangeAbove()
        fixture.layout.sections[0][0].height += 100
        fixture.layout.sections[0][2].height += 900
        fixture.layout.prepare()
        fixture.layout.prepare()
        #expect(offsets == [CGPoint(x: 0, y: 1200)])
        fixture.layout.onOffsetPreserved = nil
    }
}

private final class FixedHeightNode: ASCellNode, HeightQueryable {
    var height: CGFloat

    init(height: CGFloat) {
        self.height = height
        super.init()
        style.preferredSize = CGSize(width: 400, height: height)
    }

    func getHeight(for size: CGSize) -> CGFloat {
        height
    }
}

@MainActor
private final class TexturePageDataSource: NSObject, ASCollectionDataSource {
    var sections = [[1000, 1000, 600, 600].map { FixedHeightNode(height: CGFloat($0)) }]

    func numberOfSections(in collectionNode: ASCollectionNode) -> Int {
        sections.count
    }

    func collectionNode(_ collectionNode: ASCollectionNode, numberOfItemsInSection section: Int) -> Int {
        sections[section].count
    }

    func collectionNode(_ collectionNode: ASCollectionNode, nodeBlockForItemAt indexPath: IndexPath) -> ASCellNodeBlock {
        let node = sections[indexPath.section][indexPath.item]
        return { node }
    }
}

private struct LayoutPage {
    let id: Int
    var height: CGFloat
}

@MainActor
private final class ControlledHeightLayout: VerticalContentOffsetPreservingLayout {
    var sections = [[
        LayoutPage(id: 0, height: 1000),
        LayoutPage(id: 1, height: 1000),
        LayoutPage(id: 2, height: 600),
        LayoutPage(id: 3, height: 600)
    ]]

    override func getHeight(for indexPath: IndexPath) -> CGFloat {
        sections[indexPath.section][indexPath.item].height
    }

    override func itemIdentifier(for indexPath: IndexPath) -> AnyHashable? {
        sections[indexPath.section][indexPath.item].id
    }
}

@MainActor
private final class LayoutFixture: NSObject, UICollectionViewDataSource {
    let layout = ControlledHeightLayout()
    let collectionView: UICollectionView

    override init() {
        collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            collectionViewLayout: layout
        )
        super.init()
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "page")
        collectionView.dataSource = self
        reload()
        collectionView.contentOffset = CGPoint(x: 0, y: 1100)
    }

    func reload() {
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        layout.prepare()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        layout.sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        layout.sections[section].count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath)
    }
}
