Param(
    [Parameter(Mandatory=$true)][string]$devstackIP,
    [string]$branchName='master',
    [string]$buildFor='openstack/os-brick',
    [string]$jobType='iscsi',
    [string]$isDebug='no',
    [string]$zuulChange=''
)

if ($isDebug -eq  'yes') {
    Write-Host "Debug info:"
    Write-Host "devstackIP: $devstackIP"
    Write-Host "branchName: $branchName"
    Write-Host "buildFor: $buildFor"
}

$projectName = $buildFor.split('/')[-1]

$scriptLocation = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$scriptLocation\config.ps1"
. "$scriptLocation\utils.ps1"

$hasProject = Test-Path $buildDir\$projectName
$hasNeutronTemplate = Test-Path $neutronTemplate
$hasNovaTemplate = Test-Path $novaTemplate
$hasConfigDir = Test-Path $configDir
$hasBinDir = Test-Path $binDir
$hasMkisoFs = Test-Path $binDir\mkisofs.exe
$hasQemuImg = Test-Path $binDir\qemu-img.exe

$pip_conf_content = @"
[global]
index-url = http://10.0.110.1:8080/cloudbase/CI/+simple/
[install]
trusted-host = 10.0.110.1
"@

$ErrorActionPreference = "SilentlyContinue"

# Do a selective teardown
log_message "Ensuring nova and neutron services are stopped."
Stop-Service -Name nova-compute -Force
Stop-Service -Name neutron-hyperv-agent -Force
Stop-Service -Name cinder-volume -Force

log_message "Stopping any possible python processes left."
Stop-Process -Name python -Force

if (Get-Process -Name nova-compute){
    Throw "Nova is still running on this host"
}

if (Get-Process -Name neutron-hyperv-agent){
    Throw "Neutron is still running on this host"
}

if (Get-Process -Name python){
    Throw "Python processes still running on this host"
}

$ErrorActionPreference = "Stop"

if (-not (Get-Service neutron-hyperv-agent -ErrorAction SilentlyContinue))
{
    Throw "Neutron Hyper-V Agent Service not registered"
}

if (-not (get-service nova-compute -ErrorAction SilentlyContinue))
{
    Throw "Nova Compute Service not registered"
}

if (-not (get-service cinder-volume -ErrorAction SilentlyContinue))
{
    Throw "Cinder Volume Service not registered"
}

if ($(Get-Service nova-compute).Status -ne "Stopped"){
    Throw "Nova service is still running"
}

if ($(Get-Service neutron-hyperv-agent).Status -ne "Stopped"){
    Throw "Neutron service is still running"
}

if ($(Get-Service cinder-volume).Status -ne "Stopped"){
    Throw "Cinder service is still running"
}

log_message "Cleaning up the config folder."
if ($hasConfigDir -eq $false) {
    mkdir $configDir
}else{
    Try
    {
        Remove-Item -Recurse -Force $configDir\*
    }
    Catch
    {
        Throw "Can not clean the config folder"
    }
}

if ($hasProject -eq $false){
    Get-ChildItem $buildDir
    Get-ChildItem ( Get-Item $buildDir ).Parent.FullName
    Throw "$projectName repository was not found. Please run gerrit-git-prep.sh for this project first"
}

if ($hasBinDir -eq $false){
    mkdir $binDir
}

if (($hasMkisoFs -eq $false) -or ($hasQemuImg -eq $false)){
    Invoke-WebRequest -Uri "http://10.0.110.1/openstack_bin.zip" -OutFile "$bindir\openstack_bin.zip"
    if (Test-Path "$7zExec"){
        pushd $bindir
        & $7zExec x -y "$bindir\openstack_bin.zip"
        Remove-Item -Force "$bindir\openstack_bin.zip"
        popd
    } else {
        Throw "Required binary files (mkisofs, qemuimg etc.)  are missing"
    }
}

