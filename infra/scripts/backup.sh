#!/bin/sh
set -e

export PGPASSWORD=postgres

echo "[Backup] Esperando Postgresql..."
until pg_isready -h postgres -U postgres -d qams -q; do
  echo "[Backup] Postgresql no esta listo, reintentando en 3 segundos..."
  sleep 3
done
echo "[Backup] Postgresql esta listo"  

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

FILE=/backups/qams_${TIMESTAMP}.sql

echo "[Backup] Starting backup to $FILE"
pg_dump -h postgres -U postgres -d qams > "$FILE"

if [ -f "$FILE" ]; then
    SIZE=$(du -h "$FILE" | cut -f1)
    echo "[Backup] Backup completed to $FILE ($SIZE)"  
else
    echo "[Backup] Backup failed"
    exit 1
fi

find /backups -type f -name '*.sql' -o -name "*.dump" -mtime +7 -delete
echo "[Backup] Limpieza de backups > 7 dias completada"
