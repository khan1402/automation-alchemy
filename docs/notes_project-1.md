# Build Notes

Running log kept while building the environment. Messy on purpose — this is
source material for `architecture.md` and the README's "Challenges" section,
not a polished document. Add an entry every time you make a real decision,
hit a problem, or change your mind about something.

Suggested format per entry:
```
## Day N — <what you were working on>
**Did:** what you actually did
**Problem:** what broke or was unclear (if anything)
**Fix / decision:** how you resolved it, or what you decided and why
```

---

## Day 0 — Windows toolchain setup (VirtualBox, Vagrant, WSL2, Git)

**Did:** Installed VirtualBox 7.2.16 and Vagrant 2.4.9 on Windows. Confirmed
VT-x enabled in BIOS. Installed Git for Windows (Git Credential Manager,
LF line endings on checkout to avoid breaking shell scripts, main as
default branch name). Set up VS Code with a local (non-WSL) PowerShell
terminal as the default profile.

**Problem:** My laptop already had WSL2 (Ubuntu) set up and in regular use.
WSL2 depends on Windows' Hyper-V/VirtualMachinePlatform feature, and
VirtualBox has historically conflicted with Hyper-V being active — the two
compete for the same hardware virtualization (VT-x). Initially disabled
Hyper-V entirely for VirtualBox, which broke WSL2 and VS Code's
Remote-WSL connection. Also discovered my actual project folder only
existed inside the WSL filesystem, not on the Windows side where Vagrant
needed it — had to copy it out via `\\wsl.localhost\Ubuntu\...` and flatten
an accidental nested-folder copy.

**Fix / decision:** Re-enabled `VirtualMachinePlatform` (keeping the full
`Microsoft-Hyper-V-All` role disabled) and tested with a disposable Vagrant
VM. VirtualBox 7.2 booted it in ~20 seconds — full native speed, not the
slower Hyper-V-fallback mode some older guides warn about. Decided to run
one unified environment: WSL2 stays enabled for future projects (Ansible in
P3 needs a real Linux control node), VirtualBox/Vagrant run directly from
Windows PowerShell (not through WSL), avoiding a dual-boot workaround that
would've made Ansible unreachable later anyway.

---

## Day 1 — VM topology & networking

**Did:** Designed a 4-VM topology in the `Vagrantfile`: `load-balancer`
(192.168.56.10, 2 vCPU/1GB), `web-server-1`/`web-server-2` (.11/.12, 1
vCPU/1GB each), `app-server` (.13, 2 vCPU/2GB), all on a VirtualBox
host-only private network (192.168.56.0/24) with static IPs. Only
`load-balancer` gets a forwarded port to the host (8080→80), so it's the
only VM reachable from outside the private network — enforced at the
network layer, not just the firewall. Resource split: load balancer gets
extra CPU (connection-handling is CPU-bound), app server gets extra RAM
(business logic/caching is memory-bound), web servers stay lean since
there are two of them.

**Problem:** None yet at the design stage — issues showed up once VMs
actually ran (see later entries).

**Fix / decision:** Used static `/etc/hosts` entries on every VM (written
by `common.sh`) for hostname resolution between VMs, since there's no DNS
server in this lab network.

---

## Day 2 — devops user & SSH hardening

**Did:** `common.sh` creates the `devops` user, adds it to `sudo`, installs
the SSH public key, then hardens `sshd_config`: `PermitRootLogin no`,
`PasswordAuthentication no`, `AllowUsers devops`.

**Problem:** Vagrant's own SSH access (used internally by `vagrant ssh` /
`vagrant provision`, connecting as the `vagrant` user through a NAT port
forward) gets locked out by this same hardening — `AllowUsers devops`
rejects the `vagrant` user, and UFW (see Day 3) only accepts SSH from the
private subnet, not the NAT path Vagrant uses. Confirmed this for real
later: after the first successful `vagrant up`, `vagrant ssh load-balancer`
failed with `Connection reset` — traced it with `ssh -vvv` directly against
the NAT-forwarded key/port and confirmed the reset happens during the
identification exchange, consistent with UFW dropping it before SSH even
gets to check the username.

**Fix / decision:** Accepted this as by-design, not a bug — the whole point
of the hardening is that only `devops`, over the private network, can get
in. Documented that `vagrant ssh`/`vagrant provision` become unusable once
`common.sh` has run on a VM; any future admin access has to go through
`ssh devops@<private-ip>`, and any script changes require a full
`vagrant destroy` + `vagrant up` rather than live reprovisioning.

---

## Day 3 — UFW & firewall rules

