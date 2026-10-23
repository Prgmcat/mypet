package main

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/Prgmcat/mypet/server/internal/db"
)

type backupManifest struct {
	Version    string `json:"version"`
	CreatedAt  string `json:"createdAt"`
	DBSHA256   string `json:"dbSha256"`
	HasUploads bool   `json:"hasUploads"`
	App        string `json:"app"`
}

func dataDBPath(dataDir string) string {
	return filepath.Join(dataDir, "mypet.db")
}

func backupTimestamp() string {
	return time.Now().UTC().Format("20060102-150405")
}

// backupTo writes a zip containing mypet.db and the uploads directory.
func backupTo(dataDir, outDir string) (string, error) {
	dbPath := dataDBPath(dataDir)
	if _, err := os.Stat(dbPath); err != nil {
		return "", fmt.Errorf("database not found at %s: %w", dbPath, err)
	}
	if err := os.MkdirAll(outDir, 0o700); err != nil {
		return "", err
	}
	stamp := backupTimestamp()
	tmpDB := filepath.Join(outDir, fmt.Sprintf(".mypet-%s.db", stamp))
	_ = os.Remove(tmpDB)
	d, err := db.Open(dbPath)
	if err != nil {
		return "", err
	}
	quoted := strings.ReplaceAll(tmpDB, "'", "''")
	_, vacuumErr := d.ExecContext(context.Background(), fmt.Sprintf("VACUUM INTO '%s'", quoted))
	d.Close()
	if vacuumErr != nil {
		return "", fmt.Errorf("vacuum into backup: %w", vacuumErr)
	}
	defer os.Remove(tmpDB)

	digest, err := fileSHA256(tmpDB)
	if err != nil {
		return "", err
	}
	uploadsDir := filepath.Join(dataDir, "uploads")
	_, uploadsErr := os.Stat(uploadsDir)
	hasUploads := uploadsErr == nil

	zipPath := filepath.Join(outDir, fmt.Sprintf("mypet-%s.zip", stamp))
	file, err := os.OpenFile(zipPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return "", err
	}
	zw := zip.NewWriter(file)
	writeErr := func() error {
		if err := addFileToZip(zw, tmpDB, "mypet.db"); err != nil {
			return err
		}
		if hasUploads {
			if err := addTreeToZip(zw, uploadsDir, "uploads"); err != nil {
				return err
			}
		}
		manifest, _ := json.MarshalIndent(backupManifest{
			Version:    "1",
			CreatedAt:  time.Now().UTC().Format(time.RFC3339),
			DBSHA256:   digest,
			HasUploads: hasUploads,
			App:        "mypet",
		}, "", "  ")
		w, err := zw.Create("manifest.json")
		if err != nil {
			return err
		}
		_, err = w.Write(manifest)
		return err
	}()
	if closeErr := zw.Close(); writeErr == nil {
		writeErr = closeErr
	}
	if closeErr := file.Close(); writeErr == nil {
		writeErr = closeErr
	}
	if writeErr != nil {
		_ = os.Remove(zipPath)
		return "", writeErr
	}
	return zipPath, nil
}

func fileSHA256(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hasher := sha256.New()
	if _, err := io.Copy(hasher, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hasher.Sum(nil)), nil
}

func addFileToZip(zw *zip.Writer, path, name string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	header, err := zip.FileInfoHeader(info)
	if err != nil {
		return err
	}
	header.Name = name
	header.Method = zip.Deflate
	header.SetMode(0o600)
	writer, err := zw.CreateHeader(header)
	if err != nil {
		return err
	}
	_, err = io.Copy(writer, file)
	return err
}

func addTreeToZip(zw *zip.Writer, root, prefix string) error {
	var paths []string
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return nil
		}
		paths = append(paths, path)
		return nil
	})
	if err != nil {
		return err
	}
	sort.Strings(paths)
	for _, path := range paths {
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		name := filepath.ToSlash(filepath.Join(prefix, rel))
		if err := addFileToZip(zw, path, name); err != nil {
			return err
		}
	}
	return nil
}

