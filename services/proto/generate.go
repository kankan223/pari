// Package proto holds the API protocol buffer definitions (Task 4.1).
//
// Regenerate Go code after editing any .proto file:
//
//	cd services && go generate ./proto
//
// The generate directives below assume `protoc` and the pinned
// `protoc-gen-go` plugin (see ../tools.go) are on PATH.
package proto

//go:generate sh -c "protoc --go_out=. --go_opt=paths=source_relative *.proto"

// Placeholder ensures the package builds before any .proto files exist.
// Remove once real message definitions land.
const Placeholder = "proto definitions land in Phase 4 tasks"
