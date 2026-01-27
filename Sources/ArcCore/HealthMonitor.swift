import Foundation
import Logging

/// Health check result for a single site or service.
public struct HealthCheckResult: Codable, Sendable {
    /// The name of the site or service.
    public let name: String
    
    /// Whether the check passed.
    public let healthy: Bool
    
    /// Optional status message.
    public let message: String?
    
    /// Response time in milliseconds (for HTTP checks).
    public let responseTimeMs: Double?
    
    /// HTTP status code (for HTTP checks).
    public let statusCode: Int?
    
    /// Timestamp of the check.
    public let timestamp: Date
    
    public init(
        name: String,
        healthy: Bool,
        message: String? = nil,
        responseTimeMs: Double? = nil,
        statusCode: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.name = name
        self.healthy = healthy
        self.message = message
        self.responseTimeMs = responseTimeMs
        self.statusCode = statusCode
        self.timestamp = timestamp
    }
}

/// Overall health status with history tracking.
public enum HealthStatus: String, Codable, Sendable {
    /// All services are healthy.
    case healthy
    
    /// Some services are degraded but operational.
    case degraded
    
    /// One or more critical services are unhealthy.
    case unhealthy
}

/// Health monitoring with history tracking and degradation detection.
///
/// Tracks health check results over time to detect patterns and
/// provide insights into service reliability.
///
/// ## Example
///
/// ```swift
/// let monitor = HealthMonitor(historyLimit: 100)
/// await monitor.record(result)
/// let status = await monitor.overallStatus()
/// ```
public actor HealthMonitor {
    /// Maximum number of history entries to keep per site.
    private let historyLimit: Int
    
    /// Health check history by site name.
    private var history: [String: [HealthCheckResult]] = [:]
    
    /// Current status by site name.
    private var currentStatus: [String: HealthCheckResult] = [:]
    
    /// Consecutive failure counts by site name.
    private var consecutiveFailures: [String: Int] = [:]
    
    /// Logger for health monitoring.
    private let logger: Logger
    
    /// Threshold for consecutive failures before marking as degraded.
    private let degradedThreshold: Int
    
    /// Threshold for consecutive failures before marking as unhealthy.
    private let unhealthyThreshold: Int
    
    /// Creates a new health monitor.
    ///
    /// - Parameters:
    ///   - historyLimit: Maximum history entries per site. Defaults to 100.
    ///   - degradedThreshold: Failures before degraded status. Defaults to 2.
    ///   - unhealthyThreshold: Failures before unhealthy status. Defaults to 5.
    public init(
        historyLimit: Int = 100,
        degradedThreshold: Int = 2,
        unhealthyThreshold: Int = 5
    ) {
        self.historyLimit = historyLimit
        self.degradedThreshold = degradedThreshold
        self.unhealthyThreshold = unhealthyThreshold
        self.logger = Logger(label: "arc.health")
    }
    
    /// Records a health check result.
    ///
    /// - Parameter result: The health check result to record.
    public func record(_ result: HealthCheckResult) {
        // Update current status
        currentStatus[result.name] = result
        
        // Update history
        var siteHistory = history[result.name] ?? []
        siteHistory.append(result)
        
        // Trim history if needed
        if siteHistory.count > historyLimit {
            siteHistory = Array(siteHistory.suffix(historyLimit))
        }
        history[result.name] = siteHistory
        
        // Update consecutive failure count
        if result.healthy {
            consecutiveFailures[result.name] = 0
        } else {
            consecutiveFailures[result.name, default: 0] += 1
            
            let failures = consecutiveFailures[result.name] ?? 0
            if failures >= unhealthyThreshold {
                logger.error("Site \(result.name) is unhealthy after \(failures) consecutive failures")
            } else if failures >= degradedThreshold {
                logger.warning("Site \(result.name) is degraded after \(failures) consecutive failures")
            }
        }
    }
    
    /// Returns the overall health status across all monitored sites.
    public func overallStatus() -> HealthStatus {
        if currentStatus.isEmpty {
            return .healthy
        }
        
        var hasUnhealthy = false
        var hasDegraded = false
        
        for (name, _) in currentStatus {
            let failures = consecutiveFailures[name] ?? 0
            if failures >= unhealthyThreshold {
                hasUnhealthy = true
            } else if failures >= degradedThreshold {
                hasDegraded = true
            }
        }
        
        if hasUnhealthy {
            return .unhealthy
        } else if hasDegraded {
            return .degraded
        } else {
            return .healthy
        }
    }
    
    /// Returns the status for a specific site.
    ///
    /// - Parameter name: The site name.
    /// - Returns: The health status for the site.
    public func statusFor(name: String) -> HealthStatus {
        let failures = consecutiveFailures[name] ?? 0
        if failures >= unhealthyThreshold {
            return .unhealthy
        } else if failures >= degradedThreshold {
            return .degraded
        } else {
            return .healthy
        }
    }
    
    /// Returns the current health check result for a site.
    ///
    /// - Parameter name: The site name.
    /// - Returns: The most recent health check result, or nil if none.
    public func currentResult(for name: String) -> HealthCheckResult? {
        currentStatus[name]
    }
    
    /// Returns all current health check results.
    public func allCurrentResults() -> [HealthCheckResult] {
        Array(currentStatus.values)
    }
    
    /// Returns the health check history for a site.
    ///
    /// - Parameter name: The site name.
    /// - Returns: Array of historical health check results.
    public func historyFor(name: String) -> [HealthCheckResult] {
        history[name] ?? []
    }
    
    /// Returns uptime percentage for a site based on history.
    ///
    /// - Parameter name: The site name.
    /// - Returns: Uptime percentage (0-100), or nil if no history.
    public func uptimePercentage(for name: String) -> Double? {
        guard let siteHistory = history[name], !siteHistory.isEmpty else {
            return nil
        }
        
        let healthyCount = siteHistory.filter(\.healthy).count
        return Double(healthyCount) / Double(siteHistory.count) * 100
    }
    
    /// Returns average response time for a site based on history.
    ///
    /// - Parameter name: The site name.
    /// - Returns: Average response time in ms, or nil if no data.
    public func averageResponseTime(for name: String) -> Double? {
        guard let siteHistory = history[name] else { return nil }
        
        let responseTimes = siteHistory.compactMap(\.responseTimeMs)
        guard !responseTimes.isEmpty else { return nil }
        
        return responseTimes.reduce(0, +) / Double(responseTimes.count)
    }
    
    /// Returns a summary of health status for all sites.
    public func summary() -> HealthSummary {
        let results = allCurrentResults()
        let overallStatus = overallStatus()
        
        var siteStatuses: [SiteHealthSummary] = []
        for result in results {
            let status = statusFor(name: result.name)
            let uptime = uptimePercentage(for: result.name)
            let avgResponseTime = averageResponseTime(for: result.name)
            let failures = consecutiveFailures[result.name] ?? 0
            
            siteStatuses.append(SiteHealthSummary(
                name: result.name,
                status: status,
                lastCheck: result.timestamp,
                healthy: result.healthy,
                uptimePercentage: uptime,
                averageResponseTimeMs: avgResponseTime,
                consecutiveFailures: failures,
                lastMessage: result.message
            ))
        }
        
        return HealthSummary(
            overallStatus: overallStatus,
            sites: siteStatuses,
            timestamp: Date()
        )
    }
    
    /// Clears all health history.
    public func clearHistory() {
        history = [:]
        currentStatus = [:]
        consecutiveFailures = [:]
    }
}

/// Summary of health status for a single site.
public struct SiteHealthSummary: Codable, Sendable {
    public let name: String
    public let status: HealthStatus
    public let lastCheck: Date
    public let healthy: Bool
    public let uptimePercentage: Double?
    public let averageResponseTimeMs: Double?
    public let consecutiveFailures: Int
    public let lastMessage: String?
}

/// Overall health summary for all monitored sites.
public struct HealthSummary: Codable, Sendable {
    public let overallStatus: HealthStatus
    public let sites: [SiteHealthSummary]
    public let timestamp: Date
}
