package relay

import (
	"context"
	"errors"
	"math"
	"sync"
	"time"

	"github.com/coder/websocket"

	"github.com/kankan223/pari/services/proto"
)

// Peer is one live device connection attached to the hub. Implemented by the
// WebSocket connection pump (connection.go); faked in tests.
type Peer interface {
	DeviceID() string
	// WriteEnvelope sends one envelope frame; must be safe for concurrent use.
	WriteEnvelope(ctx context.Context, env *proto.Envelope) error
	// Close tears the connection down with a WebSocket close frame.
	Close(code websocket.StatusCode, reason string)
}

// ErrNoLiveDevices is returned by Hub.Deliver when the recipient is offline
// and the caller opted out of the offline queue.
var ErrNoLiveDevices = errors.New("relay: recipient has no live devices")

// writeTimeout bounds a single fan-out write so a stalled peer cannot block
// routing to other devices.
const writeTimeout = 5 * time.Second

// msToUint64 clamps a signed millisecond timestamp (a negative sent_at is
// impossible) for the uint64 proto field.
func msToUint64(ms int64) uint64 {
	if ms < 0 {
		return 0
	}
	return uint64(ms)
}

// uint64ToMs clamps absurd sent_at values for the int64 queue field.
func uint64ToMs(v uint64) int64 {
	if v > uint64(math.MaxInt64) {
		return math.MaxInt64
	}
	return int64(v)
}

// RouteResult reports how a routed envelope was handled.
type RouteResult struct {
	// DeliveredTo counts live devices that accepted the envelope (including
	// the sender's own other devices for multi-device sync).
	DeliveredTo int
	// Queued is true when the recipient had no live device, so the envelope
	// was persisted to the offline queue.
	Queued bool
	// EntryID is the offline-queue entry when Queued (empty otherwise).
	EntryID string
}

// Hub is the multi-device connection registry and fan-out router (Task 4.4).
//
// Registry: one blind_hash_id → many device connections. A reconnecting
// device with the same ID evicts the previous connection (idempotent
// reconnect). Routing: an envelope is fanned out to every live device of the
// recipient; when the recipient is offline it is persisted to the per-recipient
// Redis Stream offline queue. The sender's own other devices also receive a
// copy (multi-device sync), excluding the sending device to avoid echo; sync
// copies are never queued — the recipient copy is the durable one.
//
// ZERO-KNOWLEDGE: the hub treats Envelope.Ciphertext as opaque bytes. It
// never deserializes, decrypts, or inspects the payload — it only decides
// which connection to write the frame to.
type Hub struct {
	mu      sync.Mutex
	devices map[string]map[string]Peer // blind_hash_id → device_id → peer
	queue   OfflineQueue
}

// NewHub builds a hub that falls back to [queue] for offline recipients.
func NewHub(queue OfflineQueue) *Hub {
	return &Hub{
		devices: make(map[string]map[string]Peer),
		queue:   queue,
	}
}

// Register attaches [peer] for (blindHashID, deviceID), evicting any previous
// connection under the same device ID.
func (h *Hub) Register(blindHashID, deviceID string, peer Peer) {
	h.mu.Lock()
	defer h.mu.Unlock()
	devs := h.devices[blindHashID]
	if devs == nil {
		devs = make(map[string]Peer)
		h.devices[blindHashID] = devs
	}
	if prev, ok := devs[deviceID]; ok && prev != peer {
		prev.Close(websocket.StatusPolicyViolation, "replaced by new connection")
	}
	devs[deviceID] = peer
}

// Unregister removes [peer] from the registry unless it has already been
// replaced by a newer connection for the same device ID.
func (h *Hub) Unregister(blindHashID, deviceID string, peer Peer) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if devs, ok := h.devices[blindHashID]; ok {
		if cur, ok := devs[deviceID]; ok && cur == peer {
			delete(devs, deviceID)
			if len(devs) == 0 {
				delete(h.devices, blindHashID)
			}
		}
	}
}

// OnlineCount returns the number of live device connections.
func (h *Hub) OnlineCount() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	n := 0
	for _, devs := range h.devices {
		n += len(devs)
	}
	return n
}

// DeviceCount returns the number of live devices for one blind_hash_id.
func (h *Hub) DeviceCount(blindHashID string) int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.devices[blindHashID])
}

