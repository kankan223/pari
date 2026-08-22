package relay

import (
	"context"
	"strconv"
	"sync"
	"time"
)

// InMemoryOfflineQueue is a development/staging OfflineQueue with no
// persistence. Messages are lost on restart — suitable for staging only.
type InMemoryOfflineQueue struct {
	mu   sync.Mutex
	ttl  time.Duration
	data map[string][]memEntry
}

type memEntry struct {
	msg QueuedMessage
	ts  time.Time
}

// NewInMemoryOfflineQueue builds an empty in-memory offline queue.
func NewInMemoryOfflineQueue(ttl time.Duration) *InMemoryOfflineQueue {
	return &InMemoryOfflineQueue{
		ttl:  ttl,
		data: make(map[string][]memEntry),
	}
}

func (q *InMemoryOfflineQueue) Enqueue(_ context.Context, recipientHash string, m QueuedMessage) (string, error) {
	q.mu.Lock()
	defer q.mu.Unlock()

	now := time.Now().UTC()
	seq := len(q.data[recipientHash])
	entryID := strconv.FormatInt(now.UnixMilli(), 10) + "-" + strconv.Itoa(seq)

	if m.Ciphertext == nil {
		m.Ciphertext = []byte{}
	}
	m.EntryID = entryID

	q.data[recipientHash] = append(q.data[recipientHash], memEntry{msg: m, ts: now})
	q.trimLocked(recipientHash, now.Add(-q.ttl))
	return entryID, nil
}

func (q *InMemoryOfflineQueue) ReadPending(_ context.Context, recipientHash string, count int64) ([]QueuedMessage, error) {
	q.mu.Lock()
	defer q.mu.Unlock()

	entries := q.data[recipientHash]
	if len(entries) == 0 {
		return nil, ErrQueueEmpty
	}
	if count <= 0 || count > int64(len(entries)) {
		count = int64(len(entries))
	}
	out := make([]QueuedMessage, count)
	for i := int64(0); i < count; i++ {
		out[i] = entries[i].msg
	}
	return out, nil
}

func (q *InMemoryOfflineQueue) Ack(_ context.Context, recipientHash, entryID string) error {
	q.mu.Lock()
	defer q.mu.Unlock()

	entries := q.data[recipientHash]
	for i, e := range entries {
		if e.msg.EntryID == entryID {
			q.data[recipientHash] = append(entries[:i], entries[i+1:]...)
			break
		}
	}
	if len(q.data[recipientHash]) == 0 {
		delete(q.data, recipientHash)
	}
	return nil
}

func (q *InMemoryOfflineQueue) AckByMsgID(ctx context.Context, recipientHash, msgID string) error {
	q.mu.Lock()
	entries := q.data[recipientHash]
	q.mu.Unlock()

	for _, e := range entries {
		if e.msg.MsgID == msgID {
			return q.Ack(ctx, recipientHash, e.msg.EntryID)
		}
	}
	return nil
}

func (q *InMemoryOfflineQueue) TrimOlderThan(_ context.Context, recipientHash string, cutoff time.Time) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.trimLocked(recipientHash, cutoff)
	return nil
}

func (q *InMemoryOfflineQueue) Purge(_ context.Context, recipientHash string) error {
	q.mu.Lock()
	defer q.mu.Unlock()
	delete(q.data, recipientHash)
	return nil
}

func (q *InMemoryOfflineQueue) Len(_ context.Context, recipientHash string) (int64, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	return int64(len(q.data[recipientHash])), nil
}

func (q *InMemoryOfflineQueue) trimLocked(recipientHash string, cutoff time.Time) {
	entries := q.data[recipientHash]
	trimmed := entries[:0]
	for _, e := range entries {
		if !e.ts.Before(cutoff) {
			trimmed = append(trimmed, e)
		}
	}
	if len(trimmed) == 0 {
		delete(q.data, recipientHash)
	} else {
		q.data[recipientHash] = trimmed
	}
}
