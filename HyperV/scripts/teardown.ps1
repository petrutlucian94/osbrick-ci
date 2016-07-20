# Loading config

. "C:\OpenStack\osbrick-ci\HyperV\scripts\config.ps1"
. "C:\OpenStack\osbrick-ci\HyperV\scripts\utils.ps1"
. "C:\OpenStack\osbrick-ci\HyperV\scripts\iscsi_utils.ps1"

# end Loading config

$ErrorActionPreference = "SilentlyContinue"

log_message "Stopping Nova and Neutron services"
Stop-Service -Name nova-compute -Force
Stop-Service -Name neutron-hyperv-agent -Force

log_message "Stopping any python processes that might have been left running"
Stop-Process -Name python -Force
Stop-Process -Name nova-compute -Force
Stop-Process -Name neutron-hyperv-agent -Force

log_message "Checking that services and processes have been succesfully stopped"
if (Get-Process -Name nova-compute){
    Throw "Nova is still running on this host"
}else {
    log_message "No nova process running."
}

if (Get-Process -Name neutron-hyperv-agent){
    Throw "Neutron is still running on this host"
}else {
    log_message "No neutron process running"
}

if (Get-Process -Name python){
    Throw "Python processes still running on this host"
}else {
    log_message "No python processes left running"
}

if ($(Get-Service nova-compute).Status -ne "Stopped"){
    Throw "Nova service is still running"
}else {
    log_message "Nova service is in Stopped state."
}

if ($(Get-Service neutron-hyperv-agent).Status -ne "Stopped"){
    Throw "Neutron service is still running"
}else {
    log_message "Neutron service is in Stopped state"
}



log_message "Clearing any VMs that might have been left."
Get-VM | where {$_.State -eq 'Running' -or $_.State -eq 'Paused'} | Stop-Vm -Force
Remove-VM * -Force

cleanup_iscsi_targets

log_message "Cleaning the build folder."
Remove-Item -Recurse -Force $buildDir\*
log_message "Cleaning the virtualenv folder."
Remove-Item -Recurse -Force $virtualenv
log_message "Cleaning the logs folder."
Remove-Item -Recurse -Force $openstackDir\Log\*
log_message "Cleaning the config folder."
Remove-Item -Recurse -Force $openstackDir\etc\*
log_message "Cleaning the Instances folder."
Remove-Item -Recurse -Force $openstackDir\Instances\*
log_message "Cleaning eventlog"
cleareventlog
log_message "Cleaning up process finished."
