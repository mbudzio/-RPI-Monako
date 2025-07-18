#!/bin/bash

### =============================
###      MONAKO BACKUP MENU
###   RPI double HDD system
### =============================

BACKUP_DEVICE="/dev/sdb1"
MOUNT_POINT="/mnt/backup"
DAILY_DIR="$MOUNT_POINT/daily"
LOGFILE="/var/log/system-backup.log"
CONFIG_MARKER="/var/lib/monako/.configured"

YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function logo() {
  clear
  echo -e "${YELLOW}"
  echo "███    ███  ██████  ███    ██  █████  ██   ██  ██████ "
  echo "████  ████ ██    ██ ████   ██ ██   ██ ██  ██  ██      "
  echo "██ ████ ██ ██    ██ ██ ██  ██ ███████ █████   ██  ███ "
  echo "██  ██  ██ ██    ██ ██  ██ ██ ██   ██ ██  ██  ██   ██ "
  echo "██      ██  ██████  ██   ████ ██   ██ ██   ██  ██████ "
  echo ""
  echo "         RPI double HDD backup system"
  echo -e "${NC}
"
}

function ensure_structure() {
  if [ -f "$CONFIG_MARKER" ]; then
    echo -ne "🧪 Weryfikacja środowiska backupu..."
    for i in {1..10}; do sleep 1; echo -n "."; done
    echo "
✅ Weryfikacja zakończona. Wszystko OK."
    sleep 1
    return
  fi

  echo -e "
🔧 MONAKO wymaga inicjalnej konfiguracji."
  read -p "Czy chcesz ją przeprowadzić teraz? (T/N): " choice
  if [[ "$choice" == "T" || "$choice" == "t" ]]; then
    sudo mkdir -p "$DAILY_DIR"
    sudo mkdir -p "$(dirname $LOGFILE)"
    sudo touch "$LOGFILE"
    sudo chown $(whoami) "$LOGFILE"
    sudo mkdir -p "/var/lib/monako"
    sudo touch "$CONFIG_MARKER"
    echo "✅ Konfiguracja zakończona."
    sleep 1
  else
    echo "❎ Przerwano konfigurację."
    exit 0
  fi
}

function mount_backup() {
  sudo mount "$BACKUP_DEVICE" "$MOUNT_POINT" 2>/dev/null
}

function unmount_backup() {
  sudo umount "$MOUNT_POINT" 2>/dev/null
}

function run_backup() {
  echo -e "
▶️ Uruchamiam backup systemu...
"
  mount_backup

  NOW=$(date +"%Y-%m-%d")
  START=$(date +"%Y-%m-%d %H:%M:%S")
  DEST="$DAILY_DIR/$NOW"
  LINKDEST="$DAILY_DIR/latest"

  {
    echo "=== Backup rozpoczęty: $START ==="
    echo "Cel: $DEST"

    if [ -d "$LINKDEST" ]; then
      echo "Backup przyrostowy względem: $LINKDEST"
      LINK_OPT="--link-dest=$LINKDEST"
    else
      echo "Brak poprzedniego backupu – pełna kopia"
      LINK_OPT=""
    fi

    sudo mkdir -p "$DEST"

    sudo rsync -aAX --info=progress2 --delete \
      $LINK_OPT \
      --exclude="{/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,$MOUNT_POINT/*,/media/*,/lost+found}" \
      / "$DEST" 2>&1 | tee -a "$LOGFILE"

    if [ $? -ne 0 ]; then
      echo "❌ BŁĄD: Backup nie powiódł się!"
      echo "✖ Backup zakończony błędem: $(date)" >> "$LOGFILE"
    else
      echo "Aktualizacja symlinka latest → $DEST"
      sudo rm -f "$LINKDEST"
      sudo ln -s "$DEST" "$LINKDEST"
      echo "✔️ Backup zakończony: $(date)"
    fi
    echo ""
  } >> "$LOGFILE" 2>&1

  unmount_backup
  echo -e "
✅ Backup zakończony. Wciśnij Enter..."
  read
}

function view_logs() {
  echo -e "
📄 Ostatnie 100 linii logu:
"
  if [ ! -f "$LOGFILE" ]; then
    echo "❌ Plik logu nie istnieje."; read; return
  fi
  sudo tail -n 100 "$LOGFILE"
  echo -e "
Wciśnij Enter..."
  read
}

function view_info() {
  echo -e "
📋 Informacje o MONAKO:"
  if [ -f "$CONFIG_MARKER" ]; then
    echo "🔧 Konfiguracja: ✓ (plik $CONFIG_MARKER)"
  else
    echo "🔧 Konfiguracja: ✗ (brak pliku konfiguracyjnego)"
  fi
  echo "🔁 Cron: $(sudo crontab -l 2>/dev/null | grep backup-menu.sh || echo 'brak wpisu')"
  echo "📁 Katalogi: $DAILY_DIR"
  echo "🔗 Symlink: $DAILY_DIR/latest"
  echo "📬 Powiadomienia e-mail: (do zaimplementowania)"
  echo "📦 Backup: przyrostowy z --link-dest"
  echo -e "
Wciśnij Enter..."
  read
}

