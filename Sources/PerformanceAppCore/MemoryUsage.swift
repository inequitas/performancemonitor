/// Physical memory in GiB, excluding reclaimable file-backed and purgeable pages.
public struct MemoryUsage: Sendable {
    public let appGB: Double
    public let wiredGB: Double
    public let compressedGB: Double
    public var usedGB: Double { appGB + wiredGB + compressedGB }

    public init(internalPages: UInt32, purgeablePages: UInt32, wiredPages: UInt32,
                compressedPages: UInt32, pageSize: Double) {
        let gbPerPage = pageSize / 1_073_741_824
        appGB = max(0, Double(internalPages) - Double(purgeablePages)) * gbPerPage
        wiredGB = Double(wiredPages) * gbPerPage
        compressedGB = Double(compressedPages) * gbPerPage
    }
}
