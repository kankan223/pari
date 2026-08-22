package relay

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/kankan223/pari/services/internal/cache"
)

// Offline queue (Task 4.4): undelivered ciphertext envelopes live in one
// Redis Stream per recipient blind_hash_id — techstack §7.2 `msg_queue:`
// namespace (keys built by the validated cache builder, Task 4.6). Messages
// are retained for 30 days and purged by XTRIM MINID (stream entry IDs
// encode their insertion time in milliseconds, so trimming by ID == trimming
// by age). No consumer groups: the stream is a FIFO queue the relay drains
// on connect and acknowledges on delivery.

// ErrQueueEmpty is returned when a recipient stream has no pending messages.
var ErrQueueEmpty = errors.New("relay: queue empty")

// QueuedMessage is one undelivered envelope in a recipient's stream.
type QueuedMessage struct {
	EntryID        string // Redis stream entry ID (ms-seq)
	MsgID          string // application msg_id (client UUID)
	SenderHash     string
	Ciphertext     []byte // OPAQUE — the relay never inspects these bytes
	SentAtMS       int64
	SenderDeviceID string
}

// OfflineQueue persists undelivered envelopes per recipient.
type OfflineQueue interface {
	// Enqueue appends an envelope to the recipient's stream and returns the
	// new entry ID. Old entries beyond the retention window are trimmed in
	// the same round trip.
	Enqueue(ctx context.Context, recipientHash string, m QueuedMessage) (string, error)
	// ReadPending returns up to [count] undelivered messages, oldest first.
	ReadPending(ctx context.Context, recipientHash string, count int64) ([]QueuedMessage, error)
	// Ack removes a delivered entry (by stream entry ID) and deletes the
	// stream entirely when it drains (queue purge).
	Ack(ctx context.Context, recipientHash, entryID string) error
	// AckByMsgID removes the entry carrying [msgID] and purges the stream
	// when it drains (client DeliveryAck flow).
	AckByMsgID(ctx context.Context, recipientHash, msgID string) error
	// TrimOlderThan purges entries older than [cutoff] (the 30-day TTL).
	TrimOlderThan(ctx context.Context, recipientHash string, cutoff time.Time) error
	// Purge deletes the recipient's stream entirely (full queue purge).
	Purge(ctx context.Context, recipientHash string) error
	// Len returns the number of pending messages.
	Len(ctx context.Context, recipientHash string) (int64, error)
}

// RedisOfflineQueue is the production OfflineQueue backed by a
// Redis-compatible client (go-redis *redis.Client or Upstash HTTP).
type RedisOfflineQueue struct {
	rdb cache.RedisClient
	ttl time.Duration
}

// NewRedisOfflineQueue wraps [rdb] with a retention window of [ttl]
// (30 days in production; shortened in tests).
func NewRedisOfflineQueue(rdb cache.RedisClient, ttl time.Duration) *RedisOfflineQueue {
	return &RedisOfflineQueue{rdb: rdb, ttl: ttl}
}

func queueKey(hash string) (string, error) { return cache.MsgQueueKey(hash) }

// Enqueue implements OfflineQueue. XADD and the retention XTRIM MINID are
// issued in one pipeline round trip.
func (q *RedisOfflineQueue) Enqueue(ctx context.Context, recipientHash string, m QueuedMessage) (string, error) {
	if m.Ciphertext == nil {
		m.Ciphertext = []byte{}
	}
	key, err := queueKey(recipientHash)
	if err != nil {
		return "", err
	}
	cutoff := strconv.FormatInt(time.Now().UTC().Add(-q.ttl).UnixMilli(), 10)

	pipe := q.rdb.Pipeline()
	xadd := pipe.XAdd(ctx, &redis.XAddArgs{
		Stream: key,
		Values: map[string]any{
			"msg_id":           m.MsgID,
			"sender_hash":      m.SenderHash,
			"ciphertext":       m.Ciphertext,
			"sent_at_ms":       m.SentAtMS,
			"sender_device_id": m.SenderDeviceID,
		},
	})
	pipe.XTrimMinID(ctx, key, cutoff)
	if _, err := pipe.Exec(ctx); err != nil {
		return "", fmt.Errorf("relay: enqueue: %w", err)
	}
	return xadd.Val(), nil
}

