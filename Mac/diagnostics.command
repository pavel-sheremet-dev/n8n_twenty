#!/bin/bash
# Збір діагностики (macOS). Двічі клацніть цей файл у Finder.
# Створює файл diagnostics.txt, який можна надіслати викладачу. Паролі та токени в ньому приховано.

source "$(cd "$(dirname "$0")" && pwd)/../scripts/mac/common.sh" || exit 1

title "Діагностика n8n + Twenty CRM"
echo "Збираю інформацію, це займе до хвилини..."

OUT_FILE="$PROJECT_ROOT/diagnostics.txt"
section() { printf '\n===== %s =====\n' "$1"; }

{
  section "Час";            date
  section "Система";        sw_vers; uname -m
  echo "RAM: $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB"
  section "Папка проєкту";  echo "$PROJECT_ROOT"

  if ! docker_installed; then
    section "Docker"; echo "Docker не знайдено (не встановлений або не в PATH)."
  else
    section "Docker version"; docker version 2>&1
    if docker_running; then
      set_compose_fallback_env
      section "docker compose version"; docker compose version 2>&1
      section "Контейнери";             docker compose --profile tunnel ps --all 2>&1
      section "Використання ресурсів";  docker stats --no-stream 2>&1
      section "Томи з даними";          docker volume ls --filter name=n8n-twenty 2>&1
      for svc in $CORE_SERVICES ngrok; do
        section "Журнал: $svc (останні 80 рядків)"
        docker compose --profile tunnel logs --no-color --tail 80 "$svc" 2>&1
      done
    else
      section "Docker"; echo "Docker встановлений, але не запущений."
    fi
  fi

  # Налаштування з .env: показуємо лише, чи заповнені секретні значення, але не їх самих.
  section "Файл .env"
  if [ -f "$ENV_FILE" ]; then
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | cut -d '=' -f 1 | sort -u | while read -r key; do
      value="$(get_env_value "$key")"
      case " $SECRET_KEYS " in
        *" $key "*) if [ -n "$value" ]; then echo "$key = (заповнено)"; else echo "$key = (порожньо)"; fi ;;
        *) echo "$key = $value" ;;
      esac
    done
  else
    echo "Файлу .env немає (start.command ще не запускали?)."
  fi

  if tunnel_configured; then
    section "Тунель ngrok"
    if test_tunnel 2; then echo "https://$(get_env_value NGROK_DOMAIN) — працює"
    else echo "https://$(get_env_value NGROK_DOMAIN) — НЕ відповідає"; fi
  fi
} > "$OUT_FILE"

# Прибираємо кольорові коди з журналів, а також — про всяк випадок — усі паролі та токени.
sed -i '' -E $'s/\x1b\\[[0-9;]*m//g' "$OUT_FILE"
for key in $SECRET_KEYS; do
  value="$(get_env_value "$key")"
  if [ ${#value} -ge 6 ]; then
    escaped="$(printf '%s' "$value" | sed 's/[][\.*^$/]/\\&/g')"
    sed -i '' "s/$escaped/***/g" "$OUT_FILE"
  fi
done

ok "Готово: $OUT_FILE"
echo "Зараз відкриється папка з цим файлом — надішліть його викладачу."
open -R "$OUT_FILE"
wait_exit 0
