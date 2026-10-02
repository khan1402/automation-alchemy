#!/usr/bin/env bash
# bootstrap.sh - the ONLY shell provisioning in this project.
#
# It does the bare minimum so Ansible can take over:
#   every VM  : create 'devops', install the public key, allow sudo
#   cicd only : install Ansible, the private key and a copy of the playbooks
#
# Usage (called by the Vagrantfile): bootstrap.sh <inventory-group>
set -euo pipefail

GROUP="${1:?usage: bootstrap.sh <group>}"
USER_NAME="devops"
USER_HOME="/home/${USER_NAME}"

# Wait for first-boot cloud-init to finish, otherwise it can hold the apt lock.
cloud-init status --wait >/dev/null 2>&1 || true

echo "==> [bootstrap] ${HOSTNAME} (${GROUP})"

# --- devops user -----------------------------------------------------------
if ! id "${USER_NAME}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups sudo "${USER_NAME}"
fi

install -d -m 700 -o "${USER_NAME}" -g "${USER_NAME}" "${USER_HOME}/.ssh"
install -m 600 -o "${USER_NAME}" -g "${USER_NAME}" /tmp/ansible_key.pub "${USER_HOME}/.ssh/authorized_keys"

# TEMPORARY passwordless sudo so Ansible can start working.
# The hardening role (Group 2) removes this file and enforces a sudo password.
echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-devops-bootstrap
chmod 440 /etc/sudoers.d/90-devops-bootstrap
visudo -cf /etc/sudoers.d/90-devops-bootstrap >/dev/null

# --- cicd-server only: become the Ansible control node -----------------------
if [[ "${GROUP}" == "cicd" ]]; then
  APT="apt-get -o DPkg::Lock::Timeout=600 -y -q"

  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "==> [bootstrap] installing Ansible"
    export DEBIAN_FRONTEND=noninteractive
    add-apt-repository -y -n ppa:ansible/ansible >/dev/null
    $APT update >/dev/null
    $APT install ansible >/dev/null
  fi

  # Private key: lets devops@cicd-server SSH into every other VM.
  install -m 600 -o "${USER_NAME}" -g "${USER_NAME}" /vagrant/keys/ansible_key "${USER_HOME}/.ssh/ansible_key"

  # Copy the playbooks out of /vagrant. The shared folder is world-writable,
  # and Ansible refuses to load ansible.cfg from a world-writable directory.
  # (rsync only creates the LAST folder of a path, so create the parents first.)
  mkdir -p "${USER_HOME}/automation-alchemy/ansible"
  rsync -r --delete /vagrant/ansible/ "${USER_HOME}/automation-alchemy/ansible/"
  chown -R "${USER_NAME}:${USER_NAME}" "${USER_HOME}/automation-alchemy"
  chmod -R u=rwX,go=rX "${USER_HOME}/automation-alchemy"
fi

echo "==> [bootstrap] done"

