#!/bin/sh
# Consistent backup of a Vaultwarden data folder.
#
# `vaultwarden backup` snapshots the live database with VACUUM INTO over a
# read-only connection: a transactionally consistent copy, unlike a copy of
# db.sqlite3 while its WAL is being written. The snapshot, the RSA key that
# signs sessions, attachments, sends and config.json go into one archive.
# icon_cache is left out: it is rebuilt on demand.
#
# Environment: DATA_FOLDER (default /data), BACKUP_DIR (default /backup),
# RETENTION (archives kept, default 14).
set -eu
umask 077

DATA_FOLDER="${DATA_FOLDER:-/data}"
BACKUP_DIR="${BACKUP_DIR:-/backup}"
RETENTION="${RETENTION:-14}"

fail() { echo "backup: $*" >&2; exit 1; }

case "$RETENTION" in
  ''|*[!0-9]*|0) fail "RETENTION must be a positive integer, got '$RETENTION'" ;;
esac
[ -f "$DATA_FOLDER/db.sqlite3" ] || fail "no database at $DATA_FOLDER/db.sqlite3"
[ -w "$BACKUP_DIR" ] || fail "$BACKUP_DIR is not writable by uid $(id -u)"

out="$(/vaultwarden backup)" || fail "vaultwarden backup failed: $out"
snapshot="$(printf '%s\n' "$out" | sed -n "s/^Backup to '\(.*\)' was successful\$/\1/p")"
[ -n "$snapshot" ] && [ -s "$snapshot" ] || fail "no snapshot reported: $out"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$BACKUP_DIR/vaultwarden-$stamp.tar.gz"
tmp="$BACKUP_DIR/.vaultwarden-$stamp.tar.gz.tmp"
trap 'rm -f "$snapshot" "$tmp"' EXIT

set -- "${snapshot#"$DATA_FOLDER"/}"
for item in rsa_key.pem attachments sends config.json; do
  [ -e "$DATA_FOLDER/$item" ] && set -- "$@" "$item"
done

# The snapshot is stored as db.sqlite3: restoring is a plain extraction.
tar -C "$DATA_FOLDER" \
  --transform "s|^${1}\$|db.sqlite3|" \
  -czf "$tmp" "$@"

tar -tzf "$tmp" | grep -qx 'db.sqlite3' || fail "archive has no db.sqlite3"
if [ -e "$DATA_FOLDER/rsa_key.pem" ]; then
  tar -tzf "$tmp" | grep -qx 'rsa_key.pem' || fail "archive has no rsa_key.pem"
fi
mv "$tmp" "$archive"
echo "backup: wrote $archive ($(wc -c < "$archive") bytes)"

# Retention: globs expand sorted, and UTC timestamps sort chronologically,
# so the oldest archives come first.
set -- "$BACKUP_DIR"/vaultwarden-[0-9]*T[0-9]*Z.tar.gz
excess=$(($# - RETENTION))
for old in "$@"; do
  [ "$excess" -gt 0 ] || break
  rm -f "$old"
  echo "backup: removed ${old##*/} (retention $RETENTION)"
  excess=$((excess - 1))
done
