//go:build tools

// Package tools pins code-generation tool versions so `go mod tidy` keeps
// them in go.mod/go.sum without them being part of the service binaries.
package tools

import (
	_ "google.golang.org/protobuf/cmd/protoc-gen-go"
)