// Deliver routes one envelope: fan-out to the recipient's live devices and,
// when the recipient is fully offline, persist it to the offline queue.
// env.SenderHash must already be the authenticated identity (never client
// supplied) — the connection pump enforces this.
func (h *Hub) Deliver(ctx context.Context, env *proto.Envelope) (RouteResult, error) {
	res := RouteResult{}

	h.mu.Lock()
	targets, recipientPeers := h.collectTargetsLocked(env)
	h.mu.Unlock()

	recipientOK := make(map[Peer]bool, len(recipientPeers))
	delivered := 0
	for _, p := range targets {
		select {
		case <-ctx.Done():
			return res, ctx.Err()
		default:
		}
		wctx, cancel := context.WithTimeout(ctx, writeTimeout)
		err := p.WriteEnvelope(wctx, env)
		cancel()
		if err == nil {
			delivered++
			recipientOK[p] = true
		} else {
			// Dead peer — evict so it stops receiving, then fall through.
			// Close in a goroutine: coder/websocket's Close waits for the
			// peer's close response, which must not stall the sender's read
			// loop that is running this Deliver.
			h.Unregister(hashOf(h, p), p.DeviceID(), p)
			go p.Close(websocket.StatusInternalError, "write failed")
		}
	}
	res.DeliveredTo = delivered

	// Offline fallback: enqueue iff no live device of the *recipient*
	// accepted the envelope. Sender-sync failures never queue (the
	// recipient copy is the durable one).
	recipientGotIt := false
	for p := range recipientPeers {
		if recipientOK[p] {
			recipientGotIt = true
			break
		}
	}
	if !recipientGotIt {
		entry, err := h.queue.Enqueue(ctx, env.RecipientHash, QueuedMessage{
			MsgID:          env.MsgId,
			SenderHash:     env.SenderHash,
			Ciphertext:     env.Ciphertext,
			SentAtMS:       uint64ToMs(env.SentAtMs),
			SenderDeviceID: env.SenderDeviceId,
		})
		if err != nil {
			return res, err
		}
		res.Queued = true
		res.EntryID = entry
	}
	return res, nil
}

// collectTargetsLocked snapshots the fan-out target set: every live device of
// the recipient (recipientPeers) plus (for multi-device sync) the sender's
// devices excluding the sending device. Must be called with h.mu held.
func (h *Hub) collectTargetsLocked(env *proto.Envelope) (targets []Peer, recipientPeers map[Peer]struct{}) {
	seen := make(map[Peer]struct{})
	recipientPeers = make(map[Peer]struct{})
	add := func(hash string, skipDevice string, isRecipient bool) {
		for devID, p := range h.devices[hash] {
			if devID == skipDevice {
				continue
			}
			if _, ok := seen[p]; ok {
				continue
			}
			seen[p] = struct{}{}
			if isRecipient {
				recipientPeers[p] = struct{}{}
			}
			targets = append(targets, p)
		}
	}
	add(env.RecipientHash, "", true) // recipient receives on ALL its devices
	if env.SenderHash != env.RecipientHash {
		add(env.SenderHash, env.SenderDeviceId, false) // self-sync, no echo
	}
	return targets, recipientPeers
}

// Ack purges a delivered queued message (client DeliveryAck → queue purge).
func (h *Hub) Ack(ctx context.Context, recipientHash, msgID string) error {
	return h.queue.AckByMsgID(ctx, recipientHash, msgID)
}

// Pending returns the recipient's undelivered messages (used to drain the
// offline queue on reconnect).
func (h *Hub) Pending(ctx context.Context, recipientHash string, count int64) ([]QueuedMessage, error) {
	return h.queue.ReadPending(ctx, recipientHash, count)
}

// TrimOlderThan drops queued entries older than [cutoff] for a recipient
// (the 30-day TTL, enforced at delivery time on reconnect).
func (h *Hub) TrimOlderThan(ctx context.Context, recipientHash string, cutoff time.Time) error {
	return h.queue.TrimOlderThan(ctx, recipientHash, cutoff)
}

// hashOf returns the registered hash for a peer (used when evicting a failed
// write). Cheap and correct because a peer lives under exactly one hash.
func hashOf(h *Hub, p Peer) string {
	h.mu.Lock()
	defer h.mu.Unlock()
	for hash, devs := range h.devices {
		for _, dev := range devs {
			if dev == p {
				return hash
			}
		}
	}
	return ""
}
