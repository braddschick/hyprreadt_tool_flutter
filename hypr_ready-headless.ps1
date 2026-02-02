# 1. Gather User Inputs
$exePath = Read-Host "What is the path to HYPRReady.exe?"
$logPath = Read-Host "Where do you want the Log File to be created? [C:\Temp\hyprready.log]"
if ([string]::IsNullOrWhiteSpace($logPath)) { $logPath = "C:\Temp\hyprready.log" }

# Ensure the log directory exists
$logDir = Split-Path $logPath
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force }

$sslUrl = Read-Host "What URL should be used to test SSL Pinning? [https://show.gethypr.com]"
if ([string]::IsNullOrWhiteSpace($sslUrl)) { $sslUrl = "https://show.gethypr.com" }

# Ask for the boot delay
$delayInput = Read-Host "How many seconds of delay would you like after boot? (Enter 0 for no delay) [5]"
if ([string]::IsNullOrWhiteSpace($delayInput)) { $delayInput = 5 }

$testCert = Read-Host "Do you want to test a Certificate Template? (Y/N)"

$certTemplate = ""
$adcsServer = ""

if ($testCert -eq 'Y' -or $testCert -eq 'y') {
    $certTemplate = Read-Host "Ask for Cert Template Name? [hyprwin]"
    if ([string]::IsNullOrWhiteSpace($certTemplate)) { $certTemplate = "hyprwin" }
    
    $adcsServer = Read-Host "Ask for ADCS Server IP Address or FQDN?"
}

# 2. Create the JSON Configuration File
$configPath = Join-Path (Split-Path $exePath) "hyprready.json"
$configContent = @{
    targetUrl    = $sslUrl
    adcsServer   = $adcsServer
    certTemplate = $certTemplate
} | ConvertTo-Json

$configContent | Out-File -FilePath $configPath -Encoding utf8 -Force

Write-Host "`nConfig file created at: $configPath" -ForegroundColor Cyan

# 3. Create the Task Scheduler Entry
$taskName = "HYPRReady_Boot_Diagnostic"

# The Action: runs the exe with arguments
# Quotes around the log path are handled for paths with spaces
$arguments = "--headless --log-file `"$logPath`""
$action = New-ScheduledTaskAction -Execute $exePath -Argument $arguments

# The Trigger: AtStartup
$trigger = New-ScheduledTaskTrigger -AtStartup

# Apply delay logic
if ([int]$delayInput -gt 0) {
    $trigger.Delay = "PT$($delayInput)S"
    $msgDelay = "with a $delayInput second delay"
} else {
    $msgDelay = "with no delay"
}

# The Principal: Runs as SYSTEM
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Register the task
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force

Write-Host "Success! Task '$taskName' registered to run at machine boot $msgDelay." -ForegroundColor Green
Write-Host "Arguments set: $arguments" -ForegroundColor Gray