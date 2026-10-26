package fetchcache

import (
	"bytes"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestFetchHonorsModeAndTTL(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	for _, test := range []struct {
		name      string
		age       time.Duration
		mode      Mode
		wantValue string
		wantStale bool
		wantFetch bool
	}{
		{name: "fresh entry is reused", age: time.Minute, mode: Fresh, wantValue: "cached"},
		{name: "expired entry is refetched", age: TTL, mode: Fresh, wantValue: "fetched", wantFetch: true},
		{name: "future entry is refetched", age: -time.Minute, mode: Fresh, wantValue: "fetched", wantFetch: true},
		{name: "stale mode reuses expired entry", age: time.Hour, mode: Stale, wantValue: "cached", wantStale: true},
		{name: "stale mode reuses fresh entry", age: time.Minute, mode: Stale, wantValue: "cached"},
		{name: "refresh ignores fresh entry", age: time.Minute, mode: Refresh, wantValue: "fetched", wantFetch: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			cache := Cache{dir: t.TempDir(), Now: func() time.Time { return now }}
			if err := cache.write("entry", envelope[string]{FetchedAt: now.Add(-test.age), Value: "cached"}); err != nil {
				t.Fatal(err)
			}

			var previous *string
			fetched := false
			value, stale, err := Fetch(cache, "entry", test.mode, &bytes.Buffer{}, func(cached *string) (string, error) {
				fetched, previous = true, cached
				return "fetched", nil
			})
			if err != nil {
				t.Fatal(err)
			}
			if value != test.wantValue || stale != test.wantStale || fetched != test.wantFetch {
				t.Fatalf("got value %q stale %v fetched %v, want %q %v %v",
					value, stale, fetched, test.wantValue, test.wantStale, test.wantFetch)
			}
			if fetched && (previous == nil || *previous != "cached") {
				t.Fatalf("fetch got previous %v, want the cached value to revalidate", previous)
			}

			var entry envelope[string]
			if !cache.read("entry", &entry) || entry.Value != test.wantValue {
				t.Fatalf("cache holds %q, want %q", entry.Value, test.wantValue)
			}
			if fetched && !entry.FetchedAt.Equal(now) {
				t.Fatalf("refetched entry stamped %v, want %v", entry.FetchedAt, now)
			}
		})
	}
}

func TestFetchFallsBackToCacheOnError(t *testing.T) {
	now := time.Now()
	cache := Cache{dir: t.TempDir(), Now: func() time.Time { return now }}
	if err := cache.write("entry", envelope[string]{FetchedAt: now.Add(-time.Hour), Value: "cached"}); err != nil {
		t.Fatal(err)
	}

	var warnings bytes.Buffer
	value, stale, err := Fetch(cache, "entry", Fresh, &warnings, func(*string) (string, error) {
		return "", errors.New("offline")
	})
	if err != nil || value != "cached" || !stale {
		t.Fatalf("got %q stale %v err %v, want stale cached value", value, stale, err)
	}
	if !strings.Contains(warnings.String(), "offline") {
		t.Fatalf("warnings = %q, want the fetch error", warnings.String())
	}
}

func TestFetchReturnsErrorWithoutCache(t *testing.T) {
	cache := Cache{dir: t.TempDir(), Now: time.Now}
	_, _, err := Fetch(cache, "entry", Stale, &bytes.Buffer{}, func(*string) (string, error) {
		return "", errors.New("offline")
	})
	if err == nil || !strings.Contains(err.Error(), "offline") {
		t.Fatalf("err = %v, want the fetch error", err)
	}
}

func TestNewUsesXDGCacheHome(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", "/tmp/cache-home")
	first, err := New("/work/sheer")
	if err != nil {
		t.Fatal(err)
	}
	second, err := New("/other/sheer")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(first.dir, "/tmp/cache-home/herdrctl/sheer-") {
		t.Fatalf("cache dir = %q, want it under $XDG_CACHE_HOME/herdrctl", first.dir)
	}
	if first.dir == second.dir {
		t.Fatalf("checkouts share cache dir %q", first.dir)
	}
}
