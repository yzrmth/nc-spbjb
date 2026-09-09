# Deploy via GitHub: dari repo ini ke PC workstation

Alur: **push repo ini ke GitHub (private) → clone di workstation → `docker compose up -d`**.
Tidak ada image custom, Dockerfile, atau registry — cukup Git + Docker Compose.

File yang sudah disiapkan untuk alur ini:

| File | Fungsi |
|---|---|
| `.gitignore` | Mengecualikan `.env` (password asli), `backup/`, `CLAUDE.md` |
| `.gitattributes` | Paksa `*.sh` dan `Caddyfile` jadi LF supaya tidak rusak saat checkout di Windows |

---

## A. Sekali di mesin ini (sumber)

```bash
cd F:/nc-spbjb

git init
git add .
git status          # WAJIB cek: .env TIDAK boleh muncul di daftar
git commit -m "Initial commit: Nextcloud + PostGIS + Redis + Caddy stack"
```

Buat repo **private** di GitHub (config infra, bukan untuk publik), lalu:

```bash
git remote add origin git@github.com:<user>/<repo>.git   # atau URL https
git branch -M main
git push -u origin main
```

> Kalau `git status` menampilkan `.env`, **jangan commit**. Pastikan `.gitignore`
> ada di root dan berisi baris `.env`.

---

## B. Di PC workstation (target)

### 1. Prasyarat

- Docker Desktop terpasang, **WSL2 backend aktif**
  (Settings → General → "Use the WSL 2 based engine").
- Git terpasang.

### 2. Clone

```bash
git clone git@github.com:<user>/<repo>.git nc-spbjb
cd nc-spbjb
```

> Nama folder (`nc-spbjb`) dipakai Compose sebagai prefix nama volume
> (`nc-spbjb_nextcloud_data`, dst). Kalau folder diganti nama, sesuaikan juga
> perintah backup di `README.md` §5.

### 3. Isi `.env` (tidak ikut ter-clone — memang sengaja)

```bash
cp .env.example .env
```

Isi 5 field password, generate acak untuk MASING-MASING (jangan reuse):

```bash
openssl rand -base64 24
```

- `POSTGRES_SUPERUSER_PASSWORD`
- `NEXTCLOUD_DB_PASSWORD`
- `GIS_DB_PASSWORD`
- `REDIS_PASSWORD`
- `NEXTCLOUD_ADMIN_PASSWORD`

### 4. Set target deploy (IP LAN workstation)

Cari IP LAN statis workstation (`ipconfig`, set DHCP reservation di router mis.
`192.168.1.50`). Ganti di **3 tempat**:

- `Caddyfile` — host block paling atas
- `.env` → `NEXTCLOUD_TRUSTED_DOMAINS`
- `.env` → `NEXTCLOUD_OVERWRITE_CLI_URL` (mis. `https://192.168.1.50`)

### 5. Jalankan

```bash
docker compose config -q          # cek syntax
docker compose up -d
docker compose ps
docker compose logs -f nextcloud  # tunggu auto-install selesai (beberapa menit)
```

### 6. Post-install (occ)

Aktifkan Redis untuk cache & locking — lihat `README.md` §3:

```bash
docker compose exec -u www-data nextcloud php occ config:system:set memcache.local --value="\OC\Memcache\Redis"
docker compose exec -u www-data nextcloud php occ config:system:set memcache.locking --value="\OC\Memcache\Redis"
docker compose exec -u www-data nextcloud php occ config:system:set redis host --value="redis"
docker compose exec -u www-data nextcloud php occ config:system:set redis password --value="<sama dengan REDIS_PASSWORD di .env>"
docker compose exec -u www-data nextcloud php occ config:system:set redis port --value=6379 --type=integer
```

### 7. Akses

Buka `https://192.168.1.50` dari LAN. Browser warning sertifikat self-signed
(`tls internal`) — normal, klik lanjutkan.

---

## C. Update berikutnya

Di mesin sumber:

```bash
git add . && git commit -m "..." && git push
```

Di workstation:

```bash
git pull
docker compose up -d          # re-create service yang berubah
```

`.env` di workstation tidak tersentuh (gitignored). Kalau perubahan menyangkut
`init-db/` → tidak berpengaruh ke DB yang sudah jalan (script hanya jalan saat
volume `db_data` kosong).

Update versi Nextcloud sendiri: lihat `README.md` §4 (naik satu versi mayor
per langkah).
