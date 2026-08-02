# Civic Commons — Go Services

Phase 4 backend foundation (API Gateway & backend services), Go 1.22+.

## Layout (standard Go project layout)

```
services/
├── cmd/                    # entry points
│   └── api/                #   API gateway service binary
├── internal/               # private application/domain logic
│   ├── config/             #   env-based configuration (never logs secrets)
│   ├── database/           #   DB open helpers (postgres + sqlcipher drivers)
│   ├── cache/              #   Redis client factory
│   ├── events/             #   NATS connection factory
│   └── storage/            #   MinIO client factory
├── pkg/                    # public/shared library code
│   └── version/
├── proto/                  # protocol buffer definitions + go:generate
├── go.mod                  # module github.com/kankan223/pari/services (Go 1.22)
├── go.sum
├── .golangci.yml           # strict static-analysis rules
└── tools.go                # pinned codegen tool versions (build-tagged)
```

## Module & dependencies

Pinned direct dependencies (see `go.mod`; also maintained by `go mod tidy`):

- `github.com/mutecomm/go-sqlcipher` — SQLCipher driver (blank import, driver name `sqlite3`)
- `github.com/lib/pq` — PostgreSQL driver (blank import, driver name `postgres`)
- `github.com/redis/go-redis/v9` — Redis client
- `github.com/nats-io/nats.go` — NATS client
- `github.com/minio/minio-go/v7` — MinIO S3 client
- `google.golang.org/protobuf` — protobuf runtime + `protoc-gen-go` (tool pin)

## Tooling

```sh
go mod tidy          # resolve deps (no conflicts)
go vet ./...         # static analysis
go test -race ./...  # unit tests
golangci-lint run    # strict linters (see .golangci.yml)
./scripts/generate_proto.sh   # regenerate protobuf Go code (go generate)
./scripts/verify_go_deps.sh   # SECURITY CHECKPOINT: no cloud AI/telemetry SDKs
```

## Security posture

- No cloud-based AI, analytics, or telemetry SDKs are permitted in Go
  dependencies — enforced by `scripts/verify_go_deps.sh` (deny-list scan of
  `go.mod` + `go.sum`).
- Configuration is read from environment variables; secrets are never logged.
- All data-layer work is SQLCipher-encrypted at rest / TLS-in-transit by design.
