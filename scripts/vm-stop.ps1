# vm-stop.ps1 - cleanly shut down the project VMs WITHOUT Vagrant.
# Sends the "power button" signal, so Ubuntu shuts down properly.
# See vm-start.ps1 for why Vagrant cannot do this after hardening.
#
# Usage (PowerShell, repo root):  .\scripts\vm-stop.ps1

$vbox = Join-Path $env:VBOX_MSI_INSTALL_PATH "VBoxManage.exe"
$vms  = & $vbox list runningvms | ForEach-Object { ($_ -split '"')[1] } | Where-Object { $_ -like "alchemy-*" }

foreach ($vm in $vms) {
    Write-Host "Shutting down $vm"
    & $vbox controlvm $vm acpipowerbutton
}
Write-Host "Done. VMs power off within a few seconds."

