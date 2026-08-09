package identity

import (
	"context"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
)

// testPubKey returns a base64url-encoded 32-byte Ed25519 public key.
func testPubKey(seed byte) string {
	raw := make([]byte, ed25519PubKeyLen)
	for i := range raw {
		raw[i] = seed
	}
	return base64.RawURLEncoding.EncodeToString(raw)
}

func TestValidPublicKey(t *testing.T) {
	if !ValidPublicKey(testPubKey(0x01)) {
		t.Fatal("valid 32-byte base64url key rejected")
	}
	if !ValidPublicKey(base64.StdEncoding.EncodeToString(make([]byte, 32))) {
		t.Fatal("valid 32-byte padded base64 key rejected")
	}
	for _, bad := range []string{"", "abc", base64.RawURLEncoding.EncodeToString(make([]byte, 31)), base64.RawURLEncoding.EncodeToString(make([]byte, 33)), "!!!"} {
		if ValidPublicKey(bad) {
			t.Errorf("invalid key %q accepted", bad)
		}
	}
}

func TestDeviceRegisterListRevoke(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	hashID := mustRequestAndVerifyPhone(t, ts, testPhone)

	if err := ts.svc.RegisterDevice(ctx, hashID, "dev-1", testPubKey(0xAA)); err != nil {
		t.Fatalf("RegisterDevice() error = %v", err)
	}
	if err := ts.svc.RegisterDevice(ctx, hashID, "dev-2", testPubKey(0xBB)); err != nil {
		t.Fatalf("RegisterDevice() error = %v", err)
	}

	devices, err := ts.svc.ListDevices(ctx, hashID)
	if err != nil {
		t.Fatalf("ListDevices() error = %v", err)
	}
	if len(devices) != 2 {
		t.Fatalf("ListDevices() len = %d, want 2", len(devices))
	}

	// Registering the same device_id updates in place (idempotent re-pair).
	if err := ts.svc.RegisterDevice(ctx, hashID, "dev-1", testPubKey(0xCC)); err != nil {
		t.Fatalf("re-register error = %v", err)
	}
	devices, _ = ts.svc.ListDevices(ctx, hashID)
	if len(devices) != 2 {
		t.Fatalf("re-register added a device: len = %d, want 2", len(devices))
	}

	if err := ts.svc.RevokeDevice(ctx, hashID, "dev-2"); err != nil {
		t.Fatalf("RevokeDevice() error = %v", err)
	}
	devices, _ = ts.svc.ListDevices(ctx, hashID)
	if len(devices) != 1 || devices[0].DeviceID != "dev-1" {
		t.Fatalf("after revoke: %+v", devices)
	}
}

func TestDeviceInvalidKey(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	hashID := mustRequestAndVerifyPhone(t, ts, testPhone)

	if err := ts.svc.RegisterDevice(ctx, hashID, "dev-1", "not-a-key"); !errors.Is(err, ErrDeviceKey) {
		t.Fatalf("invalid key = %v, want ErrDeviceKey", err)
	}
}

func TestDeviceCap(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	hashID := mustRequestAndVerifyPhone(t, ts, testPhone)

	for i := 0; i < maxDevicesPerUser; i++ {
		if err := ts.svc.RegisterDevice(ctx, hashID, "dev-"+strings.Repeat("x", i), testPubKey(byte(i))); err != nil {
			t.Fatalf("RegisterDevice() #%d error = %v", i, err)
		}
	}
	if err := ts.svc.RegisterDevice(ctx, hashID, "overflow", testPubKey(0xFF)); !errors.Is(err, ErrDeviceCap) {
		t.Fatalf("cap overflow = %v, want ErrDeviceCap", err)
	}
}

func TestDevicesIsolatedPerIdentity(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	hashA := mustRequestAndVerifyPhone(t, ts, testPhone)
	hashB := mustRequestAndVerifyPhone(t, ts, "+919876543210")

	if err := ts.svc.RegisterDevice(ctx, hashA, "dev-1", testPubKey(0x01)); err != nil {
		t.Fatalf("RegisterDevice() error = %v", err)
	}
	devicesB, _ := ts.svc.ListDevices(ctx, hashB)
	if len(devicesB) != 0 {
		t.Fatalf("identity B sees identity A's devices: %+v", devicesB)
	}
}
