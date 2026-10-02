import Foundation

public struct XCFrameworkBuildRequest: Sendable {
    public let sourceLibraryURL: URL
    public let iosDeviceSourceLibraryURL: URL?
    public let iosSimulatorSourceLibraryURL: URL?
    public let macCatalystSourceLibraryURL: URL?
    public let headersDirectoryURL: URL
    public let outputDirectoryURL: URL
    public let outputLibraryName: String
    public let xcframeworkName: String
    public let moduleName: String?
    public let umbrellaHeader: String?
    public let macCatalystMinimumVersion: String
    public let macCatalystSDKVersion: String

    public init(
        sourceLibraryURL: URL,
        iosDeviceSourceLibraryURL: URL? = nil,
        iosSimulatorSourceLibraryURL: URL? = nil,
        macCatalystSourceLibraryURL: URL? = nil,
        headersDirectoryURL: URL,
        outputDirectoryURL: URL,
        outputLibraryName: String,
        xcframeworkName: String,
        moduleName: String? = nil,
        umbrellaHeader: String? = nil,
        macCatalystMinimumVersion: String,
        macCatalystSDKVersion: String
    ) {
        self.sourceLibraryURL = sourceLibraryURL
        self.iosDeviceSourceLibraryURL = iosDeviceSourceLibraryURL
        self.iosSimulatorSourceLibraryURL = iosSimulatorSourceLibraryURL
        self.macCatalystSourceLibraryURL = macCatalystSourceLibraryURL
        self.headersDirectoryURL = headersDirectoryURL
        self.outputDirectoryURL = outputDirectoryURL
        self.outputLibraryName = outputLibraryName
        self.xcframeworkName = xcframeworkName
        self.moduleName = moduleName
        self.umbrellaHeader = umbrellaHeader
        self.macCatalystMinimumVersion = macCatalystMinimumVersion
        self.macCatalystSDKVersion = macCatalystSDKVersion
    }
}

public final class XCFrameworkBuildTool {
    private let fileManager: FileManager
    private let toolLocator: XCFrameworkDeveloperToolLocator

    public init(fileManager: FileManager = .default, toolLocator: XCFrameworkDeveloperToolLocator = .init()) {
        self.fileManager = fileManager
        self.toolLocator = toolLocator
    }

