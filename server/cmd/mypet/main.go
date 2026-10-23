package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/Prgmcat/mypet/server/internal/auth"
	"github.com/Prgmcat/mypet/server/internal/db"
	"github.com/Prgmcat/mypet/server/internal/httpapi"
	"github.com/Prgmcat/mypet/server/internal/store"
)

const version = "0.1.0-dev"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "init":
		err = runInit(os.Args[2:])
	case "serve":
		err = runServe(os.Args[2:])
	case "create-invite":
		err = runCreateInvite(os.Args[2:])
	case "reset-password":
		err = runResetPassword(os.Args[2:])
	case "backup":
		err = runBackup(os.Args[2:])
	case "restore":
		err = runRestore(os.Args[2:])
	case "doctor":
		err = runDoctor(os.Args[2:])
	case "version":
		fmt.Println(version)
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		log.Fatal(err)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `喵了个咪 server

Usage:
  mypet init           -data ./data -username admin -password 'Passw0rd!'
  mypet serve          -data ./data -addr 0.0.0.0:8787
  mypet create-invite  -data ./data -ttl-hours 168 -max-uses 1
  mypet reset-password -data ./data -username admin -password 'NewPassw0rd!'
  mypet backup         -data ./data -out ./backup
  mypet restore        -data ./data -from ./backup/mypet-YYYYmmdd-HHMMSS.zip
  mypet doctor         -data ./data
  mypet version`)
}

func openDB(dataDir string) (*db.DB, *store.Store, error) {
	path := filepath.Join(dataDir, "mypet.db")
	d, err := db.Open(path)
	if err != nil {
		return nil, nil, err
	}
	if err := d.Migrate(context.Background()); err != nil {
		d.Close()
		return nil, nil, err
	}
	return d, store.New(d), nil
}

func runInit(args []string) error {
	fs := flag.NewFlagSet("init", flag.ExitOnError)
	dataDir := fs.String("data", "./data", "data directory")
	username := fs.String("username", "admin", "admin username")
	password := fs.String("password", "", "admin password")
	fs.Parse(args)
	if *password == "" {
		return errors.New("password is required")
	}
	d, st, err := openDB(*dataDir)
	if err != nil {
		return err
	}
	defer d.Close()
	n, err := st.CountUsers(context.Background())
	if err != nil {
		return err
	}
	if n > 0 {
		return errors.New("server already initialized")
	}
	hash, err := auth.HashPassword(*password)
	if err != nil {
		return err
	}
	u, err := st.CreateAdmin(context.Background(), strings.TrimSpace(*username), hash)
	if err != nil {
		return err
	}
	fmt.Printf("initialized admin %s (%s)\n", u.Username, u.ID)
	fmt.Println("start the server with: mypet serve -data", *dataDir)
	return nil
}

func runServe(args []string) error {
	fs := flag.NewFlagSet("serve", flag.ExitOnError)
	dataDir := fs.String("data", "./data", "data directory")
	addr := fs.String("addr", "0.0.0.0:8787", "listen address")
	fs.Parse(args)
	d, st, err := openDB(*dataDir)
	if err != nil {
		return err
	}
	defer d.Close()
	handler := httpapi.New(st, version)
	srv := &http.Server{
		Addr:              *addr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	go func() {
		log.Printf("mypet %s listening on %s (data: %s)", version, *addr, *dataDir)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return srv.Shutdown(ctx)
}

func runCreateInvite(args []string) error {
	fs := flag.NewFlagSet("create-invite", flag.ExitOnError)
	dataDir := fs.String("data", "./data", "data directory")
	ttlHours := fs.Int("ttl-hours", 168, "invite lifetime in hours")
	maxUses := fs.Int("max-uses", 1, "maximum uses")
	fs.Parse(args)
	d, st, err := openDB(*dataDir)
	if err != nil {
		return err
	}
	defer d.Close()
	users, err := st.ListUsers(context.Background())
	if err != nil {
		return err
	}
	var adminID string
	for _, u := range users {
		if u.IsAdmin {
			adminID = u.ID
			break
		}
	}
	if adminID == "" {
		return errors.New("no admin user; run init first")
	}
	code, expires, err := st.CreateInvite(context.Background(), adminID, *maxUses, time.Duration(*ttlHours)*time.Hour)
	if err != nil {
		return err
	}
	fmt.Printf("invite code: %s\n", code)
	fmt.Printf("expires at: %s\n", expires)
	fmt.Printf("max uses: %d\n", *maxUses)
	return nil
}

func runResetPassword(args []string) error {
	fs := flag.NewFlagSet("reset-password", flag.ExitOnError)
	dataDir := fs.String("data", "./data", "data directory")
	username := fs.String("username", "", "username")
	password := fs.String("password", "", "new password")
	fs.Parse(args)
	if *username == "" || *password == "" {
		return errors.New("username and password are required")
	}
	d, st, err := openDB(*dataDir)
	if err != nil {
		return err
	}
	defer d.Close()
	u, _, err := st.FindUserByUsername(context.Background(), *username)
	if err != nil {
		return err
	}
	hash, err := auth.HashPassword(*password)
	if err != nil {
		return err
	}
	if err := st.UpdatePassword(context.Background(), u.ID, hash, ""); err != nil {
		return err
	}
	fmt.Printf("password reset for %s; all devices revoked\n", u.Username)
	return nil
}

func runBackup(args []string) error {
	fs := flag.NewFlagSet("backup", flag.ExitOnError)
	dataDir := fs.String("data", "./data", "data directory")
	outDir := fs.String("out", "./backup", "output directory")
	fs.Parse(args)
	path, err := backupTo(*dataDir, *outDir)
	if err != nil {
		return err
	}
	fmt.Println(path)
	return nil
}
