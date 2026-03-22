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
        let directory = fileManager.temporaryDirectory.appendingPathComponent("machoknife-cli-xcframework-builder", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("build_static_sdk_xcframework.py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }

    private let script = #"""
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
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

def patch_object_platform(src: Path, dst: Path, *, target_platform: int, min_version: str | None = None, sdk_version: str | None = None) -> None:
    data = bytearray(src.read_bytes())
    magic, _, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != MH_MAGIC_64 or filetype != MH_OBJECT:
        raise ValueError(f"{src} is not a 64-bit MH_OBJECT Mach-O")

    cmd_offset = 32
    version_cmd_offset = None
    version_cmd_size = None
    version_cmd_kind = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, cmd_offset)
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
        raise ValueError(f"{src} does not contain a supported version load command")

    if version_cmd_kind == LC_BUILD_VERSION:
        patched = bytearray(data)
        source_minos = struct.unpack_from("<I", patched, version_cmd_offset + 12)[0]
        source_sdk = struct.unpack_from("<I", patched, version_cmd_offset + 16)[0]
        struct.pack_into("<I", patched, version_cmd_offset + 8, target_platform)
        struct.pack_into("<I", patched, version_cmd_offset + 12, encode_version(min_version) if min_version else source_minos)
        struct.pack_into("<I", patched, version_cmd_offset + 16, encode_version(sdk_version) if sdk_version else source_sdk)
        dst.write_bytes(patched)
        return

    source_minos = struct.unpack_from("<I", data, version_cmd_offset + 8)[0]
    source_sdk = struct.unpack_from("<I", data, version_cmd_offset + 12)[0]
    build_version_command = struct.pack("<IIIIIIII", LC_BUILD_VERSION, 32, target_platform, encode_version(min_version) if min_version else source_minos, encode_version(sdk_version) if sdk_version else source_sdk, 1, TOOL_LD, 0)
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

def build_patched_archive(source_library: Path, arch: str, output_library: Path, *, target_platform: int, min_version: str | None = None, sdk_version: str | None = None) -> None:
    output_library.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f"static_sdk_{arch}_") as temp_dir:
        temp_path = Path(temp_dir)
        thin_library = temp_path / f"input-{arch}.a"
        extracted_dir = temp_path / "members"
        patched_dir = temp_path / "patched"
        extracted_dir.mkdir()
        patched_dir.mkdir()
        thin_archive(source_library, arch, thin_library)
        run([AR, "-x", str(thin_library)], cwd=extracted_dir)
        members = [member for member in capture([AR, "-t", str(thin_library)]).splitlines() if member and not member.startswith("__.SYMDEF")]
        patched_members: list[str] = []
        for member_name in members:
            source_member = extracted_dir / member_name
            patched_member = patched_dir / member_name
            if member_name.endswith(".o"):
                patch_object_platform(source_member, patched_member, target_platform=target_platform, min_version=min_version, sdk_version=sdk_version)
            else:
                shutil.copy2(source_member, patched_member)
            patched_members.append(member_name)
        if output_library.exists():
            output_library.unlink()
        run([LIBTOOL, "-static", "-o", str(output_library), *patched_members], cwd=patched_dir)

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
    if umbrella_header_name and module_name:
        umbrella_header_path = headers_root_dir / umbrella_header_name
        if not umbrella_header_path.exists():
            header_imports = []
            for header_path in sorted(headers_root_dir.glob("*.h")):
                if header_path.name != umbrella_header_name:
                    header_imports.append(f'#import <{module_name}/{header_path.name}>\\n')
            umbrella_header_path.write_text("".join(header_imports), encoding="utf-8")
        modules_dir = output_headers_dir / "Modules"
        modules_dir.mkdir(exist_ok=True)
        (modules_dir / "module.modulemap").write_text(
            f'module {module_name} {{\\n  umbrella header "{module_name}/{umbrella_header_name}"\\n  export *\\n}}\\n',
            encoding="utf-8",
        )

def detect_arches(source_library: Path, preferred_arches: list[str]) -> list[str]:
    available_arches = set(list_arches(source_library))
    return sort_arches([arch for arch in preferred_arches if arch in available_arches])

def build_xcframework(args: argparse.Namespace) -> Path:
    ios_device_source_library = Path(args.ios_device_source_library or args.source_library).resolve()
    ios_simulator_source_library = Path(args.ios_simulator_source_library or args.source_library).resolve()
    maccatalyst_source_library = Path(args.maccatalyst_source_library).resolve() if args.maccatalyst_source_library else None
    headers_dir = args.headers_dir.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    artifacts_dir = output_dir / "artifacts"
    prepared_headers_dir = output_dir / "Headers"
    xcframework_dir = output_dir / args.xcframework_name
    if artifacts_dir.exists():
        shutil.rmtree(artifacts_dir)
    artifacts_dir.mkdir(parents=True)

    ios_device_arches = detect_arches(ios_device_source_library, ["arm64"])
    ios_simulator_native_arches = detect_arches(ios_simulator_source_library, ["arm64", "x86_64"])
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
        build_patched_archive(ios_device_source_library, arch, output_path, target_platform=PLATFORM_IOSSIMULATOR)
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

    if xcframework_dir.exists():
        shutil.rmtree(xcframework_dir)
    command = [XCODEBUILD, "-create-xcframework"]
    if ios_device_library.exists():
        command.extend(["-library", str(ios_device_library), "-headers", str(prepared_headers_dir)])
    if ios_simulator_library and ios_simulator_library.exists():
        command.extend(["-library", str(ios_simulator_library), "-headers", str(prepared_headers_dir)])
    if catalyst_library and catalyst_library.exists():
        command.extend(["-library", str(catalyst_library), "-headers", str(prepared_headers_dir)])
    command.extend(["-output", str(xcframework_dir)])
    run(command)
    return xcframework_dir

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

def main() -> int:
    args = parse_args()
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MachOKnife.XCFrameworkBuild",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Unable to determine active developer directory."]
            )
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        var roots = [URL]()
        if let selected = try? selectedDeveloperDirectory() {
            roots.append(selected.deletingLastPathComponent())
            roots.append(selected)
        }
        roots.append(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer", isDirectory: true))
        return Array(Set(roots))
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