**Did:** `common.sh` sets a default-deny UFW baseline (`ufw default deny
incoming`, `ufw default allow outgoing`) with an SSH allow rule scoped to
`192.168.56.0/24` only. Role scripts add their own rules on top:
`load-balancer` opens port 80 to everyone (the one public-facing
exception), web servers only accept port 80 from the load balancer's IP,
`app-server` only accepts port 3000 from the web-tier subnet.

**Problem:** Order matters — the SSH allow rule has to exist *before*
`ufw --force enable` runs, or you lock yourself out entirely the moment
the firewall activates.

**Fix / decision:** Wrote the SSH allow rule ahead of the `ufw enable` line
in `common.sh` specifically to avoid that trap. Also confirmed (see Day 2)
that this same subnet restriction is what blocks Vagrant's own NAT-based
access after provisioning — intentional, but worth explaining clearly
during review since it looks like a Vagrant problem at first glance and is
actually the firewall working correctly.

---

## Day 4 — umask, auto-updates, sudo password gap, boot timeout

**Did:** Set `UMASK 027` system-wide via `/etc/login.defs` and a
`profile.d` script. Installed and enabled `unattended-upgrades` with both
`Update-Package-Lists` and `Unattended-Upgrade` turned on. Ran the first
full `vagrant up` across all 4 VMs — provisioning completed with no
errors, `groups devops` correctly showed `devops sudo`.

**Problem:** SSHed in as `devops` (worked instantly, no password — key
auth confirmed working) but `sudo whoami` rejected every attempt. Turned
out `common.sh` only ever ran `useradd` and installed the SSH key for
`devops` — it never actually set a Linux password with `passwd`/
`chpasswd`. SSH key auth and sudo's local password check are two
completely separate systems; disabling `PasswordAuthentication` in
`sshd_config` has zero effect on what `sudo` checks locally. Tried
`vagrant ssh` as a workaround to fix it live — blocked by the same
UFW/AllowUsers restriction from Day 2/3, confirming that path really is
dead once hardening has run. Separately, on the rebuild attempt, hit a
`Timed out while waiting for the machine to boot` error even though the
VM's own console (checked directly in VirtualBox Manager) showed it had
booted cleanly to a login prompt — this particular Ubuntu cloud image uses
`cloud-init` on first boot, which occasionally takes longer than Vagrant's
default 300-second `boot_timeout`.

**Fix / decision:** Updated `common.sh` to generate a random password per
VM with `openssl rand -base64 12`, set it via `chpasswd`, and print it once
to the provisioning console output — never hardcoded or committed to git,
since that would be a real secret sitting in a public repo. Raised
`config.vm.boot_timeout` to 600 in the `Vagrantfile` to give cloud-init
more room. Destroyed and rebuilt all 4 VMs from the fixed script rather
than patching the already-broken ones by hand — treating VMs as disposable
felt like the actual point of infrastructure-as-code rather than a
workaround. Re-verified after rebuild: `sudo whoami` correctly prompted
for the new password and returned `root`.

---

## Day 5 — automated validation, PAM umask bug, and umask breaking nginx/systemd

**Did:** Wrote `validate/check-requirements.sh` to automate the grading
checklist over SSH across all 4 VMs. First run: 24/32 passed. Two
consistent failures across every VM - UFW status check and umask check.

**Problem (UFW check):** The script runs `sudo ufw status`, but connects
non-interactively over SSH with no way to type a sudo password - so the
check was failing on its own limitation, not a real config issue.

**Fix (UFW check):** Added a narrowly-scoped `/etc/sudoers.d/devops-readonly`
granting `devops` passwordless sudo for exactly `ufw status` / `ufw status
verbose` - nothing else. All other sudo use (visudo, passwd, changing
firewall rules) still requires a password.

**Problem (umask check, round 1):** `common.sh` set umask via
`/etc/profile.d/99-umask.sh`, but that only applies to interactive login
shells - a non-interactive `ssh host "cmd"` (exactly what the validation
script does) skips it and falls back to Ubuntu's PAM default (`0007`
instead of `0027`). Confirmed by testing both an interactive SSH session
(showed `0027`, correct) and a one-off command (showed `0007`, wrong) -
same VM, two different results depending on connection type.

