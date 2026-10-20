#!/bin/bash
# Повне видалення даних n8n + Twenty CRM (macOS). Двічі клацніть цей файл у Finder.

source "$(cd "$(dirname "$0")" && pwd)/../scripts/mac/common.sh" || exit 1

title "Скидання: видалення ВСІХ даних"
echo
warn "Буде НАЗАВЖДИ видалено:"
echo "    - усі компанії, контакти, угоди та налаштування в Twenty CRM;"
echo "    - усі workflow, облікові дані (credentials) та історію запусків у n8n;"
echo "    - усі таблиці в базі даних practice."
echo
echo "Після цього start.command запустить систему «з нуля», як уперше."
echo "Налаштування ngrok збережуться — вводити їх знову не доведеться."
echo
read -r -p "Щоб підтвердити, введіть слово ВИДАЛИТИ (або DELETE): " answer
case "$answer" in
  ВИДАЛИТИ|видалити|Видалити|DELETE|delete|Delete) ;;
  *) ok "Скасовано. Нічого не видалено."; wait_exit 0 ;;
esac

assert_docker_ready
set_compose_fallback_env
step "Видаляю програми та всі дані..."
if ! docker compose --profile tunnel down --volumes --remove-orphans; then
  err "Не вдалося видалити дані. Перезапустіть Docker Desktop і спробуйте ще раз."
  wait_exit 1
fi

ok "Усі дані видалено. Тепер запустіть start.command — система запуститься з нуля."
wait_exit 0