    public func build(
        request: XCFrameworkBuildRequest,
        outputHandler: @escaping @Sendable (String) -> Void = { _ in }
    ) throws -> URL {
        let scriptURL = try writeScript()
        defer { try? fileManager.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = makeArguments(scriptURL: scriptURL, request: request)
        process.environment = try makeEnvironment()
        process.standardOutput = stdout
        process.standardError = stderr

        let collector = XCFrameworkBuildOutputCollector()
        let appendOutput: @Sendable (Data) -> Void = { data in
            guard let text = String(data: data, encoding: .utf8), text.isEmpty == false else { return }
            collector.append(text)
            outputHandler(text)
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            appendOutput(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            appendOutput(handle.availableData)
        }

        try process.run()
        process.waitUntilExit()

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        appendOutput(stdout.fileHandleForReading.readDataToEndOfFile())
        appendOutput(stderr.fileHandleForReading.readDataToEndOfFile())

        let output = collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationReason == .exit, process.terminationStatus == 0 {
            if let outputPath = output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .last(where: { $0.hasSuffix(".xcframework") })
                .map({ URL(fileURLWithPath: $0) }) {
                return outputPath
            }

            let fallbackURL = request.outputDirectoryURL.appendingPathComponent(request.xcframeworkName)
            if fileManager.fileExists(atPath: fallbackURL.path) {
                return fallbackURL
            }

            throw NSError(
                domain: "MachOKnife.XCFrameworkBuild",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Build completed, but no XCFramework output path was reported."]
            )
        }

        throw NSError(
            domain: "MachOKnife.XCFrameworkBuild",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "XCFramework build failed." : output]
        )
    }

    private func makeArguments(scriptURL: URL, request: XCFrameworkBuildRequest) -> [String] {
        var arguments = [scriptURL.path]
        arguments += ["--source-library", request.sourceLibraryURL.path]
        if let iosDeviceSourceLibraryURL = request.iosDeviceSourceLibraryURL {
            arguments += ["--ios-device-source-library", iosDeviceSourceLibraryURL.path]
        }
        if let iosSimulatorSourceLibraryURL = request.iosSimulatorSourceLibraryURL {
            arguments += ["--ios-simulator-source-library", iosSimulatorSourceLibraryURL.path]
        }
        if let macCatalystSourceLibraryURL = request.macCatalystSourceLibraryURL {
            arguments += ["--maccatalyst-source-library", macCatalystSourceLibraryURL.path]
        }
        arguments += ["--headers-dir", request.headersDirectoryURL.path]
        arguments += ["--output-dir", request.outputDirectoryURL.path]
        arguments += ["--output-library-name", request.outputLibraryName]
        arguments += ["--xcframework-name", request.xcframeworkName]
        arguments += ["--maccatalyst-min-version", request.macCatalystMinimumVersion]
        arguments += ["--maccatalyst-sdk-version", request.macCatalystSDKVersion]
        if let moduleName = request.moduleName, moduleName.isEmpty == false {
            arguments += ["--module-name", moduleName]
        }
        if let umbrellaHeader = request.umbrellaHeader, umbrellaHeader.isEmpty == false {
            arguments += ["--umbrella-header", umbrellaHeader]
        }
        return arguments
    }

    private func makeEnvironment() throws -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["MACHOKNIFE_LIPO"] = try toolLocator.path(named: "lipo")
        environment["MACHOKNIFE_LIBTOOL"] = try toolLocator.path(named: "libtool")
        environment["MACHOKNIFE_AR"] = try toolLocator.path(named: "ar")
        environment["MACHOKNIFE_XCODEBUILD"] = try toolLocator.path(named: "xcodebuild")
        if let developerDirectory = try? toolLocator.selectedDeveloperDirectory() {
            environment["DEVELOPER_DIR"] = developerDirectory.path
        }
        return environment
    }