func safeArchiveName(name string) bool {
	clean := filepath.ToSlash(filepath.Clean(name))
	if clean == "." || strings.HasPrefix(clean, "../") || strings.HasPrefix(clean, "/") {
		return false
	}
	if clean != "mypet.db" && clean != "manifest.json" &&
		!strings.HasPrefix(clean, "uploads/") {
		return false
	}
	return true
}

func runRestore(args []string) error {
	fs := flag.NewFlagSet("restore", flag.ExitOnError)
	dataDir := fs.String("data", "./data", "data directory")
	fromPath := fs.String("from", "", "backup zip to restore")
	backupOut := fs.String("backup-out", "./backup", "directory for the automatic pre-restore backup")
	fs.Parse(args)
	if strings.TrimSpace(*fromPath) == "" {
		return errors.New("restore requires -from <backup.zip>")
	}
	archive, err := zip.OpenReader(*fromPath)
	if err != nil {
		return fmt.Errorf("open backup: %w", err)
	}
	defer archive.Close()

	for _, entry := range archive.File {
		if !safeArchiveName(entry.Name) {
			return fmt.Errorf("backup contains an unsupported path: %s", entry.Name)
		}
	}

	parent := filepath.Dir(*dataDir)
	if err := os.MkdirAll(parent, 0o700); err != nil {
		return err
	}
	tmpDir, err := os.MkdirTemp(parent, ".mypet-restore-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmpDir)

	var manifest backupManifest
	hasDB := false
	var extractedSize int64
	for _, entry := range archive.File {
		if entry.FileInfo().IsDir() {
			continue
		}
		if entry.Name != "mypet.db" && entry.Name != "manifest.json" &&
			!strings.HasPrefix(entry.Name, "uploads/") {
			continue
		}
		target := filepath.Join(tmpDir, filepath.FromSlash(entry.Name))
		if !strings.HasPrefix(target, tmpDir+string(os.PathSeparator)) {
			return fmt.Errorf("backup path escapes restore directory: %s", entry.Name)
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
			return err
		}
		src, err := entry.Open()
		if err != nil {
			return err
		}
		dst, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
		if err != nil {
			src.Close()
			return err
		}
		n, copyErr := io.Copy(dst, io.LimitReader(src, 2<<30))
		src.Close()
		closeErr := dst.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
		extractedSize += n
		if entry.Name == "mypet.db" {
			hasDB = true
		}
		if entry.Name == "manifest.json" {
			raw, err := os.ReadFile(target)
			if err == nil {
				_ = json.Unmarshal(raw, &manifest)
			}
		}
	}
	if !hasDB {
		return errors.New("backup does not contain mypet.db")
	}
	if manifest.DBSHA256 != "" {
		actual, err := fileSHA256(filepath.Join(tmpDir, "mypet.db"))
		if err != nil {
			return err
		}
		if actual != manifest.DBSHA256 {
			return errors.New("backup database digest does not match manifest")
		}
	}
	if err := verifyDatabase(filepath.Join(tmpDir, "mypet.db")); err != nil {
		return err
	}

	if err := os.MkdirAll(*dataDir, 0o700); err != nil {
		return err
	}
	var autoBackup string
	if _, err := os.Stat(dataDBPath(*dataDir)); err == nil {
		autoBackup, err = backupTo(*dataDir, *backupOut)
		if err != nil {
			return fmt.Errorf("pre-restore backup failed: %w", err)
		}
	}

	stamp := backupTimestamp()
	currentDB := dataDBPath(*dataDir)
	preDB := currentDB + ".pre-restore-" + stamp
	if _, err := os.Stat(currentDB); err == nil {
		if err := os.Rename(currentDB, preDB); err != nil {
			return err
		}
	}
	for _, suffix := range []string{"-wal", "-shm"} {
		_ = os.Remove(currentDB + suffix)
	}
	if err := copyFile(filepath.Join(tmpDir, "mypet.db"), currentDB, 0o600); err != nil {
		return err
	}

	uploadsSrc := filepath.Join(tmpDir, "uploads")
	uploadsDst := filepath.Join(*dataDir, "uploads")
	if info, err := os.Stat(uploadsSrc); err == nil && info.IsDir() {
		if _, err := os.Stat(uploadsDst); err == nil {
			if err := os.Rename(uploadsDst, uploadsDst+".pre-restore-"+stamp); err != nil {
				return err
			}
		}
		if err := os.Rename(uploadsSrc, uploadsDst); err != nil {
			return err
		}
	}

	fmt.Printf("restored %s (%d bytes)\n", *dataDir, extractedSize)
	if manifest.CreatedAt != "" {
		fmt.Printf("backup created at: %s\n", manifest.CreatedAt)
	}
	if autoBackup != "" {
		fmt.Printf("pre-restore backup: %s\n", autoBackup)
	}
	if _, err := os.Stat(preDB); err == nil {
		fmt.Printf("previous database kept at: %s\n", preDB)
	}
	return nil
}

func verifyDatabase(path string) error {
	d, err := db.Open(path)
	if err != nil {
		return fmt.Errorf("open restored database: %w", err)
	}
	defer d.Close()
	var result string
	if err := d.QueryRowContext(context.Background(), "PRAGMA integrity_check").Scan(&result); err != nil {
		return fmt.Errorf("integrity check: %w", err)
	}
	if result != "ok" {
		return fmt.Errorf("integrity check failed: %s", result)
	}
	var users int
	if err := d.QueryRowContext(context.Background(), "SELECT COUNT(1) FROM users").Scan(&users); err != nil {
		return fmt.Errorf("restored database has no users table: %w", err)
	}
	return nil
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(out, in)
	closeErr := out.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}

func runDoctor(args []string) error {
	fs := flag.NewFlagSet("doctor", flag.ExitOnError)
	dataDir := fs.String("data", "./data", "data directory")
	fs.Parse(args)
	dbPath := dataDBPath(*dataDir)
	fmt.Printf("data directory: %s\n", *dataDir)
	if info, err := os.Stat(*dataDir); err != nil {
		fmt.Printf("data directory: MISSING (%v)\n", err)
	} else {
		fmt.Printf("data directory mode: %v\n", info.Mode().Perm())
	}
	if _, err := os.Stat(dbPath); err != nil {
		return fmt.Errorf("database missing: %w", err)
	}
	d, err := db.Open(dbPath)
	if err != nil {
		return err
	}
	defer d.Close()
	var integrity string
	if err := d.QueryRowContext(context.Background(), "PRAGMA integrity_check").Scan(&integrity); err != nil {
		return err
	}
	fmt.Printf("sqlite integrity: %s\n", integrity)
	var users, pets, records int
	_ = d.QueryRowContext(context.Background(), "SELECT COUNT(1) FROM users").Scan(&users)
	_ = d.QueryRowContext(context.Background(), "SELECT COUNT(1) FROM pets WHERE deleted_at IS NULL").Scan(&pets)
	_ = d.QueryRowContext(context.Background(), "SELECT COUNT(1) FROM health_records WHERE deleted_at IS NULL").Scan(&records)
	fmt.Printf("users: %d, active pets: %d, active records: %d\n", users, pets, records)
	uploads := filepath.Join(*dataDir, "uploads")
	if err := os.MkdirAll(uploads, 0o700); err != nil {
		fmt.Printf("uploads directory: NOT WRITABLE (%v)\n", err)
	} else {
		probe := filepath.Join(uploads, ".doctor-probe")
		if err := os.WriteFile(probe, []byte("ok"), 0o600); err != nil {
			fmt.Printf("uploads directory: NOT WRITABLE (%v)\n", err)
		} else {
			_ = os.Remove(probe)
			fmt.Printf("uploads directory: writable (%s)\n", uploads)
		}
	}
	if integrity != "ok" {
		return errors.New("database integrity check failed")
	}
	fmt.Println("doctor: ok")
	return nil
}
