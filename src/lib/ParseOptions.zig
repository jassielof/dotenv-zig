//! Options for parsing dotenv input.
const errors = @import("errors.zig");
const enums = @import("enums.zig");

/// Enables `$VAR` and `${VAR}` interpolation in unquoted and double-quoted values.
interpolate: bool = true,
/// On undefined interpolation target, either return an error or substitute empty string.
undefined_variable_behavior: enums.UndefinedVariableBehavior = .@"error",
/// Controls behavior when an unknown escape sequence appears in double quotes.
invalid_escape_behavior: enums.InvalidEscapeBehavior = .@"error",
