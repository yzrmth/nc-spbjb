# Nextcloud (Docker Compose) - workstation Windows/WSL2, akses LAN

Stack: `nextcloud:apache` + `postgis/postgis` (Postgres+PostGIS) + `redis` + `caddy`.

## 1. Setup pertama kali

1. Pastikan Docker Desktop terpasang dengan **WSL2 backend** aktif (Settings ->
   General -> "Use the WSL 2 based engine").
2. Cari IP LAN PC workstation kamu (`ipconfig` -> lihat adapter aktif, mis.
   `192.168.1.50`). IP ini harus **statis/reserved** (set DHCP reservation di
   router) supaya tidak berubah-ubah.
3. Ganti `192.168.1.50` di dua tempat:
   - `Caddyfile` (baris host block paling atas)
   - `.env` -> `NEXTCLOUD_TRUSTED_DOMAINS` dan `NEXTCLOUD_OVERWRITE_CLI_URL`
4. Copy `.env.example` jadi `.env`, isi semua password `changeme_*`:
   ```bash
   cp .env.example .env
   ```
   Ada 5 field password (`POSTGRES_SUPERUSER_PASSWORD`, `NEXTCLOUD_DB_PASSWORD`,
   `GIS_DB_PASSWORD`, `REDIS_PASSWORD`, `NEXTCLOUD_ADMIN_PASSWORD`) - jangan
   dibiarkan `changeme_...`. Generate password acak yang kuat untuk MASING-MASING
   field (jalankan berkali-kali, tiap kali hasilnya beda, jangan reuse satu
   password buat semua):
   ```bash
   openssl rand -base64 24
   ```
   Copy hasilnya, tempel ke bagian setelah `=` di tiap baris `..._PASSWORD=`
   di `.env`.
5. Jalankan stack:
   ```bash
   docker compose up -d
   ```
6. Cek semua service sehat:
   ```bash
   docker compose ps
   docker compose logs -f nextcloud
   ```
7. Buka `https://192.168.1.50` dari browser di PC yang sama atau laptop di
   jaringan LAN yang sama. Browser akan warning sertifikat tidak dipercaya
   (karena `tls internal`/self-signed) - itu wajar, klik lanjutkan (atau
   import root CA Caddy kalau mau hilangkan warning, lihat dokumentasi Caddy
   `tls internal`).
8. Nextcloud akan auto-install pakai `NEXTCLOUD_ADMIN_USER` /
   `NEXTCLOUD_ADMIN_PASSWORD` dari `.env` (butuh beberapa menit di run pertama).
9. Setelah instalasi selesai, set Redis untuk memcache & locking (lihat
   perintah occ di bawah) - image Nextcloud sudah otomatis mengarahkan
   `REDIS_HOST`/`REDIS_HOST_PASSWORD` dari environment, tapi `memcache.local`
   dan `memcache.locking` perlu diaktifkan manual lewat `config.php`/occ.

## 2. Set trusted_domains

Sudah diisi lewat env var `NEXTCLOUD_TRUSTED_DOMAINS` di `.env` (dipakai saat
instalasi pertama). Untuk menambah/mengubah domain **setelah** instalasi,
edit `config.php` langsung lewat occ (env var tidak dibaca ulang setelah
instalasi awal):

```bash
docker compose exec -u www-data nextcloud php occ config:system:get trusted_domains
docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 1 --value=192.168.1.50
docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 2 --value=localhost
```

## 3. Contoh perintah occ yang sering dipakai

```bash
# Cek status instalasi & integritas
docker compose exec -u www-data nextcloud php occ status
docker compose exec -u www-data nextcloud php occ integrity:check-core

# Aktifkan Redis untuk memcache.local dan memcache.locking
docker compose exec -u www-data nextcloud php occ config:system:set memcache.local --value="\OC\Memcache\Redis"
docker compose exec -u www-data nextcloud php occ config:system:set memcache.locking --value="\OC\Memcache\Redis"
docker compose exec -u www-data nextcloud php occ config:system:set redis host --value="redis"
docker compose exec -u www-data nextcloud php occ config:system:set redis password --value="ISI_SAMA_DENGAN_REDIS_PASSWORD_DI_ENV"
docker compose exec -u www-data nextcloud php occ config:system:set redis port --value=6379 --type=integer
# Catatan: memcache.local biasanya lebih optimal pakai APCu (\OC\Memcache\APCu,
# sudah tersedia di image nextcloud:apache) karena APCu lokal ke tiap proses
# PHP tanpa round-trip network. Redis untuk memcache.local dipilih di sini
# sesuai requirement, tapi kalau nanti mau ganti ke APCu tinggal set ulang
# memcache.local ke \OC\Memcache\APCu.

# Jalankan cron manual / cek background jobs
docker compose exec -u www-data nextcloud php occ background:cron

# Scan file yang ditambahkan langsung ke storage (jarang perlu di setup ini)
docker compose exec -u www-data nextcloud php occ files:scan --all

# Maintenance mode saat maintenance/upgrade
docker compose exec -u www-data nextcloud php occ maintenance:mode --on
docker compose exec -u www-data nextcloud php occ maintenance:mode --off

# Tambah user
docker compose exec -u www-data nextcloud php occ user:add namauser
```

