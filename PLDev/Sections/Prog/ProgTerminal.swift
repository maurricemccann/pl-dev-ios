import NIOCore
import NIOSSH
import NIOTransportServices
import SwiftTerm
import SwiftUI

// A terminal inside PL Prog (S355, his ask 11-27: "a terminal frame to follow along the lessons"; spec "PL PROG TERMINAL" in the
// vault). SSH to the Linux box he learns on, with Apple's swift-nio-ssh and SwiftTerm. The address and password are typed by him on
// the phone (password in the Keychain); nothing of his is in this repo. The host key is trusted once and then held to.

private enum ProgSSHError: LocalizedError {
    case timedOut, closed, hostKeyChanged, unreachable
    var errorDescription: String? {
        switch self {
        case .unreachable: "Can\u{2019}t reach that address. Is Tailscale on, and the computer awake?"
        case .timedOut: "No answer in 15 seconds. Is the computer on and reachable?"
        case .closed: "The connection closed. Check the user name and password."
        case .hostKeyChanged: "This computer\u{2019}s identity changed since last time. Forget it only if you reinstalled it."
        }
    }
}

/// Trust on first use: the first key seen for an address is kept; a different one is refused.
private final class ProgHostKey: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let store: String
    private(set) var changed = false
    init(host: String, port: Int) { store = "prog.hostkey.\(host):\(port)" }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let seen = String(openSSHPublicKey: hostKey)
        if let known = UserDefaults.standard.string(forKey: store), known != seen {
            changed = true
            validationCompletePromise.fail(ProgSSHError.hostKeyChanged)
        } else {
            UserDefaults.standard.set(seen, forKey: store)
            validationCompletePromise.succeed(())
        }
    }
}

/// The shell channel: asks for a terminal and a shell, passes bytes both ways.
private final class ProgShell: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let cols: Int, rows: Int
    private let output: @Sendable ([UInt8]) -> Void
    private let ended: @Sendable () -> Void

    init(cols: Int, rows: Int, output: @escaping @Sendable ([UInt8]) -> Void, ended: @escaping @Sendable () -> Void) {
        self.cols = cols; self.rows = rows; self.output = output; self.ended = ended
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in }
    }

    func channelActive(context: ChannelHandlerContext) {
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: false, term: "xterm-256color", terminalCharacterWidth: cols, terminalRowHeight: rows,
            terminalPixelWidth: 0, terminalPixelHeight: 0, terminalModes: SSHTerminalModes([:])), promise: nil)
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: false), promise: nil)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .byteBuffer(let b) = unwrapInboundIn(data).data else { return }
        output(Array(b.readableBytesView))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let bytes = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(bytes))), promise: promise)
    }

    func channelInactive(context: ChannelHandlerContext) {
        ended()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) { context.close(promise: nil) }
}

/// One session, kept while he moves between lessons.
@MainActor @Observable final class ProgTerm {
    static let shared = ProgTerm()

    enum State: Equatable { case idle, connecting, connected }
    private(set) var state = State.idle
    private(set) var problem: String?
    private(set) var keyChanged = false

    var host = UserDefaults.standard.string(forKey: "prog.ssh.host") ?? "" { didSet { UserDefaults.standard.set(host, forKey: "prog.ssh.host") } }
    var port = UserDefaults.standard.string(forKey: "prog.ssh.port") ?? "2222" { didSet { UserDefaults.standard.set(port, forKey: "prog.ssh.port") } }
    var user = UserDefaults.standard.string(forKey: "prog.ssh.user") ?? "r1" { didSet { UserDefaults.standard.set(user, forKey: "prog.ssh.user") } }

