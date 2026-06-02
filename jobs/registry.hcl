job "registry" {
  datacenters = ["dc1"]
  type        = "service"

  # Pin to bigo-server: amd64 client with the most free disk among the non-server
  # nodes (~29 GiB), and port 5000 is free there (oraclebox1 already runs a
  # localhost:5000 registry). Keeping it off the Raft servers means a registry that
  # fills its disk can never threaten the control plane. Reachable tailnet-wide at
  # 100.78.218.70:5000 (bigo-server advertise addr).
  constraint {
    attribute = "${node.unique.name}"
    value     = "bigo-server"
  }

  group "registry" {
    count = 1

    network {
      port "registry" {
        static = 5000
        to     = 5000
      }
    }

    restart {
      attempts = 3
      interval = "10m"
      delay    = "15s"
      mode     = "delay"
    }

    task "registry" {
      driver = "docker"

      config {
        image = "registry:2"
        ports = ["registry"]

        # Persistent image store. A docker bind-mount (volumes.enabled on this node)
        # rather than a Nomad host volume, so no client-config change / Nomad restart
        # is needed. Docker creates the source dir on first run.
        volumes = [
          "/opt/monad-registry:/var/lib/registry",
        ]
      }

      env {
        REGISTRY_HTTP_ADDR = "0.0.0.0:5000"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name     = "registry"
        port     = "registry"
        provider = "nomad"

        check {
          type     = "http"
          path     = "/v2/"
          port     = "registry"
          interval = "30s"
          timeout  = "5s"
        }
      }
    }
  }
}
