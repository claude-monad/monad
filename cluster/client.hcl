# Monad Cluster - Client Node Configuration Template
# Copy to /etc/nomad.d/nomad.hcl on worker nodes
#
# Variables to replace:
#   TAILSCALE_IP - this node's Tailscale IP
#   NODE_NAME    - hostname
#   SERVER_IP    - bootstrap server's Tailscale IP (100.87.219.108)

log_level = "INFO"
data_dir  = "/opt/nomad/data"
name      = "NODE_NAME"

bind_addr = "TAILSCALE_IP"

advertise {
  http = "TAILSCALE_IP"
  rpc  = "TAILSCALE_IP"
  serf = "TAILSCALE_IP"
}

ports {
  http = 4646
  rpc  = 4647
  serf = 4648
}

client {
  enabled = true

  servers = ["SERVER_IP:4647"]

  meta {
    role           = "worker"
    location       = "unknown"
    # Set claude_account to the account logged in on this node (max-1, max-2, max-3, pro)
    claude_account = "pro"
    # Set math_agent = "true" on nodes that are registered math research agents
    # (windesk, mac-mini). This enables math-agent-relay and math-pro-sessions jobs.
    math_agent     = "false"
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

telemetry {
  disable_hostname       = true
  prometheus_metrics     = true
  publish_allocation_metrics = true
  publish_node_metrics       = true
}
