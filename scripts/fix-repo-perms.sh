#!/usr/bin/env bash
# fix-repo-perms.sh — keep the monad repo writable by every agent on this node.
#
# THE PROBLEM THIS SOLVES
#   The monad checkout is a SHARED working tree. Agents run as the repo owner
#   (e.g. `bigo`), but root-run jobs also run git here — node-doctor cron,
#   monad-sync, Nomad raw_exec tasks. When root runs `git fetch`/`pull`, the new
#   objects in .git/objects/<xx>/ are created root-owned and not group-writable.
#   The next non-root `git rebase`/`commit`/`gc` then dies with:
#       error: insufficient permission for adding an object to repository database
#   — silently breaking every agent's ability to commit and push its work.
#
# THE FIX
#   Make the repo a proper git *shared repository*: set core.sharedRepository=group
#   (git then creates group-writable, setgid object dirs regardless of which user
#   runs it) and normalise ownership/group/setgid on any pre-existing drift. With
#   the .git tree owned by the agent's group and its dirs setgid + group-writable,
#   objects written by root OR the agent are always writable by the agent.
#
# Idempotent and cheap when already correct — safe to call on every doctor pass
# and from node setup. Run as the repo owner or as root; it self-escalates with
# sudo only when it must.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GITDIR="$REPO_DIR/.git"
[ -e "$GITDIR" ] || { echo "fix-repo-perms: no .git at $REPO_DIR" >&2; exit 1; }
# Support worktrees / gitdir files (rare here, but be safe).
[ -f "$GITDIR" ] && GITDIR="$(git -C "$REPO_DIR" rev-parse --git-common-dir 2>/dev/null)"

# Identity the repo belongs to: the owner of the working tree.
OWNER="$(stat -c '%U' "$REPO_DIR" 2>/dev/null || echo "${SUDO_USER:-$(id -un)}")"
GROUP="$(id -gn "$OWNER" 2>/dev/null || stat -c '%G' "$REPO_DIR" 2>/dev/null || echo "$OWNER")"

# Run a privileged command directly if we can, otherwise via sudo.
priv() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        sudo "$@"
    else
        "$@"   # best effort; may fail without privileges
    fi
}

changed=0

# 1) Tell git to create shared (group-writable, setgid) objects from now on.
cur="$(git -C "$REPO_DIR" config --get core.sharedRepository 2>/dev/null || true)"
case "$cur" in
    group|true|1) ;;                              # already shared
    *) priv git -C "$REPO_DIR" config core.sharedRepository group && changed=1 ;;
esac

# 2) Repair drift: anything under .git not owned by OWNER, or a directory that is
#    not group-writable or not setgid. (Object FILES are read-only 0444 by design;
#    what matters for adding objects is the DIRECTORY being group-writable.)
drift=0
find "$GITDIR" ! -user "$OWNER" -print -quit 2>/dev/null | grep -q . && drift=1
[ "$drift" = "0" ] && { find "$GITDIR" -type d ! -perm -2020 -print -quit 2>/dev/null | grep -q . && drift=1; }
if [ "$drift" = "1" ]; then
    priv chown -R "$OWNER:$GROUP" "$GITDIR"
    priv chmod -R g+rwX "$GITDIR"
    priv find "$GITDIR" -type d -exec chmod g+s {} +
    changed=1
fi

if [ "$changed" = "1" ]; then
    echo "fix-repo-perms: normalized shared-repo perms on $GITDIR (owner=$OWNER group=$GROUP)"
fi
exit 0
