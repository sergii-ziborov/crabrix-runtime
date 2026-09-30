import WasmTypes

/// A cumulative limit shared by stdout and stderr for one guest invocation.
/// A denied write leaves the capture files unchanged and sets `wasExceeded`.
public final class WASIOutputBudget: Sendable {
    private struct State: Sendable {
        var written = 0
        var wasExceeded = false
    }

    public let maximumBytes: Int
    private let onExceeded: @Sendable () -> Void
    nonisolated(unsafe) private var state: PlatformMutex<State>

    public init(maximumBytes: Int, onExceeded: @escaping @Sendable () -> Void = {}) throws {
        guard maximumBytes > 0 else { throw WASIAbi.Errno.EINVAL }
        self.maximumBytes = maximumBytes
        self.onExceeded = onExceeded
        self.state = PlatformMutex(State())
    }

    public var wasExceeded: Bool {
        state.withLock { $0.wasExceeded }
    }

    fileprivate func reject() throws -> Never {
        state.withLock { $0.wasExceeded = true }
        onExceeded()
        throw WASIAbi.Errno.EFBIG
    }

    fileprivate func write(
        requestedBytes: Int,
        operation: () throws -> WASIAbi.Size
    ) throws -> WASIAbi.Size {
        do {
            return try state.withLock { state in
                guard requestedBytes <= maximumBytes - state.written else {
                    state.wasExceeded = true
                    throw WASIAbi.Errno.EFBIG
                }
                let written = try operation()
                state.written += Int(written)
                return written
            }
        } catch let error as WASIAbi.Errno where error == .EFBIG {
            onExceeded()
            throw error
        }
    }
}

/// The host fd remains borrowed by WASI. Seeking, positioned writes and
/// truncation are denied so a guest cannot create a sparse file past the limit.
struct BoundedStdioFile: FdWASIFile {
    let fd: FileDescriptor
    let accessMode: FileAccessMode = .write
    let isBorrowed = true
    let budget: WASIOutputBudget

    func attributes() throws -> WASIAbi.Filestat {
        try StdioFileEntry(fd: fd, accessMode: .write).attributes()
    }

    func write(vectored buffers: GuestBuffers) throws -> WASIAbi.Size {
        guard buffers.count <= 1_024 else { throw WASIAbi.Errno.EINVAL }
        var requested = 0
        for index in 0..<buffers.count {
            let count = try buffers.withHostBuffer(at: index) { $0.count }
            guard count <= budget.maximumBytes - requested else {
                try budget.reject()
            }
            requested += count
        }
        return try budget.write(requestedBytes: requested) {
            try StdioFileEntry(fd: fd, accessMode: .write).write(vectored: buffers)
        }
    }

    func pwrite(vectored buffers: GuestBuffers, offset: WASIAbi.FileSize) throws -> WASIAbi.Size {
        throw WASIAbi.Errno.ESPIPE
    }

    func seek(offset: WASIAbi.FileDelta, whence: WASIAbi.Whence) throws -> WASIAbi.FileSize {
        throw WASIAbi.Errno.ESPIPE
    }

    func setFilestatSize(_ size: WASIAbi.FileSize) throws {
        throw WASIAbi.Errno.EINVAL
    }
}
