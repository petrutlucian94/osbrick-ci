function ExecRetry($command, $maxRetryCount = 10, $retryInterval=2)
{
    $currErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $retryCount = 0
    while ($true)
    {
        try 
        {
            & $command
            break
        }
        catch [System.Exception]
        {
            $retryCount++
            if ($retryCount -ge $maxRetryCount)
            {
                $ErrorActionPreference = $currErrorActionPreference
                throw
            }
            else
            {
                Write-Error $_.Exception
                Start-Sleep $retryInterval
            }
        }
    }

    $ErrorActionPreference = $currErrorActionPreference
}

function GitClonePull($path, $url, $branch="master")
{
    Write-Host "Calling GitClonePull with path=$path, url=$url, branch=$branch"
    if (!(Test-Path -path $path))
    {
        ExecRetry {
            git clone $url $path
            if ($LastExitCode) { throw "git clone failed - GitClonePull - Path does not exist!" }
        }
        pushd $path
        git checkout $branch
        git pull
        popd
        if ($LastExitCode) { throw "git checkout failed - GitCLonePull - Path does not exist!" }
    }else{
        pushd $path
        try
        {
            ExecRetry {
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue "$path\*"
                git clone $url $path
                if ($LastExitCode) { throw "git clone failed - GitClonePull - After removing existing Path.." }
            }
            ExecRetry {
                (git checkout $branch) -Or (git checkout master)
                if ($LastExitCode) { throw "git checkout failed - GitClonePull - After removing existing Path.." }
            }

            Get-ChildItem . -Include *.pyc -Recurse | foreach ($_) {Remove-Item $_.fullname}

            git reset --hard
            if ($LastExitCode) { throw "git reset failed!" }

            git clean -f -d
            if ($LastExitCode) { throw "git clean failed!" }

            ExecRetry {
                git pull
                if ($LastExitCode) { throw "git pull failed!" }
            }
        }
        finally
        {
            popd
        }
    }
}


function dumpeventlog($path){
	
	Get-Eventlog -list | Where-Object { $_.Entries -ne '0' } | ForEach-Object {
		$logFileName = $_.LogDisplayName
		$exportFileName =$path + "\eventlog_" + $logFileName + ".evt"
		$exportFileName = $exportFileName.replace(" ","_")
		$logFile = Get-WmiObject Win32_NTEventlogFile | Where-Object {$_.logfilename -eq $logFileName}
		try{
			$logFile.backupeventlog($exportFileName)
		} catch {
			Write-Host "Could not dump $_.LogDisplayName (it might not exist)."
		}
	}
}

function exporteventlog($path){

	Get-Eventlog -list | Where-Object { $_.Entries -ne '0' } | ForEach-Object {
		$logfilename = "eventlog_" + $_.LogDisplayName + ".txt"
		$logfilename = $logfilename.replace(" ","_")
		Get-EventLog -Logname $_.LogDisplayName | fl | out-file $path\$logfilename -ErrorAction SilentlyContinue
	}
}

function exporthtmleventlog($path){
	$css = Get-Content $eventlogcsspath -Raw
	$js = Get-Content $eventlogjspath -Raw
	$HTMLHeader = @"
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<script type="text/javascript">$js</script>
<style type="text/css">$css</style>
"@

	foreach ($i in (Get-EventLog -List | Where-Object { $_.Entries -ne '0' }).Log) {
		$Report = Get-EventLog $i
		$Report = $Report | ConvertTo-Html -Title "${i}" -Head $HTMLHeader -As Table
		$Report = $Report | ForEach-Object {$_ -replace "<body>", '<body id="body">'}
		$Report = $Report | ForEach-Object {$_ -replace "<table>", '<table class="sortable" id="table" cellspacing="0">'}
		$logName = "eventlog_" + $i + ".html"
		$logName = $logName.replace(" ","_")
		$bkup = Join-Path $path $logName
		$Report = $Report | Set-Content $bkup
	}
	#Also getting the hyper-v logs
	$rep = Get-WinEvent -FilterHashtable @{LogName="Microsoft-Windows-Hyper-V*"}
	$rep = $rep | ConvertTo-Html -Title "Hyper-V" -Head $HTMLHeader -As Table
 	$rep = $rep | ForEach-Object {$_ -replace "<body>", '<body id="body">'}
	$rep = $rep | ForEach-Object {$_ -replace "<table>", '<table class="sortable" id="table" cellspacing="0">'}
	$logName = "eventlog_hyperv.html"
	$bkup = Join-Path $path $logName
	$rep = $rep | Set-Content $bkup
}

