#=============================================================================
# make_server_ini.ps1 - builds System\UT2004SkaarjInfection.ini from the
# proven UT2004MFC.ini server template and swaps the MFC gametype for
# SkaarjInfectionV1.
#
# Usage: powershell -ExecutionPolicy Bypass -File .\make_server_ini.ps1
#
# Outputs:
#   System\UT2004SkaarjInfection.ini - server ini for RunServerSkaarjInfection.bat
#=============================================================================
$ErrorActionPreference = "Stop"
$g = "C:\Program Files (x86)\Steam\steamapps\common\Unreal Tournament 2004"
$src = "$g\System\UT2004MFC.ini"
$dst = "$g\System\UT2004SkaarjInfection.ini"
$projIni = "$g\SkaarjInfectionV1\SkaarjInfectionV1.ini"

if (-not (Test-Path $src)) { Write-Error "Template missing: $src"; exit 1 }
if (-not (Test-Path $projIni)) { Write-Error "Project ini missing: $projIni"; exit 1 }

$lines = [System.Collections.Generic.List[string]](Get-Content $src)

#--- 1. swap gametype references -------------------------------------------
for ($i = 0; $i -lt $lines.Count; $i++)
{
    $l = $lines[$i]
    if ($l -eq "ServerPackages=MonsterFightClubV1")
        { $lines[$i] = "ServerPackages=SkaarjInfectionV1" }
    elseif ($l -eq "EditPackages=MonsterFightClubV1")
        { $lines[$i] = "EditPackages=SkaarjInfectionV1" }
    elseif ($l -match '^Games=\(GameType="MonsterFightClubV1')
        { $lines[$i] = 'Games=(GameType="SkaarjInfectionV1.SkaarjInfectionGame",ActiveMaplist="Default INF")' }
    elseif ($l -match '^GameConfig=\(GameClass="MonsterFightClubV1')
        { $lines[$i] = 'GameConfig=(GameClass="SkaarjInfectionV1.SkaarjInfectionGame",Prefix="DM",Acronym="INF",GameName="Skaarj Infection",Mutators=,Options=)' }
}

#--- 2. replace the MFC map list + maplist record blocks -------------------
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++)
{
    if ($lines[$i] -match '^\[MonsterFightClubV1\.MapListMonsterFightClub\]') { $start = $i; break }
}
if ($start -ge 0)
{
    $end = $start + 1
    while ($end -lt $lines.Count -and $lines[$end] -notmatch '^\[MonsterFightClubV1\.MonsterFightClubGame\]')
        { $end++ }

    $maps = @('DM-1on1-Albatross','DM-1on1-Crash','DM-1on1-Desolation','DM-1on1-Idoma',
              'DM-1on1-Irondust','DM-1on1-Mixer','DM-1on1-Roughinery','DM-1on1-Serpentine',
              'DM-1on1-Spirit','DM-1on1-Squader','DM-1on1-Trite','DM-Antalus',
              'DM-Asbestos','DM-BP2-Calandras','DM-DesertIsle','DM-Rankin')
    $block = [System.Collections.Generic.List[string]]@('[SkaarjInfectionV1.MapListSkaarjInfection]', 'MapNum=0')
    foreach ($m in $maps) { $block.Add("Maps=$m") }
    $block.Add('[Default INF MaplistRecord]')
    $block.Add('DefaultTitle=Default INF')
    $block.Add('DefaultGameType=SkaarjInfectionV1.SkaarjInfectionGame')
    $block.Add('DefaultActive=0')
    foreach ($m in $maps) { $block.Add("DefaultMaps=$m") }

    $lines.RemoveRange($start, $end - $start)
    $lines.InsertRange($start, $block)
}

#--- 3. replace the game config sections ------------------------------------
$cfgStart = -1
for ($i = 0; $i -lt $lines.Count; $i++)
{
    if ($lines[$i] -match '^\[MonsterFightClubV1\.MonsterFightClubGame\]') { $cfgStart = $i; break }
}
if ($cfgStart -ge 0)
{
    $lines.RemoveRange($cfgStart, $lines.Count - $cfgStart)

    $cfg = Get-Content $projIni
    $cfgLines = [System.Collections.Generic.List[string]]@('[SkaarjInfectionV1.SkaarjInfectionGame]')
    for ($i = 1; $i -lt $cfg.Count; $i++)
    {
        if ($cfg[$i] -match '^\[') { break }
        $cfgLines.Add($cfg[$i])
    }
    $lines.InsertRange($cfgStart, $cfgLines)
}

#--- 4. [Engine.GameInfo] - endless (TimeLimit=0) ---------------------------
$inGameInfo = -1
for ($i = 0; $i -lt $lines.Count; $i++)
{
    if ($lines[$i] -eq "[Engine.GameInfo]") { $inGameInfo = $i; break }
}
if ($inGameInfo -ge 0)
{
    for ($i = $inGameInfo + 1; $i -lt $lines.Count -and $lines[$i] -notmatch '^\['; $i++)
    {
        if ($lines[$i] -match '^TimeLimit=')  { $lines[$i] = "TimeLimit=0"; continue }
        if ($lines[$i] -match '^MaxPlayers=') { $lines[$i] = "MaxPlayers=32"; continue }
        if ($lines[$i] -match '^MaxSpectators=') { $lines[$i] = "MaxSpectators=32"; continue }
    }
}

#--- 5. Server name + redact secrets -----------------------------------------
for ($i = 0; $i -lt $lines.Count; $i++)
{
    if ($lines[$i] -match '^ServerName=')
        { $lines[$i] = "ServerName=Skaarj Infection (Test)" }
    elseif ($lines[$i] -match '^AdminPassword=')
        { $lines[$i] = "AdminPassword=CHANGE_ME" }
    elseif ($lines[$i] -match '^GamePassword=')
        { $lines[$i] = "GamePassword=CHANGE_ME" }
    elseif ($lines[$i] -match '^SavedPasswords=')
        { $lines[$i] = "SavedPasswords=" }
}

Set-Content -Path $dst -Value $lines -Encoding ASCII
Write-Host "Wrote $dst ($($lines.Count) lines)"
