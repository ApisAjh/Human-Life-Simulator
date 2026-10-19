# Human Life Simulator (MVP)

Game simulasi kehidupan manusia (React + Vite, Vercel Functions, Supabase). Seluruh logika ekonomi, waktu, dan reward berjalan di fungsi PostgreSQL `game_action` (atomik, baris dikunci) yang hanya bisa dipanggil lewat `api/game.js` dengan service role.

## 1. Supabase
1. Buat project di supabase.com.
2. SQL Editor → tempel isi `supabase/schema.sql` → Run (membuat tabel, RLS, fungsi, dan data awal).
   Lalu jalankan `supabase/v2.sql` (pakaian, furnitur, misi, achievement, sosial; menggantikan fungsi `game_action`).
   Terakhir jalankan `supabase/v3.sql` (tabel `character_stats` terpisah, kerja berdurasi, gaya rambut/mata). Urutan wajib: schema → v2 → v3.
3. Authentication → Providers → Email aktif (untuk uji cepat, matikan "Confirm email").
4. Settings → API: salin Project URL, anon key, dan service_role key.

## 2. Lokal
```
npm install
cp .env.example .env.local   # isi semua nilai
npm i -g vercel && vercel dev  # menjalankan frontend + /api
```
(`npm run dev` hanya frontend; endpoint `/api/game` butuh `vercel dev`.)

## 3. GitHub & Vercel
```
git init && git add . && git commit -m "init"
git remote add origin <url-repo> && git push -u origin main
```
Vercel → Add New Project → import repo (preset Vite otomatis: build `npm run build`, output `dist`).
Isi Environment Variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`. Deploy.

## 4. Checklist uji manual
- Daftar → karakter terbuat sekali; refresh, data tetap.
- Beli makanan → saldo turun, inventaris naik; beri makan → lapar naik.
- Klik beli/kerja berulang cepat → tidak ada reward ganda (cooldown + kunci baris).
- Tidur → bangun → energi naik; tutup tab saat tidur, buka lagi → masih tidur.
- Akun lain tidak bisa melihat/mengubah data akun ini.

## 5. Telegram Mini App
1. BotFather → `/newbot` → simpan token ke `TELEGRAM_BOT_TOKEN`.
2. Isi `TELEGRAM_WEBHOOK_SECRET` (acak), `TELEGRAM_LOGIN_SECRET` (acak panjang), `APP_URL` di Vercel, lalu redeploy.
3. Pasang webhook (sekali):
```
curl "https://api.telegram.org/bot<TOKEN>/setWebhook" -d "url=<APP_URL>/api/telegram-webhook" -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>"
```
4. Kirim `/start` ke bot → tekan tombol Main. (Opsional: BotFather → `/newapp` atau Menu Button ke `APP_URL`.)

## 6. Checklist tambahan
- Misi: lakukan aksi → progres naik; Klaim dua kali → ditolak.
- Hadiah harian: klaim dua kali di hari yang sama → ditolak.
- Kamar: beli furnitur → Pasang/Lepas; pakaian → Pakai.
- Sosial: tukar kode teman, kirim makanan, cek papan peringkat (hanya nama & level).
- Telegram: buka dari bot → langsung masuk tanpa login; initData palsu → 401.

## Checklist v3
- Kerja: Mulai → hitung mundur → Ambil gaji (ditolak jika belum selesai/diklik dua kali); tutup tab saat bekerja lalu buka lagi → status tetap.
- Kamar → Gaya rambut/mata: berubah dan tetap setelah refresh.
- Misi "Jaga semua kebutuhan ≥ 50" naik hanya saat semua kebutuhan ≥ 50.