    private func writeScript() throws -> URL {
        // A unique directory per build keeps concurrent builds (app + CLI, or two windows) from
        // overwriting each other's script; `build` removes it when it finishes.
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("machoknife-xcframework-builder-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("build_static_sdk_xcframework.py")
        try Self.scriptSource.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }

    /// The Python build script, shared with the app's cancellable build service.
    public static let scriptSource = #"""
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
MH_OBJECT = 0x1
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
LC_DYSYMTAB = 0xB
LC_VERSION_MIN_IPHONEOS = 0x25
LC_BUILD_VERSION = 0x32
LINKEDIT_DATA_COMMANDS = {0x1D, 0x1E, 0x26, 0x29, 0x2B, 0x2E, 0x34, 0x35}
PLATFORM_IOSSIMULATOR = 7
PLATFORM_MACCATALYST = 6
TOOL_LD = 3
ARM64_SIMULATOR_MIN_VERSION = "14.0"
LIPO = os.environ.get("MACHOKNIFE_LIPO", "lipo")
LIBTOOL = os.environ.get("MACHOKNIFE_LIBTOOL", "libtool")
AR = os.environ.get("MACHOKNIFE_AR", "ar")
XCODEBUILD = os.environ.get("MACHOKNIFE_XCODEBUILD", "xcodebuild")

def run(cmd: list[str], *, cwd: Path | None = None) -> None:
    subprocess.run(cmd, cwd=cwd, check=True)

def capture(cmd: list[str], *, cwd: Path | None = None) -> str:
    return subprocess.check_output(cmd, cwd=cwd, text=True)

def list_arches(library: Path) -> list[str]:
    return capture([LIPO, "-archs", str(library)]).strip().split()

def encode_version(version: str) -> int:
    parts = [int(part) for part in version.split(".")]
    while len(parts) < 3:
        parts.append(0)
    major, minor, patch = parts[:3]
    return (major << 16) | (minor << 8) | patch

def sort_arches(arches: list[str]) -> list[str]:
    order = {"arm64": 0, "arm64e": 1, "x86_64": 2, "i386": 3, "armv7": 4}
    return sorted(arches, key=lambda arch: (order.get(arch, 99), arch))

def patch_u32(blob: bytearray, offset: int, delta: int) -> None:
    value = struct.unpack_from("<I", blob, offset)[0]
    if value != 0:
        struct.pack_into("<I", blob, offset, value + delta)

def patch_u64(blob: bytearray, offset: int, delta: int) -> None:
    value = struct.unpack_from("<Q", blob, offset)[0]
    if value != 0:
        struct.pack_into("<Q", blob, offset, value + delta)

def patch_object_platform(src: Path, dst: Path, *, target_platform: int, min_version: str | None = None, sdk_version: str | None = None, min_version_floor: str | None = None) -> bool:
    """Retags a 64-bit MH_OBJECT. Members that are not such objects, or that carry no
    version load command, are copied unchanged and False is returned."""
    data = bytearray(src.read_bytes())
    if len(data) < 32:
        shutil.copy2(src, dst)
        return False
    magic, _, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != MH_MAGIC_64 or filetype != MH_OBJECT:
        shutil.copy2(src, dst)
        return False
    if 32 + sizeofcmds > len(data):
        raise ValueError(f"{src} has load commands beyond the end of the file")

    cmd_offset = 32
    version_cmd_offset = None
    version_cmd_size = None
    version_cmd_kind = None
    for _ in range(ncmds):
        if cmd_offset + 8 > 32 + sizeofcmds:
            raise ValueError(f"{src} has a truncated load command")
        cmd, cmdsize = struct.unpack_from("<II", data, cmd_offset)
        if cmdsize < 8 or cmd_offset + cmdsize > 32 + sizeofcmds:
            raise ValueError(f"{src} has a malformed load command")
        if cmd == LC_VERSION_MIN_IPHONEOS:
            version_cmd_offset = cmd_offset
            version_cmd_size = cmdsize
            version_cmd_kind = LC_VERSION_MIN_IPHONEOS
            break
        if cmd == LC_BUILD_VERSION:
            version_cmd_offset = cmd_offset
            version_cmd_size = cmdsize
            version_cmd_kind = LC_BUILD_VERSION
            break
        cmd_offset += cmdsize

    if version_cmd_offset is None:
        shutil.copy2(src, dst)
        return False

    def resolved_versions(source_minos: int, source_sdk: int) -> tuple[int, int]:
        minos = encode_version(min_version) if min_version else source_minos
        sdk = encode_version(sdk_version) if sdk_version else source_sdk
        if min_version_floor:
            floor = encode_version(min_version_floor)
            minos = max(minos, floor)
            sdk = max(sdk, minos)
        return minos, sdk

    if version_cmd_kind == LC_BUILD_VERSION:
        patched = bytearray(data)
        source_minos = struct.unpack_from("<I", patched, version_cmd_offset + 12)[0]
        source_sdk = struct.unpack_from("<I", patched, version_cmd_offset + 16)[0]
        minos, sdk = resolved_versions(source_minos, source_sdk)
        struct.pack_into("<I", patched, version_cmd_offset + 8, target_platform)
        struct.pack_into("<I", patched, version_cmd_offset + 12, minos)
        struct.pack_into("<I", patched, version_cmd_offset + 16, sdk)
        dst.write_bytes(patched)
        return True

    source_minos = struct.unpack_from("<I", data, version_cmd_offset + 8)[0]
    source_sdk = struct.unpack_from("<I", data, version_cmd_offset + 12)[0]
    minos, sdk = resolved_versions(source_minos, source_sdk)
    build_version_command = struct.pack("<IIIIIIII", LC_BUILD_VERSION, 32, target_platform, minos, sdk, 1, TOOL_LD, 0)
    delta = len(build_version_command) - version_cmd_size
    patched = bytearray()
    patched.extend(data[:version_cmd_offset])
    patched.extend(build_version_command)
    patched.extend(data[version_cmd_offset + version_cmd_size :])
    struct.pack_into("<I", patched, 20, sizeofcmds + delta)

    cmd_offset = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", patched, cmd_offset)
        if cmd == LC_SEGMENT_64:
            patch_u64(patched, cmd_offset + 40, delta)
            nsects = struct.unpack_from("<I", patched, cmd_offset + 64)[0]
            section_offset = cmd_offset + 72
            for _ in range(nsects):
                patch_u32(patched, section_offset + 48, delta)
                patch_u32(patched, section_offset + 56, delta)
                section_offset += 80
        elif cmd == LC_SYMTAB:
            patch_u32(patched, cmd_offset + 8, delta)
            patch_u32(patched, cmd_offset + 16, delta)
        elif cmd == LC_DYSYMTAB:
            for field_offset in (32, 40, 48, 56, 64, 72):
                patch_u32(patched, cmd_offset + field_offset, delta)
        elif cmd in LINKEDIT_DATA_COMMANDS:
            patch_u32(patched, cmd_offset + 8, delta)
        cmd_offset += cmdsize

    dst.write_bytes(patched)
    return True

def read_archive_members(library: Path) -> list[tuple[str, bytes]]:
    """Returns (name, payload) for every member of a thin `ar` archive, in order, skipping the
    symbol table. Handles BSD `#1/<len>` long names; duplicate names are preserved."""
    data = library.read_bytes()
    if not data.startswith(b"!<arch>\n"):
        raise ValueError(f"{library} is not a static archive")
    members: list[tuple[str, bytes]] = []
    offset = 8
    while offset + 60 <= len(data):
        header = data[offset : offset + 60]
        if header[58:60] != b"`\n":
            raise ValueError(f"{library} has a malformed member header at offset {offset}")
        raw_name = header[0:16].decode("ascii", errors="replace").rstrip(" ")
        size = int(header[48:58].decode("ascii").strip() or "0")
        body_start = offset + 60
        body_end = body_start + size
        if body_end > len(data):
            raise ValueError(f"{library} has a truncated member at offset {offset}")
        if raw_name.startswith("#1/"):
            name_length = int(raw_name[3:])
            name = data[body_start : body_start + name_length].split(b"\0", 1)[0].decode("utf-8", errors="replace")
            payload = data[body_start + name_length : body_end]
        else:
            name = raw_name.rstrip("/")
            payload = data[body_start:body_end]
        if not name.startswith("__.SYMDEF"):
            members.append((Path(name).name or f"member-{len(members)}.o", payload))
        offset = body_end + (body_end & 1)
    return members

def thin_archive(source_library: Path, arch: str, output_library: Path) -> None:
    output_library.parent.mkdir(parents=True, exist_ok=True)
    if output_library.exists():
        output_library.unlink()
    arches = list_arches(source_library)
    if len(arches) == 1 and arches[0] == arch:
        shutil.copy2(source_library, output_library)
        return
    run([LIPO, str(source_library), "-thin", arch, "-output", str(output_library)])

def combine_libraries(input_libraries: list[Path], output_library: Path) -> bool:
    if not input_libraries:
        return False
    output_library.parent.mkdir(parents=True, exist_ok=True)
    if output_library.exists():
        output_library.unlink()
    if len(input_libraries) == 1:
        shutil.copy2(input_libraries[0], output_library)
    else:
        run([LIPO, "-create", *[str(path) for path in input_libraries], "-output", str(output_library)])
    return True

def build_library_from_arches(source_library: Path, arches: list[str], output_library: Path) -> bool:
    if not arches:
        return False
    with tempfile.TemporaryDirectory(prefix="fat_library_") as temp_dir:
        temp_path = Path(temp_dir)
        thin_outputs: list[Path] = []
        for arch in arches:
            thin_output = temp_path / f"{arch}.a"
            thin_archive(source_library, arch, thin_output)
            thin_outputs.append(thin_output)
        return combine_libraries(thin_outputs, output_library)

def build_patched_archive(source_library: Path, arch: str, output_library: Path, *, target_platform: int, min_version: str | None = None, sdk_version: str | None = None, min_version_floor: str | None = None) -> None:
    output_library.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f"static_sdk_{arch}_") as temp_dir:
        temp_path = Path(temp_dir)
        thin_library = temp_path / f"input-{arch}.a"
        extracted_dir = temp_path / "members"
        patched_dir = temp_path / "patched"
        extracted_dir.mkdir()
        patched_dir.mkdir()
        thin_archive(source_library, arch, thin_library)
        patched_members: list[str] = []
        # Each member gets its own directory: archives may hold several members with the same
        # name, which `ar -x` would collapse into one file. libtool names members by basename.
        for index, (member_name, payload) in enumerate(read_archive_members(thin_library)):
            source_member = extracted_dir / str(index) / member_name
            patched_member = patched_dir / str(index) / member_name
            source_member.parent.mkdir(parents=True)
            patched_member.parent.mkdir(parents=True)
            source_member.write_bytes(payload)
            patch_object_platform(source_member, patched_member, target_platform=target_platform, min_version=min_version, sdk_version=sdk_version, min_version_floor=min_version_floor)
            patched_members.append(str(patched_member))
        if not patched_members:
            raise ValueError(f"{source_library} ({arch}) contains no archive members")
        if output_library.exists():
            output_library.unlink()
        run([LIBTOOL, "-static", "-o", str(output_library), *patched_members])

def prepare_headers(source_headers_dir: Path, output_headers_dir: Path, *, umbrella_header_name: str | None, module_name: str | None) -> None:
    if output_headers_dir.exists():
        shutil.rmtree(output_headers_dir)
    output_headers_dir.mkdir(parents=True)
    headers_root_dir = output_headers_dir / module_name if module_name else output_headers_dir
    for source_path in source_headers_dir.rglob("*"):
        if not source_path.is_file() or source_path.suffix not in {".h", ".modulemap"}:
            continue
        relative_path = source_path.relative_to(source_headers_dir)
        destination_path = (output_headers_dir / relative_path) if source_path.suffix == ".modulemap" else (headers_root_dir / relative_path)
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination_path)
    if module_name and not umbrella_header_name:
        umbrella_header_name = f"{module_name}.h"
    if umbrella_header_name and module_name:
        headers_root_dir.mkdir(parents=True, exist_ok=True)
        umbrella_header_path = headers_root_dir / umbrella_header_name
        if not umbrella_header_path.exists():
            header_imports = []
            for header_path in sorted(headers_root_dir.glob("*.h")):
                if header_path.name != umbrella_header_name:
                    header_imports.append(f'#import <{module_name}/{header_path.name}>\n')
            umbrella_header_path.write_text("".join(header_imports), encoding="utf-8")
        # Clang discovers `<search path>/<Module>/module.modulemap`, and the umbrella header path
        # is resolved relative to the module map's directory.
        # A module map shipped with the headers wins over the generated one.
        modulemap_path = headers_root_dir / "module.modulemap"
        if not modulemap_path.exists():
            modulemap_path.write_text(
                f'module {module_name} {{\n  umbrella header "{umbrella_header_name}"\n  export *\n}}\n',
                encoding="utf-8",
            )

