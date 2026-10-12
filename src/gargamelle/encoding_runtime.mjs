// Validate text before JSON serialization so admission errors retain leaf paths.
// Type errors and operational exceptions propagate.
export const scalar = text => text.isWellFormed();
