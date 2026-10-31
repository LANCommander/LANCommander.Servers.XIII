#Requires -Modules Logging

# Create the server ini (XIII_INI, default System/Server.ini) from the game's XIII.ini on first
# start, then write the XIII_* engine settings into it. It's created through the merged view, so it
# lands in Overlay/ and can be edited there. Game rules (map, mode, limits, name, passwords) are
# passed on the UCC command line by xiii-server, not stored here.

$system   = Join-Path $Env:SERVER_ROOT 'System'
$template = Join-Path $system 'XIII.ini'
$ini      = Join-Path $system $Env:XIII_INI

if (-not (Test-Path -Path $ini)) {
    if (-not (Test-Path -Path $template)) {
        Write-Log -Level Error "$template not found; skipping server configuration"
        return
    }

    Copy-Item -Path $template -Destination $ini
    Write-Log "Created $ini from XIII.ini"
}

$text    = [System.IO.File]::ReadAllText($ini)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines   = [System.Collections.Generic.List[string]]::new([string[]]($text -split "\r?\n"))

# Set Key=Value in [Section], replacing the first existing Key= line or appending to the section
function Set-IniValue([string] $Section, [string] $Key, [string] $Value) {
    $start = $lines.IndexOf("[$Section]")
    if ($start -lt 0) {
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
        return
    }

    $end = $start + 1
    while ($end -lt $lines.Count -and -not $lines[$end].StartsWith('[')) { $end++ }

    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($lines[$i] -like "$Key=*") {
            $lines[$i] = "$Key=$Value"
            return
        }
    }

    # Insert after the section's last non-blank line
    $at = $end
    while ($at -gt $start + 1 -and [string]::IsNullOrWhiteSpace($lines[$at - 1])) { $at-- }
    $lines.Insert($at, "$Key=$Value")
}

if ($Env:XIII_PORT) { Set-IniValue 'URL' 'Port' $Env:XIII_PORT }

# Ubi.com's master server is gone, so by default drop the uplink server actors (they only fail
# DNS/login)
if ($Env:XIII_MASTER_SERVER_UPLINK -notin @('true', '1', 'yes')) {
    $removed = $lines.RemoveAll({ param($l) $l -match '^;?ServerActors=IpDrv(Plus)?\.(MasterServerUplink|RegisterServerToUbiCom)' })
    if ($removed) { Write-Log "Removed $removed master server uplink(s) from $Env:XIII_INI" }
}

[System.IO.File]::WriteAllText($ini, ($lines -join $newline))
chown "$($Env:UID):$($Env:GID)" $ini

Write-Log "Applied XIII_* settings to $ini"