PLATFORM_IOS = 2

def object_platform(payload: bytes, arch: str) -> int | None:
    if len(payload) < 32:
        return None
    magic, _, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<IiiIIIII", payload, 0)
    if magic != MH_MAGIC_64 or filetype != MH_OBJECT or 32 + sizeofcmds > len(payload):
        return None
    cmd_offset = 32
    for _ in range(ncmds):
        if cmd_offset + 8 > 32 + sizeofcmds:
            return None
        cmd, cmdsize = struct.unpack_from("<II", payload, cmd_offset)
        if cmdsize < 8:
            return None
        if cmd == LC_BUILD_VERSION and cmd_offset + 12 <= len(payload):
            return struct.unpack_from("<I", payload, cmd_offset + 8)[0]
        if cmd == LC_VERSION_MIN_IPHONEOS:
            # The legacy command does not name the simulator; Intel slices can only be simulator code.
            return PLATFORM_IOSSIMULATOR if arch == "x86_64" else PLATFORM_IOS
        cmd_offset += cmdsize
    return None

def archive_platform(source_library: Path, arch: str) -> int | None:
    """The platform recorded by the first object in the `arch` slice, if any."""
    with tempfile.TemporaryDirectory(prefix=f"platform_{arch}_") as temp_dir:
        thin_library = Path(temp_dir) / f"{arch}.a"
        thin_archive(source_library, arch, thin_library)
        for _, payload in read_archive_members(thin_library):
            platform = object_platform(payload, arch)
            if platform is not None:
                return platform
    return None

