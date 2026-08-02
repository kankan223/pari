// Package version exposes the build version, shared across public packages.
package version

// Version is the service build version. Override at build time with
// -ldflags "-X github.com/kankan223/pari/services/pkg/version.Version=<tag>".
var Version = "dev"

// String returns the current build version.
func String() string {
	return Version
}
