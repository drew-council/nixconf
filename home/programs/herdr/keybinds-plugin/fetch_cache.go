package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// fetchCacheTTL bounds how long network results are reused without contacting
// the network, so agents that call herdrctl in a loop cannot run up GitHub's
// rate limit.
const fetchCacheTTL = 5 * time.Minute

// fetchMode controls when cached network results are reused.
type fetchMode int

const (
	// fetchFresh reuses results younger than fetchCacheTTL and refetches
	// older ones.
	fetchFresh fetchMode = iota
	// fetchStale reuses results of any age, so a caller can show them at once
	// and refresh afterwards. It only waits on the network when nothing is
	// cached yet.
	fetchStale
	// fetchRefresh always refetches, ignoring the TTL.
	fetchRefresh
)

// fetchCache stores JSON network results for one repository under
// $XDG_CACHE_HOME/herdrctl.
type fetchCache struct {
	dir string
	now func() time.Time
}

// cacheEnvelope records when a cached value was fetched.
type cacheEnvelope[T any] struct {
	FetchedAt time.Time `json:"fetched_at"`
	Value     T         `json:"value"`
}

// newFetchCache returns the cache for repo. The directory keeps the repo's
// name for readability and a hash of its path so checkouts never collide.
func newFetchCache(repo string) (fetchCache, error) {
	base, err := xdgBaseDir("XDG_CACHE_HOME", ".cache")
	if err != nil {
		return fetchCache{}, err
	}
	repo = filepath.Clean(repo)
	sum := sha256.Sum256([]byte(repo))
	name := filepath.Base(repo) + "-" + hex.EncodeToString(sum[:6])
	return fetchCache{dir: filepath.Join(base, "herdrctl", name), now: time.Now}, nil
}

// read loads name into entry, reporting false when it is missing or corrupt.
func (cache fetchCache) read(name string, entry any) bool {
	data, err := os.ReadFile(filepath.Join(cache.dir, name+".json"))
	return err == nil && json.Unmarshal(data, entry) == nil
}

// write replaces name atomically, so concurrent herdrctl processes never read
// a partially written entry.
func (cache fetchCache) write(name string, entry any) error {
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

// cachedFetch returns name's cached value when mode allows it. Otherwise it
// calls fetch with the cached value, if any, so fetch can revalidate rather
// than download everything again, and caches the result. When fetch fails,
// the cached value is used with a warning. stale reports whether the value
// returned is older than fetchCacheTTL.
func cachedFetch[T any](
	cache fetchCache,
	name string,
	mode fetchMode,
	warnings io.Writer,
	fetch func(previous *T) (T, error),
) (value T, stale bool, err error) {
	var entry cacheEnvelope[T]
	cached := cache.read(name, &entry)
	if cached {
		age := cache.now().Sub(entry.FetchedAt)
		expired := age < 0 || age >= fetchCacheTTL
		if mode == fetchStale || (mode == fetchFresh && !expired) {
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
	if err := cache.write(name, cacheEnvelope[T]{FetchedAt: cache.now(), Value: value}); err != nil {
		fmt.Fprintf(warnings, "warning: caching %s: %v\n", name, err)
	}
	return value, false, nil
}