def detect_simulator_arches(simulator_source_library: Path, device_source_library: Path) -> list[str]:
    """Arches of the simulator input that already are simulator code. When the simulator input
    is the device library itself, an arm64 slice is device code and must be retagged instead."""
    arches = detect_arches(simulator_source_library, ["arm64", "x86_64"])
    shared_input = simulator_source_library == device_source_library
    native: list[str] = []
    for arch in arches:
        platform = archive_platform(simulator_source_library, arch)
        if platform == PLATFORM_IOSSIMULATOR or (platform is None and not shared_input) or (platform is None and arch == "x86_64"):
            native.append(arch)
    return native

def detect_arches(source_library: Path, preferred_arches: list[str]) -> list[str]:
    available_arches = set(list_arches(source_library))
    return sort_arches([arch for arch in preferred_arches if arch in available_arches])

def build_xcframework(args: argparse.Namespace) -> Path:
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    xcframework_dir = output_dir / args.xcframework_name
    # Intermediate libraries and headers live in a private scratch directory so nothing the
    # user keeps next to the output (for example an existing `Headers` folder) is touched.
    with tempfile.TemporaryDirectory(prefix="machoknife_xcframework_") as scratch:
        scratch_dir = Path(scratch)
        staged_xcframework_dir = scratch_dir / args.xcframework_name
        build_xcframework_slices(args, scratch_dir / "artifacts", scratch_dir / "Headers", staged_xcframework_dir)
        if xcframework_dir.is_symlink() or xcframework_dir.is_file():
            xcframework_dir.unlink()
        elif xcframework_dir.exists():
            shutil.rmtree(xcframework_dir)
        shutil.move(str(staged_xcframework_dir), str(xcframework_dir))
    return xcframework_dir