if ($hasNovaTemplate -eq $false){
    Throw "Nova template not found"
}

if ($hasNeutronTemplate -eq $false){
    Throw "Neutron template not found"
}

if ($isDebug -eq  'yes') {
    log_message "Status of $buildDir before GitClonePull"
    Get-ChildItem $buildDir
}

git config --global user.email "hyper-v_ci@microsoft.com"
git config --global user.name "Hyper-V CI"

ExecRetry {
    GitClonePull "$buildDir\nova" "https://git.openstack.org/openstack/nova.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\neutron" "https://git.openstack.org/openstack/neutron.git" $branchName
}
ExecRetry {
    GitClonePull "$buildDir\networking-hyperv" "https://git.openstack.org/openstack/networking-hyperv.git" $branchName
}

if ($jobType -eq 'smbfs')
{
    ExecRetry {
        GitClonePull "$buildDir\cinder" "https://git.openstack.org/openstack/cinder.git" $branchName
    }    
}

$hasLogDir = Test-Path $openstackLogs
if ($hasLogDir -eq $false){
    mkdir $openstackLogs
}

$hasConfigDir = Test-Path $remoteConfigs\$hostname
if ($hasConfigDir -eq $false){
    mkdir $remoteConfigs\$hostname
}

pushd C:\
if (Test-Path $pythonArchive)
{
    Remove-Item -Force $pythonArchive
}
Invoke-WebRequest -Uri http://10.0.110.1/python27new.tar.gz -OutFile $pythonArchive
if (Test-Path $pythonTar)
{
    Remove-Item -Force $pythonTar
}
if (Test-Path $pythonDir)
{
    Remove-Item -Recurse -Force $pythonDir
}
log_message "Ensure Python folder is up to date"
log_message "Extracting archive.."
& $7zExec x -y "$pythonArchive"
& $7zExec x -y "$pythonTar"

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false){
    mkdir "$env:APPDATA\pip"
}
else 
{
    Remove-Item -Force "$env:APPDATA\pip\*"
}
Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

& easy_install -U pip
& pip install -U setuptools
& pip install -U virtualenv
& pip install -U distribute
& pip install -U --pre pymi
& pip install cffi
& pip install numpy
& pip install pycrypto
& pip install -U os-win
& pip install amqp==1.4.9
& pip install cffi==1.6.0
& pip install pymysql

popd

$hasPipConf = Test-Path "$env:APPDATA\pip"
if ($hasPipConf -eq $false){
    mkdir "$env:APPDATA\pip"
}
else 
{
    Remove-Item -Force "$env:APPDATA\pip\*"
}
Add-Content "$env:APPDATA\pip\pip.ini" $pip_conf_content

cp $templateDir\distutils.cfg "$pythonDir\Lib\distutils\distutils.cfg"


if ($isDebug -eq  'yes') {
    log_message "BuildDir is: $buildDir"
    log_message "ProjectName is: $projectName"
    log_message "Listing $buildDir parent directory:"
    Get-ChildItem ( Get-Item $buildDir ).Parent.FullName
    log_message "Listing $buildDir before install"
    Get-ChildItem $buildDir
}

ExecRetry {
    if ($isDebug -eq  'yes') {
        log_message "Content of $buildDir\neutron"
        Get-ChildItem $buildDir\neutron
    }
    pushd $buildDir\neutron
    & pip install $buildDir\neutron
    if ($LastExitCode) { Throw "Failed to install neutron from repo" }
    popd
}

ExecRetry {
    if ($isDebug -eq  'yes') {
        log_message "Content of $buildDir\networking-hyperv"
        Get-ChildItem $buildDir\networking-hyperv
    }
    pushd $buildDir\networking-hyperv
    & pip install $buildDir\networking-hyperv
    if ($LastExitCode) { Throw "Failed to install networking-hyperv from repo" }
    popd
}

