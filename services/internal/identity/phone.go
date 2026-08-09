package identity

import "regexp"

// E.164 international phone number format: +[country code][subscriber number].
// Mirrors the client-side PhoneValidator (Task 2.4): 8–15 characters total,
// starting with '+', a country code of 1–4 digits beginning with 1-9, and a
// 6–14 digit subscriber number.
var e164Pattern = regexp.MustCompile(`^\+[1-9]\d{0,3}\d{6,14}$`)

// ValidE164 reports whether [phone] is a well-formed E.164 phone number.
//
// The phone value is used ONLY in memory for the duration of the OTP-request
// handler: it is hashed immediately and never stored or logged.
func ValidE164(phone string) bool {
	if len(phone) < 8 || len(phone) > 15 {
		return false
	}
	return e164Pattern.MatchString(phone)
}
