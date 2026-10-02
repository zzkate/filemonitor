#!/usr/bin/env bash

set -uo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/filemonitor.conf}"
LOGGER_TAG="filemonitor"

if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "Configuration file is not readable: $CONFIG_FILE" >&2
    exit 1
fi

# Загружаем обычные параметры конфигурации.
# MD5 исключается, поскольку он может быть объявлен несколько раз.
source <(
    sed \
        -e '/^[[:space:]]*MD5[[:space:]]*=/d' \
        "$CONFIG_FILE"
)

: "${MONITOR_DIR:?MONITOR_DIR is not set}"
: "${EMAIL_TO:?EMAIL_TO is not set}"
: "${EMAIL_SUBJECT:?EMAIL_SUBJECT is not set}"

if ! command -v find >/dev/null 2>&1 ||
   ! command -v logger >/dev/null 2>&1 ||
   ! command -v md5sum >/dev/null 2>&1 ||
   ! command -v mail >/dev/null 2>&1; then
    echo "Required command is missing: find, logger, md5sum or mail" >&2
    exit 1
fi

if [[ ! -d "$MONITOR_DIR" ]]; then
    echo "Directory does not exist: $MONITOR_DIR" >&2
    exit 1
fi

# Массив MD5-сумм. Каждая строка вида MD5='...' добавляется отдельно.
declare -a EXPECTED_MD5=()

while IFS= read -r line; do
    # Удаляем комментарий и пробелы по краям.
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^MD5[[:space:]]*=[[:space:]]*\'([^\']*)\'$ ]]; then
        md5_value="${BASH_REMATCH[1]}"

        # Поддерживаются как одна сумма в строке,
        # так и несколько сумм через пробел:
        # MD5='hash1 hash2 hash3'
        read -r -a md5_values <<< "$md5_value"

        for md5 in "${md5_values[@]}"; do
            EXPECTED_MD5+=("$md5")
        done
    elif [[ "$line" =~ ^MD5[[:space:]]*=[[:space:]]*\"([^\"]*)\"$ ]]; then
        md5_value="${BASH_REMATCH[1]}"
        read -r -a md5_values <<< "$md5_value"

        for md5 in "${md5_values[@]}"; do
            EXPECTED_MD5+=("$md5")
        done
    fi
done < "$CONFIG_FILE"

# Проверяем формат MD5-сумм.
for md5 in "${EXPECTED_MD5[@]}"; do
    if [[ ! "$md5" =~ ^[[:xdigit:]]{32}$ ]]; then
        echo "Invalid MD5 value in configuration: $md5" >&2
        exit 1
    fi
done

is_md5_match() {
    local file="$1"
    local actual_md5

    [[ ${#EXPECTED_MD5[@]} -gt 0 ]] || return 1

    actual_md5="$(md5sum -- "$file" | awk '{print $1}')" || return 1

    for expected_md5 in "${EXPECTED_MD5[@]}"; do
        if [[ "${actual_md5,,}" == "${expected_md5,,}" ]]; then
            return 0
        fi
    done

    return 1
}

get_file_size() {
    local file="$1"

    if stat -c '%s' -- "$file" 2>/dev/null; then
        return 0
    fi

    stat -f '%z' -- "$file"
}

declare -a found_files=()
declare -a found_reasons=()

echo "start scanning $MONITOR_DIR..."

while IFS= read -r -d '' file; do
    filename="${file##*/}"
    matched=false
    reason=""

    # Критерий 1: регулярное выражение для имени файла.
    if [[ -n "${REGEX:-}" ]] &&
       [[ "$filename" =~ $REGEX ]]; then
        matched=true
        reason="name matches regex: $REGEX"
    fi

    # Критерий 2: размер файла больше SIZE байт.
    if [[ "$matched" == false ]] &&
       [[ -n "${SIZE:-}" ]]; then

        if [[ ! "$SIZE" =~ ^[0-9]+$ ]]; then
            echo "SIZE must be a non-negative integer: $SIZE" >&2
            exit 1
        fi

        file_size="$(get_file_size "$file")"

        if [[ "$file_size" -gt "$SIZE" ]]; then
            matched=true
            reason="size is ${file_size} bytes, limit is ${SIZE} bytes"
        fi
    fi

    # Критерий 3: совпадение с одной из MD5-сумм.
    if [[ "$matched" == false ]] &&
       is_md5_match "$file"; then
        actual_md5="$(md5sum -- "$file" | awk '{print $1}')"
        matched=true
        reason="MD5 matches: $actual_md5"
    fi

    if [[ "$matched" == true ]]; then
        found_files+=("$file")
        found_reasons+=("$reason")
        echo "matched: $file  reason: $reason" 
    fi
done < <(find "$MONITOR_DIR" -type f -print0)

found_count="${#found_files[@]}"
timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

logger -t "$LOGGER_TAG" \
    "Scan completed: $found_count files matched criteria in $MONITOR_DIR"
echo "Scan completed: $found_count files matched criteria in $MONITOR_DIR"

if [[ "$found_count" -gt 0 ]]; then

    echo "Sending alert to system log..."
    for i in "${!found_files[@]}"; do
        logger -t "$LOGGER_TAG" \
            "MATCH: ${found_files[$i]} (${found_reasons[$i]})"
    done

    echo "Sending email alert..."
    MAIL_APP="/usr/local/filemonitor/mail.sh"
    if [[ ! -x "$MAIL_APP" ]]; then
        echo "Error: no $MAIL_APP" >&2
        exit 1
    fi

    {
        printf '%s\n' "File Monitor Alert"
        printf '%s\n' "=================="
        printf 'Time: %s\n' "$timestamp"
        printf 'Directory: %s\n' "$MONITOR_DIR"
        printf 'Total files found: %s\n\n' "$found_count"

        printf '%s\n' "Files:"
        printf '%s\n' "------"

        for i in "${!found_files[@]}"; do
            printf '%d. %s\n' "$((i + 1))" "${found_files[$i]}"
            printf '   Reason: %s\n' "${found_reasons[$i]}"
        done

        printf '\n%s\n' "---"
        printf 'REGEX: %s\n' "${REGEX:-}"
        printf 'SIZE: %s bytes\n' "${SIZE:-}"

        if [[ ${#EXPECTED_MD5[@]} -gt 0 ]]; then
            printf 'MD5 values:\n'
            for md5 in "${EXPECTED_MD5[@]}"; do
                printf '  %s\n' "$md5"
            done
        else
            printf '%s\n' "MD5 values: disabled"
        fi
    } | $($MAIL_APP $EMAIL_TO $EMAIL_SUBJECT)
fi

exit 0