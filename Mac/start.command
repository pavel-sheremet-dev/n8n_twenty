#!/bin/bash
# Запуск n8n + Twenty CRM (macOS). Двічі клацніть цей файл у Finder.

source "$(cd "$(dirname "$0")" && pwd)/../scripts/mac/common.sh" || exit 1

title "Запуск n8n + Twenty CRM"

assert_docker_ready
initialize_env_file
initialize_secrets
tunnel_configured || request_ngrok_settings
update_derived_settings

step "Запускаю n8n і Twenty CRM..."
echo "Під час ПЕРШОГО запуску Docker завантажить близько 2–3 ГБ програм."
echo "Це може тривати 5–20 хвилин (залежить від інтернету). Не закривайте це вікно."
echo "Наступні запуски займатимуть 1–2 хвилини."
echo
# shellcheck disable=SC2086
if ! docker compose up --detach --wait --wait-timeout 900 $CORE_SERVICES; then
  err "Не вдалося запустити всі програми."
  echo "Спробуйте запустити start.command ще раз. Якщо помилка повториться —"
  echo "запустіть diagnostics.command і надішліть створений файл викладачу."
  wait_exit 1
fi
ok "n8n і Twenty CRM запущено."

tunnel_ok=""
if tunnel_configured; then
  step "Запускаю тунель ngrok..."
  docker compose up --detach ngrok
  if test_tunnel; then
    tunnel_ok="yes"
  else
    warn "Тунель ngrok не запрацював. Ось останні повідомлення ngrok:"
    docker compose logs --tail 10 ngrok
    echo
    echo "Найчастіша причина — помилка в токені або домені (див. README, Крок 3)."
    read -r -p "Ввести дані ngrok ще раз? Введіть т (так) або н (ні): " answer
    case "$answer" in
      т*|Т*|t*|T*|y*|Y*|д*|Д*)
        request_ngrok_settings again
        update_derived_settings
        docker compose up --detach --wait --wait-timeout 300 n8n
        docker compose up --detach ngrok
        test_tunnel && tunnel_ok="yes"
        ;;
    esac
  fi
  # Якщо ngrok завершився з помилкою (наприклад, неправильний токен), не даємо йому перезапускатися без кінця.
  if [ -z "$tunnel_ok" ] && docker compose ps --all --format '{{.State}}' ngrok 2>/dev/null | grep -qE 'restarting|exited'; then
    docker compose stop ngrok >/dev/null 2>&1
  fi
else
  # ngrok не налаштований: прибираємо контейнер, якщо він лишився з минулих запусків.
  docker compose rm --stop --force ngrok >/dev/null 2>&1
fi

save_env_backup

title "Готово!"
echo
printf '\033[32m  Twenty CRM:  http://localhost:3000\033[0m\n'
printf '\033[32m  n8n:         http://localhost:5678\033[0m\n'
echo
if tunnel_configured; then
  domain="$(get_env_value NGROK_DOMAIN)"
  if [ -n "$tunnel_ok" ]; then
    ok "Публічна адреса n8n для вебхуків: https://$domain"
  else
    warn "Тунель https://$domain поки не працює — вебхуки з інтернету не надходитимуть."
    echo "    Усе інше працює. Перевірте дані ngrok і запустіть start.command ще раз."
  fi
  echo "    Запити, що приходять через тунель, видно тут: http://localhost:4040"
else
  warn "ngrok не налаштований: вебхуки з інтернету не працюватимуть (усе інше працює)."
  echo "    Щоб налаштувати — запустіть start.command ще раз і введіть дані ngrok."
fi
echo
echo "  Адреса n8n для вебхуків з Twenty: http://n8n.internal:5678/webhook/..."
echo "  Адреса Twenty для запитів з n8n:  http://twenty.internal:3000"
echo
echo "Зараз відкриються сторінки в браузері."
echo "Щоб зупинити програми — запустіть stop.command."

open "http://localhost:3000"
open "http://localhost:5678"

wait_exit 0
