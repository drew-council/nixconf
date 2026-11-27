// Command archive compresses directories into .tar.zst, .tar.gz, or .zip
// archives and extracts them without writing outside the output directory.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/signal"
	"path"
	"path/filepath"
	"strings"

	"github.com/mholt/archives"
	"github.com/schollz/progressbar/v3"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)

type format interface {
	archives.Archiver
	archives.Extractor
}

var formats = []struct {
	ext    string
	format format
}{
	{".tar.zst", archives.CompressedArchive{Compression: archives.Zstd{}, Archival: archives.Tar{}, Extraction: archives.Tar{}}},
	{".tar.gz", archives.CompressedArchive{Compression: archives.Gz{}, Archival: archives.Tar{}, Extraction: archives.Tar{}}},
	{".zip", archives.Zip{}},
}

func main() {
	root := &cobra.Command{
		Use:               "archive",
		Short:             "Compress and extract archive files",
		SilenceUsage:      true,
		CompletionOptions: cobra.CompletionOptions{DisableDefaultCmd: true},
	}

	var compressForce bool
	compressCmd := &cobra.Command{
		Use:   "compress DIRECTORY [ARCHIVE]",
		Short: "Compress DIRECTORY into an archive",
		Long: "Compress DIRECTORY into an archive.\n\n" +
			"ARCHIVE is a path or a bare extension (.tar.zst, .tar.gz, .zip).\n" +
			"It defaults to DIRECTORY.tar.zst in the current directory.",
		Args: cobra.RangeArgs(1, 2),
		RunE: func(cmd *cobra.Command, args []string) error {
			return compress(cmd.Context(), args[0], optional(args, 1), compressForce)
		},
	}
	compressCmd.Flags().BoolVar(&compressForce, "force", false, "replace the archive if it already exists")

	var extractForce bool
	extractCmd := &cobra.Command{
		Use:   "extract ARCHIVE [DIRECTORY]",
		Short: "Extract ARCHIVE into a directory",
		Long: "Extract ARCHIVE into a directory.\n\n" +
			"DIRECTORY defaults to the archive name without its extension.",
		Args: cobra.RangeArgs(1, 2),
		RunE: func(cmd *cobra.Command, args []string) error {
			return extract(cmd.Context(), args[0], optional(args, 1), extractForce)
		},
	}
	extractCmd.Flags().BoolVar(&extractForce, "force", false, "replace the output directory if it already exists")

	root.AddCommand(compressCmd, extractCmd)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	if err := root.ExecuteContext(ctx); err != nil {
		os.Exit(1)
	}
}

func optional(args []string, i int) string {
	if i < len(args) {
		return args[i]
	}
	return ""
}

// formatFor returns the format matching name's extension
// and name without that extension.
func formatFor(name string) (format, string, error) {
	lower := strings.ToLower(name)
	for _, f := range formats {
		if strings.HasSuffix(lower, f.ext) {
			return f.format, name[:len(name)-len(f.ext)], nil
		}
	}
	return nil, "", fmt.Errorf("unsupported archive extension for %s: expected .tar.zst, .tar.gz, or .zip", name)
}

func absPath(p string) (string, error) {
	if p == "~" || strings.HasPrefix(p, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		p = filepath.Join(home, p[1:])
	}
	return filepath.Abs(p)
}

// clearTarget fails if path exists, unless force is set, in which case it removes path.
func clearTarget(path string, force bool) error {
	if _, err := os.Lstat(path); errors.Is(err, fs.ErrNotExist) {
		return nil
	} else if err != nil {
		return err
	}
	if !force {
		return fmt.Errorf("%s already exists (use --force to replace it)", path)
	}
	return os.RemoveAll(path)
}

func newBar(total int64, desc string) *progressbar.ProgressBar {
	if !term.IsTerminal(int(os.Stderr.Fd())) {
		return progressbar.DefaultBytesSilent(total, desc)
	}
	return progressbar.DefaultBytes(total, desc)
}

