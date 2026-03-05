<powershell>
# --- GitLab Runner & Flutter Windows Dependencies Bootstrap ---
# Download and install required dependencies for Flutter Windows builds

$LogFile = "C:\terraform_bootstrap.log"

function Write-Log($Message) {
    echo $Message | Out-File -Append -FilePath $LogFile
}

Write-Log "Starting Bootstrap..."

# 1. Install Choco
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
Write-Log "Chocolatey installed."

# 2. Install Git and VS Build Tools (Required for Flutter Windows builds)
choco install git -y
choco install visualstudio2022buildtools -y
choco install visualstudio2022-workload-vctools --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --includeOptional" -y
Write-Log "Git and Build Tools installed."

# 3. Install Flutter
Write-Log "Downloading Flutter SDK..."
$FlutterZipUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.0-stable.zip" # Using a stable version, update as needed
$FlutterZipPath = "C:\flutter_sdk.zip"
$ExpectedFlutterHash = "3235bba436fc79261aae8d14fe810f6eacb6dfcce8e0df6ab5dcad3eec77e1bf" # SHA256 for 3.24.0 Windows

Invoke-WebRequest -Uri $FlutterZipUrl -OutFile $FlutterZipPath

Write-Log "Verifying Flutter SDK hash..."
$FlutterHash = (Get-FileHash $FlutterZipPath -Algorithm SHA256).Hash
if ($FlutterHash -ne $ExpectedFlutterHash) {
    Write-Log "ERROR: Flutter SDK hash mismatch! Expected $ExpectedFlutterHash but got $FlutterHash"
    exit 1
}

Expand-Archive -Path $FlutterZipPath -DestinationPath "C:\src"
Remove-Item -Path $FlutterZipPath
[System.Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\src\flutter\bin", [System.EnvironmentVariableTarget]::Machine)
# You may also need to run flutter doctor --android-licenses etc, but that usually requires manual input. For purely windows desktop builds it shouldn't be strictly necessary but good to check.
Write-Log "Flutter SDK installed."

# 4. Install and Configure GitLab Runner
Write-Log "Downloading GitLab Runner..."
New-Item -Path 'C:\GitLab-Runner' -ItemType Directory
$RunnerUrl = "https://gitlab-runner-downloads.s3.amazonaws.com/v17.3.1/binaries/gitlab-runner-windows-amd64.exe"
$RunnerPath = "C:\GitLab-Runner\gitlab-runner.exe"
$ExpectedRunnerHash = "9db88b0a9ebd69a3182b81d4b68c5b0577ceb83e35ba7b30f4cfd762040b2a8d" # v17.3.1 Windows AMD64

Invoke-WebRequest -Uri $RunnerUrl -OutFile $RunnerPath

Write-Log "Verifying GitLab Runner hash..."
$RunnerHash = (Get-FileHash $RunnerPath -Algorithm SHA256).Hash
if ($RunnerHash -ne $ExpectedRunnerHash) {
    Write-Log "ERROR: GitLab Runner hash mismatch! Expected $ExpectedRunnerHash but got $RunnerHash"
    exit 1
}

Write-Log "Registering GitLab Runner..."
C:\GitLab-Runner\gitlab-runner.exe register `
  --non-interactive `
  --url "${gitlab_url}" `
  --token "${runner_token}" `
  --executor "shell" `
  --description "Terraform Windows Builder" `
  --tag-list "windows-builder,flutter,windows" `
  --run-untagged="false"

Write-Log "Installing and starting GitLab Runner service..."
C:\GitLab-Runner\gitlab-runner.exe install
C:\GitLab-Runner\gitlab-runner.exe start

Write-Log "Bootstrap Complete."
</powershell>