// ReadPending implements OfflineQueue (XREAD from the beginning, oldest
// first). An XLEN guard short-circuits empty streams before the XREAD — a
// no-op in production (real Redis returns empty immediately) and required
// for miniredis, whose XREAD never answers a missing/drained stream.
func (q *RedisOfflineQueue) ReadPending(ctx context.Context, recipientHash string, count int64) ([]QueuedMessage, error) {
	if count <= 0 {
		count = 100
	}
	key, err := queueKey(recipientHash)
	if err != nil {
		return nil, err
	}
	n, err := q.rdb.XLen(ctx, key).Result()
	if err != nil {
		return nil, fmt.Errorf("relay: read pending len: %w", err)
	}
	if n == 0 {
		return nil, ErrQueueEmpty
	}
	streams, err := q.rdb.XRead(ctx, &redis.XReadArgs{
		Streams: []string{key, "0"},
		Count:   count,
	}).Result()
	if err != nil {
		return nil, fmt.Errorf("relay: read pending: %w", err)
	}
	if len(streams) == 0 || len(streams[0].Messages) == 0 {
		return nil, ErrQueueEmpty
	}

	out := make([]QueuedMessage, 0, len(streams[0].Messages))
	for _, msg := range streams[0].Messages {
		out = append(out, QueuedMessage{
			EntryID:        msg.ID,
			MsgID:          strValue(msg.Values["msg_id"]),
			SenderHash:     strValue(msg.Values["sender_hash"]),
			Ciphertext:     bytesValue(msg.Values["ciphertext"]),
			SentAtMS:       int64Value(msg.Values["sent_at_ms"]),
			SenderDeviceID: strValue(msg.Values["sender_device_id"]),
		})
	}
	return out, nil
}

// Ack implements OfflineQueue. Removes the entry and, when the stream drains,
// deletes the key entirely (queue purge). The purge race is benign: a
// concurrent ack DEL of an already-drained stream is a no-op. (Implemented
// without a Lua script so miniredis can exercise it in unit tests.)
func (q *RedisOfflineQueue) Ack(ctx context.Context, recipientHash, entryID string) error {
	key, err := queueKey(recipientHash)
	if err != nil {
		return err
	}
	if err := q.rdb.XDel(ctx, key, entryID).Err(); err != nil {
		return fmt.Errorf("relay: ack: %w", err)
	}
	return q.removeAndPurge(ctx, recipientHash)
}

// AckByMsgID implements OfflineQueue. Locates the entry carrying [msgID] and
// acks it (a linear scan bounded by the 30-day retention window; acked via
// Ack once the entry ID is known). Unknown msg IDs are a no-op.
func (q *RedisOfflineQueue) AckByMsgID(ctx context.Context, recipientHash, msgID string) error {
	msgs, err := q.ReadPending(ctx, recipientHash, 0)
	if err != nil {
		if errors.Is(err, ErrQueueEmpty) {
			return nil
		}
		return err
	}
	for _, m := range msgs {
		if m.MsgID == msgID {
			return q.Ack(ctx, recipientHash, m.EntryID)
		}
	}
	return nil
}

// removeAndPurge deletes the stream key when it drains after a removal.
func (q *RedisOfflineQueue) removeAndPurge(ctx context.Context, recipientHash string) error {
	key, err := queueKey(recipientHash)
	if err != nil {
		return err
	}
	n, err := q.rdb.XLen(ctx, key).Result()
	if err != nil {
		return fmt.Errorf("relay: ack len: %w", err)
	}
	if n == 0 {
		if err := q.rdb.Del(ctx, key).Err(); err != nil {
			return fmt.Errorf("relay: ack purge: %w", err)
		}
	}
	return nil
}

// TrimOlderThan implements OfflineQueue (XTRIM MINID — entries with IDs
// older than the cutoff are dropped).
func (q *RedisOfflineQueue) TrimOlderThan(ctx context.Context, recipientHash string, cutoff time.Time) error {
	key, err := queueKey(recipientHash)
	if err != nil {
		return err
	}
	cutoffID := strconv.FormatInt(cutoff.UnixMilli(), 10)
	if err := q.rdb.XTrimMinID(ctx, key, cutoffID).Err(); err != nil {
		return fmt.Errorf("relay: trim: %w", err)
	}
	return nil
}

// Purge implements OfflineQueue.
func (q *RedisOfflineQueue) Purge(ctx context.Context, recipientHash string) error {
	key, err := queueKey(recipientHash)
	if err != nil {
		return err
	}
	if err := q.rdb.Del(ctx, key).Err(); err != nil {
		return fmt.Errorf("relay: purge: %w", err)
	}
	return nil
}

// Len implements OfflineQueue.
func (q *RedisOfflineQueue) Len(ctx context.Context, recipientHash string) (int64, error) {
	key, err := queueKey(recipientHash)
	if err != nil {
		return 0, err
	}
	n, err := q.rdb.XLen(ctx, key).Result()
	if err != nil {
		return 0, fmt.Errorf("relay: queue len: %w", err)
	}
	return n, nil
}

// value coercers (go-redis returns XMessage.Values entries as string for
// binary-safe storage; values may also surface as []byte).
func strValue(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case []byte:
		return string(t)
	case nil:
		return ""
	default:
		return fmt.Sprintf("%v", t)
	}
}

func bytesValue(v any) []byte {
	switch t := v.(type) {
	case []byte:
		return t
	case string:
		return []byte(t)
	default:
		return nil
	}
}

func int64Value(v any) int64 {
	switch t := v.(type) {
	case int64:
		return t
	case string:
		n, _ := strconv.ParseInt(t, 10, 64)
		return n
	case []byte:
		n, _ := strconv.ParseInt(string(t), 10, 64)
		return n
	default:
		return 0
	}
}
