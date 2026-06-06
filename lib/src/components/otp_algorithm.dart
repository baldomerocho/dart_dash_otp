/// HMAC hash algorithms supported when deriving one-time passwords.
///
/// SHA-1 is the RFC 4226 / RFC 6238 default and the only algorithm that
/// every authenticator app is guaranteed to support; pick one of the
/// SHA-2 family members only when the verifying server documents support
/// for it.
// Cases intentionally stay in SCREAMING_CASE to preserve backward
// compatibility with published 1.x consumers.
enum OTPAlgorithm {
  /// HMAC-SHA-1 — the specification default, universally supported.
  SHA1,

  /// HMAC-SHA-256.
  SHA256,

  /// HMAC-SHA-384.
  SHA384,

  /// HMAC-SHA-512.
  SHA512,
}
