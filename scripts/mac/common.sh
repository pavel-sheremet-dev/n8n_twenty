#!/bin/bash
# Спільні функції для скриптів macOS.
# Ці функції підключаються файлами *.command з папки Mac — запускати цей файл напряму не потрібно.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_EXAMPLE="$PROJECT_ROOT/.env.example"
BACKUP_DIR="$HOME/.n8n-twenty"
BACKUP_ENV="$BACKUP_DIR/env-backup"

# Сервіси, які запускаються завжди (ngrok — окремо, лише якщо налаштований).
CORE_SERVICES="postgres redis twenty twenty-worker n8n n8n-runner"
# Паролі та ключі, які генеруються автоматично: назва:довжина_в_байтах.
GENERATED_SECRETS="POSTGRES_PASSWORD:24 N8N_DB_PASSWORD:24 N8N_ENCRYPTION_KEY:32 N8N_RUNNERS_AUTH_TOKEN:32 TWENTY_APP_SECRET:32 TWENTY_ENCRYPTION_KEY:32"
# Ключі з .env, значення яких не можна показувати (паролі та токени).
SECRET_KEYS="NGROK_AUTHTOKEN POSTGRES_PASSWORD N8N_DB_PASSWORD N8N_ENCRYPTION_KEY N8N_RUNNERS_AUTH_TOKEN TWENTY_APP_SECRET TWENTY_ENCRYPTION_KEY"

# Docker Desktop може класти програму docker у різні місця.
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:$HOME/.docker/bin:/Applications/Docker.app/Contents/Resources/bin"

cd "$PROJECT_ROOT" || exit 1

