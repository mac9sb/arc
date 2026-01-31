import ArcCore
import Foundation
import NIO
import NIOHTTP1
import NIOPosix
import Noora

/// Handles HTTP proxying to dynamic application sites.
///
/// Forwards incoming HTTP requests to configured application backends,
/// performs health checks, and manages request/response transformation.
///
/// ## Example
///
/// ```swift
/// let handler = ProxyHandler(config: arcConfig)
/// let response = await handler.handle(request: httpRequest, appSite: appSite)
/// ```
public final class ProxyHandler: @unchecked Sendable {
    private var config: ArcConfig
    private let eventLoopGroup: EventLoopGroup

    /// Creates a new proxy handler.
    ///
    /// - Parameter config: The Arc configuration containing site definitions.
    public init(config: ArcConfig) {
        self.config = config
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    public func updateConfig(_ config: ArcConfig) {
        self.config = config
    }

    func handle(request: HTTPRequest, appSite: AppSite) async -> HTTPResponse {
        guard let baseURL = appSite.baseURL() else {
            return .badGateway("Invalid upstream")
        }

        let url = URL(string: request.path, relativeTo: baseURL) ?? baseURL
        guard let host = url.host else {
            return .badGateway("Invalid upstream URL")
        }

        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""

        do {
            return try await makeHTTPRequest(
                host: host,
                port: port,
                path: path + query,
                method: request.method,
                headers: request.headers,
                body: request.body
            )
        } catch {
            Noora().error("Proxy error for \(appSite.name): \(error.localizedDescription)")
            return .badGateway("Upstream unavailable")
        }
    }

    public func checkHealth(appSite: AppSite) async -> (ok: Bool, message: String?) {
        guard let url = appSite.healthURL(),
            let host = url.host
        else {
            return (false, "Missing or invalid health URL")
        }

        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""

        do {
            let response = try await makeHTTPRequest(
                host: host,
                port: port,
                path: path + query,
                method: "GET",
                headers: [:],
                body: Data(),
                timeout: 5
            )

            if response.statusCode == 200 {
                return (true, nil)
            }
            return (false, "Health check failed (status \(response.statusCode))")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func makeHTTPRequest(
        host: String,
        port: Int,
        path: String,
        method: String,
        headers: [String: String],
        body: Data,
        timeout: TimeInterval = 10
    ) async throws -> HTTPResponse {
        let promise = eventLoopGroup.next().makePromise(of: HTTPResponse.self)

        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers()
                    .flatMap { _ in
                        channel.pipeline.addHandler(HTTPClientHandler(promise: promise))
                    }
            }
            .connectTimeout(.seconds(Int64(timeout)))

        let httpMethod = HTTPMethod(rawValue: method)
        var httpHeaders = HTTPHeaders()

        // Copy headers except Host/Connection
        for (key, value) in headers {
            let lower = key.lowercased()
            if lower == "host" || lower == "connection" {
                continue
            }
            httpHeaders.add(name: key, value: value)
        }

        httpHeaders.add(name: "Host", value: "\(host):\(port)")
        httpHeaders.add(name: "Connection", value: "close")
        httpHeaders.add(name: "Content-Length", value: "\(body.count)")

        let requestHead = HTTPRequestHead(
            version: .http1_1,
            method: httpMethod,
            uri: path,
            headers: httpHeaders
        )

        bootstrap.connect(host: host, port: port).whenComplete { result in
            switch result {
            case .success(let channel):
                channel.write(HTTPClientRequestPart.head(requestHead), promise: nil)

                if !body.isEmpty {
                    var buffer = channel.allocator.buffer(capacity: body.count)
                    buffer.writeBytes(body)
                    channel.write(HTTPClientRequestPart.body(.byteBuffer(buffer)), promise: nil)
                }

                channel.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)

            case .failure(let error):
                promise.fail(error)
            }
        }

        return try await promise.futureResult.get()
    }
}

private final class HTTPClientHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let promise: EventLoopPromise<HTTPResponse>
    private var responseHead: HTTPResponseHead?
    private var responseBody: Data = Data()

    init(promise: EventLoopPromise<HTTPResponse>) {
        self.promise = promise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let responsePart = unwrapInboundIn(data)

        switch responsePart {
        case .head(let head):
            responseHead = head

        case .body(let buffer):
            if let bytes = buffer.getBytes(at: 0, length: buffer.readableBytes) {
                responseBody.append(contentsOf: bytes)
            }

        case .end:
            guard let head = responseHead else {
                promise.fail(ProxyError.invalidResponse)
                return
            }

            var headers: [String: String] = [:]
            for (name, value) in head.headers {
                headers[name] = value
            }

            let reason = head.status.reasonPhrase

            let response = HTTPResponse(
                status: Int(head.status.code),
                reason: reason,
                headers: headers,
                body: responseBody
            )

            promise.succeed(response)
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }
}

private enum ProxyError: Error {
    case invalidResponse
}
