# Monad Cluster - oraclebox1 node configuration
# Role: Nomad SERVER + client. Promoted from client-only on 2026-06-01 as part of the
# v1410-1 + claudebox + oraclebox1 three-server master set (claudebox joins when revived).
# This node also hosts the cluster-conductor (it holds the Claude credentials).

log_level = "INFO"
data_dir  = "/opt/nomad/data"
name      = "oraclebox1"

region     = "global"
datacenter = "dc1"

bind_addr = "100.125.210.126"

advertise {
  http = "100.125.210.126"
  rpc  = "100.125.210.126"
  serf = "100.125.210.126"
}

ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}

# SERVER: join the existing cluster led by v1410-1 via retry_join.
# bootstrap_expect is intentionally OMITTED so this node never bootstraps a
# separate cluster — it only ever joins v1410-1's Raft as an additional voter.
server {
  enabled = true

  server_join {
    retry_join     = ["100.75.75.39"]
    retry_interval = "15s"
    retry_max      = 0
  }
}

client {
  enabled = true

  servers = ["100.75.75.39:4647", "100.125.210.126:4647"]

  meta {
    role           = "server"
    claude_account = "max-1"
    has_claude     = "true"
    location       = "unknown"
  }
}

plugin "docker" {
  config {
    allow_privileged = false
    volumes {
      enabled = true
    }
  }
}

# raw_exec: needed to run agent jobs (claude/codex sessions, maintenance-agent) that use
# the host's logged-in CLIs directly. All other agent nodes have it enabled.
plugin "raw_exec" {
  config {
    enabled = true
  }
}

telemetry {
  disable_hostname       = true
  prometheus_metrics     = true
  publish_allocation_metrics = true
  publish_node_metrics       = true
}
