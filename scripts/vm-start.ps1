# vm-start.ps1 - start the project VMs WITHOUT Vagrant.
#
# Why: after hardening, only 'devops' may log in over SSH, so Vagrant (which
# logs in as 'vagrant') can no longer confirm a VM has booted, and
# 'vagrant up' on an existing VM waits until it times out.
# VirtualBox itself does not need SSH, so we start the VMs with it directly.
#
# Usage (PowerShell, repo root):  .\scripts\vm-start.ps1

$vbox = Join-Path $env:VBOX_MSI_INSTALL_PATH "VBoxManage.exe"
$vms  = & $vbox list vms | ForEach-Object { ($_ -split '"')[1] } | Where-Object { $_ -like "alchemy-*" }

foreach ($vm in $vms) {
    Write-Host "Starting $vm"
    & $vbox startvm $vm --type headless | Out-Null
}
Write-Host "Done. Give the VMs about a minute to boot."

