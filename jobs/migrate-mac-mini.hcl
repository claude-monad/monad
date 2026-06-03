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
        args = ["-c", "curl -fsSL https://dl.min.io/client/mc/release/darwin-arm64/mc -o /tmp/monad_mc && chmod +x /tmp/monad_mc && /tmp/monad_mc alias set monad http://100.96.31.66:9000 monad-admin 7flNW73Yiq0V4dMGVAhAH9CngRPgXBaZ && /tmp/monad_mc mirror --preserve $HOME/Documents/ monad/media/documents/mac-mini/ 2>&1; /tmp/monad_mc mirror --preserve $HOME/Pictures/ monad/media/photos/mac-mini/ 2>&1; /tmp/monad_mc mirror --preserve $HOME/Movies/ monad/media/videos/mac-mini/ 2>&1; /tmp/monad_mc mirror --preserve $HOME/Music/ monad/media/music/mac-mini/ 2>&1; find $HOME -maxdepth 5 -name '*.photoslibrary' -prune -exec /tmp/monad_mc mirror --preserve {} monad/media/photo-libraries/mac-mini/ \\; 2>&1; /tmp/monad_mc ls monad/media/ 2>&1; rm -f /tmp/monad_mc; echo DONE"]
      }

      resources {
        cpu    = 500
        memory = 512
      }

      kill_timeout = "30s"
    }

    restart {
      attempts = 0
      mode     = "fail"
    }
  }
}
