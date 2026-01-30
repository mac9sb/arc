import ArcCore
import Foundation
import Logging

/// HTTP request logging middleware.
///
/// Logs incoming requests and outgoing responses with timing information,
/// correlation IDs, and structured metadata for observability.
///
/// ## Example
///
/// ```swift
/// let logger = RequestLogger(label: "arc.http")
/// let context = logger.logRequest(request)
/// // ... process request ...
/// logger.logResponse(response, context: context)
/// ```
public struct RequestLogger: Sendable {
    private let logger: StructuredLogger
    private let logLevel: Logger.Level

    /// Creates a new request logger.
    ///
    /// - Parameters:
    ///   - label: Logger label for identification.
    ///   - logLevel: Minimum level for request/response logging. Defaults to `.info`.
    init(label: String = "arc.http", logLevel: Logger.Level = .info) {
        self.logger = StructuredLogger(label: label)
        self.logLevel = logLevel
    }

    /// Logs an incoming HTTP request.
    ///
    /// Creates a request context with a new correlation ID and logs
    /// request details at the configured log level.
    ///
    /// - Parameter request: The incoming HTTP request.
    /// - Returns: A RequestContext for correlating the response log.
    func logRequest(_ request: HTTPRequest) -> RequestContext {
        // Try to extract correlation ID from request headers, or generate a new one
        let correlationID: CorrelationID
        if let existingID = request.headers["x-correlation-id"] ?? request.headers["x-request-id"] {
            correlationID = CorrelationID(existingID)
        } else {
            correlationID = CorrelationID()
        }

        let context = RequestContext(
            correlationID: correlationID,
            startTime: Date(),
            method: request.method,
            path: request.path,
            host: request.host,
            clientIP: request.headers["x-forwarded-for"] ?? request.headers["x-real-ip"],
            userAgent: request.headers["user-agent"]
        )

        logger.withCorrelationID(correlationID).info(
            "Request received",
            metadata: [
                "method": .string(request.method),
                "path": .string(request.path),
                "host": .string(request.host ?? "-"),
                "content_length": .string(request.headers["content-length"] ?? "0"),
            ]
        )

        return context
    }

    /// Logs an outgoing HTTP response.
    ///
    /// Logs response details including status code, duration, and any
    /// correlation ID from the original request.
    ///
    /// - Parameters:
    ///   - response: The HTTP response being sent.
    ///   - context: The request context from `logRequest`.
    func logResponse(_ response: HTTPResponse, context: RequestContext) {
        let durationMs = context.elapsedMs

        // Determine log level based on status code
        let statusCode = response.statusCode
        let level: Logger.Level
        if statusCode >= 500 {
            level = .error
        } else if statusCode >= 400 {
            level = .warning
        } else {
            level = logLevel
        }

        let requestLogger = logger.withCorrelationID(context.correlationID)

        switch level {
        case .error:
            requestLogger.error(
                "Response sent",
                metadata: responseMetadata(response, context: context, durationMs: durationMs)
            )
        case .warning:
            requestLogger.warning(
                "Response sent",
                metadata: responseMetadata(response, context: context, durationMs: durationMs)
            )
        default:
            requestLogger.info(
                "Response sent",
                metadata: responseMetadata(response, context: context, durationMs: durationMs)
            )
        }
    }

    private func responseMetadata(
        _ response: HTTPResponse,
        context: RequestContext,
        durationMs: Double
    ) -> Logger.Metadata {
        [
            "method": .string(context.method),
            "path": .string(context.path),
            "status": .string("\(response.statusCode)"),
            "duration_ms": .string(String(format: "%.2f", durationMs)),
            "content_length": .string("\(response.body.count)"),
        ]
    }
}

// MARK: - Request Metrics

