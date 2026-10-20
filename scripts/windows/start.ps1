# Запуск n8n + Twenty CRM (Windows). Запускається файлом Windows\start.bat.

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Title 'Запуск n8n + Twenty CRM'

Assert-DockerReady
Initialize-EnvFile
Initialize-Secrets
if (-not (Test-TunnelConfigured)) { Request-NgrokSettings }
Update-DerivedSettings

Write-Step 'Запускаю n8n і Twenty CRM...'
Write-Host 'Під час ПЕРШОГО запуску Docker завантажить близько 2–3 ГБ програм.'
Write-Host 'Це може тривати 5–20 хвилин (залежить від інтернету). Не закривайте це вікно.'
Write-Host 'Наступні запуски займатимуть 1–2 хвилини.'
Write-Host ''
& docker compose up --detach --wait --wait-timeout 900 @CoreServices
if ($LASTEXITCODE -ne 0) {
    Write-Err 'Не вдалося запустити всі програми.'
    Write-Host 'Спробуйте запустити start.bat ще раз. Якщо помилка повториться —'
    Write-Host 'запустіть diagnostics.bat і надішліть створений файл викладачу.'
    Wait-Exit 1
}
Write-Ok 'n8n і Twenty CRM запущено.'

$tunnelOk = $false
if (Test-TunnelConfigured) {
    Write-Step 'Запускаю тунель ngrok...'
    & docker compose up --detach ngrok
    $tunnelOk = Test-Tunnel
    if (-not $tunnelOk) {
        Write-Warn 'Тунель ngrok не запрацював. Ось останні повідомлення ngrok:'
        & docker compose logs --tail 10 ngrok
        Write-Host ''
        Write-Host 'Найчастіша причина — помилка в токені або домені (див. README, Крок 3).'
        $answer = Read-Host 'Ввести дані ngrok ще раз? Введіть т (так) або н (ні)'
        if ($answer -match '^\s*(т|так|t|y|yes|д)') {
            Request-NgrokSettings -Again
            Update-DerivedSettings
            & docker compose up --detach --wait --wait-timeout 300 n8n
            & docker compose up --detach ngrok
            $tunnelOk = Test-Tunnel
        }
    }
    # Якщо ngrok завершився з помилкою (наприклад, неправильний токен), не даємо йому перезапускатися без кінця.
    $ngrokState = (& docker compose ps --all --format '{{.State}}' ngrok 2>$null) -join ''
    if (-not $tunnelOk -and $ngrokState -match 'restarting|exited') { & docker compose stop ngrok > $null 2>&1 }
} else {
    # ngrok не налаштований: прибираємо контейнер, якщо він лишився з минулих запусків.
    & docker compose rm --stop --force ngrok > $null 2>&1
}

Save-EnvBackup

Write-Title 'Готово!'
Write-Host ''
Write-Host '  Twenty CRM:  http://localhost:3000' -ForegroundColor Green
Write-Host '  n8n:         http://localhost:5678' -ForegroundColor Green
Write-Host ''
if (Test-TunnelConfigured) {
    $domain = Get-EnvValue 'NGROK_DOMAIN'
    if ($tunnelOk) {
        Write-Ok "Публічна адреса n8n для вебхуків: https://$domain"
    } else {
        Write-Warn "Тунель https://$domain поки не працює — вебхуки з інтернету не надходитимуть."
        Write-Host '    Усе інше працює. Перевірте дані ngrok і запустіть start.bat ще раз.'
    }
    Write-Host '    Запити, що приходять через тунель, видно тут: http://localhost:4040'
} else {
    Write-Warn 'ngrok не налаштований: вебхуки з інтернету не працюватимуть (усе інше працює).'
    Write-Host '    Щоб налаштувати — запустіть start.bat ще раз і введіть дані ngrok.'
}
Write-Host ''
Write-Host '  Адреса n8n для вебхуків з Twenty: http://n8n.internal:5678/webhook/...'
Write-Host '  Адреса Twenty для запитів з n8n:  http://twenty.internal:3000'
Write-Host ''
Write-Host 'Зараз відкриються сторінки в браузері.'
Write-Host 'Щоб зупинити програми — запустіть stop.bat.'

Start-Process 'http://localhost:3000'
Start-Process 'http://localhost:5678'

Wait-Exit 0
