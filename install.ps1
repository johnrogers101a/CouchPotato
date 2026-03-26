# install.ps1 — PowerShell 5.1+ installer for CouchPotato WoW addons
# Installs all addons in this repo into the user's WoW Retail Interface\AddOns folder.
# Performs a CLEAN install: removes the destination addon directory before
# copying, so stale files from previously-installed-but-now-removed addons
# cannot persist and cause load failures.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

#region --- Config ---

# All source addon folders are resolved relative to the script's own location
# so the script works regardless of the caller's working directory.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$AddonNames = @(
    'CouchPotato',
    'ControllerCompanion',
    'ControllerCompanion_Loader',
    'InfoPanels'
)

#endregion

#region --- WoW Retail path discovery ---

function Find-WoWAddOnsPath {
    # 1. Try the Windows Registry — Blizzard writes the install root here.
    $RegistryKeys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
        'HKCU:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
        'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft'
    )

    foreach ($RegKey in $RegistryKeys) {
        try {
            if (Test-Path $RegKey) {
                $InstallPath = (Get-ItemProperty -LiteralPath $RegKey -ErrorAction Stop).InstallPath
                if ($InstallPath) {
                    # InstallPath may already end with _retail_; normalise either way.
                    if ($InstallPath -notmatch '[/\\]_retail_[/\\]?$') {
                        $InstallPath = Join-Path $InstallPath '_retail_'
                    }
                    $Candidate = Join-Path $InstallPath 'Interface\AddOns'
                    if (Test-Path -LiteralPath $Candidate -PathType Container) {
                        return $Candidate
                    }
                }
            }
        } catch {
            # Registry read failed — fall through to next key / standard paths.
        }
    }

    # 2. Probe well-known install locations.
    $FallbackPaths = @(
        'C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns',
        'C:\Program Files\World of Warcraft\_retail_\Interface\AddOns',
        'D:\World of Warcraft\_retail_\Interface\AddOns',
        'D:\Games\World of Warcraft\_retail_\Interface\AddOns',
        'C:\Games\World of Warcraft\_retail_\Interface\AddOns'
    )

    foreach ($Path in $FallbackPaths) {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            return $Path
        }
    }

    # 3. Filesystem search — enumerate fixed drives and look for _retail_ folders.
    $FixedDrives = Get-PSDrive -PSProvider FileSystem |
        Where-Object { $_.Root -and (Test-Path -LiteralPath $_.Root) }

    foreach ($Drive in $FixedDrives) {
        $RetailDirs = Get-ChildItem -LiteralPath $Drive.Root -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '_retail_' }
        foreach ($RetailDir in $RetailDirs) {
            $Candidate = Join-Path $RetailDir.FullName 'Interface\AddOns'
            if (Test-Path -LiteralPath $Candidate -PathType Container) {
                return $Candidate
            }
        }
    }

    # 4. Could not auto-detect — return $null so the caller can prompt.
    return $null
}

$AddOnsPath = Find-WoWAddOnsPath

if (-not $AddOnsPath) {
    Write-Host "Could not auto-detect your WoW Retail AddOns folder." -ForegroundColor Yellow
    Write-Host "Please enter the full path to your WoW _retail_ folder" `
               "(e.g. C:\Program Files (x86)\World of Warcraft\_retail_):"

    # Re-prompt until the user supplies a path that contains Interface\AddOns.
    while ($true) {
        $UserPath = (Read-Host "WoW _retail_ path").Trim().Trim('"')

        if (-not (Test-Path -LiteralPath $UserPath -PathType Container)) {
            Write-Host "Error: The path '$UserPath' does not exist. Please try again." -ForegroundColor Red
            continue
        }

        $Candidate = Join-Path $UserPath 'Interface\AddOns'
        if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) {
            Write-Host "Error: '$Candidate' does not exist. " `
                       "Make sure you entered the '_retail_' folder that already has Interface\AddOns." `
                       -ForegroundColor Red
            continue
        }

        $AddOnsPath = $Candidate
        break
    }
}

#endregion

#region --- Destination write-access check ---

# Validate writability by touching a temporary probe file.
$ProbeFile = Join-Path $AddOnsPath ([System.IO.Path]::GetRandomFileName())
try {
    [System.IO.File]::WriteAllText($ProbeFile, '')
    Remove-Item -LiteralPath $ProbeFile -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Error: The directory '$AddOnsPath' is not writable." `
               "Please run PowerShell as Administrator or check folder permissions." `
               -ForegroundColor Red
    exit 1
}

#endregion

#region --- Copy addons ---

$Installed = @()

foreach ($AddonName in $AddonNames) {
    $SourcePath = Join-Path $ScriptDir $AddonName

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        Write-Host "Warning: Source folder './$AddonName' not found — skipping." -ForegroundColor Yellow
        continue
    }

    $DestPath = Join-Path $AddOnsPath $AddonName

    # Clean remove the destination first so no stale files survive a rename/move.
    if (Test-Path -LiteralPath $DestPath -PathType Container) {
        Remove-Item -LiteralPath $DestPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Installing $AddonName ..." -ForegroundColor Cyan
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $AddOnsPath -Recurse -Force -ErrorAction Stop
        $Installed += $AddonName
    } catch [System.UnauthorizedAccessException] {
        Write-Host "Error: Permission denied while copying $AddonName." `
                   "Please run PowerShell as Administrator or check folder permissions." `
                   -ForegroundColor Red
        exit 1
    } catch {
        Write-Host "Error: Failed to copy ${AddonName}: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

#endregion

#region --- Remove stale suite addons no longer in source ---

# Any addon directory matching our naming patterns that is NOT in $AddonNames
# is a leftover from a previous layout and must be removed.
$SuitePatterns = @('CouchPotato*', 'ControllerCompanion*', 'InfoPanels*', 'DelveCompanion*', 'DelversJourney*', 'StatPriority*')
foreach ($Pattern in $SuitePatterns) {
    $Matches = Get-ChildItem -LiteralPath $AddOnsPath -Directory -Filter $Pattern -ErrorAction SilentlyContinue
    foreach ($Dir in $Matches) {
        if ($AddonNames -notcontains $Dir.Name) {
            Write-Host "Removing stale addon: $($Dir.Name)" -ForegroundColor Yellow
            Remove-Item -LiteralPath $Dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion

#region --- Success summary ---

Write-Host ""
if ($Installed.Count -gt 0) {
    Write-Host "Installation complete! Addons installed to:" -ForegroundColor Green
    Write-Host "  $AddOnsPath" -ForegroundColor Green
    Write-Host ""
    foreach ($AddonName in $Installed) {
        Write-Host "  [OK] $AddonName" -ForegroundColor Green
    }
} else {
    Write-Host "No addons were installed (all source folders were missing)." -ForegroundColor Yellow
}
Write-Host ""

#endregion
