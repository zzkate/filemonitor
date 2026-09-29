# 1. Делаем скрипты исполняемыми
chmod +x setup_cron.sh

# 2.  Настраиваем cron
sudo ./setup_cron.sh

# 4. Проверяем cron
sudo crontab -l

# 5. Снятие с cron
# Удаляет все записи, содержащие filemonitor.sh
sudo crontab -l | grep -v filemonitor.sh | grep -v "^# File Monitor" | crontab -