package relay

import (
	"context"
	"fmt"

	"github.com/coder/websocket"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

// Frame encoding (techstack §5.3: protobuf framing over WebSocket).
//
// coder/websocket's wsjson helper uses encoding/json, which cannot round-trip
// protobuf oneof payloads (the generated is*_Payload interface is not
// JSON-decodable). These helpers encode with protojson instead — the
// canonical JSON mapping for protobuf — so the wire format stays
// spec-compliant and oneofs survive. UseProtoNames emits the exact .proto
// field names (snake_case) for cross-language interop with the Flutter client.

var (
	frameMarshal = protojson.MarshalOptions{UseProtoNames: true}
	// DiscardUnknown keeps the server forward-compatible with clients that
	// ship newer proto fields before this deployment catches up.
	frameUnmarshal = protojson.UnmarshalOptions{DiscardUnknown: true}
)

// writeFrame encodes [msg] as a JSON text frame.
func writeFrame(ctx context.Context, c *websocket.Conn, msg proto.Message) error {
	b, err := frameMarshal.Marshal(msg)
	if err != nil {
		return fmt.Errorf("relay: encode frame: %w", err)
	}
	return c.Write(ctx, websocket.MessageText, b)
}

// readFrame decodes the next text frame into [msg].
func readFrame(ctx context.Context, c *websocket.Conn, msg proto.Message) error {
	_, b, err := c.Read(ctx)
	if err != nil {
		return err
	}
	if err := frameUnmarshal.Unmarshal(b, msg); err != nil {
		return fmt.Errorf("relay: decode frame: %w", err)
	}
	return nil
}
