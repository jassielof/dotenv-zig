//! Set of errors for the library.

/// Parse/serialization errors specific to dotenv processing.
pub const DotEnvError = error{
    UnterminatedString,
    InvalidKeyCharacter,
    InvalidEscapeSequence,
    UndefinedVariable,
    MissingEquals,
    EmptyKey,
    EnvironmentMutationFailed,
};
