# Спільні функції для скриптів Windows.
# Ці скрипти запускаються файлами *.bat з папки Windows — запускати їх напряму не потрібно.

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$EnvFile     = Join-Path $ProjectRoot '.env'
$EnvExample  = Join-Path $ProjectRoot '.env.example'
$BackupDir   = Join-Path $env:USERPROFILE '.n8n-twenty'
$BackupEnv   = Join-Path $BackupDir 'env-backup'
$Utf8NoBom   = New-Object System.Text.UTF8Encoding $false

# Сервіси, які запускаються завжди (ngrok — окремо, лише якщо налаштований).
$CoreServices = @('postgres', 'redis', 'twenty', 'twenty-worker', 'n8n', 'n8n-runner')
# Паролі та ключі, які генеруються автоматично: назва -> довжина в байтах.
$GeneratedSecrets = [ordered]@{
    'POSTGRES_PASSWORD'      = 24
    'N8N_DB_PASSWORD'        = 24
    'N8N_ENCRYPTION_KEY'     = 32
    'N8N_RUNNERS_AUTH_TOKEN' = 32
    'TWENTY_APP_SECRET'      = 32
    'TWENTY_ENCRYPTION_KEY'  = 32
}
# Ключі з .env, значення яких не можна показувати (паролі та токени).
$SecretKeys = @('NGROK_AUTHTOKEN') + @($GeneratedSecrets.Keys)

Set-Location $ProjectRoot

# ---------- Виведення повідомлень ----------

function Write-Title([string]$Text) {
    Write-Host ''
    Write-Host '==============================================================' -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor Cyan
}
function Write-Step([string]$Text) { Write-Host ''; Write-Host ">> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "[OK] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "[!] $Text" -ForegroundColor Yellow }
function Write-Err([string]$Text)  { Write-Host "[ПОМИЛКА] $Text" -ForegroundColor Red }

function Wait-Exit([int]$Code = 0) {
    Write-Host ''
    Read-Host 'Натисніть Enter, щоб закрити це вікно' | Out-Null
    exit $Code
}

# ---------- Docker ----------

function Find-Docker {
    if (Get-Command docker -ErrorAction SilentlyContinue) { return $true }
    # Одразу після встановлення Docker команда може бути ще не в PATH.
    $bin = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'
    if (Test-Path (Join-Path $bin 'docker.exe')) {
        $env:Path = "$bin;$env:Path"
        return $true
    }
    return $false
}

function Test-DockerRunning {
    & docker info > $null 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Assert-DockerReady {
    Write-Step 'Перевіряю Docker...'
    if (-not (Find-Docker)) {
        Write-Err "Docker Desktop не знайдено на цьому комп’ютері."
        Write-Host 'Встановіть його за інструкцією з README (Крок 1) і запустіть цей файл знову.'
        Wait-Exit 1
    }
    if (Test-DockerRunning) { Write-Ok 'Docker працює.'; return }

    $exe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $exe) {
        Write-Host 'Docker Desktop ще не запущений — запускаю його...'
        Start-Process $exe
    } else {
        Write-Warn 'Запустіть програму Docker Desktop вручну (через меню «Пуск»).'
    }
    Write-Host 'Чекаю, поки Docker буде готовий (зазвичай 1–2 хвилини)' -NoNewline
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 5
        Write-Host '.' -NoNewline
        if (Test-DockerRunning) { Write-Host ''; Write-Ok 'Docker працює.'; return }
    }
    Write-Host ''
    Write-Err 'Docker так і не запустився.'
    Write-Host 'Відкрийте вікно Docker Desktop і подивіться, чи не чекає він на вашу дію'
    Write-Host '(прийняти умови використання, оновити WSL тощо). Потім запустіть цей файл знову.'
    Wait-Exit 1
}

function Test-DataExists {
    & docker volume inspect n8n-twenty_postgres-data > $null 2>&1
    return ($LASTEXITCODE -eq 0)
}

# Якщо файлу .env немає (наприклад, для зупинки), docker compose вимагатиме паролі.
# Для команд зупинки/видалення вони не потрібні, тож підставляємо заглушку.
function Set-ComposeFallbackEnv {
    if (-not (Test-Path $EnvFile)) { $env:POSTGRES_PASSWORD = 'not-used' }
}

# ---------- Файл .env ----------

function Read-EnvFile {
    $map = @{}
    if (Test-Path $EnvFile) {
        foreach ($line in [System.IO.File]::ReadAllLines($EnvFile)) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
                $map[$Matches[1]] = $Matches[2].Trim()
            }
        }
    }
    return $map
}

function Get-EnvValue([string]$Key) {
    $map = Read-EnvFile
    if ($map.ContainsKey($Key)) { return $map[$Key] }
    return ''
}

function Set-EnvValue([string]$Key, [string]$Value) {
    $lines = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($line in [System.IO.File]::ReadAllLines($EnvFile)) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=") {
            $lines.Add("$Key=$Value")
            $found = $true
        } else {
            $lines.Add($line)
        }
    }
    if (-not $found) { $lines.Add("$Key=$Value") }
    # Пишемо з переносами рядків LF і без BOM — так файл однаково читається всюди.
    [System.IO.File]::WriteAllText($EnvFile, (($lines -join "`n") + "`n"), $Utf8NoBom)
}