if($jobType -eq 'smbfs')
{
    ExecRetry {
        if ($isDebug -eq  'yes') {
            log_message "Content of $buildDir\cinder"
            Get-ChildItem $buildDir\cinder
        }
        pushd $buildDir\cinder

        git remote add downstream https://github.com/petrutlucian94/cinder
        
        ExecRetry {
            git fetch downstream
            if ($LastExitCode) { Throw "Failed fetching remote downstream petrutlucian94" }
        }

        git checkout -b "testBranch"
        if ($branchName.ToLower() -eq "master") {
            cherry_pick dcd839978ca8995cada8a62a5f19d21eaeb399df
            cherry_pick f711195367ead9a2592402965eb7c7a73baebc9f
        }
        else {
            cherry_pick 0c13ba732eb5b44e90a062a1783b29f2718f3da8
            cherry_pick 06ee0b259daf13e8c0028a149b3882f1e3373ae1
        }

        & pip install $buildDir\cinder
        if ($LastExitCode) { Throw "Failed to install cinder from repo" }
        popd
    }
}

ExecRetry {
    pushd $buildDir\os-brick

    # TODO(lpetrut): remove those cherry-picks once all the Windows connectors get in.    
    # The patch adding the Windows FC connector.
    git fetch https://git.openstack.org/openstack/os-brick refs/changes/80/323780/8
    cherry_pick FETCH_HEAD

    # The patch adding the Windows SMBFS connector.
    git fetch https://git.openstack.org/openstack/os-brick refs/changes/81/323781/8
    cherry_pick FETCH_HEAD

    & pip install $buildDir\os-brick
    popd
}


ExecRetry {
    if ($isDebug -eq  'yes') {
        log_message "Content of $buildDir\nova"
        Get-ChildItem $buildDir\nova
    }
    pushd $buildDir\nova

    # TODO(lpetrut): remove this once the nova patch that sets the Hyper-V driver to use
    # os-brick gets in, or when this is implemented in compute-hyperv.
    # Note: this patch may need to be rebased from time to time.
    git fetch https://git.openstack.org/openstack/nova refs/changes/04/273504/9
    cherry_pick FETCH_HEAD

    & pip install $buildDir\nova
    if ($LastExitCode) { Throw "Failed to install nova fom repo" }
    popd
}

# Note: be careful as WMI queries may return only one element, in which case we
# won't get an array. To make it easier, we can just make sure we always have an
# array.
$cpu_array = ([array](gwmi -class Win32_Processor))
$cores_count = $cpu_array.count * $cpu_array[0].NumberOfCores
$novaConfig = (gc "$templateDir\nova.conf").replace('[DEVSTACK_IP]', "$devstackIP").Replace('[LOGDIR]', "$openstackLogs").Replace('[RABBITUSER]', $rabbitUser)
$neutronConfig = (gc "$templateDir\neutron_hyperv_agent.conf").replace('[DEVSTACK_IP]', "$devstackIP").Replace('[LOGDIR]', "$openstackLogs").Replace('[RABBITUSER]', $rabbitUser).replace('[CORES_COUNT]', "$cores_count")

Set-Content $configDir\nova.conf $novaConfig
if ($? -eq $false){
    Throw "Error writting $configDir\nova.conf"
}

Set-Content $configDir\neutron_hyperv_agent.conf $neutronConfig
if ($? -eq $false){
    Throw "Error writting $configDir\neutron_hyperv_agent.conf"
}

cp "$templateDir\policy.json" "$configDir\"
cp "$templateDir\interfaces.template" "$configDir\"

if ($jobType -eq 'smbfs')
{
    & $scriptLocation\generateCinderCfg.ps1 $configDir $cinderTemplate $devstackIP $rabbitUser $remoteLogs $lockPath
}

$hasNovaExec = Test-Path "$pythonScripts\nova-compute.exe"
if ($hasNovaExec -eq $false){
    Throw "No nova-compute.exe found"
}

