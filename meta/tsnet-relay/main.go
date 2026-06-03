// math-agent-relay: tsnet-based IPC relay for the math research agent network.
//
// Each agent machine runs one instance. It advertises itself on the Tailnet as
// `math-relay-<machine-id>` and exposes an HTTP API for direct message delivery.
// Received messages are written to the git repo (agents/<target>/inbox/) so they
// are durable even when the recipient is offline.
//
// Usage:
//   TS_AUTHKEY=<key> math-agent-relay --machine windesk --repo /path/to/math
//
// Endpoints:
//   POST /send          — deliver a message to this relay's inbox (body: JSON Message)
//   GET  /messages      — list messages not yet marked read
//   POST /messages/{id}/read  — mark a message as read (removes from pending list)
//   GET  /health        — liveness probe
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"tailscale.com/tsnet"
)

// Message mirrors the git-based MSG-NNN-from-... format.
type Message struct {
	ID      string    `json:"id"`
	From    string    `json:"from"`
	To      string    `json:"to"`
	Subject string    `json:"subject"`
	Body    string    `json:"body"`
	SentAt  time.Time `json:"sent_at"`
}

type store struct {
	mu      sync.RWMutex
	pending []Message
}

func (s *store) add(m Message) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pending = append(s.pending, m)
}

func (s *store) list() []Message {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Message, len(s.pending))
	copy(out, s.pending)
	return out
}

func (s *store) remove(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i, m := range s.pending {
		if m.ID == id {
			s.pending = append(s.pending[:i], s.pending[i+1:]...)
			return true
		}
	}
	return false
}

func writeToGit(repoRoot, machineID string, m Message) error {
	if repoRoot == "" {
		return nil
	}
	inboxDir := filepath.Join(repoRoot, "agents", machineID, "inbox")
	if err := os.MkdirAll(inboxDir, 0755); err != nil {
		return err
	}

	// Find next message number
	entries, _ := os.ReadDir(inboxDir)
	maxNum := 0
	for _, e := range entries {
		name := e.Name()
		if !strings.HasPrefix(name, "MSG-") {
			continue
		}
		var n int
		fmt.Sscanf(name[4:7], "%d", &n)
		if n > maxNum {
			maxNum = n
		}
	}
	num := maxNum + 1

	subject := strings.ReplaceAll(m.Subject, " ", "-")
	subject = strings.ToLower(subject)
	if len(subject) > 30 {
		subject = subject[:30]
	}
	date := m.SentAt.Format("2006-01-02")
	filename := fmt.Sprintf("MSG-%03d-from-%s-%s-%s.md", num, m.From, date, subject)
	path := filepath.Join(inboxDir, filename)

	content := fmt.Sprintf("# Message from %s\n\n**From:** %s\n**To:** %s\n**Subject:** %s\n**Sent:** %s\n**Relay-ID:** %s\n\n---\n\n%s\n",
		m.From, m.From, m.To, m.Subject, m.SentAt.Format(time.RFC3339), m.ID, m.Body)

	return os.WriteFile(path, []byte(content), 0644)
}

func main() {
	machineID := flag.String("machine", "", "this machine's math agent ID (e.g. windesk)")
	repoRoot := flag.String("repo", "", "path to math git repo root (optional, for git write-through)")
	port := flag.Int("port", 7373, "HTTP port on Tailnet")
	flag.Parse()

	if *machineID == "" {
		// Try to read from .machine-id in repo
		if *repoRoot != "" {
			b, err := os.ReadFile(filepath.Join(*repoRoot, ".machine-id"))
			if err == nil {
				*machineID = strings.TrimSpace(string(b))
			}
		}
		if *machineID == "" {
			log.Fatal("--machine is required (or provide --repo with a .machine-id file)")
		}
	}

	authKey := os.Getenv("TS_AUTHKEY")
	if authKey == "" {
		log.Fatal("TS_AUTHKEY environment variable is required")
	}

	hostname := "math-relay-" + *machineID

	srv := &tsnet.Server{
		Hostname: hostname,
		AuthKey:  authKey,
		Logf:     func(format string, args ...any) {}, // quiet tsnet internals
	}
	defer srv.Close()

	ctx := context.Background()
	if _, err := srv.Up(ctx); err != nil {
		log.Fatalf("tsnet up: %v", err)
	}
	log.Printf("tsnet node %q is up", hostname)

	ms := &store{}
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"machine": *machineID,
			"status":  "ok",
			"node":    hostname,
		})
	})

	mux.HandleFunc("POST /send", func(w http.ResponseWriter, r *http.Request) {
		var m Message
		if err := json.NewDecoder(r.Body).Decode(&m); err != nil {
			http.Error(w, "bad JSON: "+err.Error(), http.StatusBadRequest)
			return
		}
		if m.ID == "" {
			m.ID = fmt.Sprintf("%d", time.Now().UnixNano())
		}
		if m.SentAt.IsZero() {
			m.SentAt = time.Now()
		}
		ms.add(m)
		log.Printf("received message %s from %s: %s", m.ID, m.From, m.Subject)

		if err := writeToGit(*repoRoot, *machineID, m); err != nil {
			log.Printf("git write-through failed for %s: %v", m.ID, err)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		json.NewEncoder(w).Encode(map[string]string{"id": m.ID, "status": "accepted"})
	})

	mux.HandleFunc("GET /messages", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(ms.list())
	})

	mux.HandleFunc("POST /messages/{id}/read", func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		if ms.remove(id) {
			w.WriteHeader(http.StatusNoContent)
		} else {
			http.Error(w, "message not found", http.StatusNotFound)
		}
	})

	ln, err := srv.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	log.Printf("math-agent-relay/%s listening on %s:%d", *machineID, hostname, *port)

	if err := http.Serve(ln, mux); err != nil {
		log.Fatalf("serve: %v", err)
	}
}
