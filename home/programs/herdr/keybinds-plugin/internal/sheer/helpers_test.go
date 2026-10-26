package sheer

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"herdr-keybinds/internal/herdr"
	"herdr-keybinds/internal/herdr/herdrtest"
)

// testRepo returns a repo for root that talks to client and caches in a
// fresh directory, so tests never touch the real cache.
func testRepo(t *testing.T, client *herdr.Client, root string) *repo {
	t.Helper()
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	r, err := newRepo(client, root)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

// fakeSources is the raw output of each source loadCatalog reads.
// remoteStacks holds one JSON array per Stacks API page.
type fakeSources struct {
	localStacks  string
	localRefs    string
	remoteStacks []string
	originHeads  string
}

// stubSources stubs git and gh so loadCatalog reads sources: the
// gh stack catalog file, for-each-ref, the Stacks API, and ls-remote.
func stubSources(t *testing.T, sources fakeSources) func() []string {
	t.Helper()

	commonDir := t.TempDir()
	if sources.localStacks != "" {
		if err := os.WriteFile(filepath.Join(commonDir, stackCatalogFile), []byte(sources.localStacks), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("STUB_COMMON_DIR", commonDir)
	t.Setenv("STUB_LOCAL_REFS", sources.localRefs)
	t.Setenv("STUB_ORIGIN_HEADS", sources.originHeads)
	gitCalls := stubGit(t, "case \"$*\" in\n"+
		"*rev-parse*) printf '%s\\n' \"$STUB_COMMON_DIR\" ;;\n"+
		"*for-each-ref*) printf '%b' \"$STUB_LOCAL_REFS\" ;;\n"+
		"*ls-remote*) printf '%b' \"$STUB_ORIGIN_HEADS\" ;;\n"+
		"esac\n")
	stubGitHubStacks(t, sources.remoteStacks...)
	return gitCalls
}

// stubGitHubStacks puts a gh on PATH that serves pages as the Stacks API
// would through gh api --include, and returns its recorded argument lines.
// Each page's ETag is derived from its content, and a request whose
// If-None-Match matches it gets 304 Not Modified, exiting 1 like gh does.
// Pages past the last are empty. The script uses only shell builtins because
// stubGit leaves nothing else on PATH. Call it again to change the pages.
func stubGitHubStacks(t *testing.T, pages ...string) func() []string {
	t.Helper()

	for index, page := range pages {
		t.Setenv(fmt.Sprintf("STUB_PAGE_%d", index+1), page)
		t.Setenv(fmt.Sprintf("STUB_ETAG_%d", index+1), testETag(page))
	}
	t.Setenv("STUB_PAGE_COUNT", strconv.Itoa(len(pages)))
	ghLog := filepath.Join(t.TempDir(), "gh.log")
	t.Setenv("GH_LOG", ghLog)

	binDir := t.TempDir()
	script := `#!/bin/sh
printf '%s\n' "$*" >> "$GH_LOG"
page=
for arg in "$@"; do
	case "$arg" in *page=*) page=${arg##*page=} ;; esac
done
body='[]'
etag='W/"empty"'
if [ "$page" -le "$STUB_PAGE_COUNT" ]; then
	eval "body=\$STUB_PAGE_$page"
	eval "etag=\$STUB_ETAG_$page"
fi
case "$*" in *"If-None-Match: $etag"*)
	printf 'HTTP/2.0 304 Not Modified\nEtag: %s\r\n\r\n' "$etag"
	printf 'gh: HTTP 304\n' >&2
	exit 1
esac
printf 'HTTP/2.0 200 OK\nEtag: %s\r\nX-Ratelimit-Used: 1\r\n\r\n%s' "$etag" "$body"
`
	if err := os.WriteFile(filepath.Join(binDir, "gh"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	return func() []string {
		t.Helper()
		calls, err := os.ReadFile(ghLog)
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		if err != nil {
			t.Fatal(err)
		}
		return strings.Split(strings.TrimSuffix(string(calls), "\n"), "\n")
	}
}

// testETag returns the weak ETag the gh stub serves for a page body.
func testETag(page string) string {
	sum := sha256.Sum256([]byte(page))
	return `W/"` + hex.EncodeToString(sum[:8]) + `"`
}

func worktreeListResponse(root string, worktrees ...map[string]any) herdrtest.Response {
	list := []any{map[string]any{
		"branch":             "main",
		"is_linked_worktree": false,
		"path":               root,
	}}
	for _, worktree := range worktrees {
		list = append(list, worktree)
	}
	return herdrtest.Response{Result: map[string]any{"type": "worktree_list", "worktrees": list}}
}

func worktreeCreatedResponse(branch string) herdrtest.Response {
	return herdrtest.Response{Result: map[string]any{
		"type": "worktree_created",
		"worktree": map[string]any{
			"branch":            branch,
			"label":             branchLabel(branch),
			"open_workspace_id": "w2",
			"path":              "/tmp/worktrees/sheer/" + strings.ReplaceAll(branch, "/", "-"),
		},
	}}
}

func paneListResponse() herdrtest.Response {
	return herdrtest.Response{Result: map[string]any{
		"type": "pane_list",
		"panes": []any{
			map[string]any{
				"pane_id":      "w2:p1",
				"tab_id":       "w2:t1",
				"workspace_id": "w2",
			},
		},
	}}
}

func mainWorkspaceListResponse(root string) herdrtest.Response {
	return herdrtest.Response{Result: map[string]any{
		"type": "workspace_list",
		"workspaces": []any{
			map[string]any{
				"workspace_id": "w-main",
				"label":        "sheer",
				"worktree": map[string]any{
					"checkout_path":      root,
					"is_linked_worktree": false,
					"repo_key":           root + "/.git",
					"repo_name":          "sheer",
					"repo_root":          root,
				},
			},
		},
	}}
}

func stubFzf(t *testing.T, output string, status int) (string, string, string) {
	t.Helper()

	binDir := t.TempDir()
	inputPath := filepath.Join(t.TempDir(), "fzf-input")
	argsPath := filepath.Join(t.TempDir(), "fzf-args")
	fzf := filepath.Join(binDir, "fzf")
	// Only shell builtins, since stubGit can leave nothing else on PATH.
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$FZF_ARGS\"\n" +
		"while IFS= read -r line; do printf '%s\\n' \"$line\"; done > \"$FZF_INPUT\"\n" +
		"printf '%s' \"$FZF_OUTPUT\"\nexit \"$FZF_STATUS\"\n"
	if err := os.WriteFile(fzf, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("FZF_ARGS", argsPath)
	t.Setenv("FZF_INPUT", inputPath)
	t.Setenv("FZF_OUTPUT", output)
	t.Setenv("FZF_STATUS", strconv.Itoa(status))
	return fzf, inputPath, argsPath
}

// stubGit puts a logging git on PATH and returns the recorded argument lines.
// The extra script body runs after logging so tests can control exit codes and
// output.
func stubGit(t *testing.T, script string) func() []string {
	t.Helper()

	binDir := t.TempDir()
	gitLog := filepath.Join(t.TempDir(), "git.log")
	git := filepath.Join(binDir, "git")
	body := "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$GIT_LOG\"\n" + script
	if err := os.WriteFile(git, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", binDir)
	t.Setenv("GIT_LOG", gitLog)

	return func() []string {
		t.Helper()
		calls, err := os.ReadFile(gitLog)
		if err != nil {
			t.Fatal(err)
		}
		return strings.Split(strings.TrimSuffix(string(calls), "\n"), "\n")
	}
}
