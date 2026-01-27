import Foundation
import Logging

// MARK: - Correlation ID

/// A unique identifier for correlating log entries across a request lifecycle.
///
/// Correlation IDs help trace requests through the system, making it easier
/// to debug issues and understand request flow.
///
/// ## Example
///
/// ```swift
/// let correlationID = CorrelationID()
/// logger.info("Processing request", metadata: correlationID.metadata)
/// ```
public struct CorrelationID: Sendable, Hashable, CustomStringConvertible {
    /// The unique identifier string.
    public let value: String

    /// Creates a new correlation ID with a random UUID.
    public init() {
        self.value = UUID().uuidString.lowercased()
    }

    /// Creates a correlation ID from an existing string value.
    ///
    /// - Parameter value: The correlation ID string, typically from an incoming request header.
    public init(_ value: String) {
        self.value = value
    }

    /// Returns the correlation ID as logger metadata.
    public var metadata: Logger.Metadata {
        ["correlation_id": .string(value)]
    }

    public var description: String {
        value
    }
}

// MARK: - Structured Logger

/// A structured logger that automatically includes correlation IDs and context.
///
/// Wraps the standard swift-log Logger with additional context management
/// for request tracking and structured logging.
///
/// ## Example
///
/// ```swift
/// let logger = StructuredLogger(label: "arc.server")
/// logger.withCorrelationID(correlationID).info("Request received")
/// ```
public struct StructuredLogger: Sendable {
    private let logger: Logger
    private let correlationID: CorrelationID?
    private let additionalMetadata: Logger.Metadata

    /// Creates a new structured logger.
    ///
    /// - Parameters:
    ///   - label: The logger label (e.g., "arc.server").
    ///   - correlationID: Optional correlation ID for request tracking.
    ///   - metadata: Additional metadata to include in all log entries.
    public init(
        label: String,
        correlationID: CorrelationID? = nil,
        metadata: Logger.Metadata = [:]
    ) {
        self.logger = Logger(label: label)
        self.correlationID = correlationID
        self.additionalMetadata = metadata
    }

    /// Creates a structured logger from an existing Logger.
    ///
    /// - Parameters:
    ///   - logger: The underlying Logger instance.
    ///   - correlationID: Optional correlation ID for request tracking.
    ///   - metadata: Additional metadata to include in all log entries.
    public init(
        logger: Logger,
        correlationID: CorrelationID? = nil,
        metadata: Logger.Metadata = [:]
    ) {
        self.logger = logger
        self.correlationID = correlationID
        self.additionalMetadata = metadata
    }

    /// Returns a new logger with the specified correlation ID.
    ///
    /// - Parameter correlationID: The correlation ID to include in logs.
    /// - Returns: A new StructuredLogger with the correlation ID set.
    public func withCorrelationID(_ correlationID: CorrelationID) -> StructuredLogger {
        StructuredLogger(
            logger: logger,
            correlationID: correlationID,
            metadata: additionalMetadata
        )
    }

    /// Returns a new logger with additional metadata.
    ///
    /// - Parameter metadata: Additional metadata to merge.
    /// - Returns: A new StructuredLogger with the merged metadata.
    public func with(metadata: Logger.Metadata) -> StructuredLogger {
        var merged = additionalMetadata
        for (key, value) in metadata {
            merged[key] = value
        }
        return StructuredLogger(
            logger: logger,
            correlationID: correlationID,
            metadata: merged
        )
    }

    // MARK: - Logging Methods

    private func mergedMetadata(_ metadata: Logger.Metadata?) -> Logger.Metadata {
        var result = additionalMetadata
        if let correlationID = correlationID {
            result["correlation_id"] = .string(correlationID.value)
        }
        if let metadata = metadata {
            for (key, value) in metadata {
                result[key] = value
            }
        }
        return result
    }

