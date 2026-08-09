package identity

import "testing"

func TestValidE164(t *testing.T) {
	valid := []string{
		"+14155552671",  // US
		"+919876543210", // India
		"+442079460958", // UK
		"+15551234567",
	}
	for _, p := range valid {
		if !ValidE164(p) {
			t.Errorf("ValidE164(%q) = false, want true", p)
		}
	}

	invalid := []string{
		"",                 // empty
		"4155552671",       // no +
		"+",                // plus only
		"+0123456789",      // country code starts with 0
		"+1abc",            // letters
		"+155512345678901", // too long (16 chars)
		"+123456",          // too short (7 chars)
		" +14155552671",    // leading space
		"+14155552671 ",    // trailing space
	}
	for _, p := range invalid {
		if ValidE164(p) {
			t.Errorf("ValidE164(%q) = true, want false", p)
		}
	}
}
