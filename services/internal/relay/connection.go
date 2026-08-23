package relay

import (
	"context"
	"errors"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"

	"github.com/kankan223/pari/services/proto"
)

// Connection policy (techstack §5.3).
const (
	// maxFrameBytes bounds a single WebSocket message (read limit).
	maxFrameBytes = 1 << 20 // 1 MiB
	// maxDeviceIDLen bounds the client-supplied device identifier.
	maxDeviceIDLen = 64
	// maxMsgIDLen bounds the client-supplied message UUID.
	maxMsgIDLen = 128
)

// Authenticator validates a first-frame access token and returns the
// authenticated blind_hash_id (the relay's identity for routing). Implemented
// with the identity service's RS256 verifier in cmd/relay; faked in tests.
type Authenticator interface {
	Authenticate(ctx context.Context, accessToken string) (blindHashID string, err error)
}

// wsPeer adapts a coder/websocket connection to the hub's Peer interface.
// A write mutex serializes data frames (coder/websocket allows one
// concurrent writer; Ping/Close are safe to call concurrently per its docs).
type wsPeer struct {
	conn     *websocket.Conn
	deviceID string

	wmu sync.Mutex
}

// DeviceID implements Peer.
func (p *wsPeer) DeviceID() string { return p.deviceID }

// WriteEnvelope implements Peer.
func (p *wsPeer) WriteEnvelope(ctx context.Context, env *proto.Envelope) error {
	p.wmu.Lock()
	defer p.wmu.Unlock()
	wctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	return writeFrame(wctx, p.conn, &proto.ServerFrame{
		Payload: &proto.ServerFrame_Envelope{Envelope: env},
	})
}

// WriteFrame implements Peer for arbitrary server frames (typing, read
// receipts).
func (p *wsPeer) WriteFrame(ctx context.Context, frame *proto.ServerFrame) error {
	p.wmu.Lock()
	defer p.wmu.Unlock()
	wctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	return writeFrame(wctx, p.conn, frame)
}

// Close implements Peer.
func (p *wsPeer) Close(code websocket.StatusCode, reason string) {
	p.wmu.Lock()
	defer p.wmu.Unlock()
	_ = p.conn.Close(code, reason)
}

// serveWS upgrades an HTTP request and runs the connection lifecycle:
//
//  1. The FIRST frame must be an AuthRequest carrying the access token and
//     device ID (never in the URL — query strings are logged by proxies).
//  2. On success the peer registers with the hub under (blind_hash_id,
//     device_id) and receives an AuthAck.
//  3. A read loop then processes Envelope and DeliveryAck frames; the sender
//     identity on every envelope is server-overridden from the authenticated
//     token (client spoofing of sender_hash is impossible).
//  4. A heartbeat goroutine sends a server ping every 25s and closes the
//     connection when no pong arrives within 10s.
func (s *Server) serveWS(w http.ResponseWriter, r *http.Request) {
	c, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		// Auth is via the first-frame token, never Origin — the client is a
		// native app with no browser origin to trust. Origin checks are
		// therefore skipped deliberately (documented platform behavior).
		InsecureSkipVerify: true,
	})
	if err != nil {
		return
	}
	// Always tear down the TCP connection when the pump returns.
	defer func() { _ = c.CloseNow() }()

	ctx := r.Context()

	// --- 1. First-frame authentication -------------------------------------
	auth, err := s.readAuthFrame(ctx, c)
	if err != nil {
		_ = c.Close(websocket.StatusPolicyViolation, "auth frame required")
		return
	}
	blindHashID, err := s.authenticator.Authenticate(ctx, auth.AccessToken)
	if err != nil {
		s.log.Error("ws auth failed", "error", err.Error())
		_ = writeFrame(ctx, c, &proto.ServerFrame{Payload: &proto.ServerFrame_AuthAck{
			AuthAck: &proto.AuthAck{Authenticated: false},
		}})
		_ = c.Close(websocket.StatusPolicyViolation, "authentication failed")
		return
	}
	deviceID := auth.DeviceId
	if deviceID == "" || len(deviceID) > maxDeviceIDLen {
		_ = c.Close(websocket.StatusPolicyViolation, "invalid device id")
		return
	}

	// --- 2. Register with the hub -------------------------------------------
	peer := &wsPeer{conn: c, deviceID: deviceID}
	s.hub.Register(blindHashID, deviceID, peer)
	defer s.hub.Unregister(blindHashID, deviceID, peer)

	ack := &proto.ServerFrame{Payload: &proto.ServerFrame_AuthAck{
		AuthAck: &proto.AuthAck{Authenticated: true, BlindHashId: blindHashID},
	}}
	if err := writeFrame(ctx, c, ack); err != nil {
		return
	}
	s.log.Info("ws authenticated",
		"blind_hash_id", blindHashID, "device_id", deviceID)

	// --- 3. Drain the offline queue -----------------------------------------
	// Deliver anything persisted while this user was away; entries are only
	// removed when the client sends a DeliveryAck for each msg_id.
	if err := s.drainQueue(ctx, peer, blindHashID); err != nil {
		s.log.Error("ws drain failed", "error", err.Error())
		return
	}

	// --- 4. Heartbeat (25s ping / 10s pong) ---------------------------------
	heartbeatDone := make(chan struct{})
	go s.heartbeat(ctx, c, peer, heartbeatDone)

	// --- 5. Read loop --------------------------------------------------------
	c.SetReadLimit(maxFrameBytes)
	for {
		var frame proto.ClientFrame
		if err := readFrame(ctx, c, &frame); err != nil {
			break // peer closed, read limit hit, or context cancelled
		}
		if !s.handleClientFrame(ctx, &frame, blindHashID, deviceID) {
			break // protocol violation → close
		}
	}

	select {
	case <-heartbeatDone:
	default:
		close(heartbeatDone) // stop the pinger
	}
	// Graceful close in a goroutine: coder/websocket's Close waits for the
	// peer's close response, which would otherwise block the deferred
	// hub.Unregister and delay eviction of misbehaving peers.
	go func() { _ = c.Close(websocket.StatusNormalClosure, "bye") }()
}

