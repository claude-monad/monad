# Cluster Storage — death-star shared store

**death-star** (Tailscale `100.96.31.66`) is the storage node — a ~14 TB array exported to
the whole cluster over the tailnet. Every machine can use it seamlessly; low-disk nodes
(windesk, mac-mini) should put bulky data there instead of on local disk.

One tree (`/srv/samba/public` on death-star) is served three ways so every OS has a native
path. Endpoints are advertised in the Nomad var **`infra/storage`**.

| Protocol | For | Endpoint | Server job |
|----------|-----|----------|-----------|
| **NFS**  | Linux + macOS | `100.96.31.66:/` | `nfs-storage` |
| **SMB**  | Windows + macOS | `\\100.96.31.66\public` (`smb://…`) | `samba-storage` |
| **S3/MinIO** | apps / object storage | `http://100.96.31.66:9000` | `minio-storage` |

SMB auth: user `monad`, password in `nomad var get secret/samba`. The tailnet is the network
boundary (no public exposure).

## How each OS gets it (mostly automatic)

- **Linux nodes** — automatic. The `storage-mount-linux` system job NFS-mounts the share at
  **`/mnt/deathstar`** on every Linux client and keeps it mounted. Just use `/mnt/deathstar`.
- **Windows (windesk)** — automatic. The `storage-mount-windows` system job stores the
  credentials machine-wide (so `\\100.96.31.66\public` works with no prompt), maps drive
  **`Z:`**, and installs a logon task so `Z:` reappears at sign-in. Use `Z:\` or the UNC path.
- **macOS (mac-mini)** — one-time setup (macOS needs root to mount, which the agent lacks).
  Run once on the Mac:
  ```bash
  sudo bash ~/monad/scripts/mac-storage-setup.sh
  ```
  It mounts NFS at **`/Volumes/deathstar`** and installs a LaunchDaemon to re-mount at boot.

## Freeing space on low-disk nodes
Move bulky directories to the share and symlink them back, e.g. on a low node:
```bash
mv ~/big-cache /mnt/deathstar/<node>/big-cache   # (Z:\ on Windows, /Volumes/deathstar on mac)
ln -s /mnt/deathstar/<node>/big-cache ~/big-cache
```
Suggested layout under the share: `/<node>/…` per-machine, `/shared/…` for cluster-wide data,
`/artifacts/…` for build outputs. (NFS and SMB writes interoperate — the SMB share uses
`force user = root` to match the NFS export's `no_root_squash`.)

## Jobs / files
- `jobs/samba-storage.hcl` — native smbd on death-star (this added Windows/macOS SMB).
- `jobs/nfs-storage.hcl`, `jobs/minio-storage.hcl` — NFS + object storage (pre-existing).
- `jobs/storage-mount-linux.hcl`, `jobs/storage-mount-windows.hcl` — per-node auto-mounts.
- `scripts/mac-storage-setup.sh` — one-time macOS mount + boot LaunchDaemon.
- Endpoints: `nomad var get infra/storage`. Samba creds: `nomad var get secret/samba`.
