import WasmTypes

/// A file system implementation that directly accesses the host operating system's file system.
///
/// This implementation provides access to actual files and directories on the host system.
final class HostFileSystem: FileSystemImplementation, Sendable {

    /// Creates a new host file system.
    init() {
    }

    // MARK: - FileSystemImplementation (WASI API)

    func preopenDirectory(guestPath: String, hostPath: String) throws -> any WASIDir {
        try preopenDirectory(guestPath: guestPath, hostPath: hostPath, readOnly: false)
    }

    func preopenDirectory(guestPath: String, hostPath: String, readOnly: Bool) throws -> any WASIDir {
        let fd: FileDescriptor
        do {
            fd = try FileDescriptor.openPreopenDirectory(hostPath)
        } catch {
            throw WASIError(description: "Failed to open preopen path '\(hostPath)': \(error)")
        }

        do {
            guard try fd.attributes().fileType.isDirectory else {
                throw WASIAbi.Errno.ENOTDIR
            }
        } catch {
            throw CleanupFailure.preserving(error, cleanup: fd.close)
        }

        return DirEntry(preopenPath: guestPath, fd: fd, readOnly: readOnly)
    }

    func openAt(
        dirFd: any WASIDir,
        path: String,
        oflags: WASIAbi.Oflags,
        fsRightsBase: WASIAbi.Rights,
        fsRightsInheriting: WASIAbi.Rights,
        fdflags: WASIAbi.Fdflags,
        symlinkFollow: Bool
    ) throws -> FdEntry {
        var accessMode: FileAccessMode = []
        if fsRightsBase.contains(.FD_READ) {
            accessMode.insert(.read)
        }
        if fsRightsBase.contains(.FD_WRITE) {
            accessMode.insert(.write)
        }

        guard let dirFd = dirFd as? DirEntry else {
            throw WASIAbi.Errno.EBADF
        }
        if dirFd.readOnly && (
            accessMode.contains(.write) || oflags.contains(.CREAT) ||
            oflags.contains(.TRUNC) || fdflags.contains(.APPEND)
        ) {
            throw WASIAbi.Errno.ENOTCAPABLE
        }
        let hostFd = try dirFd.openFile(
            symlinkFollow: symlinkFollow,
            path: path,
            oflags: oflags,
            accessMode: accessMode,
            fdflags: fdflags
        )

        let actualFileType = try hostFd.attributes().fileType
        if oflags.contains(.DIRECTORY), !actualFileType.isDirectory {
            throw WASIAbi.Errno.ENOTDIR
        }

        if actualFileType.isDirectory {
            return .directory(DirEntry(preopenPath: nil, fd: hostFd, readOnly: dirFd.readOnly))
        } else {
            return .file(RegularFileEntry(
                fd: hostFd, accessMode: accessMode, readOnlySource: dirFd.readOnly
            ))
        }
    }

    func createStdioFile(fd: FileDescriptor, accessMode: FileAccessMode) -> any WASIFile {
        return StdioFileEntry(fd: fd, accessMode: accessMode)
    }
}
