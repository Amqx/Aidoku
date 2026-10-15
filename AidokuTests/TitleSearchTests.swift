//
//  TitleSearchTests.swift
//  Aidoku
//
//  Created by Amqx on 10/14/26.
//

import Testing
import UIKit
@testable import Aidoku

@MainActor
@Suite struct TitleSearchTests {
    // the search tab's stack used to be popped while offscreen, which detached the search bar's
    // scope container and made UIKit throw when the tab was shown (the host crashes on regression)
    @Test("Searching from another tab with a pushed search stack shows the search root")
    func searchWithPushedSearchStack() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let tabs = TabBarController()
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let searchTab = try #require(tabs.tabs.last)
        tabs.selectedTab = searchTab
        await settle()
        let searchNavigation = try #require(searchTab.viewController as? UINavigationController)
        searchNavigation.pushViewController(UIViewController(), animated: false)
        await settle()
        tabs.selectedTab = tabs.tabs.first
        await settle()

        tabs.search(for: "test")
        await settle()
        window.layoutIfNeeded()

        #expect(tabs.selectedTab === searchTab)
        #expect(searchNavigation.viewControllers.count == 1)
        #expect(searchNavigation.topViewController is SearchViewController)
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
}
