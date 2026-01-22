import ArcCore
import Foundation
import Noora

public struct ProxyHandler {
    private var config: ArcConfig
    private let session: URLSession

    public init(config: ArcConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: configuration)
    }

    public mutating func updateConfig(_ config: ArcConfig) {
        self.config = config
    }

    func handle(request: HTTPRequest, appSite: AppSite) async -> HTTPResponse {
        guard let baseURL = appSite.baseURL() else {
            return HTTPResponse(
                status: 502,
                reason: "Bad Gateway",
                headers: ["Content-Type": "text/plain"],
                body: Data("Invalid upstream".utf8)
            )
        }

        let targetURL = URL(string: request.path, relativeTo: baseURL) ?? baseURL
        var urlRequest = URLRequest(url: targetURL)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body

        // Copy headers except Host/Connection
        for (key, value) in request.headers {
            let lower = key.lowercased()
            if lower == "host" || lower == "connection" {
                continue
            }
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            if let http = response as? HTTPURLResponse {
                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    if let key = key as? String, let value = value as? String {
                        headers[key] = value
                    }
                }
                return HTTPResponse(
                    status: http.statusCode,
                    reason: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                    headers: headers,
                    body: data
                )
            }

            return HTTPResponse(
                status: 502,
                reason: "Bad Gateway",
                headers: [:],
                body: Data("Invalid upstream response".utf8)
            )
        } catch {
            Noora().error("Proxy error for \(appSite.name): \(error.localizedDescription)")
            return HTTPResponse(
                status: 502,
                reason: "Bad Gateway",
                headers: ["Content-Type": "text/plain"],
                body: Data("Upstream unavailable".utf8)
            )
        }
    }

    public func checkHealth(appSite: AppSite) async -> (ok: Bool, message: String?) {
        guard let healthURL = appSite.healthURL() else {
            return (false, "Missing health URL")
        }

        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return (true, nil)
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (false, "Health check failed (status \(code))")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