/// Metrics collected for HTTP requests.
///
/// Provides aggregated statistics about request handling including
/// counts, latencies, and error rates.
public actor RequestMetrics {
    /// Total number of requests received.
    public private(set) var totalRequests: Int = 0

    /// Number of successful requests (2xx/3xx).
    public private(set) var successfulRequests: Int = 0

    /// Number of client errors (4xx).
    public private(set) var clientErrors: Int = 0

    /// Number of server errors (5xx).
    public private(set) var serverErrors: Int = 0

    /// Total request duration in milliseconds.
    public private(set) var totalDurationMs: Double = 0

    /// Minimum request duration in milliseconds.
    public private(set) var minDurationMs: Double = .infinity

    /// Maximum request duration in milliseconds.
    public private(set) var maxDurationMs: Double = 0

    /// Requests per path.
    public private(set) var requestsByPath: [String: Int] = [:]

    /// Errors per path.
    public private(set) var errorsByPath: [String: Int] = [:]

    /// Creates a new RequestMetrics instance.
    public init() {}

    /// Records a completed request.
    ///
    /// - Parameters:
    ///   - path: The request path.
    ///   - statusCode: The response status code.
    ///   - durationMs: The request duration in milliseconds.
    public func record(path: String, statusCode: Int, durationMs: Double) {
        totalRequests += 1
        totalDurationMs += durationMs

        if durationMs < minDurationMs {
            minDurationMs = durationMs
        }
        if durationMs > maxDurationMs {
            maxDurationMs = durationMs
        }

        // Normalize path (remove query string, limit segments)
        let normalizedPath = normalizePath(path)
        requestsByPath[normalizedPath, default: 0] += 1

        if statusCode >= 200 && statusCode < 400 {
            successfulRequests += 1
        } else if statusCode >= 400 && statusCode < 500 {
            clientErrors += 1
            errorsByPath[normalizedPath, default: 0] += 1
        } else if statusCode >= 500 {
            serverErrors += 1
            errorsByPath[normalizedPath, default: 0] += 1
        }
    }

    /// Returns the average request duration in milliseconds.
    public var averageDurationMs: Double {
        totalRequests > 0 ? totalDurationMs / Double(totalRequests) : 0
    }

    /// Returns the error rate as a percentage.
    public var errorRate: Double {
        totalRequests > 0 ? Double(clientErrors + serverErrors) / Double(totalRequests) * 100 : 0
    }

    /// Returns a snapshot of current metrics.
    public func snapshot() -> MetricsSnapshot {
        MetricsSnapshot(
            totalRequests: totalRequests,
            successfulRequests: successfulRequests,
            clientErrors: clientErrors,
            serverErrors: serverErrors,
            averageDurationMs: averageDurationMs,
            minDurationMs: minDurationMs.isInfinite ? 0 : minDurationMs,
            maxDurationMs: maxDurationMs,
            errorRate: errorRate,
            topPaths: Array(requestsByPath.sorted { $0.value > $1.value }.prefix(10)),
            errorPaths: Array(errorsByPath.sorted { $0.value > $1.value }.prefix(5))
        )
    }

    /// Resets all metrics to initial values.
    public func reset() {
        totalRequests = 0
        successfulRequests = 0
        clientErrors = 0
        serverErrors = 0
        totalDurationMs = 0
        minDurationMs = .infinity
        maxDurationMs = 0
        requestsByPath = [:]
        errorsByPath = [:]
    }

    private func normalizePath(_ path: String) -> String {
        // Remove query string
        let basePath = path.split(separator: "?").first.map(String.init) ?? path

        // Limit path depth for aggregation
        let segments = basePath.split(separator: "/").prefix(3)
        return "/" + segments.joined(separator: "/")
    }
}

/// A snapshot of request metrics at a point in time.
public struct MetricsSnapshot: Codable, Sendable {
    public let totalRequests: Int
    public let successfulRequests: Int
    public let clientErrors: Int
    public let serverErrors: Int
    public let averageDurationMs: Double
    public let minDurationMs: Double
    public let maxDurationMs: Double
    public let errorRate: Double
    public let topPaths: [(String, Int)]
    public let errorPaths: [(String, Int)]

    enum CodingKeys: String, CodingKey {
        case totalRequests, successfulRequests, clientErrors, serverErrors
        case averageDurationMs, minDurationMs, maxDurationMs, errorRate
        case topPaths, errorPaths
    }

    public init(
        totalRequests: Int,
        successfulRequests: Int,
        clientErrors: Int,
        serverErrors: Int,
        averageDurationMs: Double,
        minDurationMs: Double,
        maxDurationMs: Double,
        errorRate: Double,
        topPaths: [(String, Int)],
        errorPaths: [(String, Int)]
    ) {
        self.totalRequests = totalRequests
        self.successfulRequests = successfulRequests
        self.clientErrors = clientErrors
        self.serverErrors = serverErrors
        self.averageDurationMs = averageDurationMs
        self.minDurationMs = minDurationMs
        self.maxDurationMs = maxDurationMs
        self.errorRate = errorRate
        self.topPaths = topPaths
        self.errorPaths = errorPaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalRequests = try container.decode(Int.self, forKey: .totalRequests)
        successfulRequests = try container.decode(Int.self, forKey: .successfulRequests)
        clientErrors = try container.decode(Int.self, forKey: .clientErrors)
        serverErrors = try container.decode(Int.self, forKey: .serverErrors)
        averageDurationMs = try container.decode(Double.self, forKey: .averageDurationMs)
        minDurationMs = try container.decode(Double.self, forKey: .minDurationMs)
        maxDurationMs = try container.decode(Double.self, forKey: .maxDurationMs)
        errorRate = try container.decode(Double.self, forKey: .errorRate)

        let topPathsDict = try container.decode([[String: String]].self, forKey: .topPaths)
        topPaths = topPathsDict.compactMap { dict in
            guard let path = dict["path"], let countStr = dict["count"], let count = Int(countStr) else { return nil }
            return (path, count)
        }

        let errorPathsDict = try container.decode([[String: String]].self, forKey: .errorPaths)
        errorPaths = errorPathsDict.compactMap { dict in
            guard let path = dict["path"], let countStr = dict["count"], let count = Int(countStr) else { return nil }
            return (path, count)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalRequests, forKey: .totalRequests)
        try container.encode(successfulRequests, forKey: .successfulRequests)
        try container.encode(clientErrors, forKey: .clientErrors)
        try container.encode(serverErrors, forKey: .serverErrors)
        try container.encode(averageDurationMs, forKey: .averageDurationMs)
        try container.encode(minDurationMs, forKey: .minDurationMs)
        try container.encode(maxDurationMs, forKey: .maxDurationMs)
        try container.encode(errorRate, forKey: .errorRate)

        let topPathsDicts = topPaths.map { ["path": $0.0, "count": String($0.1)] }
        try container.encode(topPathsDicts, forKey: .topPaths)

        let errorPathsDicts = errorPaths.map { ["path": $0.0, "count": String($0.1)] }
        try container.encode(errorPathsDicts, forKey: .errorPaths)
    }
}
