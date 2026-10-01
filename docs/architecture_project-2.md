# Infrastructure Insight — Architecture

## Network Diagram

```
                         +----------------------+
   Internet/Host -------->|   load-balancer      |  192.168.56.10
   (port 8080 -> 80)      |   nginx (least_conn) |  ONLY VM reachable
                         +----------+-----------+  from outside subnet
                                    |
                    +---------------+---------------+
                    v                                v
         +----------------------+          +----------------------+
         |   web-server-1        |          |   web-server-2        |
         |   192.168.56.11        |          |   192.168.56.12        |
         |   frontend-app          |          |   frontend-app          |
         |   (Docker, port 80)     |          |   (Docker, port 80)     |
         +----------+-----------+          +----------+-----------+
                     |                                  |
                     +----------------+-----------------+
                                       v
                          +----------------------+
                          |   app-server           |  192.168.56.13
                          |   backend-app           |  reachable only
                          |   (Docker, port 3000)   |  from web tier
                          +----------------------+

         +----------------------+
         |   backup               |  192.168.56.14
         |   pulls from all 4      |  SSH out to every VM
         |   VMs via SSH            |  (own devops_key copy)
         +----------------------+
```

## IP & Resource Table

| VM | IP | vCPU | RAM | Role |
|---|---|---|---|---|
| load-balancer | 192.168.56.10 | 2 | 1024MB | nginx reverse proxy, public entry point |
| web-server-1 | 192.168.56.11 | 1 | 1024MB | frontend container |
| web-server-2 | 192.168.56.12 | 1 | 1024MB | frontend container |
| app-server | 192.168.56.13 | 2 | 2048MB | backend container |
| backup | 192.168.56.14 | 1 | 1024MB | backup/restore, no application role |

## Firewall Rules (confirmed via `sudo ufw status verbose`)

| VM | Port | Source |
|---|---|---|
| load-balancer | 22/tcp | 192.168.56.0/24 |
| load-balancer | 80/tcp | Anywhere |
| web-server-1/2 | 22/tcp | 192.168.56.0/24 |
| web-server-1/2 | 80/tcp | 192.168.56.10 only (load balancer) |
| app-server | 22/tcp | 192.168.56.0/24 |
| app-server | 3000/tcp | 192.168.56.0/24 (web tier subnet) |
| backup | 22/tcp | 192.168.56.0/24 |

No unused ports open on any VM -- each rule scoped to the minimum source needed.

## Docker/UFW Port Binding

**The gap:** by default, `docker run -p 3000:3000` binds a container to `0.0.0.0` -- every network interface on the host. Docker manages its own iptables rules for published ports, and those rules are evaluated *before* UFW's INPUT chain -- meaning UFW's subnet restriction never actually applies to container-published ports, regardless of how correctly configured it looks.

**The fix:** bind each container to its VM's specific private IP instead:
```bash
-p 192.168.56.13:3000:3000   # app-server backend
-p "${PRIVATE_IP}:80:80"     # web servers (detected dynamically, since the same script runs on both)
```
Confirmed via `docker inspect <container> --format='{{.NetworkSettings.Ports}}'` -- shows the specific IP, not `0.0.0.0`.

## Load Balancing Algorithm

`least_conn` -- routes each new request to whichever web server currently has the fewest active connections, rather than round-robin's strict alternation. Chosen because the frontend must complete an HTTP call to the backend before responding, so requests have variable duration; round-robin would keep routing new work to an already-busy server, while `least_conn` naturally avoids that. Paired with passive health checks (`max_fails=3 fail_timeout=10s`) for automatic, tool-free failover.

## Backup & Restore Design

- **Mechanism:** the backup VM authenticates as `devops` via the same SSH keypair already trusted by every VM (no separate credential system) and pulls `/etc`, `/home/devops`, and `/opt/app` (where applicable) via `rsync` over SSH.
- **Schedule:** weekly, Sunday 2:00 AM, via `/etc/cron.d/backup` (system-wide cron, appropriate for provisioning-installed jobs -- not a personal crontab, which requires interactive setup).
- **Storage:** one compressed `.tar.gz` per run in `/var/backups/infrastructure-insight/`, oldest pruned beyond the last 4.
- **Root-only file exclusions:** SSH host keys, `shadow`/`gshadow`, `sudoers`, UFW's compiled rule files -- genuinely unreadable by the non-root `devops` user and not needed for restore purposes (rsync exit code 23, "partial transfer," is treated as success, not failure).
- **Restore safety:** `app-data` and `home-devops` restore directly; `etc` restores to a staging folder (`/tmp/restored-etc/`) rather than overwriting a live server's system config directly, avoiding the risk of breaking SSH/sudo mid-restore.

## Sudo Password Handling

Carried forward from Project 1: SSH key authentication gets you *into* a VM; `sudo` checks a completely separate local Linux password. `common.sh` generates one random password per VM at provisioning time (`openssl rand -base64 12`) and prints it once to the console -- never hardcoded in the repo. If lost, there's no recovery path; destroy and rebuild that VM.

## Recommendations for Future Improvements

- TLS termination on the load balancer (currently plain HTTP)
- Centralized logging across all 5 VMs (currently per-VM only)
- Active health checks on the load balancer (currently passive-only, via failed-request counting)
- Automated restore verification (currently manual, on-demand)

