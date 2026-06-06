# math-campaign — keep a bunch of Claude explorers running on a focused campaign for a long time.
#
# Periodic top-up: every pass, scripts/math-campaign.sh reads the campaign brief from the Nomad
# var monad/campaign/signed-lrc and tops up math-explore sessions to TARGET concurrent (governor-
# admitted, distinct angles). Runs until the campaign's `active` is set false:
#   nomad var put -force monad/campaign/signed-lrc active=false   # stop the campaign
# Inspect: monad/campaign/signed-lrc, nomad job status math-explore.

job "math-campaign" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["*/20 * * * *"]  # top up every 20 minutes
    prohibit_overlap = true
    time_zone        = "America/Denver"
  }

  constraint {
    attribute = "${attr.kernel.name}"
    value     = "linux"
  }
  constraint {
    attribute = "${attr.driver.raw_exec}"
    value     = "1"
  }

  group "campaign" {
    count = 1

    task "topup" {
      driver = "raw_exec"
      config {
        command = "/bin/bash"
        args = ["-c", <<-EOC
          for u in ubuntu bigo e eliott root; do
            home="$(getent passwd "$u" | cut -d: -f6)"; [ -n "$home" ] || continue
            repo="$home/monad"
            [ -f "$repo/scripts/math-campaign.sh" ] || continue
            if [ "$(id -u)" = 0 ] && [ "$u" != root ]; then exec su - "$u" -c "exec bash '$repo/scripts/math-campaign.sh'"
            else exec bash "$repo/scripts/math-campaign.sh"; fi
          done
          WORK="$NOMAD_TASK_DIR/mc-monad"
          [ -f "$WORK/scripts/math-campaign.sh" ] || { rm -rf "$WORK"; git clone -q --depth 1 https://github.com/eliott-monad/monad "$WORK" >/dev/null 2>&1 || true; }
          [ -f "$WORK/scripts/math-campaign.sh" ] && exec bash "$WORK/scripts/math-campaign.sh"
          echo "math-campaign: no checkout found" >&2; exit 1
        EOC
        ]
      }

      env {
        CAMPAIGN_VAR = "monad/campaign/signed-lrc"
        EXPLORE_JOB  = "math-explore"
        TARGET       = "4"
        PER_PASS     = "3"
        NOMAD_ADDR   = "http://100.75.75.39:4646"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    restart {
      attempts = 1
      interval = "20m"
      delay    = "1m"
      mode     = "fail"
    }
  }
}
