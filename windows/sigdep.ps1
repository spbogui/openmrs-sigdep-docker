<#
  SIGDEP 3.x - outil de gestion pour les sites sous Windows
  ---------------------------------------------------------
  Usage :
    powershell -ExecutionPolicy Bypass -File windows\sigdep.ps1 <commande> [argument]

  Commandes :
    install [dump.zip]   premiere installation (.env, mots de passe, dump, demarrage)
    start                demarre SIGDEP
    stop                 arrete SIGDEP
    restart              redemarre OpenMRS
    status               etat des conteneurs
    logs [service]       journaux en direct (defaut : openmrs) - Ctrl+C pour quitter
    backup               sauvegarde immediate de la base (dossier backups\)
    list                 liste les sauvegardes
    restore <fichier>    restaure une sauvegarde (ECRASE la base)
    update <version>     passe a une autre version de l'image (ex. 3.0.1)
    prepare-db <dump>    prepare db\init\01-openmrs.sql.gz depuis un .zip/.sql/.sql.gz
    firewall             ouvre le port HTTP dans le pare-feu (administrateur)

  Remarque : fichier volontairement sans accents (compatibilite PowerShell 5.1).
#>
param(
  [Parameter(Position = 0)][string]$Command = 'help',
  [Parameter(Position = 1)][string]$Arg = ''
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot

# Chemin passe en argument : resolu AVANT de changer de dossier
if ($Arg -and (Test-Path -LiteralPath $Arg)) { $Arg = (Resolve-Path -LiteralPath $Arg).Path }
Set-Location -LiteralPath $Root
$EnvFile = Join-Path $Root '.env'

function Info($m) { Write-Host "[SIGDEP] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[SIGDEP] ATTENTION : $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[SIGDEP] ERREUR : $m" -ForegroundColor Red; exit 1 }

function Compose {
  & docker compose @args
  if ($LASTEXITCODE -ne 0) { Fail "echec de : docker compose $($args -join ' ')" }
}

# ------------------------------------------------------------------ Docker
function Test-Docker {
  & docker info *> $null
  return ($LASTEXITCODE -eq 0)
}

function Ensure-Docker {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail "Docker n'est pas installe. Voir README.md, section Windows."
  }
  if (Test-Docker) { return }
  $dd = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
  if (Test-Path -LiteralPath $dd) {
    Info 'Demarrage de Docker Desktop (1 a 3 minutes)...'
    Start-Process -FilePath $dd
  }
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 5
    if (Test-Docker) { Info 'Docker est pret.'; return }
  }
  Fail 'Docker ne repond pas. Demarrez Docker Desktop puis relancez la commande.'
}

# --------------------------------------------------------------------- .env
function Get-EnvValue($key, $default = '') {
  if (-not (Test-Path -LiteralPath $EnvFile)) { return $default }
  foreach ($l in [IO.File]::ReadAllLines($EnvFile)) {
    if ($l -match "^\s*$key\s*=(.*)$") { return $Matches[1].Trim() }
  }
  return $default
}

function Set-EnvValue($key, $value) {
  $lines = New-Object System.Collections.Generic.List[string]
  $found = $false
  if (Test-Path -LiteralPath $EnvFile) {
    foreach ($l in [IO.File]::ReadAllLines($EnvFile)) {
      if ($l -match "^\s*$key\s*=") { $lines.Add("$key=$value"); $found = $true }
      else { $lines.Add($l) }
    }
  }
  if (-not $found) { $lines.Add("$key=$value") }
  # UTF-8 sans BOM, lu correctement par docker compose
  [IO.File]::WriteAllLines($EnvFile, $lines)
}

