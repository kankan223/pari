// Package events provides the event-bus (NATS) connection factory.
package events

import (
	"fmt"

	"github.com/nats-io/nats.go"
)

// NewConnection opens a NATS connection to [url].
//
// NOTE: this dials the network — call it only when the service is ready to
// connect (e.g. during startup wiring, not in unit tests).
func NewConnection(url string) (*nats.Conn, error) {
	conn, err := nats.Connect(url)
	if err != nil {
		return nil, fmt.Errorf("connect nats: %w", err)
	}
	return conn, nil
}
