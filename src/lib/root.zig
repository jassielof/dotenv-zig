//! Dot env loading and parsing.
const std = @import("std");

const Allocator = std.mem.Allocator;

pub const DotEnv = @import("DotEnv.zig");
pub const ParseOptions = @import("ParseOptions.zig");

const enums = @import("enums.zig");
pub const UndefinedVariableBehavior = enums.UndefinedVariableBehavior;
pub const InvalidEscapeBehavior = enums.InvalidEscapeBehavior;
pub const QuoteStyle = enums.QuoteStyle;

const errors = @import("errors.zig");
pub const DotEnvError = errors.DotEnvError;

/// Controls how the default loader discovers a dotenv file.
pub const LoadStrategy = enum {
    /// Try current file directory (if provided), then cwd, then project root.
    auto,
    /// Search from the directory containing `current_file_path`.
    current_file,
    /// Search from the process working directory.
    working_directory,
    /// Search from detected project root (via marker files/dirs).
    project_directory,
};

/// Options for default dotenv file discovery/loading.
pub const LoadOptions = struct {
    /// Dotenv filename to discover.
    filename: []const u8 = ".env",
    /// Parse options forwarded to parser.
    parse_options: ParseOptions = .{},
    /// Discovery strategy.
    strategy: LoadStrategy = .auto,
    /// Current source file path (caller-provided), used by `.auto` and `.current_file`.
    current_file_path: ?[]const u8 = null,
    /// Files/dirs used to detect project root while traversing upward.
    project_markers: []const []const u8 = &.{ ".git", "build.zig", "build.zig.zon" },
};

/// Load dotenv using default auto-discovery, similar to Rust/Go ergonomics.
///
/// Search order:
/// 1. directory of `current_file_path` (if provided)
/// 2. process working directory
/// 3. detected project root
pub fn dotenv(allocator: Allocator) !DotEnv {
    return load(allocator, .{});
}

/// Load dotenv file using discovery options.
pub fn load(allocator: Allocator, options: LoadOptions) !DotEnv {
    const found = try discoverDotEnvPath(allocator, options);
    defer allocator.free(found);
    return parseFromPath(allocator, found, options.parse_options);
}

/// Parse dotenv content from an in-memory string.
pub fn parseFromSlice(allocator: Allocator, input: []const u8, options: ParseOptions) !DotEnv {
    return DotEnv.parseFromSlice(allocator, input, options);
}

/// Parse dotenv content from file path.
pub fn parseFromPath(
    /// The allocator
    allocator: Allocator,
    /// The path to the dotenv file
    path: []const u8,
    /// Parsing options
    options: ParseOptions,
) !DotEnv {
    return DotEnv.parseFromPath(allocator, path, options);
}

fn discoverDotEnvPath(allocator: Allocator, options: LoadOptions) ![]u8 {
    switch (options.strategy) {
        .auto => {
            if (options.current_file_path) |file_path| {
                if (try searchFromFilePath(allocator, file_path, options.filename)) |match| {
                    return match;
                }
            }

            if (try searchFromWorkingDirectory(allocator, options.filename)) |match| {
                return match;
            }

            if (try searchFromProjectDirectory(allocator, options.filename, options.project_markers)) |match| {
                return match;
            }
        },
        .current_file => {
            const file_path = options.current_file_path orelse return error.FileNotFound;
            if (try searchFromFilePath(allocator, file_path, options.filename)) |match| {
                return match;
            }
        },
        .working_directory => {
            if (try searchFromWorkingDirectory(allocator, options.filename)) |match| {
                return match;
            }
        },
        .project_directory => {
            if (try searchFromProjectDirectory(allocator, options.filename, options.project_markers)) |match| {
                return match;
            }
        },
    }

    return error.FileNotFound;
}

fn searchFromFilePath(allocator: Allocator, file_path: []const u8, filename: []const u8) !?[]u8 {
    const dir = std.fs.path.dirname(file_path) orelse ".";
    return searchUpwardForFile(allocator, dir, filename);
}

fn searchFromWorkingDirectory(allocator: Allocator, filename: []const u8) !?[]u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);
    return searchUpwardForFile(allocator, cwd, filename);
}

fn searchFromProjectDirectory(allocator: Allocator, filename: []const u8, markers: []const []const u8) !?[]u8 {
    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const project_dir = (try findProjectDir(allocator, cwd, markers)) orelse return null;
    defer allocator.free(project_dir);

    const candidate = try std.fs.path.join(allocator, &.{ project_dir, filename });
    errdefer allocator.free(candidate);
    if (try pathExists(candidate)) {
        return candidate;
    }
    allocator.free(candidate);
    return null;
}

fn searchUpwardForFile(allocator: Allocator, start_dir: []const u8, filename: []const u8) !?[]u8 {
    var current = try allocator.dupe(u8, start_dir);
    defer allocator.free(current);

    while (true) {
        const candidate = try std.fs.path.join(allocator, &.{ current, filename });
        if (try pathExists(candidate)) {
            return candidate;
        }
        allocator.free(candidate);

        const maybe_parent = std.fs.path.dirname(current);
        if (maybe_parent == null) return null;
        const parent = maybe_parent.?;
        if (parent.len == current.len) return null;

        const next = try allocator.dupe(u8, parent);
        allocator.free(current);
        current = next;
    }
}

fn findProjectDir(allocator: Allocator, start_dir: []const u8, markers: []const []const u8) !?[]u8 {
    var current = try allocator.dupe(u8, start_dir);
    defer allocator.free(current);

    while (true) {
        for (markers) |marker| {
            const marker_path = try std.fs.path.join(allocator, &.{ current, marker });
            defer allocator.free(marker_path);
            if (try pathExists(marker_path)) {
                return try allocator.dupe(u8, current);
            }
        }

        const maybe_parent = std.fs.path.dirname(current);
        if (maybe_parent == null) return null;
        const parent = maybe_parent.?;
        if (parent.len == current.len) return null;

        const next = try allocator.dupe(u8, parent);
        allocator.free(current);
        current = next;
    }
}

fn pathExists(path: []const u8) !bool {
    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}