def build_xcframework_slices(args: argparse.Namespace, artifacts_dir: Path, prepared_headers_dir: Path, xcframework_dir: Path) -> None:
    ios_device_source_library = Path(args.ios_device_source_library or args.source_library).resolve()
    ios_simulator_source_library = Path(args.ios_simulator_source_library or args.source_library).resolve()
    maccatalyst_source_library = Path(args.maccatalyst_source_library).resolve() if args.maccatalyst_source_library else None
    headers_dir = args.headers_dir.resolve()
    artifacts_dir.mkdir(parents=True)

    ios_device_arches = detect_arches(ios_device_source_library, ["arm64"])
    ios_simulator_native_arches = detect_simulator_arches(ios_simulator_source_library, ios_device_source_library)
    ios_simulator_retag_arches = [arch for arch in detect_arches(ios_device_source_library, ["arm64"]) if arch not in ios_simulator_native_arches]
    catalyst_device_arches = detect_arches(ios_device_source_library, ["arm64"])
    catalyst_simulator_arches = detect_arches(ios_simulator_source_library, ["x86_64"])

    ios_device_library = artifacts_dir / "ios-arm64" / args.output_library_name
    build_library_from_arches(ios_device_source_library, ios_device_arches, ios_device_library)

    ios_simulator_outputs: list[tuple[str, Path]] = []
    for arch in ios_simulator_native_arches:
        output_path = artifacts_dir / f"ios-{arch}-simulator-native" / f"{arch}-{args.output_library_name}"
        build_library_from_arches(ios_simulator_source_library, [arch], output_path)
        ios_simulator_outputs.append((arch, output_path))
    for arch in ios_simulator_retag_arches:
        output_path = artifacts_dir / f"ios-{arch}-simulator-retagged" / f"{arch}-{args.output_library_name}"
        # The arm64 iOS simulator only exists from iOS 14.0 on; older deployment targets fail to link.
        build_patched_archive(ios_device_source_library, arch, output_path, target_platform=PLATFORM_IOSSIMULATOR, min_version_floor=ARM64_SIMULATOR_MIN_VERSION if arch == "arm64" else None)
        ios_simulator_outputs.append((arch, output_path))

    ios_simulator_library = None
    if ios_simulator_outputs:
        ordered_arches = sort_arches([arch for arch, _ in ios_simulator_outputs])
        ios_simulator_library = artifacts_dir / f"ios-{'_'.join(ordered_arches)}-simulator" / args.output_library_name
        combine_libraries([path for arch in ordered_arches for output_arch, path in ios_simulator_outputs if output_arch == arch], ios_simulator_library)

    catalyst_library = None
    if maccatalyst_source_library:
        catalyst_arches = detect_arches(maccatalyst_source_library, ["arm64", "arm64e", "x86_64"])
        if catalyst_arches:
            catalyst_library = artifacts_dir / f"ios-{'_'.join(catalyst_arches)}-maccatalyst" / args.output_library_name
            build_library_from_arches(maccatalyst_source_library, catalyst_arches, catalyst_library)
    else:
        catalyst_outputs: list[Path] = []
        for arch in catalyst_device_arches:
            output_path = artifacts_dir / f"ios-{arch}-maccatalyst" / f"{arch}-{args.output_library_name}"
            build_patched_archive(ios_device_source_library, arch, output_path, target_platform=PLATFORM_MACCATALYST, min_version=args.maccatalyst_min_version, sdk_version=args.maccatalyst_sdk_version)
            catalyst_outputs.append(output_path)
        for arch in catalyst_simulator_arches:
            output_path = artifacts_dir / f"ios-{arch}-simulator-maccatalyst" / f"{arch}-{args.output_library_name}"
            build_patched_archive(ios_simulator_source_library, arch, output_path, target_platform=PLATFORM_MACCATALYST, min_version=args.maccatalyst_min_version, sdk_version=args.maccatalyst_sdk_version)
            catalyst_outputs.append(output_path)

        if catalyst_outputs:
            catalyst_library = artifacts_dir / "ios-arm64_x86_64-maccatalyst" / args.output_library_name
            combine_libraries(catalyst_outputs, catalyst_library)

    prepare_headers(headers_dir, prepared_headers_dir, umbrella_header_name=args.umbrella_header, module_name=args.module_name)

    command = [XCODEBUILD, "-create-xcframework"]
    if ios_device_library.exists():
        command.extend(["-library", str(ios_device_library), "-headers", str(prepared_headers_dir)])
    if ios_simulator_library and ios_simulator_library.exists():
        command.extend(["-library", str(ios_simulator_library), "-headers", str(prepared_headers_dir)])
    if catalyst_library and catalyst_library.exists():
        command.extend(["-library", str(catalyst_library), "-headers", str(prepared_headers_dir)])
    command.extend(["-output", str(xcframework_dir)])
    run(command)

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build an XCFramework from a static iOS SDK library with optional retagged simulator and Mac Catalyst slices.")
    parser.add_argument("--source-library", type=Path, required=True)
    parser.add_argument("--ios-device-source-library", type=Path, default=None)
    parser.add_argument("--ios-simulator-source-library", type=Path, default=None)
    parser.add_argument("--maccatalyst-source-library", type=Path, default=None)
    parser.add_argument("--headers-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--output-library-name", default="libSDK.a")
    parser.add_argument("--xcframework-name", default="SDK.xcframework")
    parser.add_argument("--module-name", default=None)
    parser.add_argument("--umbrella-header", default=None)
    parser.add_argument("--maccatalyst-min-version", default="13.1")
    parser.add_argument("--maccatalyst-sdk-version", default="17.5")
    return parser.parse_args()

