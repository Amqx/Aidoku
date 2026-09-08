//
//  LibraryRefreshBackgroundAssertion.swift
//  Aidoku
//
//  Created by Amqx on 9/7/26.
//

import UIKit

/// Releases UIKit's background time on expiration even if source work is still blocked.
@MainActor
final class LibraryRefreshBackgroundAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(onExpiration: @escaping @Sendable () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Library Refresh") { [self] in
            end()
            onExpiration()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        let identifier = self.identifier
        self.identifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }
}
