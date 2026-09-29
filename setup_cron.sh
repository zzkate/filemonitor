#!/bin/bash
set -euo pipefail

cp filemonitor.sh /usr/local/bin/filemonitor.sh
cp filemonitor.conf /etc/filemonitor.conf

chmod +x /usr/local/bin/filemonitor.sh

SCRIPT_PATH="/usr/local/bin/filemonitor.sh"
CRON_ENTRY="0 6,18 * * * $SCRIPT_PATH"
CRON_COMMENT="# File Monitor: runs twice daily at 06:00 and 18:00"

# Проверяем существование скрипта
if [[ ! -x "$SCRIPT_PATH" ]]; then
    echo "Error: Script not found or not executable: $SCRIPT_PATH" >&2
    echo "Run: chmod +x $SCRIPT_PATH" >&2
    exit 1
fi

# Проверяем cron
if ! command -v crontab &>/dev/null; then
    echo "Error: crontab not found. Install cron package." >&2
    exit 1
fi

# Получаем текущий crontab (если есть)
current_crontab=$(crontab -l 2>/dev/null || true)

# Проверяем, есть ли уже такая запись
if echo "$current_crontab" | grep -qF "$SCRIPT_PATH"; then
    echo "Cron entry for filemonitor.sh already exists."
    echo "Current crontab:"
    crontab -l | grep -A1 -B1 "$SCRIPT_PATH" || true
    exit 0
fi

# Добавляем запись
{
    echo "$CRON_COMMENT"
    echo "$CRON_ENTRY"
} | {
    if [[ -n "$current_crontab" ]]; then
        cat - <(echo "$current_crontab")
    else
        cat -
    fi
} | crontab -

echo "Cron entry added successfully."
echo ""
echo "Current crontab:"
crontab -l