#!/bin/bash
# =============================================================================
# Skrip ini dijalankan otomatis oleh entrypoint image postgres/postgis
# (mekanisme bawaan docker-entrypoint-initdb.d) HANYA saat direktori data
# Postgres (volume db_data) masih kosong -> otomatis "sekali saja" saat
# pertama kali stack dijalankan. Kalau volume db_data sudah ada isinya,
# skrip ini TIDAK akan dijalankan lagi walau file ini diubah.
#
# Membuat:
# - user + database Nextcloud (NEXTCLOUD_DB_*), tanpa extension apapun.
# - user + database GIS (GIS_DB_*), dengan extension postgis di-enable
#   HANYA pada database ini.
# =============================================================================
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
	CREATE USER "$NEXTCLOUD_DB_USER" WITH PASSWORD '$NEXTCLOUD_DB_PASSWORD';
	CREATE DATABASE "$NEXTCLOUD_DB_NAME" OWNER "$NEXTCLOUD_DB_USER";

	CREATE USER "$GIS_DB_USER" WITH PASSWORD '$GIS_DB_PASSWORD';
	CREATE DATABASE "$GIS_DB_NAME" OWNER "$GIS_DB_USER";
EOSQL

# PostGIS diaktifkan sebagai superuser di database GIS saja - database
# Nextcloud tidak pernah disentuh di sini.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$GIS_DB_NAME" <<-EOSQL
	CREATE EXTENSION IF NOT EXISTS postgis;
EOSQL