func compress(ctx context.Context, dir, dest string, force bool) error {
	dir, err := absPath(dir)
	if err != nil {
		return err
	}
	if info, err := os.Stat(dir); err != nil {
		return err
	} else if !info.IsDir() {
		return fmt.Errorf("not a directory: %s", dir)
	}

	if dest == "" {
		dest = ".tar.zst"
	}
	if _, stem, err := formatFor(dest); err == nil && stem == "" {
		dest = filepath.Base(dir) + dest
	}
	if dest, err = absPath(dest); err != nil {
		return err
	}
	f, _, err := formatFor(filepath.Base(dest))
	if err != nil {
		return err
	}
	if err := clearTarget(dest, force); err != nil {
		return err
	}
	fmt.Printf("Compressing %s to %s\n", dir, dest)

	// A trailing separator archives the directory's contents
	// without the directory itself.
	files, err := archives.FilesFromDisk(ctx, nil, map[string]string{dir + string(filepath.Separator): ""})
	if err != nil {
		return err
	}
	src, err := os.OpenRoot(dir)
	if err != nil {
		return err
	}
	defer src.Close()

	var bar *progressbar.ProgressBar
	var total int64
	for i, file := range files {
		switch {
		case file.LinkTarget != "":
			// Root.Stat fails on links that are broken or escape dir.
			if _, err := src.Stat(file.NameInArchive); err != nil {
				return fmt.Errorf("refusing to archive symlink %s -> %s: %w", file.NameInArchive, file.LinkTarget, err)
			}
		case file.Mode().IsRegular():
			total += file.Size()
			open := file.Open
			files[i].Open = func() (fs.File, error) {
				f, err := open()
				if err != nil {
					return nil, err
				}
				return progressFile{f, bar}, nil
			}
		case !file.IsDir():
			return fmt.Errorf("unsupported file type %s for %s", file.Mode().Type(), file.NameInArchive)
		}
	}
	bar = newBar(total, "compress")
	defer bar.Close()

	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	out, err := os.Create(dest)
	if err != nil {
		return err
	}
	if err := errors.Join(f.Archive(ctx, out, files), out.Close()); err != nil {
		os.Remove(dest)
		return err
	}
	fmt.Printf("created %s\n", dest)
	return nil
}

type progressFile struct {
	fs.File
	bar *progressbar.ProgressBar
}

func (p progressFile) Read(b []byte) (int, error) {
	n, err := p.File.Read(b)
	p.bar.Add(n)
	return n, err
}

func extract(ctx context.Context, src, dest string, force bool) error {
	src, err := absPath(src)
	if err != nil {
		return err
	}
	f, stem, err := formatFor(filepath.Base(src))
	if err != nil {
		return err
	}
	if dest == "" {
		if stem == "" {
			return fmt.Errorf("cannot infer an output directory from %s", src)
		}
		dest = stem
	}
	if dest, err = absPath(dest); err != nil {
		return err
	}

	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if info, err := in.Stat(); err != nil {
		return err
	} else if !info.Mode().IsRegular() {
		return fmt.Errorf("not a file: %s", src)
	}

	if err := clearTarget(dest, force); err != nil {
		return err
	}
	fmt.Printf("Extracting %s to %s\n", src, dest)
	if err := os.MkdirAll(dest, 0o755); err != nil {
		return err
	}
	root, err := os.OpenRoot(dest)
	if err != nil {
		return err
	}
	bar := newBar(-1, "extract")
	err = f.Extract(ctx, in, func(_ context.Context, file archives.FileInfo) error {
		return extractFile(root, file, bar)
	})
	bar.Close()
	if err := errors.Join(err, root.Close()); err != nil {
		os.RemoveAll(dest)
		return err
	}
	fmt.Printf("extracted %s\n", dest)
	return nil
}

// extractFile writes one archive entry under root.
// Root keeps every operation inside the output directory,
// including writes through symlinks made by earlier entries.
func extractFile(root *os.Root, file archives.FileInfo, w io.Writer) error {
	name := path.Clean(file.NameInArchive)
	if !filepath.IsLocal(name) {
		return fmt.Errorf("refusing unsafe entry %q", file.NameInArchive)
	}
	if err := root.MkdirAll(path.Dir(name), 0o755); err != nil {
		return err
	}

	mode := file.Mode()
	switch {
	case mode.IsDir():
		if err := root.MkdirAll(name, 0o755); err != nil {
			return err
		}
		// Keep directories writable so their entries can still be extracted.
		return root.Chmod(name, mode.Perm()|0o700)
	case mode&fs.ModeSymlink != 0:
		target := file.LinkTarget
		if path.IsAbs(target) || !filepath.IsLocal(path.Join(path.Dir(name), target)) {
			return fmt.Errorf("refusing symlink %s -> %s: target escapes the output directory", name, target)
		}
		return root.Symlink(target, name)
	case file.LinkTarget != "":
		return fmt.Errorf("hard links are not supported: %s", name)
	case mode.IsRegular():
		in, err := file.Open()
		if err != nil {
			return err
		}
		defer in.Close()
		out, err := root.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
		if err != nil {
			return err
		}
		_, err = io.Copy(io.MultiWriter(out, w), in)
		if err := errors.Join(err, out.Close()); err != nil {
			return err
		}
		return root.Chmod(name, mode.Perm())
	default:
		return fmt.Errorf("unsupported entry type %s for %s", mode.Type(), name)
	}
}
