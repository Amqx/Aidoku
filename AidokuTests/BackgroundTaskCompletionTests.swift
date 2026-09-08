//
//  BackgroundTaskCompletionTests.swift
//  Aidoku
//
//  Created by Amqx on 9/7/26.
//

@testable import Aidoku
import Foundation
import Testing

struct BackgroundTaskCompletionTests {
    @Test func expirationCompletesBeforeWorkerReturns() {
        let results = Results()
        let completion = BackgroundTaskCompletion { results.append($0) }

        // Expiration must report failure immediately, without needing the worker's result.
        completion.finish(success: false)
        #expect(results.values == [false])

        // A non-cooperative worker eventually returns after its OS task has ended.
        completion.finish(success: true)
        #expect(results.values == [false])
    }

    @Test func expirationAfterNormalCompletionDoesNotCompleteAgain() {
        let results = Results()
        let completion = BackgroundTaskCompletion { results.append($0) }

        completion.finish(success: true)
        completion.finish(success: false)
        #expect(results.values == [true])
    }

    @Test func concurrentCompletionAndExpiration() {
        let results = Results()
        let completion = BackgroundTaskCompletion { results.append($0) }

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            completion.finish(success: index.isMultiple(of: 2))
        }
        #expect(results.values.count == 1)
    }

    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Bool] = []

        var values: [Bool] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ value: Bool) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(value)
        }
    }
}
