#!/bin/bash

# Setzen Sie die Konfiguration
ALSA_OUTPUT_DEVICE="hw:Intel"
NQPTP_REPO="https://github.com/mikebrady/nqptp.git"
SHAIRPORT_SYNC_REPO="https://github.com/mikebrady/shairport-sync.git"

# Setzen Sie das Arbeitsverzeichnis
WORK_DIR="$HOME/shairport-instupdater"
mkdir -p "$WORK_DIR"

# Funktion zur Fehlerbehandlung
function error_check {
  if [ $? -ne 0 ]; then
    echo "$1: Ein Fehler ist aufgetreten. Bitte überprüfen Sie die Ausgabe oben."
    exit 1
  fi
}

# Aktualisieren Sie das System
echo "Aktualisieren des Systems..."
sudo apt update
error_check "Systemaktualisierung (apt update)"
sudo apt upgrade -y
error_check "Systemaktualisierung (apt upgrade)"

# Installieren Sie die benötigten Werkzeuge und Bibliotheken
echo "Installieren der benötigten Werkzeuge und Bibliotheken..."
sudo apt install -y build-essential git autoconf automake libtool libpopt-dev libconfig-dev libasound2-dev avahi-daemon libavahi-client-dev libssl-dev libsoxr-dev libplist-dev libsodium-dev libavutil-dev libavcodec-dev libavformat-dev uuid-dev libgcrypt-dev xxd
error_check "Installation der benötigten Werkzeuge und Bibliotheken"

# Wechseln Sie in das Arbeitsverzeichnis
cd "$WORK_DIR"
error_check "Wechsel in das Arbeitsverzeichnis"

# Sichern Sie die bestehende Konfigurationsdatei, wenn sie vorhanden ist
echo "Sichern der bestehenden Konfigurationsdatei..."
if [ -f "/etc/shairport-sync.conf" ]; then
  cp /etc/shairport-sync.conf "$WORK_DIR/shairport-sync.conf.backup"
  error_check "Sicherung der bestehenden Konfigurationsdatei"
fi

echo "Klonen/Aktualisieren und Installieren des NQPTP-Repositories..."
if [ -d "nqptp" ]; then
  if systemctl --quiet is-active nqptp; then
    echo "Stoppe NQPTP-Dienst vor der Aktualisierung..."
    sudo systemctl stop nqptp
  fi
  cd nqptp
  git pull
  error_check "Aktualisierung des NQPTP-Repositories"
else
  git clone $NQPTP_REPO
  error_check "Klonen des NQPTP-Repositories"
  cd nqptp
fi

# Fügen Sie die fehlenden Schritte hier ein
autoreconf -fi
error_check "Ausführen von autoreconf für NQPTP"
./configure --with-systemd-startup
error_check "Konfigurieren von NQPTP"
make
error_check "Kompilieren von NQPTP"
sudo make install
error_check "Installieren von NQPTP"


# Wechseln Sie zurück in das Arbeitsverzeichnis
cd "$WORK_DIR"
error_check

echo "Klonen/Aktualisieren und Installieren des Shairport Sync-Repositories..."
if [ -d "shairport-sync" ]; then
  if systemctl --quiet is-active shairport-sync; then
    echo "Stoppe Shairport Sync-Dienst vor der Aktualisierung..."
    sudo systemctl stop shairport-sync
  fi
  cd shairport-sync
  git pull
  error_check "Aktualisierung des Shairport Sync-Repositories"
else
  git clone $SHAIRPORT_SYNC_REPO
  error_check "Klonen des Shairport Sync-Repositories"
  cd shairport-sync
fi

NEW_COMMIT_SHAIRPORT=$(git rev-parse HEAD)
error_check "Abrufen des neuesten Commit-Hashes für Shairport Sync"
if [ "$NEW_COMMIT_SHAIRPORT" != "$(cat "$WORK_DIR/last_commit_shairport.txt" 2>/dev/null)" ]; then
  echo "$NEW_COMMIT_SHAIRPORT" > "$WORK_DIR/last_commit_shairport.txt"
  autoreconf -fi
  error_check "Ausführen von autoreconf für Shairport Sync"
  ./configure --sysconfdir=/etc --with-alsa --with-soxr --with-avahi --with-ssl=openssl --with-systemd --with-airplay-2
  error_check "Konfigurieren von Shairport Sync"
  make
  error_check "Kompilieren von Shairport Sync"
  sudo make install
  error_check "Installieren von Shairport Sync"
fi
cd ..

echo "Kopieren und Anpassen der Beispielkonfigurationsdatei..."
# sudo cp shairport-sync/scripts/shairport-sync.conf.sample /etc/shairport-sync.conf
sudo cp "$WORK_DIR/shairport-sync/scripts/shairport-sync.conf" /etc/shairport-sync.conf

error_check "Kopieren der Beispielkonfigurationsdatei"
sudo sed -i "s|//\s*output_device = \"default\".*|output_device = \"$ALSA_OUTPUT_DEVICE\";|g" /etc/shairport-sync.conf

error_check "Setzen des ALSA-Ausgabegerätes"

echo "Überprüfen und Starten des Shairport Sync-Dienstes..."
if systemctl --quiet is-active shairport-sync; then
  sudo systemctl restart shairport-sync
  error_check "Neustart des Shairport Sync-Dienstes"
else
  sudo systemctl enable shairport-sync
  error_check "Aktivieren des Shairport Sync-Dienstes"
  sudo systemctl start shairport-sync
  error_check "Starten des Shairport Sync-Dienstes"
fi

echo "Überprüfen und Starten des NQPTP-Dienstes..."
if systemctl --quiet is-active nqptp; then
  sudo systemctl restart nqptp
  error_check "Neustart des NQPTP-Dienstes"
else
  sudo systemctl enable nqptp
  error_check "Aktivieren des NQPTP-Dienstes"
  sudo systemctl start nqptp
  error_check "Starten des NQPTP-Dienstes"
fi

echo "Überprüfen des Status des NQPTP-Dienstes..."
systemctl is-active --quiet nqptp && echo "NQPTP ist aktiv" || (echo "Fehler: NQPTP ist nicht aktiv"; exit 1)

echo "Installation/Update abgeschlossen."
