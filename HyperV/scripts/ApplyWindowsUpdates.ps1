$scriptLocation = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
. "$scriptLocation\utils.ps1"


$UpdateSession = New-Object -Com Microsoft.Update.Session
$UpdateSearcher = $UpdateSession.CreateUpdateSearcher()

$SearchResult = $UpdateSearcher.Search("IsInstalled=0 and Type='Software'")

log_message "List of applicable items on the machine:"
For ($X = 0; $X -lt $SearchResult.Updates.Count; $X++){
    $Update = $SearchResult.Updates.Item($X)
    log_message( ($X + 1).ToString() + "&gt; " + $Update.Title)
}
 
If ($SearchResult.Updates.Count -eq 0) {
    log_message "There are no applicable updates."
    Exit 0
}

$UpdatesToDownload = New-Object -Com Microsoft.Update.UpdateColl

For ($X = 0; $X -lt $SearchResult.Updates.Count; $X++){
    $Update = $SearchResult.Updates.Item($X)
    #Write-Host( ($X + 1).ToString() + "&gt; Adding: " + $Update.Title)
    $Null = $UpdatesToDownload.Add($Update)
}

log_message "Downloading Updates..."

$Downloader = $UpdateSession.CreateUpdateDownloader()
$Downloader.Updates = $UpdatesToDownload
$Null = $Downloader.Download()

$UpdatesToInstall = New-Object -Com Microsoft.Update.UpdateColl

For ($X = 0; $X -lt $SearchResult.Updates.Count; $X++){
    $Update = $SearchResult.Updates.Item($X)
    If ($Update.IsDownloaded) {
        log_message( ($X + 1).ToString() + "&gt; " + $Update.Title)
        $Null = $UpdatesToInstall.Add($Update)        
    }
}

log_message "Installing Updates..."
$Installer = $UpdateSession.CreateUpdateInstaller()
$Installer.Updates = $UpdatesToInstall

$InstallationResult = $Installer.Install()

For ($X = 0; $X -lt $UpdatesToInstall.Count; $X++){
    log_message($UpdatesToInstall.Item($X).Title + ": " + $InstallationResult.GetUpdateResult($X).ResultCode)
}

log_message("Installation Result: " + $InstallationResult.ResultCode)
log_message("    Reboot Required: " + $InstallationResult.RebootRequired)

If ($InstallationResult.RebootRequired -eq $True){
    Start-Sleep -s 10
    (Get-WMIObject -Class Win32_OperatingSystem).Reboot()
}
