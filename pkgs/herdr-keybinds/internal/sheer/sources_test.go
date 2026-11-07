package sheer

import (
	"encoding/json"
	"reflect"
	"slices"
	"strings"
	"testing"
)

func TestParseLocalStacks(t *testing.T) {
	stacks, err := parseLocalStacks([]byte(`{
		"schemaVersion": 1,
		"stacks": [
			{"id": "1", "number": 27930, "trunk": {"branch": "main"}, "branches": [
				{"branch": "drew/a", "pullRequest": {"number": 1, "merged": true}},
				{"branch": "drew/b", "pullRequest": {"number": 2}},
				{"branch": "drew/c"}
			]},
			{"trunk": {"branch": "main"}, "branches": []}
		]
	}`))
	if err != nil {
		t.Fatal(err)
	}
	want := []catalogEntry{{
		Kind:   entryStack,
		Number: 27930,
		Local:  true,
		Branches: []stackLayer{
			{Name: "drew/a", Merged: true},
			{Name: "drew/b"},
			{Name: "drew/c"},
		},
	}}
	if !reflect.DeepEqual(stacks, want) {
		t.Fatalf("stacks = %#v, want %#v", stacks, want)
	}
}

func TestParseRemoteStacks(t *testing.T) {
	stacks, err := parseRemoteStacks([]githubStackPage{
		{Body: json.RawMessage(`[{"number": 30033, "pull_requests": [
			{"number": 1, "merged_at": "2026-10-01T00:00:00Z", "head": {"ref": "drew/a"}},
			{"number": 2, "merged_at": null, "head": {"ref": "drew/b"}}
		]}]`)},
		{Body: json.RawMessage(`[{"number": 0, "pull_requests": [{"head": {"ref": "ignored"}}]}, {"number": 5, "pull_requests": []}]`)},
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []catalogEntry{{
		Kind:   entryStack,
		Number: 30033,
		Remote: true,
		Branches: []stackLayer{
			{Name: "drew/a", Merged: true},
			{Name: "drew/b"},
		},
	}}
	if !reflect.DeepEqual(stacks, want) {
		t.Fatalf("stacks = %#v, want %#v", stacks, want)
	}
}

func TestFetchGitHubStackPagesRevalidatesByETag(t *testing.T) {
	root := t.TempDir()
	full := testStackPage(githubStacksPerPage)
	calls := stubGitHubStacks(t, full, `[{"number":1}]`)

	pages, err := fetchGitHubStackPages(root, nil)
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
	pages, err = fetchGitHubStackPages(root, pages)
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
	root := t.TempDir()
	full := testStackPage(githubStacksPerPage)
	stubGitHubStacks(t, full, `[]`)

	pages, err := fetchGitHubStackPages(root, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(pages) != 2 {
		t.Fatalf("got %d pages, want 2", len(pages))
	}

	calls := stubGitHubStacks(t, full, full, `[{"number":1}]`)
	pages, err = fetchGitHubStackPages(root, pages)
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
	pages, err = fetchGitHubStackPages(root, pages)
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
