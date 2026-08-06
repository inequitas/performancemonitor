import Darwin
import Foundation
import PerformanceAppCore

/// Listening ports plus how many connections each process has open.
struct PortSnapshot: Sendable {
    let listening: [ListeningPort]
    /// Established TCP connections per app, helpers counted together, largest
    /// first. Carried as `ProcessUsage` so it renders through the same row as
    /// every other per-process list, with the same grouping and glossary names.
    let connections: [ProcessUsage]
}

@MainActor
protocol PortSampling: AnyObject {
    /// Walks every readable process's file descriptors. Returns `nil` while a
    /// previous run is in flight, the throttle blocks this call, or the pid
    /// enumeration failed.
    func sample(owners: [String: String]) async -> PortSnapshot?
    func resetThrottle()
}

/// Reads socket state straight from the kernel: no subprocess, no `lsof`, and
/// measured at under 10 ms for a full sweep of 443 processes.
///
/// Cheap as it is, it still only runs while the Network window is open, for the
/// same reason as every other per-process sampler here.
///
/// ## What it can and cannot see
///
/// Without root the kernel refuses file descriptor listings for processes owned
/// by other users, which on a normal Mac means most of the system daemons: 292
/// of 735 were refused on the machine this was written against. That sounds
/// worse than it is. `lsof -iTCP -sTCP:LISTEN` without sudo reported exactly the
/// same 13 listening sockets this does, so the gap is the same one every tool
/// has short of asking for a password, and asking for one is not worth it for a
/// feature that only reports.
@MainActor
final class PortSampler: PortSampling {
    private var inFlight = false
    private var cacheDate: Date = .distantPast
    private static let interval: TimeInterval = 3

    func sample(owners: [String: String]) async -> PortSnapshot? {
        guard !inFlight else { return nil }
        let now = Date()
        guard now.timeIntervalSince(cacheDate) >= Self.interval else { return nil }
        inFlight = true
        cacheDate = now
        defer { inFlight = false }

        guard let raw = await Self.read() else { return nil }
        let connections = ProcessGrouping.group(raw.connections, parents: [:],
                                                owners: owners, topCount: 8)
        return PortSnapshot(listening: ListeningPortList.aggregate(raw.sockets),
                            connections: connections)
    }

    func resetThrottle() { cacheDate = .distantPast }

    private static func read() async
        -> (sockets: [ListeningPortList.Socket], connections: [ProcessUsage])? {
        await Task.detached(priority: .utility) { () -> ([ListeningPortList.Socket], [ProcessUsage])? in
            let sizeBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
            guard sizeBytes > 0 else { return nil }
            let capacity = Int(sizeBytes) / MemoryLayout<pid_t>.size
            guard capacity > 0 else { return nil }
            var pids = [pid_t](repeating: 0, count: capacity)
            let written = pids.withUnsafeMutableBufferPointer { buffer in
                proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress,
                              Int32(buffer.count * MemoryLayout<pid_t>.size))
            }
            guard written > 0 else { return nil }

            var sockets: [ListeningPortList.Socket] = []
            var connections: [ProcessUsage] = []

            for pid in pids.prefix(Swift.min(Int(written) / MemoryLayout<pid_t>.size, capacity))
            where pid > 0 {
                // Expected common case: the process is not ours and the kernel
                // refuses. Skip it silently rather than logging every sweep.
                let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
                guard bufferSize > 0 else { continue }

                var descriptors = [proc_fdinfo](
                    repeating: proc_fdinfo(),
                    count: Int(bufferSize) / MemoryLayout<proc_fdinfo>.size
                )
                let filled = descriptors.withUnsafeMutableBufferPointer { buffer in
                    proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, bufferSize)
                }
                guard filled > 0 else { continue }

                var nameBuffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN) + 1)
                guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
                let name = String(cString: nameBuffer)

                var established = 0
                for descriptor in descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.size)
                where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                    var info = socket_fdinfo()
                    let result = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO,
                                                &info, Int32(MemoryLayout<socket_fdinfo>.size))
                    guard result == Int32(MemoryLayout<socket_fdinfo>.size),
                          info.psi.soi_kind == SOCKINFO_TCP else { continue }

                    let tcp = info.psi.soi_proto.pri_tcp
                    switch tcp.tcpsi_state {
                    case TSI_S_LISTEN:
                        // The kernel reports the port in network byte order in
                        // the low half of an int.
                        let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
                        sockets.append(ListeningPortList.Socket(
                            pid: pid, processName: name, port: port,
                            isIPv6: info.psi.soi_family == AF_INET6
                        ))
                    case TSI_S_ESTABLISHED:
                        established += 1
                    default:
                        break
                    }
                }
                if established > 0 {
                    connections.append(ProcessUsage(pid: pid, name: name, value: Double(established)))
                }
            }
            return (sockets, connections)
        }.value
    }
}
