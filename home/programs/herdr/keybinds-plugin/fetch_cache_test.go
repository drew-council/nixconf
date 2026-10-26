package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"
)

func TestCachedFetchHonorsModeAndTTL(t *testing.T) {
	now := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	for _, test := range []struct {
		name      string
		age       time.Duration
		mode      fetchMode
		wantValue string
		wantStale bool
		wantFetch bool
	}{
		{name: "fresh entry is reused", age: time.Minute, mode: fetchFresh, wantValue: "cached"},
		{name: "expired entry is refetched", age: fetchCacheTTL, mode: fetchFresh, wantValue: "fetched", wantFetch: true},
		{name: "future entry is refetched", age: -time.Minute, mode: fetchFresh, wantValue: "fetched", wantFetch: true},
		{name: "stale mode reuses expired entry", age: time.Hour, mode: fetchStale, wantValue: "cached", wantStale: true},
		{name: "stale mode reuses fresh entry", age: time.Minute, mode: fetchStale, wantValue: "cached"},
		{name: "refresh ignores fresh entry", age: time.Minute, mode: fetchRefresh, wantValue: "fetched", wantFetch: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			cache := fetchCache{dir: t.TempDir(), now: func() time.Time { return now }}
			if err := cache.write("entry", cacheEnvelope[string]{FetchedAt: now.Add(-test.age), Value: "cached"}); err != nil {
				t.Fatal(err)
			}

			var previous *string
			fetched := false
			value, stale, err := cachedFetch(cache, "entry", test.mode, &bytes.Buffer{}, func(cached *string) (string, error) {
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

			var entry cacheEnvelope[string]
			if !cache.read("entry", &entry) || entry.Value != test.wantValue {
				t.Fatalf("cache holds %q, want %q", entry.Value, test.wantValue)
			}
			if fetched && !entry.FetchedAt.Equal(now) {
				t.Fatalf("refetched entry stamped %v, want %v", entry.FetchedAt, now)
			}
		})
	}
}

func TestCachedFetchFallsBackToCacheOnError(t *testing.T) {
	now := time.Now()
	cache := fetchCache{dir: t.TempDir(), now: func() time.Time { return now }}
	if err := cache.write("entry", cacheEnvelope[string]{FetchedAt: now.Add(-time.Hour), Value: "cached"}); err != nil {
		t.Fatal(err)
	}

	var warnings bytes.Buffer
	value, stale, err := cachedFetch(cache, "entry", fetchFresh, &warnings, func(*string) (string, error) {
		return "", errors.New("offline")
	})
	if err != nil || value != "cached" || !stale {
		t.Fatalf("got %q stale %v err %v, want stale cached value", value, stale, err)
	}
	if !strings.Contains(warnings.String(), "offline") {
		t.Fatalf("warnings = %q, want the fetch error", warnings.String())
	}
}

func TestCachedFetchReturnsErrorWithoutCache(t *testing.T) {
	cache := fetchCache{dir: t.TempDir(), now: time.Now}
	_, _, err := cachedFetch(cache, "entry", fetchStale, &bytes.Buffer{}, func(*string) (string, error) {
		return "", errors.New("offline")
	})
	if err == nil || !strings.Contains(err.Error(), "offline") {
		t.Fatalf("err = %v, want the fetch error", err)
	}
}

func TestNewFetchCacheUsesXDGCacheHome(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", "/tmp/cache-home")
	first, err := newFetchCache("/work/sheer")
	if err != nil {
		t.Fatal(err)
	}
	second, err := newFetchCache("/other/sheer")
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

func TestFetchGitHubStackPagesRevalidatesByETag(t *testing.T) {
	repo := t.TempDir()
	full := testStackPage(githubStacksPerPage)
	calls := stubGitHubStacks(t, full, `[{"number":1}]`)

	pages, err := fetchGitHubStackPages(repo, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(pages) != 2 || pages[0].ETag != testETag(full) || string(pages[1].Body) != `[{"number":1}]` {
		t.Fatalf("pages = %+v, want both pages with ETags", pages)
	}
	if got := calls(); len(got) != 2 || strings.Contains(strings.Join(got, "\n"), "If-None-Match") {
		t.Fatalf("first fetch calls = %q, want two unconditional requests", got)
	}

	// Only the second page changes, so the first is answered with 304.
	calls = stubGitHubStacks(t, full, `[{"number":2}]`)
	pages, err = fetchGitHubStackPages(repo, pages)
	if err != nil {
		t.Fatal(err)
	}
	if string(pages[0].Body) != full || string(pages[1].Body) != `[{"number":2}]` {
		t.Fatalf("revalidated pages = %+v, want cached first page and new second page", pages)
	}
	for _, call := range calls() {
		if !strings.Contains(call, "--header If-None-Match: W/") {
			t.Errorf("revalidation call %q does not send If-None-Match", call)
		}
	}
}

func TestFetchGitHubStackPagesFollowsGrowthAndDropsShrinkage(t *testing.T) {
	repo := t.TempDir()
	full := testStackPage(githubStacksPerPage)
	stubGitHubStacks(t, full, `[]`)

	pages, err := fetchGitHubStackPages(repo, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(pages) != 2 {
		t.Fatalf("got %d pages, want 2", len(pages))
	}

	calls := stubGitHubStacks(t, full, full, `[{"number":1}]`)
	pages, err = fetchGitHubStackPages(repo, pages)
	if err != nil {
		t.Fatal(err)
	}
	if len(pages) != 3 {
		t.Fatalf("after growth got %d pages, want 3", len(pages))
	}
	var requested []string
	for _, call := range calls() {
		requested = append(requested, call[strings.LastIndex(call, "page="):][:6])
	}
	slices.Sort(requested)
	if want := []string{"page=1", "page=2", "page=3"}; !slices.Equal(requested, want) {
		t.Fatalf("requested %q, want %q", requested, want)
	}

	stubGitHubStacks(t, `[{"number":1}]`)
	pages, err = fetchGitHubStackPages(repo, pages)
	if err != nil {
		t.Fatal(err)
	}
	if len(pages) != 1 {
		t.Fatalf("after shrinking got %d pages, want 1", len(pages))
	}
}

func TestParseIncludedResponse(t *testing.T) {
	status, etag, body, err := parseIncludedResponse([]byte(
		"HTTP/2.0 200 OK\nCache-Control: private\r\nEtag: W/\"abc\"\r\n\r\n[{\"number\":1}]"))
	if err != nil {
		t.Fatal(err)
	}
	if status != 200 || etag != `W/"abc"` || string(body) != `[{"number":1}]` {
		t.Fatalf("got %d %q %q", status, etag, body)
	}

	status, _, body, err = parseIncludedResponse([]byte("HTTP/2.0 304 Not Modified\nEtag: \"abc\"\r\n\r\n"))
	if err != nil || status != 304 || len(body) != 0 {
		t.Fatalf("got %d %q %v, want empty 304", status, body, err)
	}

	if _, _, _, err := parseIncludedResponse([]byte("gh: not found")); err == nil {
		t.Fatal("expected an error for output without headers")
	}
}

// testStackPage returns a Stacks API page holding count stacks.
func testStackPage(count int) string {
	stacks := make([]map[string]int, count)
	for index := range stacks {
		stacks[index] = map[string]int{"number": index + 1}
	}
	data, _ := json.Marshal(stacks)
	return string(data)
}
