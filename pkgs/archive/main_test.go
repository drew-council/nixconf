package main

import (
	"archive/tar"
	"compress/gzip"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTree(t *testing.T, dir string) {
	t.Helper()
	must(t, os.MkdirAll(filepath.Join(dir, "sub", "empty"), 0o755))
	must(t, os.WriteFile(filepath.Join(dir, "sub", "file.txt"), []byte("hello"), 0o644))
	must(t, os.WriteFile(filepath.Join(dir, "run.sh"), []byte("#!/bin/sh\n"), 0o755))
	must(t, os.Symlink("sub/file.txt", filepath.Join(dir, "link")))
}

// snapshot describes every entry under dir by mode, content, and link target.
func snapshot(t *testing.T, dir string) map[string]string {
	t.Helper()
	got := map[string]string{}
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil || p == dir {
			return err
		}
		rel, _ := filepath.Rel(dir, p)
		info, err := d.Info()
		if err != nil {
			return err
		}
		desc := info.Mode().String()
		switch {
		case info.Mode()&fs.ModeSymlink != 0:
			target, err := os.Readlink(p)
			if err != nil {
				return err
			}
			desc += " -> " + target
		case info.Mode().IsRegular():
			data, err := os.ReadFile(p)
			if err != nil {
				return err
			}
			desc += " " + string(data)
		}
		got[rel] = desc
		return nil
	})
	must(t, err)
	return got
}

func TestRoundTrip(t *testing.T) {
	for _, f := range formats {
		t.Run(f.ext, func(t *testing.T) {
			tmp := t.TempDir()
			src := filepath.Join(tmp, "src")
			writeTree(t, src)
			archive := filepath.Join(tmp, "out"+f.ext)
			out := filepath.Join(tmp, "out")

			must(t, compress(t.Context(), src, archive, false))
			must(t, extract(t.Context(), archive, out, false))

			want, got := snapshot(t, src), snapshot(t, out)
			if len(want) != len(got) {
				t.Fatalf("entries = %v, want %v", got, want)
			}
			for name, desc := range want {
				if got[name] != desc {
					t.Errorf("%s = %q, want %q", name, got[name], desc)
				}
			}
		})
	}
}

func TestDefaultPaths(t *testing.T) {
	tmp := t.TempDir()
	t.Chdir(tmp)
	writeTree(t, filepath.Join(tmp, "proj"))

	must(t, compress(t.Context(), "proj", "", false))
	must(t, compress(t.Context(), "proj", ".zip", false))
	must(t, os.Rename("proj", "orig"))
	must(t, extract(t.Context(), "proj.zip", "", false))

	for _, name := range []string{"proj.tar.zst", "proj.zip", "proj/sub/file.txt"} {
		if _, err := os.Lstat(name); err != nil {
			t.Error(err)
		}
	}
}

func TestForce(t *testing.T) {
	tmp := t.TempDir()
	src := filepath.Join(tmp, "src")
	writeTree(t, src)
	archive := filepath.Join(tmp, "a.tar.gz")
	must(t, os.WriteFile(archive, nil, 0o644))

	if err := compress(t.Context(), src, archive, false); err == nil {
		t.Fatal("compress over an existing archive succeeded without --force")
	}
	must(t, compress(t.Context(), src, archive, true))
}

func TestCompressRejectsUnsafeSymlinks(t *testing.T) {
	for name, target := range map[string]string{
		"escaping": "../outside",
		"absolute": "/etc/passwd",
		"broken":   "missing",
	} {
		t.Run(name, func(t *testing.T) {
			tmp := t.TempDir()
			src := filepath.Join(tmp, "src")
			must(t, os.Mkdir(src, 0o755))
			must(t, os.WriteFile(filepath.Join(tmp, "outside"), nil, 0o644))
			must(t, os.Symlink(target, filepath.Join(src, "link")))

			err := compress(t.Context(), src, filepath.Join(tmp, "a.tar.zst"), false)
			if err == nil || !strings.Contains(err.Error(), "refusing to archive symlink") {
				t.Fatalf("err = %v, want symlink refusal", err)
			}
		})
	}
}

func TestExtractRejectsUnsafeEntries(t *testing.T) {
	tests := map[string]tar.Header{
		"traversal":        {Name: "../evil", Typeflag: tar.TypeReg, Mode: 0o644},
		"absolute":         {Name: "/tmp/evil", Typeflag: tar.TypeReg, Mode: 0o644},
		"escaping symlink": {Name: "a/link", Typeflag: tar.TypeSymlink, Linkname: "../../x"},
		"absolute symlink": {Name: "link", Typeflag: tar.TypeSymlink, Linkname: "/etc"},
		"hard link":        {Name: "hard", Typeflag: tar.TypeLink, Linkname: "other"},
		"device":           {Name: "fifo", Typeflag: tar.TypeFifo},
	}
	for name, hdr := range tests {
		t.Run(name, func(t *testing.T) {
			tmp := t.TempDir()
			archive := filepath.Join(tmp, "bad.tar.gz")
			writeTarGz(t, archive, hdr)
			out := filepath.Join(tmp, "out")

			if err := extract(t.Context(), archive, out, false); err == nil {
				t.Fatal("extract succeeded")
			}
			if _, err := os.Lstat(out); !os.IsNotExist(err) {
				t.Errorf("output directory left behind: %v", err)
			}
		})
	}
}

func TestExtractRejectsWritesThroughEscapingSymlink(t *testing.T) {
	tmp := t.TempDir()
	archive := filepath.Join(tmp, "bad.tar.gz")
	// Each entry looks local on its own,
	// but d/l/m resolves to the parent of the output directory.
	writeTarGz(t, archive,
		tar.Header{Name: "d/", Typeflag: tar.TypeDir, Mode: 0o755},
		tar.Header{Name: "d/l", Typeflag: tar.TypeSymlink, Linkname: ".."},
		tar.Header{Name: "d/l/m", Typeflag: tar.TypeSymlink, Linkname: ".."},
		tar.Header{Name: "d/l/m/evil", Typeflag: tar.TypeReg, Mode: 0o644},
	)
	if err := extract(t.Context(), archive, filepath.Join(tmp, "out"), false); err == nil {
		t.Fatal("extract succeeded")
	}
	if _, err := os.Lstat(filepath.Join(tmp, "evil")); !os.IsNotExist(err) {
		t.Errorf("wrote outside the output directory: %v", err)
	}
}

func writeTarGz(t *testing.T, path string, headers ...tar.Header) {
	t.Helper()
	f, err := os.Create(path)
	must(t, err)
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	for _, hdr := range headers {
		must(t, tw.WriteHeader(&hdr))
	}
	must(t, tw.Close())
	must(t, gz.Close())
	must(t, f.Close())
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}
