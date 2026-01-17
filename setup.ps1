[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Write-Warning "Run as Administrator required."
	Break
}

$ErrorActionPreference = "Continue"
Clear-Host

Write-Host ":: WINDOWS SETUP SCRIPT ::" -ForegroundColor Cyan

$repoBase = "https://raw.githubusercontent.com/LuckyOneDev/winsetup/main"
$profileUrl = "$repoBase/Microsoft.PowerShell_profile.ps1"
$terminalConfigUrl = "$repoBase/windows-terminal.json"

$logPath = "$HOME\Desktop\setup-log.txt"
$changesMade = $false

function Log {
	param([string]$Message, [string]$Type = "INFO")
	$timestamp = Get-Date -Format "HH:mm:ss"
	Add-Content -Path $logPath -Value "[$timestamp] [$Type] $Message" -ErrorAction SilentlyContinue

	switch ($Type) {
		"ACTION" { Write-Host $Message -ForegroundColor Green }
		"SKIP" { Write-Host $Message -ForegroundColor DarkGray }
		"WARNING" { Write-Host $Message -ForegroundColor Yellow }
		"ERROR" { Write-Host $Message -ForegroundColor Red }
		"INFO" { Write-Host $Message -ForegroundColor Cyan }
	}
}

$wingetApps = @(
	"Microsoft.WindowsTerminal",
	"Microsoft.PowerShell",
	"Microsoft.PowerToys",
	"DevToys-app.DevToys",
	"Docker.DockerDesktop",
	"Microsoft.DotNet.DesktopRuntime.8",
	"Microsoft.DotNet.DesktopRuntime.10",
	"Microsoft.VisualStudio.Community"
)

$scoopBuckets = @(
	"extras",
	"nerd-fonts",
	"versions"
)

$scoopApps = @(
	"curl",
	"sudo",
	"starship",
	"everything",
	"everythingtoolbar",
	"wiztree",
	"bulk-crap-uninstaller",
	"sharex",
	"neovim",
	"nvm",
	"pyenv",
	"python",
	"ffmpeg",
	"yt-dlp",
	"imagemagick",
	"JetBrainsMono-NF",
	"ungoogled-chromium",
	"bitwarden",
	"discord",
	"telegram"
)

$targetPath = Read-Host "Target Data Path (Where to install tools/repos) [Default: C:\Data]"
if ([string]::IsNullOrWhiteSpace($targetPath)) { $targetPath = "C:\Data" }
if ($targetPath.Length -gt 3 -and $targetPath.EndsWith("\")) {
	$targetPath = $targetPath.Substring(0, $targetPath.Length - 1)
}

$gitName = Read-Host "Git User Name (Optional - Press Enter to skip)"
$gitEmail = Read-Host "Git Email (Optional - Press Enter to skip)"

$runWin11Debloat = Read-Host "Run Win11Debloat script? (y/n)"
if ($runWin11Debloat.ToLower() -ne 'y') { $runWin11Debloat = 'n' }

$runMassgrave = Read-Host "Run Massgrave Activation script? (y/n)"
if ($runMassgrave.ToLower() -ne 'y') { $runMassgrave = 'n' }

Clear-Host
Write-Host "`n================= SETUP SUMMARY =================" -ForegroundColor Yellow
Write-Host ("Repository:".PadRight(24) + "$repoBase")
Write-Host ("Log File:".PadRight(24) + "$logPath")
Write-Host ("Target Path:".PadRight(24) + "$targetPath")
Write-Host ""
Write-Host "--- Winget Apps ---" -ForegroundColor Cyan
$wingetApps | ForEach-Object { Write-Host " - $_" }
Write-Host ""
Write-Host "--- Scoop Apps ---" -ForegroundColor Cyan
$scoopApps | ForEach-Object { Write-Host " - $_" }
Write-Host "==================================================" -ForegroundColor Yellow

$confirmation = Read-Host "`nProceed with setup? (y/n)"
if ($confirmation -ne 'y') {
	Write-Host "Setup cancelled by user." -ForegroundColor Red
	exit
}

if (!(Test-Path $targetPath)) {
	try {
		New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
		Write-Host "Created data directory: $targetPath" -ForegroundColor DarkGray
	}
	catch {
		Write-Warning "Could not create path $targetPath. Defaulting to C:\Data"
		$targetPath = "C:\Data"
		New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
	}
}
Log "Starting setup..."

if ($runWin11Debloat -eq 'y') {
	try {
		Log "Launching Win11Debloat..."
		Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iwr -useb https://debloat.raphi.re/ | iex`"" -Wait
		$changesMade = $true
	}
	catch { Log "Win11Debloat failed to start: $_" "ERROR" }
}

if ($runMassgrave -eq 'y') {
	try {
		Log "Launching Massgrave..."
		Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://get.activated.win | iex`"" -Wait
	}
	catch { Log "Massgrave Activation failed to start: $_" "ERROR" }
}

Log "Checking for Winget..."
if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
	Log "Winget not found. Winget apps will not be installed. Download winget from https://github.com/microsoft/winget-cli/releases/latest and run Add-AppxPackage"
	Pause
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
	Log "Installing Winget applications..."
	foreach ($app in $wingetApps) {
		try {
			Log "Installing $app..."
			winget install --id $app -e --source winget --accept-package-agreements --accept-source-agreements --silent
			$changesMade = $true
		}
		catch { Log "Winget failed for $app : $_" "ERROR" }
	}
}
else {
	Log "Winget not found. Skipping Winget apps." "WARNING"
}

