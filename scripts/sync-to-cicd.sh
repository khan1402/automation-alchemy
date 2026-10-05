#!/usr/bin/env bash
# sync-to-cicd.sh - copy your latest repo changes into cicd-server's working copy.
#
# Run ON cicd-server as devops, after editing files on your laptop:
#   bash /vagrant/scripts/sync-to-cicd.sh
#
# Same copy that bootstrap.sh does on first boot (Vagrant can no longer
# re-run bootstrap once the VMs are hardened).
set -euo pipefail

rsync -r --delete \
  --exclude .git --exclude .vagrant --exclude keys --exclude .vault_pass \
  /vagrant/ "${HOME}/automation-alchemy/"
chmod -R u=rwX,go=rX "${HOME}/automation-alchemy"
echo "Synced /vagrant -> ${HOME}/automation-alchemy"

