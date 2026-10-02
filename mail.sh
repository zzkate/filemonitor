#!/bin/bash
set -euo pipefail

if [[ ! -f "/usr/local/filemonitor/mail_app_pass" ]]; then
    echo "Error: no /usr/local/filemonitor/mail_app_pass" >&2
    exit 1
fi

EMAIL_TO="${1:-}"
EMAIL_SUBJECT="${2:-Уведомление от FileMonitor}"
FROM_ADDR="katezaytsewa@gmail.com"
APP_PASS=$(cat /usr/local/filemonitor/mail_app_pass)

if [ -z "$EMAIL_TO" ]; then
    echo "Использование: $0 <email-to[,email2,...]> [subject]" >&2
    exit 1
fi

BODY=$(cat)

# Разбиваем список по запятой и отправляем каждому
IFS=',' read -ra RECIPIENTS <<< "$EMAIL_TO"

for RECIPIENT in "${RECIPIENTS[@]}"; do
    # Убираем пробелы вокруг адреса
    RECIPIENT=$(echo "$RECIPIENT" | xargs)

    cat > /tmp/mail.txt <<EOF
From: "FileMonitor" <$FROM_ADDR>
To: "$RECIPIENT"
Subject: $EMAIL_SUBJECT

$BODY
EOF

    curl --ssl-reqd \
      --url 'smtps://smtp.gmail.com:465' \
      --user "$FROM_ADDR:$APP_PASS" \
      --mail-from "$FROM_ADDR" \
      --mail-rcpt "$RECIPIENT" \
      --upload-file /tmp/mail.txt
done

rm -f /tmp/mail.txt