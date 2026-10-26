// Package fetchcache keeps network results on disk under
// $XDG_CACHE_HOME/herdrctl for a short time, so commands that run repeatedly,
// such as agents listing workspaces in a loop, do not hit remote rate limits.
package fetchcache

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"herdr-keybinds/internal/xdg"
)

// TTL bounds how long results are reused without contacting the network.
const TTL = 5 * time.Minute

// Mode controls when cached network results are reused.
type Mode int

const (
	// Fresh reuses results younger than TTL and refetches older ones.
	Fresh Mode = iota
	// Stale reuses results of any age, so a caller can show them at once
	// and refresh afterwards. It only waits on the network when nothing is
	// cached yet.
	Stale
	// Refresh always refetches, ignoring the TTL.
	Refresh
)

// Cache stores JSON network results for one scope under
// $XDG_CACHE_HOME/herdrctl.
type Cache struct {
	dir string
	// Now is the clock entries are stamped and aged with. Tests replace it.
	Now func() time.Time
}

// envelope records when a cached value was fetched.
type envelope[T any] struct {
	FetchedAt time.Time `json:"fetched_at"`
	Value     T         `json:"value"`
}

// New returns the cache for scope, a path such as a repository checkout. The
// directory keeps the path's base name for readability and a hash of the
// whole path so scopes never collide.
func New(scope string) (Cache, error) {
	base, err := xdg.CacheHome()
	if err != nil {
		return Cache{}, err
	}
	scope = filepath.Clean(scope)
	sum := sha256.Sum256([]byte(scope))
	name := filepath.Base(scope) + "-" + hex.EncodeToString(sum[:6])
	return Cache{dir: filepath.Join(base, "herdrctl", name), Now: time.Now}, nil
}

// read loads name into entry, reporting false when it is missing or corrupt.
func (cache Cache) read(name string, entry any) bool {
	data, err := os.ReadFile(filepath.Join(cache.dir, name+".json"))
	return err == nil && json.Unmarshal(data, entry) == nil
}

// write replaces name atomically, so concurrent herdrctl processes never read
// a partially written entry.
func (cache Cache) write(name string, entry any) error {
	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(cache.dir, 0o755); err != nil {
		return err
	}
	file, err := os.CreateTemp(cache.dir, "."+name+"-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err := file.Write(data); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), filepath.Join(cache.dir, name+".json"))
}

// Fetch returns name's cached value when mode allows it. Otherwise it calls
// fetch with the cached value, if any, so fetch can revalidate rather than
// download everything again, and caches the result. When fetch fails,
// the cached value is used with a warning. stale reports whether the value
// returned is older than TTL.
func Fetch[T any](
	cache Cache,
	name string,
	mode Mode,
	warnings io.Writer,
	fetch func(previous *T) (T, error),
) (value T, stale bool, err error) {
	var entry envelope[T]
	cached := cache.read(name, &entry)
	if cached {
		age := cache.Now().Sub(entry.FetchedAt)
		expired := age < 0 || age >= TTL
		if mode == Stale || (mode == Fresh && !expired) {
			return entry.Value, expired, nil
		}
	}

	var previous *T
	if cached {
		previous = &entry.Value
	}
	value, err = fetch(previous)
	if err != nil {
		if !cached {
			return value, false, err
		}
		fmt.Fprintf(warnings, "warning: %v; using %s cached at %s\n",
			err, name, entry.FetchedAt.Local().Format(time.DateTime))
		return entry.Value, true, nil
	}
	if err := cache.write(name, envelope[T]{FetchedAt: cache.Now(), Value: value}); err != nil {
		fmt.Fprintf(warnings, "warning: caching %s: %v\n", name, err)
	}
	return value, false, nil
}