# Файли, завантажені з інтернету, macOS позначає «карантином» і не дає їх запускати подвійним кліком.
# Знімаємо цю позначку з папки проєкту та робимо скрипти запускними.
xattr -dr com.apple.quarantine "$PROJECT_ROOT" 2>/dev/null || true
chmod +x "$PROJECT_ROOT"/Mac/*.command 2>/dev/null || true

# ---------- Виведення повідомлень ----------

title() {
  printf '\n\033[36m==============================================================\033[0m\n'
  printf '\033[36m  %s\033[0m\n' "$1"
  printf '\033[36m==============================================================\033[0m\n'
}
step() { printf '\n\033[36m>> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m[OK] %s\033[0m\n' "$1"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$1"; }
err()  { printf '\033[31m[ПОМИЛКА] %s\033[0m\n' "$1"; }

wait_exit() {
  echo
  read -r -p "Натисніть Enter, щоб закрити це вікно " _
  exit "${1:-0}"
}

# ---------- Docker ----------

docker_installed() { command -v docker >/dev/null 2>&1; }
docker_running()   { docker info >/dev/null 2>&1; }

assert_docker_ready() {
  step "Перевіряю Docker..."
  if ! docker_installed && [ ! -d "/Applications/Docker.app" ]; then
    err "Docker Desktop не знайдено на цьому Mac."
    echo "Встановіть його за інструкцією з README (Крок 1) і запустіть цей файл знову."
    wait_exit 1
  fi
  if docker_installed && docker_running; then ok "Docker працює."; return; fi

  echo "Docker Desktop ще не запущений — запускаю його..."
  open -a Docker 2>/dev/null || warn "Запустіть програму Docker вручну (з папки «Програми» / Applications)."
  printf 'Чекаю, поки Docker буде готовий (зазвичай 1–2 хвилини)'
  local i=0
  while [ $i -lt 60 ]; do
    sleep 5
    printf '.'
    if docker_installed && docker_running; then echo; ok "Docker працює."; return; fi
    i=$((i + 1))
  done
  echo
  err "Docker так і не запустився."
  echo "Відкрийте Docker Desktop і подивіться, чи не чекає він на вашу дію"
  echo "(прийняти умови використання тощо). Потім запустіть цей файл знову."
  wait_exit 1
}

data_exists() { docker volume inspect n8n-twenty_postgres-data >/dev/null 2>&1; }

# Якщо файлу .env немає (наприклад, для зупинки), docker compose вимагатиме паролі.
# Для команд зупинки/видалення вони не потрібні, тож підставляємо заглушку.
set_compose_fallback_env() {
  [ -f "$ENV_FILE" ] || export POSTGRES_PASSWORD="not-used"
}

# ---------- Файл .env ----------

get_env_value() {
  [ -f "$ENV_FILE" ] || return 0
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$ENV_FILE" | tail -n 1 | cut -d '=' -f 2- | tr -d '\r' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

set_env_value() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$ENV_FILE"; then
    awk -v k="$key" -v v="$value" '
      { line = $0; sub(/^[ \t]+/, "", line) }
      index(line, k "=") == 1 || index(line, k " =") == 1 { print k "=" v; next }
      { print }
    ' "$ENV_FILE" > "$tmp"
  else
    cat "$ENV_FILE" > "$tmp"
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  cat "$tmp" > "$ENV_FILE"
  rm -f "$tmp"
}

new_secret() {
  local bytes="${1:-24}"
  openssl rand -hex "$bytes" 2>/dev/null || od -An -N"$bytes" -tx1 /dev/urandom | tr -d ' \n'
}

save_env_backup() {
  [ -f "$ENV_FILE" ] || return 0
  mkdir -p "$BACKUP_DIR"
  cp -f "$ENV_FILE" "$BACKUP_ENV"
}

initialize_env_file() {
  [ -f "$ENV_FILE" ] && return 0

  if data_exists; then
    if [ -f "$BACKUP_ENV" ]; then
      cp "$BACKUP_ENV" "$ENV_FILE"
      ok "Знайдено дані попередньої установки — налаштування відновлено з резервної копії."
      return 0
    fi
    err "На Mac уже є дані n8n і Twenty з попередньої установки, але немає файлу .env з ключами до них."
    echo "Що можна зробити:"
    echo "  1) Скопіюйте файл .env зі старої папки проєкту в цю папку і запустіть start.command ще раз."
    echo "  2) Або почніть з нуля: запустіть reset.command (УСІ дані буде видалено)."
    wait_exit 1
  fi

  step "Перший запуск: створюю файл налаштувань .env з новими паролями..."
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  initialize_secrets
  ok "Файл .env створено."
}

# Заповнює порожні паролі та ключі (наприклад, якщо в новій версії проєкту з'явився новий ключ).
initialize_secrets() {
  local item
  for item in $GENERATED_SECRETS; do
    [ -n "$(get_env_value "${item%%:*}")" ] || set_env_value "${item%%:*}" "$(new_secret "${item##*:}")"
  done
}

# ---------- ngrok ----------

tunnel_configured() {
  [ -n "$(get_env_value NGROK_AUTHTOKEN)" ] && [ -n "$(get_env_value NGROK_DOMAIN)" ]
}

normalize_domain() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#^https\{0,1\}://##' -e 's#/*$##'
}

# Використання: request_ngrok_settings [again]
request_ngrok_settings() {
  local again="${1:-}" token domain try
  step "Налаштування ngrok (публічна адреса для вебхуків n8n)"
  echo "Де взяти токен і домен — див. README, Крок 3."
  echo "Вставити скопійований текст: Cmd+V."
  echo "Якщо ngrok поки не потрібен — просто натисніть Enter (налаштуєте пізніше)."
  echo

  read -r -p "Вставте ваш Authtoken з ngrok: " token
  token="$(printf '%s' "$token" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -z "$token" ]; then
    if [ -n "$again" ]; then warn "Дані ngrok не змінено."
    else warn "ngrok пропущено: n8n працюватиме, але вебхуки з інтернету — ні."; fi
    return 0
  fi
  # Якщо вставили всю команду «ngrok config add-authtoken XXXX» — беремо лише сам токен.
  token="${token##* }"

  domain=""
  try=0
  while [ $try -lt 3 ]; do
    read -r -p "Вставте ваш домен ngrok (наприклад: abc-def.ngrok-free.app): " domain
    domain="$(normalize_domain "$domain")"
    if printf '%s' "$domain" | grep -qE '^[a-z0-9-]+(\.[a-z0-9-]+)+$'; then break; fi
    warn "Схоже, це не домен. Скопіюйте його зі сторінки https://dashboard.ngrok.com/domains"
    domain=""
    try=$((try + 1))
  done
  if [ -z "$domain" ]; then
    warn "Домен не введено — ngrok пропущено."
    return 0
  fi

  set_env_value NGROK_AUTHTOKEN "$token"
  set_env_value NGROK_DOMAIN "$domain"
  ok "Дані ngrok збережено."
}

# Оновлює значення, які залежать від налаштувань ngrok.
update_derived_settings() {
  if tunnel_configured; then
    set_env_value N8N_WEBHOOK_URL "https://$(get_env_value NGROK_DOMAIN)/"
    set_env_value COMPOSE_PROFILES "tunnel"
  else
    set_env_value N8N_WEBHOOK_URL "http://localhost:5678/"
    set_env_value COMPOSE_PROFILES ""
  fi
}

# Перевіряє тунель «від початку до кінця»: інтернет -> ngrok -> n8n.
test_tunnel() {
  local attempts="${1:-15}" url code i=0
  url="https://$(get_env_value NGROK_DOMAIN)/healthz"
  while [ $i -lt "$attempts" ]; do
    sleep 3
    code="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
      --header 'ngrok-skip-browser-warning: 1' "$url" 2>/dev/null)"
    [ "$code" = "200" ] && return 0
    i=$((i + 1))
  done
  return 1
}