def is_valid_xcframework_name(name: str) -> bool:
    return (
        bool(name)
        and "/" not in name
        and not name.startswith(".")
        and name.endswith(".xcframework")
        and len(name) > len(".xcframework")
    )

def handle_termination(signum, frame) -> None:
    # Raise SystemExit so `with`/`finally` blocks remove the scratch directory.
    raise SystemExit(128 + signum)

def main() -> int:
    if os.environ.get("MACHOKNIFE_OWN_PROCESS_GROUP") == "1":
        # The app cancels a build by signalling this process group, which then also reaches the
        # xcodebuild/libtool/lipo children. Terminal callers keep the default so Ctrl-C works.
        try:
            os.setpgid(0, 0)
        except OSError:
            pass
    signal.signal(signal.SIGTERM, handle_termination)
    args = parse_args()
    if not is_valid_xcframework_name(args.xcframework_name):
        print(f"invalid xcframework name (expected a plain name ending in .xcframework): {args.xcframework_name}", file=sys.stderr)
        return 2
    if not args.source_library.exists():
        print(f"source library not found: {args.source_library}", file=sys.stderr)
        return 1
    if args.ios_device_source_library and not Path(args.ios_device_source_library).exists():
        print(f"ios device source library not found: {args.ios_device_source_library}", file=sys.stderr)
        return 1
    if args.ios_simulator_source_library and not Path(args.ios_simulator_source_library).exists():
        print(f"ios simulator source library not found: {args.ios_simulator_source_library}", file=sys.stderr)
        return 1
    if args.maccatalyst_source_library and not Path(args.maccatalyst_source_library).exists():
        print(f"mac catalyst source library not found: {args.maccatalyst_source_library}", file=sys.stderr)
        return 1
    if not args.headers_dir.exists():
        print(f"headers dir not found: {args.headers_dir}", file=sys.stderr)
        return 1
    xcframework_dir = build_xcframework(args)
    print(xcframework_dir)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
