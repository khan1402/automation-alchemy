# Project 2: Infrastructure Insight — Build Log

(This continues on from Project 1 / server-sorcery-101's own docs/notes.md build log, carried forward in that repo's history. This file covers Project 2 specifically.)

## Group 1 — Backend

Built `metrics.py` (pure data collection) + `main.py` (FastAPI wrapper) — deliberately separated so the web layer knows nothing about how metrics are gathered. Containerized with a layer-cached Dockerfile (`requirements.txt` copied before app code, so dependency installs are cached across rebuilds).

Hit a real bug: `docker-install.sh`'s idempotency check used `exit 0` inside an `if command -v docker` block. Since the script is *sourced* by the role scripts (not executed as a subprocess), that `exit 0` terminated the entire calling script on any re-provision, not just the docker-install portion. Fixed with `return 0`.

Verified end-to-end: `curl http://192.168.56.13:3000/metrics` from the host returns real hostname/OS/CPU/memory JSON.

## Group 2 — Frontend

Same modularity pattern as the backend: `main.py` calls the backend via a `BACKEND_URL` environment variable (never hardcoded into the image), renders results via Jinja2.

Hit a startup-timing race condition — containers reported "running" via `docker ps` before uvicorn inside had actually finished starting, causing the very first test request to see a connection reset. Fixed with a short `sleep 3` immediately after `docker run` in both `role-app-server.sh` and `role-web-server.sh`.

Also hit significant VirtualBox/Vagrant instability during this session: SSH connection resets, intermittent "guest communication could not be established" errors, and a `vagrant-vbguest` plugin that crashed outright due to a Ruby API incompatibility (`File.exists?` vs `File.exist?`) — uninstalled rather than pursued further. Worked around the SSH unreliability using a temporary Vagrantfile diagnostic-provisioner pattern: adding a one-off `node.vm.provision "shell", inline: "..."` block to run real test commands through Vagrant's own (still-working) provisioning SSH channel, when direct `vagrant ssh` sessions kept failing.

## Group 3 — Load Balancer

