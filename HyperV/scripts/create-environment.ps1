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

$deployedServices = @('nova' 'neutron-hyperv-agent')
if ($jobType -eq 'smbfs') {
    $deployedServices += 'cinder-volume'
}

# Python projects installed from repo. If the repo name is missing,
# the project is expected to be already cloned at $buildDir.
$installedFromRepo = @(
    @{projectName="nova";
      repo="https://git.openstack.org/openstack/nova.git";
      branch=$branchName;
      # TODO(lpetrut): remove this once the nova patch that sets the
      # Hyper-V driver to use os-brick gets in, or when this is
      # implemented in compute-hyperv.
      # Note: this patch may need to be rebased from time to time.
      openstackPatchRefs=@("refs/changes/04/273504/9")},
    @{projectName="neutron";
      repo="https://git.openstack.org/openstack/neutron.git";
      branch=$branchName},
    @{projectName="networking-hyperv";
      repo="https://git.openstack.org/openstack/networking-hyperv.git";
      branch=$branchName},
    @{projectName="os-brick";
      branch=$branchName;
      # TODO(lpetrut): remove those cherry-picks once all
      # the Windows connectors get in.    
      openstackPatchRefs=@(
          # The patch adding the Windows FC connector.
          "refs/changes/80/323780/8",
          "refs/changes/81/323781/8")}
)

if ($jobType -eq 'smbfs') {
    $cinderInstallConfig = @{
        projectName="cinder";
        repo="https://git.openstack.org/openstack/cinder.git";
        branch=$branchName;
        extraRemotes=@(
            @{remoteName="downstream";
              remoteUrl="https://github.com/petrutlucian94/cinder"}
        )
    }
    if ($branchName.ToLower() -eq "master") {
        $cinderInstallConfig.cherryPicks = @(
            'dcd839978ca8995cada8a62a5f19d21eaeb399df',
            'f711195367ead9a2592402965eb7c7a73baebc9f'
        )
    }
    else {
        $cinderInstallConfig.cherryPicks = @(
            '0c13ba732eb5b44e90a062a1783b29f2718f3da8',
            '06ee0b259daf13e8c0028a149b3882f1e3373ae1'
        )
    }

    $installedFromRepo += $cinderInstallConfig;
}

function install_from_repo($projectInfo) {
    # TODO: add more debug information.
    log_message "Installing project: $projectInfo"
    $projectDir = "$buildDir\$($projectInfo.projectName)"
    ExecRetry {
        if ($projectInfo.branch)
            GitClonePull $projectDir $projectInfo.branch

        if ($isDebug -eq  'yes') {
            log_message "Content of $projectDir"
            Get-ChildItem $projectDir
        }
        pushd $projectDir

        foreach($extraRemote in $projectInfo.extraRemotes) {
            git remote add $extraRemote.remoteName $extraRemote.remoteUrl
            git fetch $extraRemote.remoteName
        }

        foreach($commitId in $projectInfo.cherryPicks) {
            cherry_pick $commitId
        }

        foreach($ref in $projectInfo.openstackPatchRefs) {
            git fetch "https://git.openstack.org/openstack/$($projectInfo.projectName)"
            cherry_pick FETCH_HEAD
        }

        & pip install $projectDir
        if ($LastExitCode) {
            Throw "Failed to install $($projectInfo.projectName) from repo"
        }
        popd
    }
}

$pip_conf_content = @"
[global]
index-url = http://10.0.110.1:8080/cloudbase/CI/+simple/
[install]
trusted-host = 10.0.110.1
"@


$ErrorActionPreference = "Stop"

log_message ("Ensuring that the following services are stopped and " +
             "no possbile python processes are left: $deployedServices")
foreach($serviceName in $deployedServices) {
    ensure_service $serviceName -requestedState "Stopped"

    log_message "Stopping any possible python processes left."
    ensure_process_stopped $serviceName
} 
ensure_process_stopped "python"

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

foreach($projectInfo in $installedFromRepo) {
    install_from_repo $projectInfo
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
    start_openstack_service 'cinder-volume' -configFile "$configDir\cinder.conf" `
                            -logDir $openstackLogs `
                            -exeFile "$pythonDir\Scripts\cinder-volume.exe"
start_openstack_service 'nova-compute' -configFile "$configDir\nova.conf" `
                        -logDir $openstackLogs `
                        -exeFile "$pythonDir\Scripts\nova-compute.exe"
start_openstack_service 'neutron-hyperv-agent' -configFile "$configDir\neutron_hyperv_agent.conf" `
                        -logDir $openstackLogs `
                        -exeFile "$pythonDir\Scripts\nova-compute.exe"
