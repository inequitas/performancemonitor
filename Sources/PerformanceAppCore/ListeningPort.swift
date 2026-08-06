import Foundation

/// A port something on this Mac is accepting connections on.
///
/// Useful for the ordinary question "what has opened a port on my machine, and
/// should it have", which normally means running `lsof` and reading its output.
/// Read-only: this reports, it does not block. Blocking is a firewall's job and
/// doing it badly is worse than not doing it.
public struct ListeningPort: Identifiable, Equatable, Sendable {
    public let pid: Int32
    public let processName: String
    public let port: UInt16
    /// True when the process listens on this port over both IPv4 and IPv6,
    /// which is the common case and would otherwise show as a duplicate row.
    public let bothFamilies: Bool

    public var id: String { "\(pid)-\(port)" }

    public init(pid: Int32, processName: String, port: UInt16, bothFamilies: Bool) {
        self.pid = pid
        self.processName = processName
        self.port = port
        self.bothFamilies = bothFamilies
    }
}

/// Turns raw socket rows into something worth showing.
///
/// Pure, so the folding and sorting can be tested without a machine that
/// happens to have the right things listening.
public enum ListeningPortList {

    /// One listening socket as the kernel reported it.
    public struct Socket: Equatable, Sendable {
        public let pid: Int32
        public let processName: String
        public let port: UInt16
        public let isIPv6: Bool

        public init(pid: Int32, processName: String, port: UInt16, isIPv6: Bool) {
            self.pid = pid
            self.processName = processName
            self.port = port
            self.isIPv6 = isIPv6
        }
    }

    /// Groups the two address families of one port into a single row, lowest
    /// port first.
    ///
    /// A process listening on a port almost always listens on it twice, once
    /// per family. Two identical-looking rows invite the reader to wonder what
    /// the difference is, when there is nothing there worth their attention.
    public static func aggregate(_ sockets: [Socket]) -> [ListeningPort] {
        var byKey: [String: (socket: Socket, families: Set<Bool>)] = [:]
        for socket in sockets {
            let key = "\(socket.pid)-\(socket.port)"
            if var existing = byKey[key] {
                existing.families.insert(socket.isIPv6)
                byKey[key] = existing
            } else {
                byKey[key] = (socket, [socket.isIPv6])
            }
        }

        return byKey.values
            .map { ListeningPort(pid: $0.socket.pid,
                                 processName: $0.socket.processName,
                                 port: $0.socket.port,
                                 bothFamilies: $0.families.count > 1) }
            // Port first, then name, so the order is stable between samples
            // even as processes come and go.
            .sorted { $0.port != $1.port ? $0.port < $1.port
                                         : $0.processName < $1.processName }
    }

    /// What a port is conventionally used for, where saying so helps.
    ///
    /// Only ports whose presence someone might reasonably question, and only
    /// where the answer is not a guess. A registered number does not prove what
    /// is behind it, so this describes the convention, and the process name
    /// beside it is what actually identifies the thing.
    public static func wellKnownUse(_ port: UInt16) -> String? {
        switch port {
        case 22:            return "SSH"
        case 80, 8080:      return "HTTP"
        case 443, 8443:     return "HTTPS"
        case 445:           return "File sharing (SMB)"
        case 548:           return "File sharing (AFP)"
        case 631:           return "Printing (CUPS)"
        case 3283, 5900:    return "Screen sharing"
        case 5000, 7000:    return "AirPlay"
        case 3306:          return "MySQL"
        case 5432:          return "PostgreSQL"
        case 6379:          return "Redis"
        case 27017:         return "MongoDB"
        default:            return nil
        }
    }
}