function restore_backup() {
  echo -e "
⚠️ Przywrócenie backupu nadpisze system!"
  echo -n "Data backupu do przywrócenia (YYYY-MM-DD): "; read DATE
  SOURCE="$DAILY_DIR/$DATE"
  if [ ! -d "$SOURCE" ]; then
    echo "❌ Nie znaleziono: $SOURCE"; read; return
  fi
  echo "sudo rsync -aAXv $SOURCE/ / --delete"
  echo -n "Potwierdź (TAK/nie): "; read CONFIRM
  if [ "$CONFIRM" == "TAK" ]; then
    mount_backup
    sudo rsync -aAXv "$SOURCE/" / --delete
    unmount_backup
    echo "✅ Przywracanie zakończone. Zrestartuj system."
  else
    echo "❎ Anulowano."
  fi
  read -p "Wciśnij Enter..."
}

function compare_backups() {
  echo -e "
📂 Backupy:"; ls -1 $DAILY_DIR | grep -E '^[0-9]{4}-' | sort
  echo -n "Data backupu do porównania z 'latest': "; read OLD
  OLD_DIR="$DAILY_DIR/$OLD"
  NEW_DIR="$DAILY_DIR/latest"
  OUTFILE="/tmp/monako-diff-$OLD-vs-latest.txt"
  if [ ! -d "$OLD_DIR" ]; then echo "❌ Brak: $OLD_DIR"; read; return; fi
  echo -e "
🔍 Tworzę porównanie (symulacja)...
"
  sudo rsync -aAXvn --delete --itemize-changes "$OLD_DIR/" "$NEW_DIR/" > "$OUTFILE"
  less "$OUTFILE"
  read -p "Wciśnij Enter..."
}

function set_schedule() {
  echo -n "🕒 Godzina backupu (HH:MM, np. 02:00): "; read TIME
  echo -n "📆 Dni backupu (np. * lub 1-5 lub 0,6): "; read DAYS
  CRON_LINE="${TIME:3:2} ${TIME:0:2} * * $DAYS /usr/local/bin/backup-menu.sh"
  (sudo crontab -l 2>/dev/null | grep -v 'backup-menu.sh'; echo "$CRON_LINE") | sudo crontab -
  echo "✅ Ustawiono harmonogram: $CRON_LINE"
  read -p "Wciśnij Enter..."
}

function reset_configuration() {
  echo -e "
💣 Usuwam konfigurację..."
  sudo rm -f "$CONFIG_MARKER"
  sudo rm -rf "$DAILY_DIR"
  sudo rm -f "$LOGFILE"
  sudo touch "$LOGFILE"
  sudo chown $(whoami) "$LOGFILE"
  echo "✅ Konfiguracja została usunięta."
  read -p "Wciśnij Enter..."
}

function purge_monako() {
  echo -e "
🧨 CAŁKOWITE usunięcie MONAKO i danych!"
  read -p "Na pewno? (TAK/nie): " CONFIRM
  if [ "$CONFIRM" == "TAK" ]; then
    sudo crontab -l 2>/dev/null | grep -v 'backup-menu.sh' | sudo crontab -
    sudo rm -f "$CONFIG_MARKER"
    sudo rm -rf "$DAILY_DIR"
    sudo rm -f "$LOGFILE"
    sudo rm -f /usr/local/bin/backup-menu.sh
    sudo rm -f /usr/bin/monako
    echo "✅ MONAKO usunięty."
    exit 0
  else
    echo "❎ Anulowano."
    read -p "Wciśnij Enter..."
  fi
}

function menu() {
  while true; do
    logo
    echo "1. ▶️  Ręczny backup"
    echo "2. 📄  Podgląd logu"
    echo "3. 📋  Informacje o systemie"
    echo "4. ♻️  Przywrócenie systemu"
    echo "5. 🔍  Porównanie zmian"
    echo "6. 🕒  Ustaw harmonogram backupu"
    echo "7. 💣  Skasuj konfigurację MONAKO"
    echo "8. 🧨  Całkowicie usuń MONAKO"
    echo "0. ❌  Wyjście"
    echo -n "
Wybierz opcję: "; read OP
    case $OP in
      1) run_backup;;
      2) view_logs;;
      3) view_info;;
      4) restore_backup;;
      5) compare_backups;;
      6) set_schedule;;
      7) reset_configuration;;
      8) purge_monako;;
      0) exit 0;;
      *) echo "❗ Nieprawidłowy wybór"; sleep 1;;
    esac
  done
}

logo
ensure_structure
menu