$hasNeutronExec = Test-Path "$pythonScripts\neutron-hyperv-agent.exe"
if ($hasNeutronExec -eq $false){
    Throw "No neutron-hyperv-agent.exe found"
}


Remove-Item -Recurse -Force "$remoteConfigs\$hostname\*"
Copy-Item -Recurse $configDir "$remoteConfigs\$hostname"

log_message "Starting the services"



if ($jobType -eq 'smbfs')
{
    log_message "Starting cinder-volume service"
    Try
    {
        Start-Service cinder-volume
    }
    Catch
    {
        log_message "Can not start the cinder-volume service."
    }
    Start-Sleep -s 30
    if ($(get-service cinder-volume).Status -eq "Stopped")
    {
        log_message "cinder-volume service is not running."
        log_message "We try to start:"
        Write-Host Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\cinder-volume.exe" -ArgumentList "--config-file $configDir\cinder.conf"
        log_message "Starting cinder-volume as a python process." -location "$openstackLogs\cinder-volume.log" 
        Try
        {
            $proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\cinder-volume.exe" -ArgumentList "--config-file $configDir\cinder.conf"
        }
        Catch
        {
            Throw "Could not start the process manually"
        }
        Start-Sleep -s 30
        if (! $proc.HasExited)
        {
            Stop-Process -Id $proc.Id -Force
            Throw "Process started fine when run manually."
        }
        else
        {
            Throw "Can not start the cinder-volume service. The manual run failed as well."
        }
    }
}

log_message "Starting nova-compute service"
Try
{
    Start-Service nova-compute
}
Catch
{
    log_message "Can not start the nova-compute service."
}
Start-Sleep -s 30
if ($(get-service nova-compute).Status -eq "Stopped")
{
    log_message "nova-compute service is not running."
    log_message "We try to start:"
    Write-Host Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\nova-compute.exe" -ArgumentList "--config-file $configDir\nova.conf"
    log_message "Starting nova-compute as a python process." -location "$openstackLogs\nova-compute.log"
    Try
    {
    	$proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonDir\Scripts\nova-compute.exe" -ArgumentList "--config-file $configDir\nova.conf"
    }
    Catch
    {
    	Throw "Could not start the process manually"
    }
    Start-Sleep -s 30
    if (! $proc.HasExited)
    {
    	Stop-Process -Id $proc.Id -Force
    	Throw "Process started fine when run manually."
    }
    else
    {
    	Throw "Can not start the nova-compute service. The manual run failed as well."
    }
}

log_message "Starting neutron-hyperv-agent service"
Try
{
    Start-Service neutron-hyperv-agent
}
Catch
{
    log_message "Can not start the neutron-hyperv-agent service."
}
Start-Sleep -s 30
if ($(get-service neutron-hyperv-agent).Status -eq "Stopped")
{
    log_message "neutron-hyperv-agent service is not running."
    log_message "We try to start:"
    Write-Host Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonScripts\neutron-hyperv-agent.exe" -ArgumentList "--config-file $configDir\neutron_hyperv_agent.conf"
    log_message "starting neutron-hyperv-agent as a python process." -location "$openstackLogs\neutron-hyperv-agent.log"
    Try
    {
    	$proc = Start-Process -PassThru -RedirectStandardError "$openstackLogs\process_error.txt" -RedirectStandardOutput "$openstackLogs\process_output.txt" -FilePath "$pythonScripts\neutron-hyperv-agent.exe" -ArgumentList "--config-file $configDir\neutron_hyperv_agent.conf"
    }
    Catch
    {
    	Throw "Could not start the process manually"
    }
    Start-Sleep -s 30
    if (! $proc.HasExited)
    {
    	Stop-Process -Id $proc.Id -Force
    	Throw "Process started fine when run manually."
    }
    else
    {
    	Throw "Can not start the neutron-hyperv-agent service. The manual run failed as well."
    }
}
