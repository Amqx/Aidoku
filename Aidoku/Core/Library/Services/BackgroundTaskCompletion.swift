//
//  BackgroundTaskCompletion.swift
//  Aidoku
//
//  Created by Amqx on 9/7/26.
//

import Foundation

/// Arbitrates normal completion and expiration without waiting for the refresh worker.
final class BackgroundTaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Bool) -> Void)?

    init(completion: @escaping @Sendable (Bool) -> Void) {
        self.completion = completion
    }

    func finish(success: Bool) {
        lock.lock()
        let completion = self.completion
        self.completion = nil
        lock.unlock()

        completion?(success)
    }
}
