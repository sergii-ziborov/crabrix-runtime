// Software bounds checks use the committed byte count, not the reserved size.
// The inaccessible part of this mapping exists solely to keep the base pointer
// stable while a non-shared guest grows its linear memory.
#if (os(macOS) || os(iOS) || os(Linux)) && !$Embedded

struct ReservedSoftwareMemory {
    private let vm: SystemVirtualMemory
    private(set) var byteCount: Int

    var baseAddress: UnsafeMutableRawPointer { vm.base }
    var reservationBytes: Int { vm.reservationBytes }
    var data: UnsafeBufferPointer<UInt8> {
        UnsafeBufferPointer(start: vm.base.assumingMemoryBound(to: UInt8.self), count: byteCount)
    }

    init?(initialBytes: Int, reservationBytes: Int) {
        guard initialBytes >= 0, reservationBytes > 0, initialBytes <= reservationBytes,
              let vm = SystemVirtualMemory(reservationBytes: reservationBytes, commitBytes: initialBytes)
        else { return nil }
        self.vm = vm
        self.byteCount = initialBytes
    }

    mutating func grow(to newByteCount: Int) throws {
        precondition(newByteCount >= byteCount && newByteCount <= reservationBytes)
        let delta = newByteCount - byteCount
        guard vm.commit(offset: byteCount, byteCount: delta) else {
            throw Trap(.memoryOutOfBounds)
        }
        byteCount = newByteCount
    }

    func deallocate() { vm.deallocate() }
}

#endif
