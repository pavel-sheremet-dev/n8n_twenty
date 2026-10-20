#!/bin/bash
# Зупинка n8n + Twenty CRM (macOS). Двічі клацніть цей файл у Finder.

source "$(cd "$(dirname "$0")" && pwd)/../scripts/mac/common.sh" || exit 1

title "Зупинка n8n + Twenty CRM"

if ! docker_installed || ! docker_running; then
  ok "Docker не запущений — отже, програми вже зупинені."
  wait_exit 0
fi

set_compose_fallback_env
step "Зупиняю програми..."
if ! docker compose --profile tunnel down; then
  err "Не вдалося зупинити програми. Спробуйте ще раз або перезапустіть Docker Desktop."
  wait_exit 1
fi

ok "Усе зупинено. Ваші дані збережено — наступного разу просто запустіть start.command."
echo
echo "Щоб звільнити пам’ять комп’ютера, можна також закрити Docker Desktop:"
echo "клік на іконці кита у верхньому меню -> Quit Docker Desktop."
wait_exit 0
