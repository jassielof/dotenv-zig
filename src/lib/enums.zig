/// Controls behavior when interpolating an undefined variable.
pub const UndefinedVariableBehavior = enum {
    @"error",
    empty_string,
};

/// Controls behavior for unknown escape sequences in double-quoted values.
pub const InvalidEscapeBehavior = enum {
    @"error",
    passthrough,
};

/// Quoting modes for serialization.
pub const QuoteStyle = enum {
    auto,
    unquoted,
    single,
    double,
};

pub const ValueMode = enum {
    none,
    unquoted,
    double_quoted,
    single_quoted,
};

pub const ParserState = enum {
    start,
    in_comment,
    in_key,
    pre_value,
    in_unquoted_value,
    in_double_quoted_value,
    in_single_quoted_value,
    in_escape,
    in_interpolation,
};

pub const InterpolationReturnState = enum {
    in_unquoted_value,
    in_double_quoted_value,
};
