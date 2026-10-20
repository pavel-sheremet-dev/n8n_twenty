# Зупинка n8n + Twenty CRM (Windows). Запускається файлом Windows\stop.bat.

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Title 'Зупинка n8n + Twenty CRM'

if (-not (Find-Docker) -or -not (Test-DockerRunning)) {
    Write-Ok 'Docker не запущений — отже, програми вже зупинені.'
    Wait-Exit 0
}

Set-ComposeFallbackEnv
Write-Step 'Зупиняю програми...'
& docker compose --profile tunnel down
if ($LASTEXITCODE -ne 0) {
    Write-Err 'Не вдалося зупинити програми. Спробуйте ще раз або перезапустіть Docker Desktop.'
    Wait-Exit 1
}

Write-Ok 'Усе зупинено. Ваші дані збережено — наступного разу просто запустіть start.bat.'
Write-Host ''
Write-Host "Щоб звільнити пам’ять комп’ютера, можна також закрити Docker Desktop:"
Write-Host 'клік правою кнопкою на іконці кита біля годинника -> Quit Docker Desktop.'
Wait-Exit 0
