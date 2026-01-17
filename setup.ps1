[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Write-Warning "Run as Administrator required."
	Break
}

$ErrorActionPreference = "Continue"
Clear-Host

Write-Host ":: CONFIGURATION ::" -ForegroundColor Cyan

Write-Host "Checking internet connection..." -NoNewline
try {
	$ping = Test-Connection -ComputerName google.com -Count 1 -Quiet -ErrorAction Stop
	if ($ping) { Write-Host " [OK]" -ForegroundColor Green }
}
catch {
	Write-Host " [FAIL]" -ForegroundColor Red
	Write-Warning "No internet detected."
}

$targetPath = Read-Host "Target Data Path (Where to install tools/repos) [Default: C:\Data]"
if ([string]::IsNullOrWhiteSpace($targetPath)) { $targetPath = "C:\Data" }
if ($targetPath.Length -gt 3 -and $targetPath.EndsWith("\")) {
	$targetPath = $targetPath.Substring(0, $targetPath.Length - 1)
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

$gitName = Read-Host "Git User Name (Optional - Press Enter to skip)"
$gitEmail = Read-Host "Git Email (Optional - Press Enter to skip)"
$manifestPathInput = Read-Host "Manifest Path (URL or Local Path) [Default: .\setup.json]"
if ([string]::IsNullOrWhiteSpace($manifestPathInput)) { $manifestPathInput = ".\setup.json" }
$profilePathInput = Read-Host "Custom PowerShell Profile (URL or Local Path) [Optional - Press Enter to skip]"
$runDebloat = Read-Host "Run Win11Debloat? (y/n)"
$runMas = Read-Host "Run Massgrave Activation? (y/n)"

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

Log "Loading setup configuration..."
try {
	if ($manifestPathInput -match "^https?://") {
		Log "Loading manifest from $manifestPathInput"
		$manifest = Invoke-RestMethod -Uri $manifestPathInput -ErrorAction Stop
	}
	else {
		$resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($manifestPathInput)
		Log "Reading local manifest: $resolvedPath"
		if (Test-Path $resolvedPath) {
			$rawJson = Get-Content -Path $resolvedPath -Raw -ErrorAction Stop
			$manifest = $rawJson | ConvertFrom-Json
		}
		else { throw "File not found at $resolvedPath" }
	}
	Log "Manifest loaded successfully." "ACTION"
	$wingetApps = $manifest.winget
	$scoopBuckets = $manifest.scoop.buckets
	$scoopApps = $manifest.scoop.apps
}
catch {
	Log "Failed to load manifest: $_" "ERROR"
	Break
}

Log "Target Path: $targetPath"
Log "Loaded $($scoopApps.Count) Scoop apps from config."
Log "Starting setup..."

if ($runDebloat -eq 'y') {
	try {
		Log "Running Windows Debloat..."
		& ([scriptblock]::Create((Invoke-RestMethod "https://debloat.raphi.re/" -ErrorAction Stop))) -RunDefaults -TaskbarAlign Left
		$changesMade = $true
	}
	catch { Log "Debloat failed: $_" "ERROR" }
}

if ($runMas -eq 'y') {
	try {
		Log "Running activation script..."
		Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://get.activated.win | iex`"" -Wait
	}
	catch { Log "Activation failed: $_" "ERROR" }
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
		Log "Installing Scoop apps..."
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

Log "Updating PowerShell profile..."
if (!(Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force | Out-Null }

$customProfile = ""
if (-not [string]::IsNullOrWhiteSpace($profilePathInput)) {
	try {
		if ($profilePathInput -match "^https?://") {
			Log "Fetching profile from URL: $profilePathInput"
			$customProfile = Invoke-RestMethod -Uri $profilePathInput -ErrorAction Stop
		}
		else {
			$resolvedProfilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($profilePathInput)
			Log "Reading local profile: $resolvedProfilePath"
			if (Test-Path $resolvedProfilePath) {
				$customProfile = Get-Content -Path $resolvedProfilePath -Raw -ErrorAction Stop
			}
			else { throw "Profile file not found at $resolvedProfilePath" }
		}
		Log "Loaded custom profile content." "ACTION"
	}
	catch { Log "Failed to load custom profile: $_" "ERROR" }
}

$currentProfileContent = ""
if (Test-Path $PROFILE) {
	$currentProfileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
}

if (-not [string]::IsNullOrWhiteSpace($customProfile)) {
	if ($currentProfileContent -notmatch [Regex]::Escape($customProfile)) {
		Add-Content -Path $PROFILE -Value "`n# -- custom profile import --`n$customProfile`n"
		$changesMade = $true
		Log "Applied custom PowerShell profile."
	}
 else {
		Log "Custom profile already present." "SKIP"
	}
}
else {
	if ($currentProfileContent -notmatch "setup-config") {
		Add-Content -Path $PROFILE -Value "`n# -- setup-config --`nInvoke-Expression (&starship init powershell)`nSet-PSReadLineOption -PredictionViewStyle ListView`nSet-Location `"$targetPath`""
		Log "Added default profile settings." "ACTION"
		$changesMade = $true
	}
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Log file: $logPath"
if ($changesMade) { Write-Host "RESTART RECOMMENDED." -ForegroundColor Yellow }
Pause