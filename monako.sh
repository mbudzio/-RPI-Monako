#!/bin/bash

### =============================
###        MONAKO v0.2
###   RPI double HDD system
### =============================

BACKUP_DEVICE="/dev/sdb1"
MOUNT_POINT="/mnt/backup"
DAILY_DIR="$MOUNT_POINT/daily"
LOGFILE="/var/log/system-backup.log"

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
  echo -e "${NC}\n"
}

function ensure_structure() {
  echo -ne "🧪 Weryfikacja środowiska backupu..."
  sleep 1
  for i in {1..9}; do sleep 1; echo -n "."; done
  echo ""

  local status_ok=true

  if [ ! -d "$MOUNT_POINT" ]; then status_ok=false; fi
  if [ ! -d "$DAILY_DIR" ]; then status_ok=false; fi
  if [ ! -f "$LOGFILE" ]; then status_ok=false; fi

  if [ "$status_ok" = false ]; then
    echo "\n🔧 MONAKO wymaga inicjalnej konfiguracji."
    read -p "Czy chcesz ją przeprowadzić teraz? (T/N): " choice
    if [[ "$choice" == "T" || "$choice" == "t" ]]; then
      sudo mkdir -p "$DAILY_DIR"
      sudo touch "$LOGFILE"
      sudo chown $(whoami) "$LOGFILE"
      echo "✅ Utworzono brakujące elementy."
    else
      echo "❎ Przerwano konfigurację."
      exit 0
    fi
  else
    echo "✅ Weryfikacja zakończona. Wszystko OK."
    sleep 1
  fi
}

function mount_backup() {
  sudo mount "$BACKUP_DEVICE" "$MOUNT_POINT" 2>/dev/null
}

function unmount_backup() {
  sudo umount "$MOUNT_POINT" 2>/dev/null
}

function run_backup() {
  echo -e "\n▶️ Uruchamiam backup systemu...\n"
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

    echo "🔄 Kopiowanie danych (rsync z postępem):"
    sudo rsync -aAX --info=progress2 --delete \
      $LINK_OPT \
      --exclude="{/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,$MOUNT_POINT/*,/media/*,/lost+found}" \
      / "$DEST" | tee /tmp/monako-progress.log

    if [ $? -ne 0 ]; then
      echo "❌ BŁĄD: Backup nie powiódł się!"
      echo "✖ Backup zakończony błędem: $(date)" >> "$LOGFILE"
    else
      echo "Aktualizacja symlinka latest → $DEST"
      rm -f "$LINKDEST"
      ln -s "$DEST" "$LINKDEST"
      echo "✔️ Backup zakończony: $(date)"
    fi
    echo ""
  } >> "$LOGFILE" 2>&1

  unmount_backup
  echo -e "\n✅ Backup zakończony. Wciśnij Enter..."
  read
}

function view_logs() {
  echo -e "\n📄 Ostatnie 100 linii logu:\n"
  sudo tail -n 100 "$LOGFILE"
  echo -e "\nWciśnij Enter..."
  read
}

function view_info() {
  echo -e "\n📋 Informacje o MONAKO:
🔁 Cron: codziennie o 2:00
🧹 Czyszczenie starych kopii o 2:15
📁 Katalogi: $DAILY_DIR
🔗 Symlink: $DAILY_DIR/latest
📬 Powiadomienia e-mail po backupie
📦 Przyrostowy backup z link-dest
🆚 Postęp backupu w czasie rzeczywistym z rsync"
  echo -e "\nWciśnij Enter..."
  read
}

function restore_backup() {
  echo -e "\n⚠️ Przywrócenie backupu nadpisze system!"
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
  echo -e "\n📂 Backupy:"; ls -1 $DAILY_DIR | grep -E '^[0-9]{4}-' | sort
  echo -n "Data backupu do porównania z 'latest': "; read OLD
  OLD_DIR="$DAILY_DIR/$OLD"
  NEW_DIR="$DAILY_DIR/latest"
  OUTFILE="/tmp/monako-diff-$OLD-vs-latest.txt"
  if [ ! -d "$OLD_DIR" ]; then echo "❌ Brak: $OLD_DIR"; read; return; fi
  echo -e "\n🔍 Tworzę porównanie (symulacja)...\n"
  sudo rsync -aAXvn --delete --itemize-changes "$OLD_DIR/" "$NEW_DIR/" > "$OUTFILE"
  less "$OUTFILE"
  read -p "Wciśnij Enter..."
}

function set_schedule() {
  echo -n "🕒 Godzina backupu (HH:MM, np. 02:00): "; read TIME
  echo -n "📆 Dni backupu (np. * lub 1-5 lub 0,6): "; read DAYS
  CRON_LINE="${TIME:3:2} ${TIME:0:2} * * $DAYS /usr/local/bin/monako"
  (sudo crontab -l 2>/dev/null | grep -v 'monako'; echo "$CRON_LINE") | sudo crontab -
  echo "✅ Ustawiono harmonogram: $CRON_LINE"
  read -p "Wciśnij Enter..."
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
    echo "0. ❌  Wyjście"
    echo -n "\nWybierz opcję: "; read OP
    case $OP in
      1) run_backup;;
      2) view_logs;;
      3) view_info;;
      4) restore_backup;;
      5) compare_backups;;
      6) set_schedule;;
      0) exit 0;;
      *) echo "❗ Nieprawidłowy wybór"; sleep 1;;
    esac
  done
}

logo
ensure_structure
menu
