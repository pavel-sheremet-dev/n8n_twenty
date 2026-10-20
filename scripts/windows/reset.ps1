# Повне видалення даних n8n + Twenty CRM (Windows). Запускається файлом Windows\reset.bat.

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Title 'Скидання: видалення ВСІХ даних'
Write-Host ''
Write-Warn 'Буде НАЗАВЖДИ видалено:'
Write-Host '    - усі компанії, контакти, угоди та налаштування в Twenty CRM;'
Write-Host '    - усі workflow, облікові дані (credentials) та історію запусків у n8n;'
Write-Host '    - усі таблиці в базі даних practice.'
Write-Host ''
Write-Host 'Після цього start.bat запустить систему «з нуля», як уперше.'
Write-Host 'Налаштування ngrok збережуться — вводити їх знову не доведеться.'
Write-Host ''
$answer = (Read-Host 'Щоб підтвердити, введіть слово ВИДАЛИТИ (або DELETE)').Trim()
if ($answer -ne 'видалити' -and $answer -ne 'delete') {
    Write-Ok 'Скасовано. Нічого не видалено.'
    Wait-Exit 0
}

Assert-DockerReady
Set-ComposeFallbackEnv
Write-Step 'Видаляю програми та всі дані...'
& docker compose --profile tunnel down --volumes --remove-orphans
if ($LASTEXITCODE -ne 0) {
    Write-Err 'Не вдалося видалити дані. Перезапустіть Docker Desktop і спробуйте ще раз.'
    Wait-Exit 1
}

Write-Ok 'Усі дані видалено. Тепер запустіть start.bat — система запуститься з нуля.'
Wait-Exit 0