**Fix attempt 1 (didn't work):** Tried enforcing via PAM -
`session optional pam_umask.so umask=0027` in `/etc/pam.d/common-session`.
Still failed after rebuild. Investigated: Ubuntu already ships a default
`session optional pam_umask.so` line in that file with NO umask parameter -
my script's check (`grep -q pam_umask ...`) matched that existing line and
skipped adding mine, so my `umask=0027` never actually got set anywhere.

**Fix attempt 2 (worked):** Rewrote the logic to detect three cases: an
existing line with a umask param (replace the number), an existing line
with no param (append the param), or no line at all (add one from
scratch). Rebuilt, re-ran validation: 28/32 passed, umask now correctly
`0027` in both interactive and non-interactive sessions.

**Problem (cascading bug from the umask fix):** With umask genuinely
enforced everywhere now, manually testing the load balancer
(`curl http://192.168.56.10`) returned `403 Forbidden` instead of the
expected placeholder page. nginx's own error log was empty - no proxy
failures logged - which was the clue that nginx wasn't even the source of
the problem. Checked the load balancer's config directly (`sudo cat`) -
correct, matched what the script should have written. Checked
`web-server-1`'s actual file: `ls -la /var/www/html/index.html` showed
`-rw-r----- root root` - group-and-owner-only permissions. nginx's worker
process runs as `www-data`, which isn't in the `root` group, so it
literally couldn't read its own webpage. Same root cause almost certainly
hit `app-server`'s placeholder service too, since its systemd unit runs as
`User=devops` but the script file was also root-owned under the same
strict umask.

**Fix / decision:** The now-correctly-enforced global umask (a rubric
requirement) had an unintended side effect: root-created files stopped
being readable by the non-root users/processes that needed to serve or
run them. Rather than loosen the umask itself, added explicit
`chown`/`chmod` on just the specific files that need it -
`www-data:www-data` + `644` for the web server's `index.html`, `devops:
devops` + `750` for the app server's `app.py`. Kept the strict umask
policy intact everywhere else. Rebuilt all 4 VMs, re-ran validation
(32/32 passed) and manually confirmed the load balancer now correctly
round-robins real content from both web servers instead of erroring.

Also hit the "Fixed port collision" boot-timeout flakiness a few more
times during these rebuilds - one VM at a time would occasionally time
out even at 900s, always resolved by destroying and rebuilding just that
one VM. Traced one instance to genuine RAM pressure on the host (checked
via `Get-Process VBoxHeadless`, saw ~3.5GB across VM processes on a 16GB
machine, plus browser/editor overhead) - closing Chrome before the next
`vagrant up` fixed it that time.

---

## Day 6 — bonus features: Fail2Ban, WireGuard, Netdata

**Did:** Implemented all three optional bonus categories, gated behind a
single `ENABLE_BONUS=true` environment variable flag in the `Vagrantfile`
so the required core environment stays unaffected by default (per the
assignment's own suggested pattern for bonus functionality).

**Problem 1 (Fail2Ban race condition):** First provisioning attempt on a
VM failed with `ERROR Failed to access socket path: /var/run/fail2ban/
fail2ban.sock`. The script called `systemctl enable --now fail2ban`
immediately followed by `fail2ban-client status sshd` - a race condition
where the status check ran before the service had actually finished
starting and created its socket.

**Fix 1:** Added a short retry loop (up to 10 seconds) polling
`fail2ban-client status sshd` before treating it as ready, instead of
checking immediately.

**Problem 2 (Netdata unreachable from host):** After provisioning
succeeded with no errors, `curl http://<vm-ip>:19999` returned
"Connection refused" from the host, despite the UFW rule allowing it.
Checked with `ss -tln` on the VM directly and found Netdata's Ubuntu
package binds to `127.0.0.1` (localhost) by default - the UFW rule was
correct but irrelevant, since the app itself never accepted connections
from outside the VM in the first place.

**Fix 2:** Explicitly wrote `/etc/netdata/netdata.conf` with
`bind to = 0.0.0.0` and restarted the service. UFW remains the actual
access control (still scoped to the lab subnet only) - the app now
listens broadly, but only the firewall-permitted subnet can reach it.

**Problem 3 (`ENABLE_BONUS` silently not applying):** After closing and
reopening a terminal, ran `vagrant destroy app-server -f && vagrant up
app-server` to fix an unrelated boot timeout - the VM came back up, but
none of the three bonus scripts had run, no error shown. Root cause:
`$env:ENABLE_BONUS="true"` in PowerShell only persists for the session it
was set in. A fresh terminal starts without it, so the Vagrantfile's `if
ENABLE_BONUS` check silently evaluated false and skipped those
provisioners entirely - Vagrant doesn't warn when a conditional
provisioner is skipped this way.

**Fix 3:** No code fix needed - this is expected PowerShell behavior, not
a bug. Documented clearly in the README as something to actively remember:
set `$env:ENABLE_BONUS="true"` fresh in every new terminal session before
any `vagrant up` where bonus features matter. Rebuilt `app-server` with
the flag correctly set; all three bonus scripts then ran successfully and
matched the other 3 VMs.

**Also found:** documentation had drifted behind the actual implementation
- `README.md` and `docs/architecture.md` both still described WireGuard
and Netdata as "recommended, not implemented" after they'd actually been
built and verified working. Updated both to accurately reflect current
state, since a reviewer reading stale docs after seeing working bonus
features live would reasonably question whether the rest of the
documentation could be trusted either.

---