"""#
}

public struct XCFrameworkDeveloperToolLocator {
    public init() {}

    public func path(named tool: String) throws -> String {
        let candidates = candidatePaths(for: tool)
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        throw NSError(
            domain: "MachOKnife.XCFrameworkBuild",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate developer tool: \(tool)"]
        )
    }

    public func selectedDeveloperDirectory() throws -> URL {
        let result = try ToolProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["-p"]
        )

        guard result.succeeded else {
            throw NSError(
                domain: "MachOKnife.XCFrameworkBuild",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Unable to determine active developer directory."]
            )
        }

        let output = String(decoding: result.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.isEmpty == false else {
            throw NSError(
                domain: "MachOKnife.XCFrameworkBuild",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Unable to determine active developer directory."]
            )
        }
        return URL(fileURLWithPath: output, isDirectory: true)
    }

    private func candidatePaths(for tool: String) -> [String] {
        let developerRoots = preferredDeveloperRoots()
        let toolchainRelativePath = "Toolchains/XcodeDefault.xctoolchain/usr/bin/\(tool)"
        let developerRelativePath = "usr/bin/\(tool)"

        return developerRoots.flatMap { root in
            [
                root.appendingPathComponent(toolchainRelativePath).path,
                root.appendingPathComponent(developerRelativePath).path,
            ]
        } + ["/usr/bin/\(tool)", "/bin/\(tool)"]
    }

    private func preferredDeveloperRoots() -> [URL] {
        Self.orderedDeveloperRoots(selected: try? selectedDeveloperDirectory())
    }

    /// The active developer directory first, then the default Xcode location, without duplicates.
    /// The order matters: tools are resolved from the first root that provides them.
    static func orderedDeveloperRoots(selected: URL?) -> [URL] {
        let candidates = [
            selected,
            URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer", isDirectory: true),
        ].compactMap { $0?.standardizedFileURL }

        var seenPaths = Set<String>()
        return candidates.filter { seenPaths.insert($0.path).inserted }
    }
}

private final class XCFrameworkBuildOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ text: String) {
        lock.lock()
        storage += text
        lock.unlock()
    }

    var value: String {
        lock.lock()
        let value = storage
        lock.unlock()
        return value
    }
}
