package identity

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

// SMSProvider delivers OTP codes to phone numbers.
//
// SECURITY CONTRACT: implementations must never log or persist the [phone] or
// the [code]. The phone appears only as an outbound request payload and is
// dropped as soon as the call returns.
type SMSProvider interface {
	SendOTP(ctx context.Context, phone, code string) error
}

// NoopProvider is the development provider: it skips delivery entirely.
// Enabled via OTP_PROVIDER=noop (the default) so the service runs without
// SMS credentials. It never emits the phone or the code to any sink.
type NoopProvider struct {
	log *slog.Logger
}

// NewNoopProvider builds a NoopProvider that logs a delivery-skipped warning
// (no PII).
func NewNoopProvider(log *slog.Logger) *NoopProvider {
	return &NoopProvider{log: log}
}

// SendOTP implements SMSProvider.
//
// SECURITY NOTE: In dev/noop mode the code IS logged so testers can retrieve
// it from Render logs. This provider must NEVER be used in production.
func (p *NoopProvider) SendOTP(_ context.Context, phone, code string) error {
	p.log.Warn("otp_dev_code", "code", code, "hint", "noop provider — code visible in logs only")
	return nil
}

// MSG91Config configures the MSG91 (msg91.com) provider.
type MSG91Config struct {
	APIKey     string
	SenderID   string
	TemplateID string
	BaseURL    string
}

// MSG91Provider sends OTP codes through the MSG91 v5 OTP API using net/http.
//
// Wire contract (MSG91 API v5 "send OTP with custom value"; base overridable
// for regional endpoints):
//
//	POST {BaseURL}/api/v5/otp
//	authkey: <APIKey>
//	{"template_id": "...", "sender": "...", "mobile": "<E.164 digits>", "otp": "<code>"}
//
// NOTE: MSG91 plan-specific quirks (e.g. query-string auth vs header) may
// require tweaking the request shape; the contract is pinned here so it can
// be verified with a mock server and adjusted deliberately.
type MSG91Provider struct {
	cfg MSG91Config
	hc  *http.Client
	log *slog.Logger
}

// NewMSG91Provider builds the provider. [cfg.BaseURL] defaults to
// https://control.msg91.com when empty.
func NewMSG91Provider(cfg MSG91Config, log *slog.Logger) *MSG91Provider {
	if cfg.BaseURL == "" {
		cfg.BaseURL = "https://control.msg91.com"
	}
	return &MSG91Provider{
		cfg: cfg,
		hc:  &http.Client{Timeout: 10 * time.Second},
		log: log,
	}
}

// SendOTP implements SMSProvider. The phone number is normalized to E.164
// digits (no '+') for the request and never logged.
func (p *MSG91Provider) SendOTP(ctx context.Context, phone, code string) error {
	mobile := strings.TrimPrefix(strings.TrimSpace(phone), "+")

	payload, err := json.Marshal(map[string]string{
		"template_id": p.cfg.TemplateID,
		"sender":      p.cfg.SenderID,
		"mobile":      mobile,
		"otp":         code,
	})
	if err != nil {
		return fmt.Errorf("msg91: encode request: %w", err)
	}

	url := strings.TrimRight(p.cfg.BaseURL, "/") + "/api/v5/otp"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("msg91: build request: %w", err)
	}
	req.Header.Set("authkey", p.cfg.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.hc.Do(req)
	if err != nil {
		return fmt.Errorf("msg91: send otp: %w", err)
	}
	defer func() {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		_ = resp.Body.Close()
	}()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		// Read a bounded error body for diagnostics (MSG91 returns JSON like
		// {"type":"error","message":"..."} — never includes the code).
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("msg91: send otp: http %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}