function cleareventlog(){
	Get-Eventlog -list | ForEach-Object {
		Clear-Eventlog $_.LogDisplayName -ErrorAction SilentlyContinue
	}
}

function cherry_pick($commit) {
    $eapSet = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git cherry-pick $commit

    if ($LastExitCode) {
        echo "Ignoring failed git cherry-pick $commit"
        git checkout --force
    }
    $ErrorActionPreference = $eapSet
}

function log_message {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$message,
        [string]$location = 'console'
    )
    $formated_msg = "[$(Get-Date)] $message"
    if ($location -eq 'console') {
        Write-Host $formated_msg
    }
    else {
        $formated_msg >> $location
    }
}

function ensure_process_stopped {
    $ErrorActionPreference = "Stop"
    Param(
        [Parameter(Mandatory=$true)]
        [string]$procName,
        [switch]$changeState
    )
    if ($changeState) {
        Stop-Process -Name $procName -ErrorAction SilentlyContinue
    }
    if (Get-Process -Name $procName) {
        Throw "$procName still running on this host."
    }
}

function ensure_service {
    $ErrorActionPreference = "Stop"
    Param(
        [Parameter(Mandatory=$true)]
        [string]$serviceName,
        [string]$requestedState = "",
        [switch]$changeState = $true,
        [Int]$sleepTimeBeforeCheck = 0,
    )

    $service = get-service $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Throw "The $serviceName service is not registered"
    }

    if ($changeState) {
        if $(requestedState -eq "Stopped") {
            Stop-Service -Name $serviceName -Force
        }
        else if $(requestedState -eq "Running") {
            Start-Service -Name $serviceName
        }
    }

    if ($sleepTimeBeforeCheck -eq 0) {
        Start-Sleep -s $sleepTimeBeforeCheck
    }

    if ($requestedState -and ($requestedState -ne $service.Status)) {
        $msg =  "The $serviceName requested state ($requestedState) " +
                "does not match the current state ($service.Status)"
        Throw $msg
    }
}

function start_openstack_service {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$serviceName,
        [Parameter(Mandatory=$true)]
        [string]$configFile,
        [Parameter(Mandatory=$true)]
        [string]$logDir,
        [Parameter(Mandatory=$true)]
        [string]$exeFile
    )
    log_message "Starting $serviceName service"
    Try
    {
        ensure_service $serviceName -requestedState "Running" -sleepTimeBeforeCheck 30
    }
    Catch
    {
        log_message "Can not start the $serviceName service."
        log_message "Attempting to start $serviceName as a python process."
        Write-Host Start-Process -PassThru -RedirectStandardError "$logDir\process_error.txt" `
                  -RedirectStandardOutput "$logDir\process_output.txt" `
                  -FilePath $exeFile `
                  -ArgumentList "--config-file $configFile"
        log_message "Starting nova-compute as a python process." -location "$openstackLogs\nova-compute.log"
        Try
        {
            $proc =  Start-Process -PassThru -RedirectStandardError "$logDir\process_error.txt" `
                                   -RedirectStandardOutput "$logDir\process_output.txt" `
                                   -FilePath $exeFile `
                                   -ArgumentList "--config-file $configFile"
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
            Throw "Can not start the $serviceName service. The manual run failed as well."
        }
    }
}