// drainQueue delivers the recipient's queued envelopes to the freshly
// connected peer. Messages stay in the stream until the client acks them
// (DeliveryAck → queue purge). Entries older than the retention window are
// trimmed first so the 30-day TTL holds at delivery time, not only when new
// traffic triggers an XTRIM.
func (s *Server) drainQueue(ctx context.Context, peer *wsPeer, blindHashID string) error {
	if s.queueTTL > 0 {
		if err := s.hub.TrimOlderThan(ctx, blindHashID, time.Now().UTC().Add(-s.queueTTL)); err != nil {
			s.log.Error("ws queue trim failed", "error", err.Error())
		}
	}
	for {
		pending, err := s.hub.Pending(ctx, blindHashID, 100)
		if errors.Is(err, ErrQueueEmpty) {
			return nil
		}
		if err != nil {
			return err
		}
		for _, m := range pending {
			env := &proto.Envelope{
				MsgId:          m.MsgID,
				SenderHash:     m.SenderHash,
				RecipientHash:  blindHashID,
				Ciphertext:     m.Ciphertext,
				SentAtMs:       msToUint64(m.SentAtMS),
				SenderDeviceId: m.SenderDeviceID,
			}
			if err := peer.WriteEnvelope(ctx, env); err != nil {
				return err
			}
		}
		if len(pending) < 100 {
			return nil
		}
	}
}

// readAuthFrame reads the first frame and requires it to be an AuthRequest.
func (s *Server) readAuthFrame(ctx context.Context, c *websocket.Conn) (*proto.AuthRequest, error) {
	var frame proto.ClientFrame
	if err := readFrame(ctx, c, &frame); err != nil {
		return nil, err
	}
	auth := frame.GetAuth()
	if auth == nil {
		return nil, errors.New("relay: first frame is not auth")
	}
	if auth.AccessToken == "" {
		return nil, errors.New("relay: empty access token")
	}
	return auth, nil
}

// handleClientFrame processes one client frame. Returns false when the
// connection must be closed (protocol violation).
func (s *Server) handleClientFrame(ctx context.Context, frame *proto.ClientFrame, blindHashID, deviceID string) bool {
	switch {
	case frame.GetAuth() != nil:
		// A second auth frame is a protocol violation; the deferred
		// Unregister in serveWS evicts this peer.
		return false

	case frame.GetEnvelope() != nil:
		env := frame.GetEnvelope()
		// Anti-spoofing: the sender identity is ALWAYS the authenticated
		// blind_hash_id and device ID, never client-supplied values.
		env.SenderHash = blindHashID
		env.SenderDeviceId = deviceID
		if env.MsgId == "" || len(env.MsgId) > maxMsgIDLen || env.RecipientHash == "" {
			s.log.Warn("ws dropped envelope: missing/invalid fields")
			return true // malformed envelope is dropped, connection stays
		}
		if env.SentAtMs == 0 {
			env.SentAtMs = msToUint64(time.Now().UTC().UnixMilli())
		}
		if _, err := s.hub.Deliver(ctx, env); err != nil {
			s.log.Error("ws deliver failed", "error", err.Error())
		}
		return true

	case frame.GetAck() != nil:
		// DeliveryAck is scoped to the authenticated recipient.
		if err := s.hub.Ack(ctx, blindHashID, frame.GetAck().MsgId); err != nil {
			s.log.Error("ws ack failed", "error", err.Error())
		}
		return true

	case frame.GetTyping() != nil:
		typing := frame.GetTyping()
		if typing.RecipientHash == "" {
			return true // malformed — drop, connection stays
		}
		// Set the sender hash from the authenticated connection identity.
		typing.SenderHash = blindHashID
		s.hub.ForwardTyping(ctx, typing.RecipientHash, typing)
		return true

	case frame.GetReadReceipt() != nil:
		receipt := frame.GetReadReceipt()
		if receipt.SenderHash == "" || receipt.LastMsgId == "" {
			return true // malformed — drop, connection stays
		}
		s.hub.ForwardReadReceipt(ctx, receipt.SenderHash, receipt)
		return true

	default:
		// Empty frame (no oneof payload).
		return true
	}
}

// heartbeat sends a server ping every [WSPingInterval] and closes the peer
// when no pong arrives within [WSPongTimeout]. Exits on context cancellation
// or when heartbeatDone is closed by the read loop's exit.
func (s *Server) heartbeat(ctx context.Context, c *websocket.Conn, peer *wsPeer, done <-chan struct{}) {
	ticker := time.NewTicker(s.pingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-done:
			return
		case <-ticker.C:
			pctx, cancel := context.WithTimeout(ctx, s.pongTimeout)
			err := c.Ping(pctx) // blocks until pong or timeout
			cancel()
			if err != nil {
				s.log.Warn("ws pong timeout", "device_id", peer.deviceID)
				peer.Close(websocket.StatusGoingAway, "pong timeout")
				return
			}
		}
	}
}