    @ObservationIgnored private var connection: Channel?
    @ObservationIgnored private var shell: Channel?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private lazy var delegate = ProgTermDelegate(self)
    @ObservationIgnored private(set) lazy var view: TerminalView = {
        let v = TerminalView(frame: CGRect(x: 0, y: 0, width: 360, height: 300), font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular))
        v.nativeBackgroundColor = UIColor.black
        v.nativeForegroundColor = UIColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1)
        v.terminalDelegate = delegate
        return v
    }()

    static func password() -> String { KeyStore.load(account: "prog.ssh.password").flatMap { String(data: $0, encoding: .utf8) } ?? "" }

    func connect(password: String) {
        let host = host.trimmingCharacters(in: .whitespaces), user = user.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !user.isEmpty, !password.isEmpty, let port = Int(port), (1...65535).contains(port) else {
            problem = "Fill in the address, port, user and password."; return
        }
        do { try KeyStore.save(Data(password.utf8), account: "prog.ssh.password") } catch { problem = "The Keychain refused the password." }
        disconnect()
        attempt += 1
        let mine = attempt
        state = .connecting; problem = nil; keyChanged = false
        let cols = max(20, view.getTerminal().cols), rows = max(5, view.getTerminal().rows)
        let key = ProgHostKey(host: host, port: port)
        let output: @Sendable ([UInt8]) -> Void = { bytes in
            DispatchQueue.main.async { MainActor.assumeIsolated { ProgTerm.shared.receive(bytes, mine) } }
        }
        let ended: @Sendable () -> Void = { DispatchQueue.main.async { MainActor.assumeIsolated { ProgTerm.shared.ended(mine) } } }
        Task {
            do {
                let (conn, sh) = try await Self.open(host: host, port: port, user: user, password: password, key: key,
                                                     cols: cols, rows: rows, output: output, ended: ended)
                guard mine == attempt else { conn.close(promise: nil); return }
                connection = conn; shell = sh; state = .connected
            } catch {
                guard mine == attempt else { return }
                state = .idle
                keyChanged = key.changed
                problem = key.changed ? ProgSSHError.hostKeyChanged.errorDescription : error.localizedDescription
            }
        }
    }

    nonisolated private static func open(host: String, port: Int, user: String, password: String, key: ProgHostKey, cols: Int, rows: Int,
                                         output: @escaping @Sendable ([UInt8]) -> Void,
                                         ended: @escaping @Sendable () -> Void) async throws -> (Channel, Channel) {
        // Apple's own networking (Network.framework): plain sockets timed out on his iPhone over cellular + Tailscale (11-27)
        let bootstrap = NIOTSConnectionBootstrap(group: NIOTSEventLoopGroup.singleton)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let ssh = NIOSSHHandler(role: .client(.init(userAuthDelegate: SimplePasswordDelegate(username: user, password: password),
                                                                serverAuthDelegate: key)),
                                            allocator: channel.allocator, inboundChildChannelInitializer: nil)
                    try channel.pipeline.syncOperations.addHandler(ssh)
                }
            }
        let connection: Channel
        do { connection = try await bootstrap.connect(host: host, port: port).get() } catch { throw ProgSSHError.unreachable }
        do {
            let shell: Channel = try await connection.eventLoop.flatSubmit { () -> EventLoopFuture<Channel> in
                let promise = connection.eventLoop.makePromise(of: Channel.self)
                // a wrong password closes the link; a silent server is cut off by the clock
                connection.closeFuture.whenComplete { _ in promise.fail(ProgSSHError.closed) }
                connection.eventLoop.scheduleTask(in: .seconds(15)) { promise.fail(ProgSSHError.timedOut) }
                do {
                    let ssh = try connection.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                    ssh.createChannel(promise, channelType: .session) { child, _ in
                        child.eventLoop.makeCompletedFuture {
                            try child.pipeline.syncOperations.addHandler(ProgShell(cols: cols, rows: rows, output: output, ended: ended))
                        }
                    }
                } catch {
                    promise.fail(error)
                }
                return promise.futureResult
            }.get()
            return (connection, shell)
        } catch {
            connection.close(promise: nil)
            throw error
        }
    }

    private func receive(_ bytes: [UInt8], _ from: Int) {
        guard from == attempt else { return }
        view.feed(byteArray: bytes[...])
    }

    private func ended(_ from: Int) {
        guard from == attempt else { return }
        connection?.close(promise: nil)
        connection = nil; shell = nil; state = .idle
        problem = "Disconnected."
    }

    func disconnect() {
        attempt += 1
        connection?.close(promise: nil)
        connection = nil; shell = nil; state = .idle
    }

    func send(_ bytes: [UInt8]) {
        shell?.writeAndFlush(ByteBuffer(bytes: bytes), promise: nil)
    }

    /// A lesson command, typed at the prompt; he presses return himself.
    func type(_ command: String) { send(Array(command.utf8)) }

    func resized(cols: Int, rows: Int) {
        shell?.pipeline.triggerUserOutboundEvent(SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols, terminalRowHeight: rows, terminalPixelWidth: 0, terminalPixelHeight: 0), promise: nil)
    }

    func forgetHostKey() {
        UserDefaults.standard.removeObject(forKey: "prog.hostkey.\(host.trimmingCharacters(in: .whitespaces)):\(port)")
        keyChanged = false; problem = nil
    }
}

@MainActor private final class ProgTermDelegate: NSObject, @preconcurrency TerminalViewDelegate {
    weak var term: ProgTerm?
    init(_ term: ProgTerm) { self.term = term }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { term?.send(Array(data)) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { term?.resized(cols: newCols, rows: newRows) }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}   // a remote machine never opens pages here
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}   // nor writes the clipboard
    func clipboardRead(source: TerminalView) -> Data? { nil }    // nor reads it
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

private struct ProgTermScreen: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        holder.backgroundColor = .black
        return holder
    }
    /// The one terminal view moves to whichever lesson is showing, with its scrollback.
    func updateUIView(_ holder: UIView, context: Context) {
        let view = ProgTerm.shared.view
        guard view.superview !== holder else { return }
        view.removeFromSuperview()
        view.frame = holder.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        holder.addSubview(view)
    }
}

/// The lower part of a lesson: the terminal, or how to connect it.
struct ProgTerminalPane: View {
    @State private var term = ProgTerm.shared
    @State private var setUp = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(term.state == .connected ? "Connected" : term.state == .connecting ? "Connecting" : "Not connected")
                    .font(Font.pl(.footnote)).foregroundStyle(.secondary)
                Spacer()
                if term.state == .connected {
                    Button("Disconnect") { term.disconnect() }.frame(minWidth: 44, minHeight: 44)
                } else {
                    Button("Connect") { setUp = true }.frame(minWidth: 44, minHeight: 44).disabled(term.state == .connecting)
                }
            }
            .padding(.horizontal, 12)
            if let p = term.problem {
                Text(p).font(Font.pl(.footnote)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 4)
            }
            ProgTermScreen()
        }
        .sheet(isPresented: $setUp) { ProgConnectSheet() }
    }
}

private struct ProgConnectSheet: View {
    @State private var term = ProgTerm.shared
    @State private var password = ProgTerm.password()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $term.host).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Port", text: $term.port).keyboardType(.numberPad)
                    TextField("User", text: $term.user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                } footer: {
                    Text("The computer you learn on, over your own network or Tailscale. The password stays in this iPhone\u{2019}s Keychain.")
                }
                if term.keyChanged {
                    Section { Button("Forget the old identity", role: .destructive) { term.forgetHostKey() } }
                }
            }
            .navigationTitle("Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Connect") { term.connect(password: password); dismiss() } }
            }
        }
    }
}