function New-Secret([int]$Bytes = 24) {
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($buffer)
    $rng.Dispose()
    return (-join ($buffer | ForEach-Object { $_.ToString('x2') }))
}

function Save-EnvBackup {
    if (-not (Test-Path $EnvFile)) { return }
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Copy-Item -Force $EnvFile $BackupEnv
}

function Initialize-EnvFile {
    if (Test-Path $EnvFile) { return }

    if (Test-DataExists) {
        if (Test-Path $BackupEnv) {
            Copy-Item $BackupEnv $EnvFile
            Write-Ok 'Знайдено дані попередньої установки — налаштування відновлено з резервної копії.'
            return
        }
        Write-Err "На комп’ютері вже є дані n8n і Twenty з попередньої установки, але немає файлу .env з ключами до них."
        Write-Host 'Що можна зробити:'
        Write-Host '  1) Скопіюйте файл .env зі старої папки проєкту в цю папку і запустіть start.bat ще раз.'
        Write-Host '  2) Або почніть з нуля: запустіть reset.bat (УСІ дані буде видалено).'
        Wait-Exit 1
    }

    Write-Step 'Перший запуск: створюю файл налаштувань .env з новими паролями...'
    Copy-Item $EnvExample $EnvFile
    Initialize-Secrets
    Write-Ok 'Файл .env створено.'
}

# Заповнює порожні паролі та ключі (наприклад, якщо в новій версії проєкту з'явився новий ключ).
function Initialize-Secrets {
    foreach ($key in $GeneratedSecrets.Keys) {
        if (-not (Get-EnvValue $key)) { Set-EnvValue $key (New-Secret $GeneratedSecrets[$key]) }
    }
}

# ---------- ngrok ----------

function Test-TunnelConfigured {
    return ([bool](Get-EnvValue 'NGROK_AUTHTOKEN') -and [bool](Get-EnvValue 'NGROK_DOMAIN'))
}

function ConvertTo-NgrokDomain([string]$Text) {
    $d = $Text.Trim().ToLower()
    $d = $d -replace '^https?://', ''
    $d = $d.TrimEnd('/')
    return $d
}

function Request-NgrokSettings([switch]$Again) {
    Write-Step 'Налаштування ngrok (публічна адреса для вебхуків n8n)'
    Write-Host 'Де взяти токен і домен — див. README, Крок 3.'
    Write-Host 'Вставити скопійований текст: Ctrl+V або клік правою кнопкою миші.'
    Write-Host 'Якщо ngrok поки не потрібен — просто натисніть Enter (налаштуєте пізніше).'
    Write-Host ''

    $token = (Read-Host 'Вставте ваш Authtoken з ngrok').Trim()
    if (-not $token) {
        if ($Again) { Write-Warn 'Дані ngrok не змінено.' }
        else { Write-Warn 'ngrok пропущено: n8n працюватиме, але вебхуки з інтернету — ні.' }
        return
    }
    # Якщо вставили всю команду «ngrok config add-authtoken XXXX» — беремо лише сам токен.
    $token = ($token -split '\s+')[-1]

    $domain = ''
    for ($try = 0; $try -lt 3; $try++) {
        $domain = ConvertTo-NgrokDomain (Read-Host 'Вставте ваш домен ngrok (наприклад: abc-def.ngrok-free.app)')
        if ($domain -match '^[a-z0-9-]+(\.[a-z0-9-]+)+$') { break }
        Write-Warn 'Схоже, це не домен. Скопіюйте його зі сторінки https://dashboard.ngrok.com/domains'
        $domain = ''
    }
    if (-not $domain) {
        Write-Warn 'Домен не введено — ngrok пропущено.'
        return
    }

    Set-EnvValue 'NGROK_AUTHTOKEN' $token
    Set-EnvValue 'NGROK_DOMAIN' $domain
    Write-Ok 'Дані ngrok збережено.'
}

# Оновлює значення, які залежать від налаштувань ngrok.
function Update-DerivedSettings {
    if (Test-TunnelConfigured) {
        Set-EnvValue 'N8N_WEBHOOK_URL' ("https://" + (Get-EnvValue 'NGROK_DOMAIN') + "/")
        Set-EnvValue 'COMPOSE_PROFILES' 'tunnel'
    } else {
        Set-EnvValue 'N8N_WEBHOOK_URL' 'http://localhost:5678/'
        Set-EnvValue 'COMPOSE_PROFILES' ''
    }
}

# Перевіряє тунель «від початку до кінця»: інтернет -> ngrok -> n8n.
function Test-Tunnel([int]$Attempts = 15) {
    $url = 'https://' + (Get-EnvValue 'NGROK_DOMAIN') + '/healthz'
    for ($i = 0; $i -lt $Attempts; $i++) {
        Start-Sleep -Seconds 3
        $code = & curl.exe --silent --output NUL --write-out '%{http_code}' --max-time 10 `
            --header 'ngrok-skip-browser-warning: 1' $url 2>$null
        if ($code -eq '200') { return $true }
    }
    return $false
}