Log "Setting up Scoop package manager..."
$scoopPath = "$targetPath\Scoop"
$scoopGlobal = "$targetPath\GlobalScoop"
[Environment]::SetEnvironmentVariable("SCOOP", $scoopPath, "User")
[Environment]::SetEnvironmentVariable("SCOOP_GLOBAL", $scoopGlobal, "Machine")
$env:SCOOP = $scoopPath
$env:SCOOP_GLOBAL = $scoopGlobal

if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
	try {
		Log "Installing Scoop..."
		Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
		Invoke-Expression (Invoke-RestMethod -Uri "https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1")
		$changesMade = $true
	}
	catch { Log "Scoop install failed: $_" "ERROR" }
}

if (Test-Path "$env:SCOOP\shims") {
	$env:Path += ";$env:SCOOP\shims"
}

if (Get-Command scoop -ErrorAction SilentlyContinue) {
	try {
		if (!(Get-Command git -ErrorAction SilentlyContinue)) { 
			Log "Installing Git (required for Scoop buckets)..."
			scoop install git | Out-Null 
			scoop install aria2 | Out-Null 
			scoop config aria2-warning-enabled false | Out-Null 
		}

		Log "Adding Scoop Buckets..."
		foreach ($b in $scoopBuckets) { 
			scoop bucket add $b | Out-Null 
		}
		scoop update | Out-Null
        
		Log "Installing Scoop Apps..."
		foreach ($app in $scoopApps) {
			Log "Installing $app..."
			$installOutput = scoop install $app -g 2>&1
			if ($LASTEXITCODE -eq 0) {
				Log "$app installed successfully." "ACTION"
				$changesMade = $true
			}
			else {
				if ($installOutput -match "already installed") {
					Log "$app is already installed." "SKIP"
				}
				else {
					Log "Scoop install FAILED for $app" "ERROR"
				}
			}
		}
	}
	catch { Log "Scoop package install error: $_" "ERROR" }
}

Log "Configuring Git..."
if ($gitName -and $gitEmail -and (Get-Command git -ErrorAction SilentlyContinue)) {
	git config --global user.name "$gitName"
	git config --global user.email "$gitEmail"
	git config --global core.autocrlf false
	git config --global init.defaultBranch main
	Log "Git configured." "ACTION"
}

Log "Checking Windows features..."
if ((Get-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM" -Online).State -ne "Enabled") {
	Log "Enabling Windows Sandbox..."
	Enable-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM" -All -Online -NoRestart
	$changesMade = $true
}
if (Get-Command wsl -ErrorAction SilentlyContinue) {
	if ((wsl --status 2>$null) -notmatch "Default Distribution") {
		Log "Installing WSL with Ubuntu..."
		wsl --install -d Ubuntu
		$changesMade = $true
	}
}

Log "Configuring Node Version Manager (NVM)..."

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

if (Get-Command nvm -ErrorAction SilentlyContinue) {
	try {
		Log "Installing Node LTS..."
		nvm install lts
		nvm use lts
		Log "Node setup complete." "ACTION"
		$changesMade = $true
	}
	catch {
		Log "Failed to configure NVM: $_" "ERROR"
	}
}
else {
	Log "NVM command not found. Skipping Node setup." "WARNING"
}

Log "Updating PowerShell profile from GitHub..."
try {
	$remoteProfile = Invoke-RestMethod -Uri $profileUrl -ErrorAction Stop
	if (!(Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force | Out-Null }
	$currentProfile = ""
	if (Test-Path $PROFILE) { $currentProfile = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue }

	if ($currentProfile -notmatch "GitHub winsetup profile") {
		Add-Content -Path $PROFILE -Value "`n# -- GitHub winsetup profile --`n$remoteProfile`n"
		Log "PowerShell profile updated from repository." "ACTION"
		$changesMade = $true
	}
	else {
		Log "Profile already up to date." "SKIP"
	}
}
catch { Log "Failed to fetch PowerShell profile: $_" "ERROR" }

Log "Configuring Windows Terminal..."
try {
	$terminalPackage = Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal*" -ErrorAction SilentlyContinue | Select-Object -First 1
    
	if ($terminalPackage) {
		$terminalSettingsPath = "$($terminalPackage.FullName)\LocalState\settings.json"
		Log "Downloading config from $terminalConfigUrl..."
		$terminalJsonContent = Invoke-RestMethod -Uri $terminalConfigUrl -ErrorAction Stop

		if (-not [string]::IsNullOrWhiteSpace($terminalJsonContent)) {
			Set-Content -Path $terminalSettingsPath -Value $terminalJsonContent -Force
			Log "Windows Terminal settings updated from repository." "ACTION"
			$changesMade = $true
		}
	}
	else {
		Log "Windows Terminal package directory not found. Skipping config." "WARNING"
	}
}
catch { Log "Failed to update Windows Terminal settings: $_" "ERROR" }

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Log file: $logPath"
if ($changesMade) { Write-Host "RESTART RECOMMENDED." -ForegroundColor Yellow }
Pause