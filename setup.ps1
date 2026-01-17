[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Write-Warning "Run as Administrator required."
	Break
}

$ErrorActionPreference = "Continue"
Clear-Host

Write-Host ":: WINDOWS SETUP SCRIPT ::" -ForegroundColor Cyan

# --- Constants / Repo URLs ---
$repoBase = "https://raw.githubusercontent.com/LuckyOneDev/winsetup/main"
$manifestUrl = "$repoBase/manifest.json"
$profileUrl = "$repoBase/Microsoft.PowerShell_profile.ps1"

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

# --- Load Manifest Early ---
Log "Fetching manifest from $manifestUrl"

try {
	$manifest = Invoke-RestMethod -Uri $manifestUrl -ErrorAction Stop
	Log "Manifest loaded successfully." "ACTION"
}
catch {
	Log "Failed to retrieve manifest: $_" "ERROR"
	Break
}

$wingetApps = $manifest.winget
$scoopBuckets = $manifest.scoop.buckets
$scoopApps = $manifest.scoop.apps

# --- Ask for user inputs ---
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

# --- Display Summary Before Execution ---
Clear-Host
Write-Host "`n================= SETUP SUMMARY =================" -ForegroundColor Yellow
Write-Host ("Repository:".PadRight(24) + "$repoBase")
Write-Host ("Manifest:".PadRight(24) + "$manifestUrl")
Write-Host ("Profile:".PadRight(24) + "$profileUrl")
Write-Host ("Log File:".PadRight(24) + "$logPath")
Write-Host ""
Write-Host ("Target Path:".PadRight(24) + "$targetPath")
Write-Host ("Git Name:".PadRight(24) + "$gitName")
Write-Host ("Git Email:".PadRight(24) + "$gitEmail")
Write-Host ("Run Win11Debloat:".PadRight(24) + "$runWin11Debloat")
Write-Host ("Run Massgrave Activation:".PadRight(24) + "$runMassgrave")
Write-Host ""
Write-Host "--- Manifest Data ---" -ForegroundColor Cyan
Write-Host ("Winget Apps:".PadRight(24) + ($wingetApps -join ', '))
Write-Host ("Scoop Buckets:".PadRight(24) + ($scoopBuckets -join ', '))
Write-Host ("Scoop Apps:".PadRight(24) + ($scoopApps -join ', '))
Write-Host "==================================================" -ForegroundColor Yellow

$confirmation = Read-Host "`nProceed with setup? (y/n)"
if ($confirmation -ne 'y') {
	Write-Host "Setup cancelled by user." -ForegroundColor Red
	exit
}

# --- Begin Executing ---
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
Log "Target Path: $targetPath"
Log "Starting setup..."

if ($runWin11Debloat -eq 'y') {
	try {
		Log "Running Win11Debloat..."
		& ([scriptblock]::Create((Invoke-RestMethod "https://debloat.raphi.re/" -ErrorAction Stop))) -RunDefaults -TaskbarAlign Left
		$changesMade = $true
	}
	catch { Log "Win11Debloat failed: $_" "ERROR" }
}

if ($runMassgrave -eq 'y') {
	try {
		Log "Running Massgrave Activation..."
		Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://get.activated.win | iex`"" -Wait
	}
	catch { Log "Massgrave Activation failed: $_" "ERROR" }
}

Log "Installing Winget applications..."
if (Get-Command winget -ErrorAction SilentlyContinue) {
	foreach ($app in $wingetApps) {
		try {
			if (winget list -e --id $app 2>$null) {
				Log "Already installed: $app" "SKIP"
			}
			else {
				Log "Installing $app..."
				winget install --id $app -e --source winget --accept-package-agreements --accept-source-agreements --silent
				$changesMade = $true
			}
		}
		catch { Log "Winget failed for $app : $_" "ERROR" }
	}
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

if (Test-Path "$env:SCOOP\shims\scoop.ps1") {
	$env:Path += ";$env:SCOOP\shims"
	try {
		if (!(Get-Command git -ErrorAction SilentlyContinue)) { scoop install git | Out-Null }
		foreach ($b in $scoopBuckets) { scoop bucket add $b | Out-Null }
		scoop update | Out-Null
		Log "Installing Scoop Apps..."
		scoop install $scoopApps
		$changesMade = $true
	}
	catch { Log "Scoop package install error: $_" "ERROR" }
}

Log "Configuring languages..."
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
if (Get-Command nvm -ErrorAction SilentlyContinue) {
	if ((nvm list 2>&1) -notmatch "Currently using") {
		Log "Installing Node LTS..."
		nvm install lts; nvm use lts
		$changesMade = $true
	}
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

Log "Updating PowerShell profile from GitHub..."
try {
	$remoteProfile = Invoke-RestMethod -Uri $profileUrl -ErrorAction Stop
	if (!(Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force | Out-Null }
	$currentProfile = ""
	if (Test-Path $PROFILE) { $currentProfile = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue }

	if ($currentProfile -notmatch [Regex]::Escape($remoteProfile)) {
		Add-Content -Path $PROFILE -Value "`n# -- GitHub winsetup profile --`n$remoteProfile`n"
		Log "PowerShell profile updated from repository." "ACTION"
		$changesMade = $true
	}
	else {
		Log "Profile already up to date." "SKIP"
	}
}
catch { Log "Failed to fetch PowerShell profile: $_" "ERROR" }

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Log file: $logPath"
if ($changesMade) { Write-Host "RESTART RECOMMENDED." -ForegroundColor Yellow }
Pause