Opsional: aktifkan Nextcloud cron via system cron (bukan AJAX) supaya lebih
stabil - jalankan setiap 5 menit lewat scheduler Windows/WSL yang memanggil:
```bash
docker compose exec -u www-data nextcloud php occ background:cron
```
lalu set mode cron di UI: Settings -> Administration -> Basic settings ->
Background jobs -> "Cron".

## 4. Update Nextcloud

- **Naik satu versi mayor setiap kali**, jangan loncat (mis. 29 -> 30, bukan
  29 -> 32). Ini batasan resmi Nextcloud - upgrader akan menolak loncat versi.
- Urutan:
  1. Backup dulu (lihat bagian Backup di bawah).
  2. Ubah tag image di `docker-compose.yml`, mis. `nextcloud:30-apache` ->
     `nextcloud:31-apache`.
  3. ```bash
     docker compose pull nextcloud
     docker compose up -d nextcloud
     docker compose logs -f nextcloud
     ```
     Image akan otomatis menjalankan upgrader saat container start kalau versi
     lebih baru terdeteksi.
  4. Cek status: `docker compose exec -u www-data nextcloud php occ status`
  5. Cek juga kompatibilitas app pihak ketiga sebelum upgrade (Settings ->
     Apps), nonaktifkan app yang belum kompatibel dulu kalau perlu.
- Sub-minor version dalam mayor yang sama (mis. 30.0.2 -> 30.0.5) aman
  di-pull kapan saja, tidak perlu naik bertahap.

## 5. Backup

Tiga hal yang wajib dibackup bersamaan (harus konsisten satu waktu, idealnya
nyalakan maintenance mode dulu):

```bash
docker compose exec -u www-data nextcloud php occ maintenance:mode --on

# 1. Folder data user Nextcloud (volume nextcloud_data)
docker run --rm -v nc-spbjb_nextcloud_data:/data -v "$(pwd)/backup:/backup" \
  alpine tar czf /backup/nextcloud_data_$(date +%Y%m%d).tar.gz -C /data .

# 2. Folder config Nextcloud (volume nextcloud_config, berisi config.php)
docker run --rm -v nc-spbjb_nextcloud_config:/data -v "$(pwd)/backup:/backup" \
  alpine tar czf /backup/nextcloud_config_$(date +%Y%m%d).tar.gz -C /data .

# 3. Dump database (Nextcloud + GIS terpisah, atau sekaligus pakai pg_dumpall)
docker compose exec db pg_dump -U "$NEXTCLOUD_DB_USER" "$NEXTCLOUD_DB_NAME" \
  > backup/nextcloud_db_$(date +%Y%m%d).sql
docker compose exec db pg_dump -U "$GIS_DB_USER" "$GIS_DB_NAME" \
  > backup/gis_db_$(date +%Y%m%d).sql

docker compose exec -u www-data nextcloud php occ maintenance:mode --off
```

> Ganti `nc-spbjb_` di nama volume sesuai nama folder project kamu (default
> Compose memakai nama folder sebagai prefix) - cek nama pastinya dengan
> `docker volume ls`.

Restore: kebalikannya - `docker run ... tar xzf ...` ke volume yang sudah
dibuat ulang (kosong), lalu `psql -U ... -d ... < backup.sql` setelah database
kosong dibuat via init script/manual.

Simpan hasil backup di luar PC ini juga (external drive/cloud lain) - backup
yang cuma ada di mesin yang sama tidak melindungi dari kegagalan disk.

## 6. Cloudflare Tunnel (fase public) - placeholder

Belum diaktifkan. Saat mau menambahkan:

1. Buat tunnel di Cloudflare Zero Trust dashboard, catat token/credentials.
2. Tambahkan service baru di `docker-compose.yml`:
   ```yaml
     cloudflared:
       image: cloudflare/cloudflared:latest   # pin versi juga saat production
       restart: unless-stopped
       command: tunnel run
       environment:
         TUNNEL_TOKEN: ${CLOUDFLARE_TUNNEL_TOKEN}
       networks:
         - frontend
   ```
3. Tambahkan `CLOUDFLARE_TUNNEL_TOKEN` ke `.env`.
4. Arahkan public hostname di dashboard Cloudflare ke `http://caddy:443` (atau
   `http://nextcloud:80` langsung) - lihat komentar di `Caddyfile` untuk
   pertimbangan pakai Caddy vs langsung.
5. Tambahkan domain publik ke `NEXTCLOUD_TRUSTED_DOMAINS`, tambahkan blok host
   baru di `Caddyfile` untuk domain tsb (tanpa `tls internal`), dan update
   `NEXTCLOUD_OVERWRITE_CLI_URL` kalau domain public jadi akses utama.

## Struktur file

```
docker-compose.yml   # definisi semua service
.env.example          # template variabel & password (copy ke .env)
Caddyfile             # reverse proxy HTTPS untuk LAN
init-db/
  init-nextcloud-and-gis.sh   # provisioning database Nextcloud + GIS (sekali jalan)
```
