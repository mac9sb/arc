import ArcCore
import Foundation
import Noora
import NIO
import NIOPosix
import NIOHTTP1

/// Lightweight HTTP server that handles static sites and app proxying.
///
/// Uses swift-nio for cross-platform networking support (macOS and Linux).
public final class HTTPServer: @unchecked Sendable {
    private let eventLoopGroup: EventLoopGroup
    private var serverChannel: Channel?
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
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    /// Starts the HTTP listener.
    public func start() async throws {
        guard serverChannel == nil else { return }

        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline()
                    .flatMap { _ in
                        channel.pipeline.addHandler(HTTPHandler(server: self))
                    }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let channel = try await bootstrap.bind(host: "0.0.0.0", port: Int(config.proxyPort)).get()
        self.serverChannel = channel
        
        Noora().success("HTTP server listening on port \(config.proxyPort)")
    }

    /// Stops the HTTP listener.
    public func stop() {
        serverChannel?.close(mode: .all).whenComplete { _ in
            Noora().info("HTTP server stopped")
        }
        serverChannel = nil
    }
    
    deinit {
        try? eventLoopGroup.syncShutdownGracefully()
    }

    /// Reloads configuration without restarting the process.
    public func reload(config: ArcConfig) async {
        self.config = config
        self.staticHandler = StaticFileHandler(config: config)
        self.proxyHandler.updateConfig(config)
    }

    func route(request: HTTPRequest) async -> HTTPResponse {
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

/// Sendable wrapper for ChannelHandlerContext pointer
private struct ContextRef: @unchecked Sendable {
    let ptr: UnsafeRawPointer
}

/// NIO channel handler that processes HTTP requests.
private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private let server: HTTPServer
    private var requestBuffer: Data = Data()
    private var currentRequest: HTTPRequest?
    
    init(server: HTTPServer) {
        self.server = server
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let requestPart = unwrapInboundIn(data)
        
        switch requestPart {
        case .head(let head):
            var headers: [String: String] = [:]
            for (name, value) in head.headers {
                headers[name.lowercased()] = value
            }
            
            // Reconstruct Host header with proper casing
            if let host = head.headers["host"].first {
                headers["host"] = host
            }
            
            currentRequest = HTTPRequest(
                method: head.method.rawValue,
                path: head.uri,
                headers: headers,
                body: Data()
            )
            requestBuffer = Data()
            
        case .body(let buffer):
            if let request = currentRequest {
                var body = request.body
                var mutableBuffer = buffer
                if let bytes = mutableBuffer.readBytes(length: buffer.readableBytes) {
                    body.append(contentsOf: bytes)
                }
                currentRequest = HTTPRequest(
                    method: request.method,
                    path: request.path,
                    headers: request.headers,
                    body: body
                )
            }
            
        case .end:
            guard let request = currentRequest else {
                sendError(context: context, status: 400, reason: "Bad Request")
                return
            }
            
            let serverRef = self.server
            let handler = self
            let eventLoop = context.eventLoop
            // Call directly since we're already on the event loop
            // The handleRequestAsync method is nonisolated(unsafe) to handle the context safely
            handler.handleRequestAsync(
                server: serverRef,
                context: context,
                request: request,
                eventLoop: eventLoop
            )
            currentRequest = nil
            requestBuffer = Data()
        }
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        Noora().error("Connection error: \(error.localizedDescription)")
        context.close(promise: nil)
    }
    
    /// Helper method to handle async request routing and response sending.
    /// Marked nonisolated to allow capturing non-Sendable context in Task.
    /// Safe because we ensure the context is only used on its event loop.
    nonisolated func handleRequestAsync(
        server: HTTPServer,
        context: ChannelHandlerContext,
        request: HTTPRequest,
        eventLoop: EventLoop
    ) {
        let handler = self
        // Capture context as Sendable wrapper - safe because we ensure context is only used on its event loop
        let contextRef = ContextRef(ptr: Unmanaged.passUnretained(context).toOpaque())
        Task {
            let response = await server.route(request: request)
            eventLoop.execute {
                // Access sendResponse - safe because we're on the event loop
                let context = Unmanaged<ChannelHandlerContext>.fromOpaque(contextRef.ptr).takeUnretainedValue()
                handler.sendResponse(context: context, response: response)
            }
        }
    }
    
    nonisolated private func sendResponse(context: ChannelHandlerContext, response: HTTPResponse) {
        var headers = HTTPHeaders()
        for (key, value) in response.headers {
            headers.add(name: key, value: value)
        }
        headers.add(name: "Content-Length", value: "\(response.body.count)")
        headers.add(name: "Connection", value: "close")
        
        let head = HTTPResponseHead(
            version: .http1_1,
            status: HTTPResponseStatus(statusCode: response.statusCode, reasonPhrase: response.reason),
            headers: headers
        )
        
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        
        if !response.body.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: response.body.count)
            buffer.writeBytes(response.body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
    
    private func sendError(context: ChannelHandlerContext, status: Int, reason: String) {
        let head = HTTPResponseHead(
            version: .http1_1,
            status: HTTPResponseStatus(statusCode: status, reasonPhrase: reason),
            headers: HTTPHeaders()
        )
        context.writeAndFlush(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
