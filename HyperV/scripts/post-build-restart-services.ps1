# This script restart the nova and neutron services and cleans logs
# Needed to compensate for HyperV building ahead of time
#
Param(
    [string]$jobType='iscsi',
)

. "C:\OpenStack\osbrick-ci\HyperV\scripts\config.ps1"
. "C:\OpenStack\osbrick-ci\HyperV\scripts\utils.ps1"


# We may set this in config.ps1
$deployedServices = @('nova' 'neutron-hyperv-agent')
if ($jobType -eq 'smbfs') {
    $deployedServices += 'cinder-volume'
}

log_message "post-build: Stoping the services!"

foreach($serviceName in $deployedServices) {
    ensure_service $serviceName -requestedState "Stopped"

log_message "post-build: Cleaning previous logs!"

Remove-Item -Force C:\OpenStack\Log\*.log

log_message "post-build: Starting the services!"

if ($jobType -eq 'smbfs')
    start_openstack_service 'cinder-volume' -configFile "$configDir\cinder.conf" `
                            -logDir $openstackLogs `
                            -exeFile "$pythonDir\Scripts\cinder-volume.exe"
start_openstack_service 'nova-compute' -configFile "$configDir\nova.conf" `
                        -logDir $openstackLogs `
                        -exeFile "$pythonDir\Scripts\nova-compute.exe"
start_openstack_service 'neutron-hyperv-agent' -configFile "$configDir\neutron_hyperv_agent.conf" `
                        -logDir $openstackLogs `
                        -exeFile "$pythonDir\Scripts\nova-compute.exe"
