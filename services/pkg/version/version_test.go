package version

import "testing"

func TestString(t *testing.T) {
	if String() == "" {
		t.Fatal("String() returned empty version")
	}
}
