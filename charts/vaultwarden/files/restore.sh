#!/bin/sh
# Restores a backup archive into the Vaultwarden data folder.
#
# Run it with the Deployment scaled to 0 (see the chart README). Usage:
#   restore.sh [archive]      default: the most recent archive in BACKUP_DIR
#
# Nothing is deleted: the current files are moved to
# $DATA_FOLDER/.pre-restore-<timestamp>/ before extraction.
set -eu
umask 077

DATA_FOLDER="${DATA_FOLDER:-/data}"
BACKUP_DIR="${BACKUP_DIR:-/backup}"

fail() { echo "restore: $*" >&2; exit 1; }

if [ "$#" -gt 0 ]; then
  archive="$1"
else
  # Globs expand sorted: the last match is the most recent archive.
  archive=""
  for candidate in "$BACKUP_DIR"/vaultwarden-[0-9]*T[0-9]*Z.tar.gz; do
    [ -e "$candidate" ] && archive="$candidate"
  done
  [ -n "$archive" ] || fail "no archive in $BACKUP_DIR"
fi
[ -f "$archive" ] || fail "archive '$archive' not found"
tar -tzf "$archive" | grep -qx 'db.sqlite3' || fail "'$archive' is not a Vaultwarden backup (no db.sqlite3)"

aside="$DATA_FOLDER/.pre-restore-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$aside"
for item in db.sqlite3 db.sqlite3-wal db.sqlite3-shm rsa_key.pem attachments sends config.json; do
  if [ -e "$DATA_FOLDER/$item" ]; then
    mv "$DATA_FOLDER/$item" "$aside/"
  fi
done

tar -xzf "$archive" -C "$DATA_FOLDER"
echo "restore: restored $archive into $DATA_FOLDER; previous files in $aside"
