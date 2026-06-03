job "backup-mac-mini" {
  datacenters = ["dc1"]
  type        = "batch"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "Eliotts-Mac-mini.local"
  }

  group "backup" {
    task "copy-all" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["-c", "curl -fsSL https://dl.min.io/client/mc/release/darwin-arm64/mc -o /tmp/monad_mc && chmod +x /tmp/monad_mc && /tmp/monad_mc alias set monad http://100.96.31.66:9000 monad-admin 7flNW73Yiq0V4dMGVAhAH9CngRPgXBaZ && echo '=== MAC MINI DEEP BACKUP ===' && echo 'Backing up dotfiles...' && /tmp/monad_mc mirror --preserve $HOME/.ssh/ monad/backups/mac-mini/dotfiles/ssh/ 2>&1; /tmp/monad_mc cp $HOME/.gitconfig monad/backups/mac-mini/dotfiles/gitconfig 2>&1; /tmp/monad_mc cp $HOME/.zshrc monad/backups/mac-mini/dotfiles/zshrc 2>&1; /tmp/monad_mc cp $HOME/.bash_profile monad/backups/mac-mini/dotfiles/bash_profile 2>&1; /tmp/monad_mc mirror --preserve $HOME/.config/ monad/backups/mac-mini/dotfiles/config/ 2>&1; echo 'Backing up Claude/Codex configs...' && /tmp/monad_mc mirror --preserve $HOME/.claude/ monad/backups/mac-mini/dotfiles/claude/ 2>&1; /tmp/monad_mc mirror --preserve $HOME/.codex/ monad/backups/mac-mini/dotfiles/codex/ 2>&1; echo 'Backing up VS Code settings...' && /tmp/monad_mc mirror --preserve \"$HOME/Library/Application Support/Code/User/\" monad/backups/mac-mini/vscode/ 2>&1; echo 'Backing up Safari bookmarks...' && /tmp/monad_mc cp \"$HOME/Library/Safari/Bookmarks.plist\" monad/backups/mac-mini/browsers/safari/Bookmarks.plist 2>&1; echo 'Backing up Chrome bookmarks...' && /tmp/monad_mc cp \"$HOME/Library/Application Support/Google/Chrome/Default/Bookmarks\" monad/backups/mac-mini/browsers/chrome/Bookmarks 2>&1; echo 'Backing up Firefox...' && /tmp/monad_mc mirror --preserve \"$HOME/Library/Application Support/Firefox/Profiles/\" monad/backups/mac-mini/browsers/firefox/ 2>&1; echo 'Backing up Terminal/shell history...' && /tmp/monad_mc cp $HOME/.zsh_history monad/backups/mac-mini/dotfiles/zsh_history 2>&1; /tmp/monad_mc cp $HOME/.bash_history monad/backups/mac-mini/dotfiles/bash_history 2>&1; echo 'Backing up Downloads...' && /tmp/monad_mc mirror --preserve $HOME/Downloads/ monad/backups/mac-mini/downloads/ 2>&1; echo 'Backing up Desktop...' && /tmp/monad_mc mirror --preserve $HOME/Desktop/ monad/backups/mac-mini/desktop/ 2>&1; echo 'Backing up Library/Preferences (app settings)...' && /tmp/monad_mc mirror --preserve $HOME/Library/Preferences/ monad/backups/mac-mini/preferences/ 2>&1; echo 'Backing up Keychains...' && /tmp/monad_mc mirror --preserve $HOME/Library/Keychains/ monad/backups/mac-mini/keychains/ 2>&1; echo '=== SUMMARY ===' && /tmp/monad_mc du monad/backups/mac-mini/ 2>&1; echo '=== DONE ===' && rm -f /tmp/monad_mc"]
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
