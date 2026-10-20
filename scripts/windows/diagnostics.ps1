# Збір діагностики (Windows). Запускається файлом Windows\diagnostics.bat.
# Створює файл diagnostics.txt, який можна надіслати викладачу. Паролі та токени в ньому приховано.

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Title 'Діагностика n8n + Twenty CRM'
Write-Host 'Збираю інформацію, це займе до хвилини...'

$report = New-Object System.Text.StringBuilder
function Add-Section([string]$Title, [string]$Body) {
    [void]$report.AppendLine('')
    [void]$report.AppendLine("===== $Title =====")
    [void]$report.AppendLine($Body)
}
# Виконує команду через cmd, щоб отримати звичайний текст разом із повідомленнями про помилки.
function Get-CommandOutput([string]$CommandLine) {
    return ((& cmd.exe /d /c "$CommandLine 2>&1") -join "`r`n")
}

Add-Section 'Час' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $ramGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    Add-Section 'Система' "$($os.Caption) $($os.Version) $($env:PROCESSOR_ARCHITECTURE), RAM: $ramGb GB"
} catch {
    Add-Section 'Система' ([Environment]::OSVersion.VersionString)
}
Add-Section 'Папка проєкту' $ProjectRoot

if (-not (Find-Docker)) {
    Add-Section 'Docker' 'Docker не знайдено (не встановлений або не в PATH).'
} else {
    Add-Section 'Docker version' (Get-CommandOutput 'docker version')
    Add-Section 'WSL' (Get-CommandOutput 'wsl --version')
    if (Test-DockerRunning) {
        Set-ComposeFallbackEnv
        Add-Section 'docker compose version' (Get-CommandOutput 'docker compose version')
        Add-Section 'Контейнери' (Get-CommandOutput 'docker compose --profile tunnel ps --all')
        Add-Section 'Використання ресурсів' (Get-CommandOutput 'docker stats --no-stream')
        Add-Section 'Томи з даними' (Get-CommandOutput 'docker volume ls --filter name=n8n-twenty')
        foreach ($svc in ($CoreServices + 'ngrok')) {
            Add-Section "Журнал: $svc (останні 80 рядків)" (Get-CommandOutput "docker compose --profile tunnel logs --no-color --tail 80 $svc")
        }
    } else {
        Add-Section 'Docker' 'Docker встановлений, але не запущений.'
    }
}

# Налаштування з .env: показуємо лише, чи заповнені секретні значення, але не їх самих.
if (Test-Path $EnvFile) {
    $envMap = Read-EnvFile
    $lines = foreach ($key in ($envMap.Keys | Sort-Object)) {
        if ($SecretKeys -contains $key) {
            if ($envMap[$key]) { "$key = (заповнено)" } else { "$key = (порожньо)" }
        } else {
            "$key = $($envMap[$key])"
        }
    }
    Add-Section 'Файл .env' ($lines -join "`r`n")
} else {
    Add-Section 'Файл .env' 'Файлу .env немає (start.bat ще не запускали?).'
}

if (Test-TunnelConfigured) {
    $tunnel = if (Test-Tunnel 2) { 'працює' } else { 'НЕ відповідає' }
    Add-Section 'Тунель ngrok' "https://$(Get-EnvValue 'NGROK_DOMAIN') — $tunnel"
}

# Прибираємо кольорові коди з журналів, а також — про всяк випадок — усі паролі та токени.
$text = $report.ToString() -replace "\x1b\[[0-9;]*m", ''
$envMap = Read-EnvFile
foreach ($key in $SecretKeys) {
    if ($envMap.ContainsKey($key) -and $envMap[$key].Length -ge 6) {
        $text = $text.Replace($envMap[$key], '***')
    }
}

$outFile = Join-Path $ProjectRoot 'diagnostics.txt'
[System.IO.File]::WriteAllText($outFile, $text, (New-Object System.Text.UTF8Encoding $true))

Write-Ok "Готово: $outFile"
Write-Host 'Зараз відкриється папка з цим файлом — надішліть його викладачу.'
Start-Process explorer.exe "/select,`"$outFile`""
Wait-Exit 0
