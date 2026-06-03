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
        args    = ["-c", "cd $HOME/monad && git pull origin main 2>/dev/null; exec bash $HOME/monad/scripts/migrate-mac.sh"]
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
