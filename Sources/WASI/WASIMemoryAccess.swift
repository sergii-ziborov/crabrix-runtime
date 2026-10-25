import WasmTypes

/// WASI Preview 1 pointer validation shared by interpreter and static hosts.
/// Unsafe guest-memory adapters are called only after the entire ABI buffer
/// range, including all nested iovecs, has been checked without allocation.
internal enum WASIMemoryAccess {
    static func validate<M: GuestMemory>(
        name: String, values: [Value], memory: M, byteCount: Int,
        argumentMemory: (count: Int, bytes: Int), environmentMemory: (count: Int, bytes: Int)
    ) throws {
        guard byteCount >= 0 else { throw WASIAbi.Errno.EFAULT }
        func word(_ index: Int) throws -> UInt64 {
            guard values.indices.contains(index), case .i32(let value) = values[index] else {
                throw WASIAbi.Errno.EINVAL
            }
            return UInt64(value)
        }
        func range(_ offset: UInt64, _ count: UInt64) throws {
            guard offset <= UInt64(byteCount), count <= UInt64(byteCount) - offset else {
                throw WASIAbi.Errno.EFAULT
            }
        }
        func fixed(_ pointer: Int, _ size: UInt64) throws { try range(word(pointer), size) }
        func buffer(_ pointer: Int, _ count: Int) throws { try range(word(pointer), word(count)) }
        func iovecs(_ pointer: Int, _ count: Int) throws {
            let base = try word(pointer), count = try word(count)
            try range(base, count * 8)
            guard count <= 1024 else { throw WASIAbi.Errno.EINVAL }
            // Validate the descriptor range before reading even its first byte.
            // Decode explicitly; guest pointers need not be host-aligned.
            for index in 0..<count {
                let pair = memory.withUnsafeMutableBufferPointer(offset: UInt(base + index * 8), count: 8) { raw in
                    func u32(_ start: Int) -> UInt64 {
                        (0..<4).reduce(0) { $0 | (UInt64(raw[start + $1]) << ($1 * 8)) }
                    }
                    return (u32(0), u32(4))
                }
                try range(pair.0, pair.1)
            }
        }
        switch name {
        case "args_get":
            try range(word(0), UInt64(argumentMemory.count) * 4)
            try range(word(1), UInt64(argumentMemory.bytes))
        case "environ_get":
            try range(word(0), UInt64(environmentMemory.count) * 4)
            try range(word(1), UInt64(environmentMemory.bytes))
        case "args_sizes_get", "environ_sizes_get": try fixed(0, 4); try fixed(1, 4)
        case "clock_res_get": try fixed(1, 8)
        case "clock_time_get": try fixed(2, 8)
        case "random_get": try buffer(0, 1)
        case "fd_read", "fd_write": try iovecs(1, 2); try fixed(3, 4)
        case "fd_pread", "fd_pwrite": try iovecs(1, 2); try fixed(4, 4)
        case "fd_fdstat_get": try fixed(1, 24)
        case "fd_filestat_get": try fixed(1, 64)
        case "fd_prestat_get": try fixed(1, 8)
        case "fd_prestat_dir_name": try buffer(1, 2)
        case "fd_readdir": try buffer(1, 2); try fixed(4, 4)
        case "fd_seek": try fixed(3, 8)
        case "fd_tell": try fixed(1, 8)
        case "path_create_directory", "path_remove_directory", "path_unlink_file": try buffer(1, 2)
        case "path_filestat_get": try buffer(2, 3); try fixed(4, 64)
        case "path_filestat_set_times": try buffer(2, 3)
        case "path_link": try buffer(2, 3); try buffer(5, 6)
        case "path_open": try buffer(2, 3); try fixed(8, 4)
        case "path_readlink": try buffer(1, 2); try buffer(3, 4); try fixed(5, 4)
        case "path_rename": try buffer(1, 2); try buffer(4, 5)
        case "path_symlink": try buffer(0, 1); try buffer(3, 4)
        case "poll_oneoff":
            let count = try word(2)
            guard count <= 1024 else { throw WASIAbi.Errno.EINVAL }
            try range(word(0), count * 48)
            try range(word(1), count * 32)
            try fixed(3, 4)
        case "sock_accept": try fixed(2, 4)
        case "sock_send": try iovecs(1, 2); try fixed(4, 4)
        case "sock_recv": try iovecs(1, 2); try fixed(4, 4); try fixed(5, 2)
        // These Preview 1 calls carry scalars only. Disabled capabilities keep
        // their existing ENOSYS stubs, with no guest-memory access.
        case "fd_advise", "fd_allocate", "fd_close", "fd_datasync", "fd_fdstat_set_flags",
             "fd_fdstat_set_rights", "fd_filestat_set_size", "fd_filestat_set_times",
             "fd_renumber", "fd_sync", "proc_exit", "proc_raise", "sched_yield", "sock_shutdown": break
        default: throw WASIAbi.Errno.ENOSYS
        }
    }
}
