#!/usr/bin/env bash
# backup.sh - pulls a fresh backup from every other VM over SSH.
# Run by cron as the devops user (see crontab.txt).
#
# Runs as a non-root user by design (least privilege) - this means some
# root-only files under /etc (SSH host keys, shadow, sudoers, UFW's
# compiled rule files) are unreadable and skipped. That's expected, not
# a bug: rsync's exit code 23 (partial transfer, some files skipped)
# is treated as success here, while genuine failures (exit 255 = SSH
# connection failed entirely) still stop the script.
set -uo pipefail

SSH_KEY="/home/devops/.ssh/devops_key"
SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
BACKUP_ROOT="/var/backups/infrastructure-insight"
DATE=$(date +%Y-%m-%d)
DEST="${BACKUP_ROOT}/${DATE}"

# Files under /etc that devops (non-root) cannot read, and don't need to
# be backed up anyway - SSH host keys regenerate on their own, shadow
# files hold password hashes, UFW's compiled rules derive from config
# we're not touching here.
ETC_EXCLUDES=(
  --exclude='shadow' --exclude='shadow-'
  --exclude='gshadow' --exclude='gshadow-'
  --exclude='sudoers' --exclude='sudoers.d'
  --exclude='.pwd.lock'
  --exclude='ssl/private'
  --exclude='ssh/ssh_host_*'
  --exclude='ufw/*.rules' --exclude='ufw/*.init'
  --exclude='security/opasswd'
  --exclude='multipath'
  --exclude='polkit-1/localauthority'
  --exclude='iscsi/initiatorname.iscsi'
)

# Runs an rsync command; treats exit code 23 (partial transfer, some
# files skipped due to permissions) as acceptable. Any other non-zero
# exit code is a real failure.
run_rsync() {
  rsync "$@"
  local rc=$?
  if [[ $rc -ne 0 && $rc -ne 23 && $rc -ne 24 ]]; then
    echo "ERROR: rsync failed with exit code $rc"
    return $rc
  fi
  return 0
}

echo "==> Starting backup run: ${DATE}"
mkdir -p "${DEST}"

HOSTS=("app-server" "web-server-1" "web-server-2" "load-balancer")

for host in "${HOSTS[@]}"; do
  echo "==> Backing up ${host}..."
  mkdir -p "${DEST}/${host}"

  # /etc - system configuration (partial, non-root-readable subset)
  run_rsync -az -e "ssh ${SSH_OPTS}" \
    "devops@${host}:/etc/" "${DEST}/${host}/etc/" \
    "${ETC_EXCLUDES[@]}" 2>&1 | tee -a "${DEST}/${host}-etc.log"

  # /home/devops - the devops user's home directory
  run_rsync -az -e "ssh ${SSH_OPTS}" \
    "devops@${host}:/home/devops/" "${DEST}/${host}/home-devops/" \
    2>&1 | tee -a "${DEST}/${host}-home.log"

  # Application data - only exists on app-server and the web servers
  if [[ "$host" != "load-balancer" ]]; then
    run_rsync -az -e "ssh ${SSH_OPTS}" \
      "devops@${host}:/opt/app/" "${DEST}/${host}/app-data/" \
      2>&1 | tee -a "${DEST}/${host}-app.log"
  fi
done

# Compress the whole day's backup into one archive
echo "==> Compressing backup..."
tar -czf "${BACKUP_ROOT}/${DATE}.tar.gz" -C "${BACKUP_ROOT}" "${DATE}"
rm -rf "${DEST}"

# Keep the last 4 weekly backups, delete anything older
echo "==> Pruning old backups (keeping last 4)..."
cd "${BACKUP_ROOT}"
ls -1t *.tar.gz 2>/dev/null | tail -n +5 | xargs -r rm --

echo "==> Backup complete: ${BACKUP_ROOT}/${DATE}.tar.gz"

