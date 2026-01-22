import ArcCore
import Foundation
import Network
import Noora

/// Lightweight HTTP server that handles static sites and app proxying.
///
/// Thread safety: All mutable state access is serialized through the `queue` DispatchQueue.
/// Network framework types (NWListener) are not Sendable, so we use @unchecked Sendable
/// with documented thread-safety guarantees via the serial queue.
public final class HTTPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.arc.httpserver")
    private var listener: NWListener?
    private var config: ArcConfig
    private var staticHandler: StaticFileHandler
    private var proxyHandler: ProxyHandler

    /// Creates a new HTTP server.
    ///
    /// - Parameter config: The Arc configuration to use.
    public init(config: ArcConfig) {
        self.config = config
        self.staticHandler = StaticFileHandler(config: config)
        self.proxyHandler = ProxyHandler(config: config)
    }

    /// Starts the HTTP listener.
    public func start() async throws {
        guard listener == nil else { return }

        guard let port = NWEndpoint.Port(rawValue: UInt16(config.proxyPort)) else {
            throw ArcError.invalidConfiguration("Invalid proxy port: \(config.proxyPort)")
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: port)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Noora().success("HTTP server listening on port \(self.config.proxyPort)")
            case .failed(let error):
                Noora().error("HTTP server failed: \(error.localizedDescription)")
            case .cancelled:
                Noora().info("HTTP server stopped")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    /// Stops the HTTP listener.
    public func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Reloads configuration without restarting the process.
    public func reload(config: ArcConfig) async {
        self.config = config
        self.staticHandler = StaticFileHandler(config: config)
        self.proxyHandler.updateConfig(config)
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveNext(on: connection, buffer: Data())
    }

    private func receiveNext(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                Noora().error("Connection error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            var newBuffer = buffer
            if let data {
                newBuffer.append(data)
            }

            if isComplete && newBuffer.isEmpty {
                connection.cancel()
                return
            }

            if let request = HTTPParser.parse(data: newBuffer) {
                Task {
                    let response = await self.route(request: request)
                    self.send(response: response, on: connection)
                }
            } else if isComplete {
                self.send(
                    response: HTTPResponse(
                        status: 400, reason: "Bad Request", headers: [:], body: Data()),
                    on: connection
                )
            } else {
                self.receiveNext(on: connection, buffer: newBuffer)
            }
        }
    }

    private func send(response: HTTPResponse, on connection: NWConnection) {
        let data = response.serialize()
        connection.send(
            content: data,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private func route(request: HTTPRequest) async -> HTTPResponse {
        guard let hostHeader = request.host else {
            return HTTPResponse(status: 400, reason: "Bad Request", headers: [:], body: Data())
        }

        let host = hostHeader.split(separator: ":").first.map(String.init) ?? hostHeader

        guard let site = config.sites.first(where: { $0.domain == host }) else {
            return HTTPResponse(
                status: 404,
                reason: "Not Found",
                headers: [:],
                body: Data("Route not found".utf8)
            )
        }

        switch site {
        case .static(let staticSite):
            return staticHandler.handle(request: request, site: staticSite, baseDir: config.baseDir)
        case .app(let appSite):
            return await proxyHandler.handle(request: request, appSite: appSite)
        }
    }
}
