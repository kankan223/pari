package identity

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/kankan223/pari/services/internal/logging"
)

func TestMSG91ProviderSendOTP(t *testing.T) {
	var gotMethod, gotPath, gotAuth string
	var gotBody map[string]string

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotMethod = r.Method
		gotPath = r.URL.Path
		gotAuth = r.Header.Get("authkey")
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		w.WriteHeader(http.StatusOK)
	}))
	defer ts.Close()

	p := NewMSG91Provider(MSG91Config{
		APIKey:     "secret-key",
		SenderID:   "CIVCOM",
		TemplateID: "tpl-1",
		BaseURL:    ts.URL,
	}, logging.NewRedactingLogger(&bytes.Buffer{}, slog.LevelInfo))

	if err := p.SendOTP(context.Background(), "+14155552671", "482913"); err != nil {
		t.Fatalf("SendOTP() error = %v", err)
	}

	if gotMethod != http.MethodPost || gotPath != "/api/v5/otp" {
		t.Errorf("request = %s %s, want POST /api/v5/otp", gotMethod, gotPath)
	}
	if gotAuth != "secret-key" {
		t.Errorf("authkey header = %q, want secret-key", gotAuth)
	}
	// The phone is sent WITHOUT the '+' (E.164 digits) and the code is present.
	if gotBody["mobile"] != "14155552671" {
		t.Errorf("mobile = %q, want 14155552671", gotBody["mobile"])
	}
	if gotBody["otp"] != "482913" {
		t.Errorf("otp = %q, want 482913", gotBody["otp"])
	}
	if gotBody["template_id"] != "tpl-1" || gotBody["sender"] != "CIVCOM" {
		t.Errorf("template/sender = %q/%q", gotBody["template_id"], gotBody["sender"])
	}
}

func TestMSG91ProviderError(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"type":"error","message":"invalid template"}`))
	}))
	defer ts.Close()

	p := NewMSG91Provider(MSG91Config{APIKey: "k", BaseURL: ts.URL}, logging.NewRedactingLogger(&bytes.Buffer{}, slog.LevelInfo))
	err := p.SendOTP(context.Background(), "+14155552671", "123456")
	if err == nil {
		t.Fatal("SendOTP() expected error on non-2xx")
	}
	if !strings.Contains(err.Error(), "invalid template") {
		t.Errorf("error = %v, want to surface response body", err)
	}
}

func TestMSG91ProviderTransportError(t *testing.T) {
	p := NewMSG91Provider(MSG91Config{APIKey: "k", BaseURL: "http://127.0.0.1:1"}, logging.NewRedactingLogger(&bytes.Buffer{}, slog.LevelInfo))
	if err := p.SendOTP(context.Background(), "+14155552671", "123456"); err == nil {
		t.Fatal("SendOTP() expected transport error")
	}
}

func TestNoopProviderNeverLogsPhoneOrCode(t *testing.T) {
	var buf bytes.Buffer
	p := NewNoopProvider(logging.NewRedactingLogger(&buf, slog.LevelInfo))
	if err := p.SendOTP(context.Background(), "+14155552671", "987654"); err != nil {
		t.Fatalf("SendOTP() error = %v", err)
	}
	out := buf.String()
	if strings.Contains(out, "+14155552671") || strings.Contains(out, "987654") {
		t.Fatalf("noop provider leaked PII: %s", out)
	}
}
