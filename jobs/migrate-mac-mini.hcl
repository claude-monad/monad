job "migrate-mac-mini" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "Eliotts-Mac-mini.local"
  }

  group "migrate" {
    task "copy-media" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/migrate-mac.sh"]
      }

      artifact {
        source      = "https://raw.githubusercontent.com/eliott-monad/monad/main/scripts/migrate-mac.sh"
        destination = "local/migrate-mac.sh"
        mode        = "file"
      }

      resources {
        cpu    = 500
        memory = 256
      }

      kill_timeout = "30s"
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
  }
}
