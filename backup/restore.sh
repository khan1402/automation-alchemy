#!/usr/bin/env bash
# restore.sh - restores a specific data type from a backup archive
# back onto a specific target host.
#
# Usage: ./restore.sh <backup-date> <host> <data-type>
#   data-type is one of: etc, home-devops, app-data
#
# Example: ./restore.sh 2026-09-14 app-server app-data

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <backup-date> <host> <data-type>"
  echo "  data-type: etc | home-devops | app-data"
  exit 1
fi

BACKUP_DATE="$1"
HOST="$2"
DATA_TYPE="$3"

SSH_KEY="/home/devops/.ssh/devops_key"
SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
BACKUP_ROOT="/var/backups/infrastructure-insight"
ARCHIVE="${BACKUP_ROOT}/${BACKUP_DATE}.tar.gz"
WORKDIR="/tmp/restore-${BACKUP_DATE}"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "ERROR: No backup found for ${BACKUP_DATE} at ${ARCHIVE}"
  exit 1
fi

echo "==> Extracting ${ARCHIVE}..."
mkdir -p "${WORKDIR}"
tar -xzf "${ARCHIVE}" -C "${WORKDIR}"

SOURCE_DIR="${WORKDIR}/${BACKUP_DATE}/${HOST}/${DATA_TYPE}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "ERROR: No ${DATA_TYPE} backup found for ${HOST} on ${BACKUP_DATE}"
  exit 1
fi

# --no-owner --no-group --no-perms: the original backup preserved the
# source files' owner, group, and exact permission bits (often root,
# since provisioning created them as root). Restoring as the non-root
# devops user can't re-apply any of that - devops can't chown to root
# or chmod files it doesn't own. We don't need the exact original
# metadata on restore, just the file contents, so we skip all three.
case "$DATA_TYPE" in
  etc)
    echo "==> Restoring /etc to ${HOST}..."
    rsync -az --no-owner --no-group --no-perms -e "ssh ${SSH_OPTS}" \
      "${SOURCE_DIR}/" "devops@${HOST}:/tmp/restored-etc/"
    echo "==> Restored to /tmp/restored-etc/ on ${HOST} (review before copying into /etc)"
    ;;
  home-devops)
    echo "==> Restoring /home/devops to ${HOST}..."
    rsync -az --no-owner --no-group --no-perms -e "ssh ${SSH_OPTS}" \
      "${SOURCE_DIR}/" "devops@${HOST}:/home/devops/"
    echo "==> Restored directly to /home/devops on ${HOST}"
    ;;
  app-data)
    echo "==> Restoring /opt/app to ${HOST}..."
    rsync -az --no-owner --no-group --no-perms -e "ssh ${SSH_OPTS}" \
      "${SOURCE_DIR}/" "devops@${HOST}:/opt/app/"
    echo "==> Restored directly to /opt/app on ${HOST}"
    ;;
  *)
    echo "ERROR: Unknown data-type '${DATA_TYPE}'"
    exit 1
    ;;
esac

rm -rf "${WORKDIR}"
echo "==> Restore complete."