function New-Password {
  $chars = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
  -join (1..24 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Get-Url {
  $port = Get-EnvValue 'HTTP_PORT' '80'
  if ($port -eq '80') { return 'http://localhost/openmrs/' }
  return "http://localhost:$port/openmrs/"
}

# ----------------------------------------------------------------- Dump SQL
function Prepare-Db($src) {
  if (-not $src -or -not (Test-Path -LiteralPath $src)) { Fail "fichier de dump introuvable : $src" }
  $initDir = Join-Path $Root 'db\init'
  New-Item -ItemType Directory -Force -Path $initDir | Out-Null
  $dest = Join-Path $initDir '01-openmrs.sql.gz'
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  Info "Preparation du dump : $src"

  if ($src -like '*.sql.gz') {
    Copy-Item -LiteralPath $src -Destination $dest -Force
  } else {
    $zip = $null; $in = $null
    if ($src -like '*.zip') {
      $zip = [IO.Compression.ZipFile]::OpenRead($src)
      $entry = $zip.Entries | Where-Object { $_.FullName -like '*.sql' -and $_.FullName -notlike '__MACOSX*' } | Select-Object -First 1
      if (-not $entry) { $zip.Dispose(); Fail 'aucun fichier .sql dans l''archive' }
      $in = $entry.Open()
    } elseif ($src -like '*.sql') {
      $in = [IO.File]::OpenRead($src)
    } else {
      Fail 'format non supporte (attendu : .zip, .sql ou .sql.gz)'
    }
    $out = [IO.File]::Create($dest)
    $gz = New-Object IO.Compression.GZipStream($out, [IO.Compression.CompressionMode]::Compress)
    try { $in.CopyTo($gz) } finally { $gz.Dispose(); $out.Dispose(); $in.Dispose(); if ($zip) { $zip.Dispose() } }
  }
  $mb = [math]::Round((Get-Item -LiteralPath $dest).Length / 1MB, 1)
  Info "db\init\01-openmrs.sql.gz pret ($mb Mo)"
}

# ---------------------------------------------------------------- Commandes
function Do-Start {
  Ensure-Docker
  if (-not (Test-Path -LiteralPath $EnvFile)) { Fail 'fichier .env absent : lancez d''abord "install".' }
  New-Item -ItemType Directory -Force -Path (Join-Path $Root 'backups') | Out-Null
  Info 'Demarrage des conteneurs...'
  Compose up -d
  Info "SIGDEP demarre. Adresse : $(Get-Url)"
  Info 'Le 1er demarrage (import de la base) peut prendre 15 a 30 minutes.'
  Info 'Suivre l''avancement : windows\journaux.bat'
}

function Do-Install {
  Ensure-Docker
  if (-not (Test-Path -LiteralPath $EnvFile)) {
    Copy-Item -LiteralPath (Join-Path $Root '.env.example') -Destination $EnvFile
    Set-EnvValue 'MYSQL_ROOT_PASSWORD' (New-Password)
    Set-EnvValue 'OPENMRS_DB_PASSWORD' (New-Password)
    Set-EnvValue 'OPENMRS_DATA_PATH' 'openmrs-data'
    Info '.env cree avec des mots de passe generes automatiquement.'
    Warn 'Conservez une copie du fichier .env en lieu sur (mots de passe de la base).'
  } else {
    Info '.env existant conserve.'
  }

  if ($Arg) { Prepare-Db $Arg }

  $dump = Get-ChildItem -Path (Join-Path $Root 'db\init') -Include '*.sql', '*.sql.gz' -Recurse -ErrorAction SilentlyContinue
  $volExists = (& docker volume ls -q --filter name=sigdep_db-data) -ne $null
  if (-not $dump -and -not $volExists) {
    Warn 'aucun dump dans db\init : la base OpenMRS sera VIDE.'
    $r = Read-Host 'Continuer quand meme ? (o/N)'
    if ($r -notmatch '^[oOyY]') { Fail 'installation annulee. Relancez avec : installer.bat <chemin\dump.zip>' }
  }

  Info 'Telechargement des images Docker (peut etre long)...'
  Compose pull
  Do-Start
}

function Do-Backup {
  Ensure-Docker
  Compose exec -T backup sigdep-backup now
  Compose exec -T backup sigdep-backup list
  Info "Fichiers dans : $(Join-Path $Root 'backups')"
}

function Do-Restore {
  Ensure-Docker
  if (-not $Arg) { Compose exec -T backup sigdep-backup list; Fail 'precisez le fichier : sigdep.ps1 restore <fichier>' }
  $backups = Join-Path $Root 'backups'
  $name = Split-Path -Leaf $Arg
  if ((Test-Path -LiteralPath $Arg) -and ((Split-Path -Parent $Arg) -ne $backups)) {
    Copy-Item -LiteralPath $Arg -Destination (Join-Path $backups $name) -Force
  }
  if (-not (Test-Path -LiteralPath (Join-Path $backups $name))) { Fail "sauvegarde introuvable : $name" }
  Warn "la base actuelle va etre REMPLACEE par $name."
  $r = Read-Host 'Tapez OUI pour confirmer'
  if ($r -ne 'OUI') { Fail 'restauration annulee.' }
  Compose stop openmrs
  Compose exec -T backup sigdep-backup restore $name
  Compose start openmrs
  Info 'Restauration terminee, OpenMRS redemarre.'
}

function Do-Update {
  Ensure-Docker
  if (-not $Arg) { Fail "precisez la version : sigdep.ps1 update 3.0.1 (actuelle : $(Get-EnvValue 'SIGDEP_VERSION'))" }
  Info "Passage de $(Get-EnvValue 'SIGDEP_VERSION') a $Arg"
  Set-EnvValue 'SIGDEP_VERSION' $Arg
  Compose pull openmrs
  Compose up -d openmrs
  Info 'Mise a jour lancee. Suivre : windows\journaux.bat'
}

function Do-Firewall {
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $admin) { Fail 'lancez cette commande en tant qu''administrateur (clic droit > Executer en tant qu''administrateur).' }
  $port = Get-EnvValue 'HTTP_PORT' '80'
  Get-NetFirewallRule -DisplayName 'SIGDEP HTTP' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName 'SIGDEP HTTP' -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Domain, Private | Out-Null
  Info "Port $port ouvert dans le pare-feu Windows (reseaux prives et domaine)."
}

switch ($Command.ToLower()) {
  'install'    { Do-Install }
  'start'      { Do-Start }
  'stop'       { Ensure-Docker; Compose stop; Info 'SIGDEP arrete.' }
  'restart'    { Ensure-Docker; Compose restart openmrs }
  'status'     { Ensure-Docker; Compose ps; Info "Adresse : $(Get-Url)" }
  'logs'       { Ensure-Docker; $svc = if ($Arg) { $Arg } else { 'openmrs' }; & docker compose logs -f --tail 200 $svc }
  'backup'     { Do-Backup }
  'list'       { Ensure-Docker; Compose exec -T backup sigdep-backup list }
  'restore'    { Do-Restore }
  'update'     { Do-Update }
  'prepare-db' { Prepare-Db $Arg }
  'firewall'   { Do-Firewall }
  default      { Get-Content -LiteralPath $PSCommandPath -TotalCount 21 | Select-Object -Skip 1 | Out-Host }
}