    public func trace(
        _ message: @autoclosure () -> Logger.Message,
        metadata: Logger.Metadata? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.trace(message(), metadata: mergedMetadata(metadata), file: file, function: function, line: line)
    }

    public func debug(
        _ message: @autoclosure () -> Logger.Message,
        metadata: Logger.Metadata? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.debug(message(), metadata: mergedMetadata(metadata), file: file, function: function, line: line)
    }

    public func info(
        _ message: @autoclosure () -> Logger.Message,
        metadata: Logger.Metadata? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.info(message(), metadata: mergedMetadata(metadata), file: file, function: function, line: line)
    }

    public func notice(
        _ message: @autoclosure () -> Logger.Message,
        metadata: Logger.Metadata? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.notice(message(), metadata: mergedMetadata(metadata), file: file, function: function, line: line)
    }

    public func warning(
        _ message: @autoclosure () -> Logger.Message,
        metadata: Logger.Metadata? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.warning(message(), metadata: mergedMetadata(metadata), file: file, function: function, line: line)
    }

    public func error(
        _ message: @autoclosure () -> Logger.Message,
        metadata: Logger.Metadata? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.error(message(), metadata: mergedMetadata(metadata), file: file, function: function, line: line)
    }

    public func critical(
        _ message: @autoclosure () -> Logger.Message,
        metadata: Logger.Metadata? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.critical(message(), metadata: mergedMetadata(metadata), file: file, function: function, line: line)
    }
}

// MARK: - Log Entry

/// A structured log entry for persistence and analysis.
public struct LogEntry: Codable, Sendable {
    /// Timestamp of the log entry.
    public let timestamp: Date

    /// Log level.
    public let level: String

    /// Log message.
    public let message: String

    /// Correlation ID for request tracking.
    public let correlationID: String?

    /// Additional metadata.
    public let metadata: [String: String]

    /// Source file.
    public let file: String?

    /// Source function.
    public let function: String?

    /// Source line number.
    public let line: UInt?

    public init(
        timestamp: Date = Date(),
        level: String,
        message: String,
        correlationID: String? = nil,
        metadata: [String: String] = [:],
        file: String? = nil,
        function: String? = nil,
        line: UInt? = nil
    ) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.correlationID = correlationID
        self.metadata = metadata
        self.file = file
        self.function = function
        self.line = line
    }

    /// Returns a JSON representation of the log entry.
    public func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Request Context

/// Context information for an HTTP request.
///
/// Contains all the metadata needed to trace and log a request.
public struct RequestContext: Sendable {
    /// Unique correlation ID for the request.
    public let correlationID: CorrelationID

    /// Request start time.
    public let startTime: Date

    /// HTTP method.
    public let method: String

    /// Request path.
    public let path: String

    /// Request host.
    public let host: String?

    /// Client IP address.
    public let clientIP: String?

    /// User agent string.
    public let userAgent: String?

    /// Creates a new request context.
    public init(
        correlationID: CorrelationID = CorrelationID(),
        startTime: Date = Date(),
        method: String,
        path: String,
        host: String? = nil,
        clientIP: String? = nil,
        userAgent: String? = nil
    ) {
        self.correlationID = correlationID
        self.startTime = startTime
        self.method = method
        self.path = path
        self.host = host
        self.clientIP = clientIP
        self.userAgent = userAgent
    }

    /// Returns the elapsed time since the request started.
    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    /// Returns the elapsed time in milliseconds.
    public var elapsedMs: Double {
        elapsed * 1000
    }

    /// Returns logger metadata for this request context.
    public var metadata: Logger.Metadata {
        var meta: Logger.Metadata = [
            "correlation_id": .string(correlationID.value),
            "method": .string(method),
            "path": .string(path),
        ]
        if let host = host {
            meta["host"] = .string(host)
        }
        if let clientIP = clientIP {
            meta["client_ip"] = .string(clientIP)
        }
        if let userAgent = userAgent {
            meta["user_agent"] = .string(userAgent)
        }
        return meta
    }
}
