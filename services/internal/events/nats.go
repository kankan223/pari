// Package events provides the NATS JetStream event bus (Task 4.7).
//
// The bus carries domain events between services with at-least-once delivery:
//
//   - Streams are durable and replicated (JetStream); publishers wait for a
//     PUBACK from the JetStream API before considering a publish committed.
//   - Consumers are DURABLE — the server tracks acked messages per consumer
//     name, so a consumer that dies (or the whole service restarts) resumes
//     where it left off; unacked messages are redelivered.
//   - Reconnect handling is built into the nats.go client (configurable
//     budget/wait); the connection factory registers reconnect/closed
//     handlers that log through the redacting logger.
//
// ZERO-KNOWLEDGE: event subjects and payloads are validated before publish —
// only registered non-PII subjects are allowed, and payloads carrying E.164
// phones / e-mails are rejected (SECURITY CHECKPOINT Task 4.7).
package events

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/nats-io/nats.go"
)

// DefaultStreamName is the JetStream stream that carries all Civic Commons
// domain events (per techstack §5.2 / Task 4.7).
const DefaultStreamName = "CIVIC_EVENTS"

// Options configures the event bus connection and stream.
type Options struct {
	// URL is the NATS server URL (nats://host:port).
	URL string

	// StreamName is the JetStream stream that captures all event subjects.
	// Defaults to [DefaultStreamName].
	StreamName string

	// Storage selects the JetStream stream storage engine.
	Storage StorageType

	// MaxAge bounds how long events are retained (0 = server default).
	MaxAge time.Duration

	// Reconnect resilience.
	// MaxReconnects is the reconnect budget before giving up: -1 = infinite
	// (production default), 0 = nats.go's library default of 60, >0 = that
	// many attempts. ReconnectWait is the delay between attempts and
	// ConnectTimeout bounds the initial dial (both default to the library
	// defaults when zero).
	MaxReconnects  int
	ReconnectWait  time.Duration
	ConnectTimeout time.Duration

	// Log is the (redacting) logger for connection events. Defaults to the
	// package default logger when nil.
	Log *slog.Logger
}

// StorageType selects the JetStream storage engine.
type StorageType string

const (
	// StorageFile persists stream data to disk (durable across restarts).
	StorageFile StorageType = "file"
	// StorageMemory keeps stream data in RAM only (dev/test).
	StorageMemory StorageType = "memory"
)

// Client is a NATS connection with a JetStream context. Create it with
// [NewClient]; call [Client.EnsureStream] before publishing.
type Client struct {
	nc     *nats.Conn
	js     nats.JetStreamContext
	stream string
	// storage and maxAge default the stream config when the caller passes
	// zero-valued fields (so Options.Storage/Options.MaxAge always take
	// effect, even when a custom StreamConfig is supplied).
	storage StorageType
	maxAge  time.Duration
	log     *slog.Logger
}

// NewClient dials NATS and returns a JetStream-enabled client.
//
// NOTE: this dials the network (and may retry per MaxReconnects) — call it
// only during startup wiring, not in unit tests (tests use an in-process
// nats-server). The stream is NOT created here; call [Client.EnsureStream].
func NewClient(opts Options) (*Client, error) {
	if opts.StreamName == "" {
		opts.StreamName = DefaultStreamName
	}
	log := opts.Log
	if log == nil {
		log = slog.Default()
	}

	connectOpts := []nats.Option{
		nats.Name("civic-commons-event-bus"),
		nats.MaxReconnects(opts.MaxReconnects),
		nats.ReconnectWait(opts.ReconnectWait),
		nats.Timeout(opts.ConnectTimeout),
		nats.DisconnectErrHandler(func(nc *nats.Conn, err error) {
			// err is nil on a clean (drain/close) disconnect.
			if err != nil {
				log.Warn("nats disconnected", "error", err.Error())
			} else {
				log.Warn("nats disconnected")
			}
		}),
		nats.ReconnectHandler(func(nc *nats.Conn) {
			log.Info("nats reconnected", "url", nc.ConnectedUrl())
		}),
		nats.ClosedHandler(func(nc *nats.Conn) {
			if !nc.IsClosed() {
				return
			}
			// Closed without reconnect: report the last error.
			if err := nc.LastError(); err != nil {
				log.Error("nats connection closed", "error", err.Error())
			} else {
				log.Info("nats connection closed")
			}
		}),
	}

	nc, err := nats.Connect(opts.URL, connectOpts...)
	if err != nil {
		return nil, fmt.Errorf("connect nats: %w", err)
	}
	js, err := nc.JetStream()
	if err != nil {
		nc.Close()
		return nil, fmt.Errorf("jetstream: %w", err)
	}
	return &Client{nc: nc, js: js, stream: opts.StreamName, storage: opts.Storage, maxAge: opts.MaxAge, log: log}, nil
}

