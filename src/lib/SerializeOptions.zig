const enums = @import("enums.zig");

/// Options for serializing dotenv content.
pub const SerializeOptions = @This();
/// Optional comment written as the first line as `# <header_comment>`.
header_comment: ?[]const u8 = null,
/// When true, writes `# generated_at_unix=<timestamp>` as the first line.
include_timestamp_header: bool = false,
/// Overrides auto-quoting behavior when not `.auto`.
quote_style: enums.QuoteStyle = .auto,
