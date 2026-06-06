/// The two one-time-password flavours defined by the OATH specifications.
enum OTPType {
  /// Time-based OTP (RFC 6238) — codes change every fixed time interval.
  TOTP,

  /// HMAC-based OTP (RFC 4226) — codes advance with an explicit counter.
  HOTP,
}
