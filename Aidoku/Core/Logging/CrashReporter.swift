//
//  CrashReporter.swift
//  Aidoku
//
//  Created by Amqx on 9/2/26.
//

import Darwin
import Foundation

/// Durable logging that survives a crash.
enum CrashReporter {
    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Logs", isDirectory: true)
    static var currentSessionURL: URL { directory.appendingPathComponent("session-current.log") }
    static var previousSessionURL: URL { directory.appendingPathComponent("session-previous.log") }

    /// Whether the verbose breadcrumbs are recorded.
    static var verbose: Bool {
        UserDefaults.standard.bool(forKey: "Logs.verbose")
    }

    static func install() {
        directory.createDirectory()

        // rotate: keep the log from the session that just died
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: currentSessionURL.path) {
            try? fileManager.removeItem(at: previousSessionURL)
            try? fileManager.moveItem(at: currentSessionURL, to: previousSessionURL)
        }

        fileManager.createFile(atPath: currentSessionURL.path, contents: nil)
        logFileDescriptor = open(currentSessionURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)

        backtraceBuffer = .allocate(capacity: backtraceFrameCount)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        write("=== session start — Aidoku \(version) (\(build)) — \(ProcessInfo.processInfo.operatingSystemVersionString) ===")

        NSSetUncaughtExceptionHandler(exceptionHandler)
        for signalNumber in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(signalNumber, fatalSignalHandler)
        }
    }

    /// Records a line in the durable session log, and mirrors it into the in-app log store.
    static func breadcrumb(_ message: @autoclosure () -> String, category: String = "reader") {
        guard verbose else { return }
        let message = message()
        write("[\(category)] \(message)")
        LogManager.logger.debug("[\(category)] \(message)")
    }

    /// Records a line that should always be kept, verbose logging or not.
    static func note(_ message: String, category: String = "reader") {
        write("[\(category)] \(message)")
        LogManager.logger.info("[\(category)] \(message)")
    }

    /// Records something that looks wrong but isn't (yet) fatal. Always kept.
    static func warn(_ message: String, category: String = "reader") {
        write("[\(category)] [WARN] \(message)")
        LogManager.logger.warn("[\(category)] \(message)")
    }

    /// Resident memory footprint in megabytes, as jetsam accounts for it.
    static var memoryFootprint: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1024 / 1024
    }

    private static func write(_ line: String) {
        guard logFileDescriptor >= 0 else { return }
        let stamped = "\(timestampFormatter.string(from: Date())) \(String(format: "%6.1fMB", memoryFootprint)) \(line)\n"
        let bytes = Array(stamped.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = Darwin.write(logFileDescriptor, base, buffer.count)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

private nonisolated(unsafe) var logFileDescriptor: Int32 = -1
private let backtraceFrameCount = 128
private nonisolated(unsafe) var backtraceBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?

/// Writes a compile-time string without allocating, so it is safe from a signal handler.
private func writeStatic(_ string: StaticString) {
    guard logFileDescriptor >= 0 else { return }
    _ = write(logFileDescriptor, string.utf8Start, string.utf8CodeUnitCount)
}

/// Writes a small integer without allocating, so it is safe from a signal handler.
private func writeInt(_ value: Int32) {
    guard logFileDescriptor >= 0 else { return }
    var digits = [CChar](repeating: 0, count: 12)
    var value = value
    var index = digits.count - 1
    if value == 0 {
        digits[index] = CChar(48)
        index -= 1
    }
    while value > 0 && index >= 0 {
        digits[index] = CChar(48 + value % 10)
        value /= 10
        index -= 1
    }
    digits.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        _ = write(logFileDescriptor, base + index + 1, buffer.count - index - 1)
    }
}

private let fatalSignalHandler: @convention(c) (Int32) -> Void = { signalNumber in
    writeStatic("\n!!! fatal signal ")
    writeInt(signalNumber)
    writeStatic(" — backtrace follows\n")

    if let backtraceBuffer {
        let frames = backtrace(backtraceBuffer, Int32(backtraceFrameCount))
        backtrace_symbols_fd(backtraceBuffer, frames, logFileDescriptor)
    }
    writeStatic("!!! end of backtrace\n")

    // restore the default disposition so the OS still records a proper crash report
    signal(signalNumber, SIG_DFL)
    raise(signalNumber)
}

private let exceptionHandler: @convention(c) (NSException) -> Void = { exception in
    // this runs before abort() on the throwing thread, so allocating is still fine here
    var report = "\n!!! uncaught exception: \(exception.name.rawValue)\n"
    report += "!!! reason: \(exception.reason ?? "(none)")\n"
    if let userInfo = exception.userInfo, !userInfo.isEmpty {
        report += "!!! userInfo: \(userInfo)\n"
    }
    report += exception.callStackSymbols.joined(separator: "\n")
    report += "\n!!! end of exception\n"

    let bytes = Array(report.utf8)
    bytes.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        _ = write(logFileDescriptor, base, buffer.count)
    }
}
