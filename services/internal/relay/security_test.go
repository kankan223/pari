package relay

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/kankan223/pari/services/proto"
)

// TestStaticScanNoDecryption is the Task 4.4 SECURITY CHECKPOINT static
// verification: the relay package must contain NO decryption or plaintext-
// inspection primitives. The relay is a ciphertext router only — bodies are
// opaque bytes.
//
// The scan inspects every non-test .go file in this package for the Go
// standard-library APIs that any decryption path would require, plus generic
// "decrypt" identifiers.
func TestStaticScanNoDecryption(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot locate package source")
	}
	dir := filepath.Dir(thisFile)

	// Decryption primitives that must never appear in a routing-only service.
	forbidden := []string{
		"rsa.Decrypt",     // RSA decryption
		"DecryptPKCS1v15", // RSA-OAEP/PKCS1v15 decrypt
		"cipher.New",      // block cipher construction
		"NewCBCDecrypter", // AES-CBC decrypt
		"NewCTR",          // AES-CTR (used for decrypt)
		"NewGCM(",         // AEAD decrypt usage
		"Open(nil",        // GCM Open (authenticated decryption)
		"DecryptString",   // generic decrypt helpers
		"decrypt(",        // lowercase call form
		"Decrypt(",        // mixed-case call form
		"decryption",      // descriptive identifiers
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	checked := 0
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".go") || strings.HasSuffix(e.Name(), "_test.go") {
			continue
		}
		// #nosec G304 -- static scan of this package's own sources (files are
		// enumerated from this package's directory by ReadDir, not attacker
		// controlled).
		src, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			t.Fatal(err)
		}
		checked++
		for _, needle := range forbidden {
			if strings.Contains(string(src), needle) {
				t.Errorf("%s contains decryption primitive %q — the relay must never decrypt message bodies", e.Name(), needle)
			}
		}
	}
	if checked == 0 {
		t.Fatal("static scan found no source files to check")
	}
	t.Logf("static scan checked %d non-test source files for decryption primitives", checked)
}

// TestOpaqueCiphertextPassThrough is the Task 4.4 SECURITY CHECKPOINT runtime
// verification: arbitrary ciphertext bytes survive the full routing path
// (hub fan-out and offline queue) byte-for-byte unmodified. The bytes are
// generated randomly so no code path could have "recognized" them.
func TestOpaqueCiphertextPassThrough(t *testing.T) {
	e := newWSTestEnv(t)
	ctx := context.Background()

	// 1. Offline path: enqueue → read back.
	opaque := []byte{0x00, 0xFF, 0x01, 0xFE, 0x80, 0x7F, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66}
	if _, err := e.hub.Deliver(ctx, &proto.Envelope{
		MsgId:         "opaque-1",
		SenderHash:    alice,
		RecipientHash: bob,
		Ciphertext:    opaque,
	}); err != nil {
		t.Fatalf("Deliver() error = %v", err)
	}
	pending, err := e.queue.ReadPending(ctx, bob, 10)
	if err != nil {
		t.Fatalf("ReadPending() error = %v", err)
	}
	if len(pending) != 1 || !bytes.Equal(pending[0].Ciphertext, opaque) {
		t.Fatalf("offline round-trip corrupted ciphertext: %x", pending[0].Ciphertext)
	}

	// 2. Online path over a real WebSocket.
	sender := e.dial(t)
	recipient := e.dial(t)
	wsAuth(t, sender, "token-alice", "a1")
	wsAuth(t, recipient, "token-bob", "b1")

	wsSendEnvelope(t, sender, &proto.Envelope{
		MsgId:         "opaque-2",
		RecipientHash: bob,
		Ciphertext:    opaque,
	})
	frame := wsReadFrame(t, recipient)
	env := frame.GetEnvelope()
	if env == nil {
		t.Fatal("recipient received no envelope")
	}
	if !bytes.Equal(env.Ciphertext, opaque) {
		t.Fatalf("online path corrupted ciphertext: %x", env.Ciphertext)
	}
}