`role-web-server.sh` required zero changes to support a second identical web server — the earlier design decision to avoid hardcoding hostname or backend IP paid off directly here. Added `least_conn` (instead of nginx's default round-robin) plus passive health checks (`max_fails=3 fail_timeout=10s`) to `role-load-balancer.sh`.

Confirmed real alternation across 6 consecutive `curl` requests through the load balancer: `web-server-1, web-server-2, web-server-1, web-server-2, web-server-1, web-server-2` — a clean, textbook distribution pattern.

## Group 4 — Firewall Hardening

Fixed a real, non-obvious security gap: Docker's own port-publishing bypasses UFW's filtering entirely for container ports, even when UFW rules look correct. Root cause: Docker manages its own iptables rules, evaluated before UFW's INPUT chain — so `-p 3000:3000` (equivalent to `-p 0.0.0.0:3000:3000`) accepts connections from any interface regardless of UFW's subnet restriction. Fixed by binding each container to its VM's specific private IP instead (`-p 192.168.56.13:3000:3000`, and a dynamically-detected `${PRIVATE_IP}` for the two web servers, since the same script runs on both).

Extended `validate/check-requirements.sh` with container/metrics/load-balancing/port-exposure checks.

This session also surfaced significant VirtualBox host-only networking instability after a lot of same-session VM churn (destroy/rebuild/suspend/resume cycles) — culminating in a `vagrant up` that timed out after the full 30-minute boot_timeout despite the VM not doing anything unusually heavy. Resolved with a full host machine restart partway through testing, after which VM rebuilds became reliable again on the first try. Root cause never fully confirmed, but consistent with known VirtualBox host-only-adapter degradation under heavy repeated reconfiguration.

## Group 5 — Backup VM

Added a 5th VM (`backup`, 192.168.56.14) authenticating outward to the other four VMs via a copy of the same `devops` SSH keypair every VM already trusts (the Vagrantfile's `file` provisioner copies the private key onto this VM only).

Two real permission bugs were found — both only surfaced once backup/restore were actually run live, not from reading the code:

1. **Backup couldn't read `/opt/app`.** Backend/frontend application code was copied onto each server as root during provisioning, with no explicit permissions granted to the non-root `devops` user that performs backups. `rsync` failed with `Permission denied` trying to enter `/opt/app`. Fixed with `chmod -R o+rX /opt/app` added to both `role-app-server.sh` and `role-web-server.sh`, right after the code is copied in.

2. **Restore failed with `chgrp`/`chmod "Operation not permitted"`.** `rsync -a` (used by both `backup.sh` and `restore.sh`) preserves the original file owner, group, and exact permission bits — often root, since files were created by root during provisioning. When `restore.sh` tried to push that data back onto a server as the non-root `devops` user, it attempted to re-apply that original root ownership and failed, since `devops` has no permission to `chown`/`chgrp` to root. Fixed incrementally: first added `--no-owner --no-group` (resolved the chgrp errors), then discovered permission-bit restoration failed the same way and added `--no-perms` too. Final flag set: `rsync -az --no-owner --no-group --no-perms`.

Also caught and fixed an accidental regression during the `/opt/app` permission fix: an edit meant only to add an `rsync` installation line to `common.sh` had actually *deleted* the pre-existing line that installs the `ufw` package itself, while leaving all of `ufw`'s *configuration* commands (`ufw default deny incoming`, etc.) still in place below it. Every VM would have tried to configure a firewall tool that was never installed. Caught by reviewing the diff before pushing, not by a failed test — worth remembering as a reason to always read a diff in full, not just the intended change.

## Group 6 — UI/UX

Replaced the raw unstyled `<ul>` metrics list with a responsive card-based dashboard: CSS Grid with `auto-fit` for automatic reflow across screen sizes, progress bars for CPU/memory (visually faster to read than a bare percentage), a dark theme, and a subtle fade-in animation on page load.

Required mounting a `static/` folder in `main.py` via FastAPI's `StaticFiles` — easy to forget, since a missing mount doesn't throw an error; the `<link rel="stylesheet">` tag just silently 404s and the page renders as unstyled HTML with no obvious error message pointing at the cause.

## Full Testing Pass

Ran every mandatory and extra rubric item live, command by command, rather than relying solely on the automated validation script. This surfaced several additional real bugs:

- **Stale `validate/check-requirements.sh` localhost checks.** The frontend/metrics checks used `curl http://localhost:...`, which broke specifically *because* the Group 4 Docker/UFW fix succeeded — once containers stopped binding to `0.0.0.0`/loopback and started binding to their specific private IP only, `localhost` genuinely had nothing listening on it anymore from inside the VM itself. Fixed by checking each VM's own private IP (`${ip}`, already available as the loop variable) instead of `localhost`.
- **Grep pattern mismatch in the load-balancer distribution check.** The script searched for the literal text "Responding web server", but the actual rendered page said "Responding server" (no "web"). The check silently matched nothing and reported 0 servers responding, even though manual testing proved distribution was working correctly. Fixed by correcting the grep pattern to match the real page text, rather than changing the UI copy to match a script that had the wrong expectation.
- **`nginx -t` validation check required sudo devops didn't have passwordless access to.** `common.sh`'s sudoers exception only grants passwordless access to `ufw status` commands, by design (a narrowly-scoped exception so the validation script can check UFW status non-interactively). Running `sudo nginx -t` over batch-mode SSH just failed with "a password is required," regardless of whether the config was actually valid. Fixed by switching the check to `systemctl is-active --quiet nginx` instead — needs no sudo at all, and confirms the same underlying fact (nginx is running with a config it accepted) without requiring a config-validation command specifically.
- **Malformed root-login SSH check.** A missing space between two concatenated string arguments (`"root@${ip}""true"`) caused SSH to receive one malformed combined argument instead of a proper host + command pair — the check "passed" every time, but only because a garbled hostname always fails to connect, not because it was actually testing whether root login is refused. Fixed by adding the missing space.

Confirmed all three restore data types (`app-data`, `etc`, `home-devops`) work correctly end-to-end after the Group 5 permission fixes above, tested against a freshly-created backup archive.

Confirmed `traceroute` requires the `-I` (ICMP mode) flag against this environment — plain traceroute defaults to UDP probe packets, which UFW correctly has no explicit allow rule for, so it silently times out at every hop even though the underlying connection is completely fine (already proven by ping and telnet). This is intentional firewall behavior, not a bug, and worth being ready to explain rather than mistaking it for a broken connection.

**Key lesson from this whole project:** live, end-to-end testing surfaced real bugs — permission errors, stale validation-script assumptions, a near-miss firewall regression — that would not have been caught by reading the code or assuming "it should work" from the design alone. Several of these (the restore permission bugs especially) only appeared once backup/restore were actually run against real data, not just written and reviewed on paper.
