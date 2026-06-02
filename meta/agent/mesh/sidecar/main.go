// tsnet-sidecar — gives one Monad agent its own node on the Tailscale network.
//
// Each agent container runs this beside the LLM. It joins the tailnet as "agent-<name>"
// (its own IP + MagicDNS name), so agents can see and message each other directly over
// Tailscale. It serves two HTTP APIs:
//
//   * MESH api  (on the tailnet IP, MESH_PORT) — how PEERS reach this agent:
//       POST /msg   {from,body}   deliver a message into this agent's inbox
//       GET  /id                  {"name":...}
//
//   * LOCAL api (127.0.0.1:LOCAL_PORT) — how THIS agent's LLM drives the mesh
//       GET  /whoami              {name, ip}
//       GET  /peers               [{name, ip}, ...]   other agent-* nodes on the tailnet
//       POST /send  {to,body}     send a message to peer <to> (its agent name)
//       GET  /recv                drain + return this agent's inbox  [{from,body,ts}, ...]
//
// Env: AGENT_NAME, TS_AUTHKEY (required), TS_STATE_DIR, MESH_PORT (8472), LOCAL_PORT (8473).
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"tailscale.com/tsnet"
)

type Msg struct {
	From string `json:"from"`
	To   string `json:"to,omitempty"`
	Body string `json:"body"`
	Ts   string `json:"ts"`
}

type Peer struct {
	Name string `json:"name"`
	IP   string `json:"ip"`
}

var (
	mu    sync.Mutex
	inbox []Msg
	self  string
)

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func main() {
	self = getenv("AGENT_NAME", "agent-"+fmt.Sprint(time.Now().UnixNano()%100000))
	authkey := os.Getenv("TS_AUTHKEY")
	if authkey == "" {
		log.Fatal("TS_AUTHKEY is required")
	}
	stateDir := getenv("TS_STATE_DIR", "/var/lib/tsnet-"+self)
	meshPort := getenv("MESH_PORT", "8472")
	localPort := getenv("LOCAL_PORT", "8473")
	_ = os.MkdirAll(stateDir, 0700)

	s := &tsnet.Server{
		Hostname:  self,
		AuthKey:   authkey,
		Dir:       stateDir,
		Ephemeral: true,
	}
	defer s.Close()

	ctx := context.Background()
	status, err := s.Up(ctx)
	if err != nil {
		log.Fatalf("tsnet up: %v", err)
	}
	selfIP := ""
	if status != nil && status.Self != nil && len(status.Self.TailscaleIPs) > 0 {
		selfIP = status.Self.TailscaleIPs[0].String()
	}
	log.Printf("[mesh] %s up on tailnet ip=%s", self, selfIP)

	lc, err := s.LocalClient()
	if err != nil {
		log.Fatalf("local client: %v", err)
	}

	// HTTP client that dials peers over the tailnet.
	meshClient := &http.Client{
		Transport: &http.Transport{DialContext: s.Dial},
		Timeout:   10 * time.Second,
	}

	// ── MESH api (peers reach us here, on the tailnet IP) ─────────────────────
	ln, err := s.Listen("tcp", ":"+meshPort)
	if err != nil {
		log.Fatalf("listen mesh :%s: %v", meshPort, err)
	}
	meshMux := http.NewServeMux()
	meshMux.HandleFunc("/msg", func(w http.ResponseWriter, r *http.Request) {
		var m Msg
		if err := json.NewDecoder(r.Body).Decode(&m); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if m.Ts == "" {
			m.Ts = time.Now().UTC().Format(time.RFC3339)
		}
		mu.Lock()
		inbox = append(inbox, m)
		mu.Unlock()
		log.Printf("[mesh] rx from=%s (%d bytes)", m.From, len(m.Body))
		w.WriteHeader(204)
	})
	meshMux.HandleFunc("/id", func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]string{"name": self, "ip": selfIP})
	})
	go func() { _ = http.Serve(ln, meshMux) }()

	// ── peer discovery over the tailnet (agent-* nodes) ───────────────────────
	listPeers := func(ctx context.Context) ([]Peer, error) {
		st, err := lc.Status(ctx)
		if err != nil {
			return nil, err
		}
		var out []Peer
		for _, p := range st.Peer {
			name := p.HostName
			if name == "" {
				name = strings.SplitN(p.DNSName, ".", 2)[0]
			}
			if strings.HasPrefix(name, "agent-") && p.Online && len(p.TailscaleIPs) > 0 {
				out = append(out, Peer{Name: name, IP: p.TailscaleIPs[0].String()})
			}
		}
		return out, nil
	}
	resolve := func(ctx context.Context, name string) string {
		peers, _ := listPeers(ctx)
		for _, p := range peers {
			if p.Name == name || p.Name == "agent-"+name {
				return p.IP
			}
		}
		return ""
	}

	// ── LOCAL api (our own LLM drives the mesh from 127.0.0.1) ────────────────
	localMux := http.NewServeMux()
	localMux.HandleFunc("/whoami", func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(Peer{Name: self, IP: selfIP})
	})
	localMux.HandleFunc("/peers", func(w http.ResponseWriter, r *http.Request) {
		peers, err := listPeers(r.Context())
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		_ = json.NewEncoder(w).Encode(peers)
	})
	localMux.HandleFunc("/recv", func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		out := inbox
		inbox = nil
		mu.Unlock()
		if out == nil {
			out = []Msg{}
		}
		_ = json.NewEncoder(w).Encode(out)
	})
	localMux.HandleFunc("/send", func(w http.ResponseWriter, r *http.Request) {
		var m Msg
		if err := json.NewDecoder(r.Body).Decode(&m); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		ip := resolve(r.Context(), m.To)
		if ip == "" {
			http.Error(w, "peer not found: "+m.To, 404)
			return
		}
		m.From = self
		m.Ts = time.Now().UTC().Format(time.RFC3339)
		body, _ := json.Marshal(m)
		url := fmt.Sprintf("http://%s:%s/msg", ip, meshPort)
		resp, err := meshClient.Post(url, "application/json", strings.NewReader(string(body)))
		if err != nil {
			http.Error(w, err.Error(), 502)
			return
		}
		defer resp.Body.Close()
		log.Printf("[mesh] tx to=%s (%s) status=%d", m.To, ip, resp.StatusCode)
		w.WriteHeader(204)
	})

	log.Printf("[mesh] %s ready: mesh api :%s, local api 127.0.0.1:%s", self, meshPort, localPort)
	if err := http.ListenAndServe("127.0.0.1:"+localPort, localMux); err != nil {
		log.Fatalf("local api: %v", err)
	}
}