// EnsureStream creates the configured stream if absent, or reconciles its
// config if present (idempotent — safe to call on every startup).
//
// Zero-valued fields in [cfg] fall back to the client's Options (Storage,
// MaxAge) so an operator setting NATS_STORAGE / NATS_MAX_AGE always sees
// them take effect.
func (c *Client) EnsureStream(ctx context.Context, cfg StreamConfig) error {
	if cfg.Storage == "" {
		cfg.Storage = c.storage
	}
	if cfg.MaxAge == 0 {
		cfg.MaxAge = c.maxAge
	}
	if cfg.Storage == "" {
		cfg.Storage = StorageFile
	}
	want := &nats.StreamConfig{
		Name:       c.stream,
		Subjects:   cfg.Subjects,
		Retention:  nats.LimitsPolicy,
		Storage:    toNATSStorage(cfg.Storage),
		MaxAge:     cfg.MaxAge,
		MaxMsgs:    cfg.MaxMsgs,
		MaxBytes:   cfg.MaxBytes,
		Discard:    nats.DiscardOld,
		Duplicates: time.Minute,
	}
	_, err := c.js.AddStream(want, nats.Context(ctx))
	if err == nil {
		return nil
	}
	if errors.Is(err, nats.ErrStreamNameAlreadyInUse) {
		// Stream exists — reconcile so config drift (e.g. a new subject
		// registered) is picked up on deploy.
		_, err = c.js.UpdateStream(want, nats.Context(ctx))
		if err != nil {
			return fmt.Errorf("update stream %s: %w", c.stream, err)
		}
		return nil
	}
	return fmt.Errorf("add stream %s: %w", c.stream, err)
}

// StreamInfo returns the live server-side stream info (verification/tests).
func (c *Client) StreamInfo(ctx context.Context) (*nats.StreamInfo, error) {
	si, err := c.js.StreamInfo(c.stream, nats.Context(ctx))
	if err != nil {
		return nil, fmt.Errorf("stream info %s: %w", c.stream, err)
	}
	return si, nil
}

// Publish publishes [payload] to [subject] with at-least-once semantics:
// it validates the subject/payload (zero PII), then waits for the JetStream
// PUBACK — an error means the event was NOT committed, so the caller can
// retry safely.
func (c *Client) Publish(ctx context.Context, subject string, payload []byte) error {
	if err := ValidateSubject(subject); err != nil {
		return err
	}
	if err := ValidatePayload(payload); err != nil {
		return fmt.Errorf("event payload rejected: %w", err)
	}
	if _, err := c.js.Publish(subject, payload, nats.Context(ctx)); err != nil {
		return fmt.Errorf("publish %s: %w", subject, err)
	}
	return nil
}

// SubscribeDurable registers (or binds to) a durable consumer for [subject]
// named [durable].
//
// The consumer is created explicitly if absent, then BOUND — the nats.go
// bind path does not mark the consumer for deletion on drain/unsubscribe, so
// the consumer's ack progress survives graceful restarts and the server
// redelivers only messages that were never acked (at-least-once). [handler]
// must be safe for concurrent invocation.
//
// Acking is explicit: an event is only removed from the consumer's backlog
// after the handler returns nil; a handler error NAKs the message for
// redelivery.
func (c *Client) SubscribeDurable(ctx context.Context, subject, durable string, handler func(*nats.Msg) error) (*nats.Subscription, error) {
	if err := ValidateSubject(subject); err != nil {
		return nil, err
	}

	// Create the durable consumer explicitly if it does not exist yet, so
	// subsequent subscriptions BIND to it (bind keeps the consumer alive
	// across drains/restarts — a durable created implicitly by js.Subscribe
	// is deleted on Unsubscribe/Drain).
	if _, err := c.js.ConsumerInfo(c.stream, durable, nats.Context(ctx)); err != nil {
		if errors.Is(err, nats.ErrConsumerNotFound) {
			cfg := &nats.ConsumerConfig{
				Durable:        durable,
				DeliverPolicy:  nats.DeliverAllPolicy,
				AckPolicy:      nats.AckExplicitPolicy,
				AckWait:        30 * time.Second,
				MaxAckPending:  1024,
				FilterSubject:  subject,
				DeliverSubject: nats.NewInbox(), // push-mode consumer
			}
			if _, cerr := c.js.AddConsumer(c.stream, cfg, nats.Context(ctx)); cerr != nil {
				// A concurrent subscriber (another replica/consumer group)
				// may have created the same durable first — that is fine.
				if !errors.Is(cerr, nats.ErrConsumerNameAlreadyInUse) {
					return nil, fmt.Errorf("create durable consumer %s: %w", durable, cerr)
				}
			}
		} else if !errors.Is(err, nats.ErrJetStreamNotEnabled) {
			return nil, fmt.Errorf("lookup durable consumer %s: %w", durable, err)
		}
	}

	sub, err := c.js.Subscribe(
		subject,
		func(m *nats.Msg) {
			if err := handler(m); err != nil {
				c.log.Error("event handler failed (message will redeliver)", "subject", subject, "durable", durable, "error", err.Error())
				_ = m.Nak() // redeliver — at-least-once
				return
			}
			_ = m.Ack()
		},
		nats.Context(ctx),
		nats.Bind(c.stream, durable),
		nats.ManualAck(),
	)
	if err != nil {
		return nil, fmt.Errorf("subscribe durable %s: %w", subject, err)
	}
	return sub, nil
}

// Close flushes pending publishes and closes the connection.
func (c *Client) Close() error {
	// Drain (graceful) if connected, else plain close.
	if c.nc.IsConnected() {
		if err := c.nc.Drain(); err != nil {
			c.nc.Close()
			return err
		}
		return nil
	}
	c.nc.Close()
	return nil
}

// Flush blocks until the connection has processed all buffered messages
// (used in tests / shutdown sequencing).
func (c *Client) Flush() error { return c.nc.Flush() }

// Connected reports whether the underlying connection is up.
func (c *Client) Connected() bool { return c.nc != nil && c.nc.IsConnected() }

func toNATSStorage(s StorageType) nats.StorageType {
	if s == StorageMemory {
		return nats.MemoryStorage
	}
	return nats.FileStorage
}
