# CaritaHub Health Station Lite

Versi standalone dan **offline** dari Health Station (branch `health-device` di
`caritahub-panti-jompo-staff-ops`). Petugas cukup mengetik nama, mengukur dengan
alat Bluetooth, lalu hasilnya disimpan di perangkat dan dicetak di printer
thermal bawaan **iMin**.

- Tanpa login, tanpa server, tanpa izin INTERNET di Android.
- Semua alat dari branch `health-device`: tensimeter, oksimeter, termometer,
  timbangan komposisi tubuh (IF_B8B), dan hand grip Squegg.
- Struk dicetak sebagai gambar hitam-putih selebar kertas (58 mm / 80 mm), jadi
  pratinjau di layar sama persis dengan hasil cetak.

## Alur (v1.1 — satu lansia, semua alat sekaligus)

1. **Beranda** — ketik nama lalu **Enter**. L/P, umur, tinggi opsional di baris
   yang sama (dipakai timbangan; default 60 tahun / 160 cm).
2. **Pengukuran paralel terpandu** — satu layar berisi kotak semua alat; strip
   panduan **Berdiri → Duduk → Genggam**:
   - *Berdiri*: timbang, sambil suhu & oksimeter dipasang bersamaan.
   - *Duduk tenang*: tensi.
   - *Genggam terakhir* (meremas menaikkan tensi), 3 kiri + 3 kanan, pindah
     tangan otomatis, tanpa dialog.
3. **Kunci otomatis per alat** — suhu: 1 bacaan; tensi: hasil akhir manset;
   oksimeter: 5 bacaan stabil (±1 %, ±3 bpm); timbangan: berat terkunci +
   analisa komposisi (atau 6 dtk); genggam: 6 remasan. Setelah terkunci, bacaan
   susulan diabaikan sampai **Ukur ulang**.
4. **Gerbang anti-bocor** — oksimeter & timbangan menahan bacaan sampai jari
   lansia sebelumnya dilepas / turun dari timbangan (atau alat diam 2 dtk).
   Tombol **Mulai** untuk paksa.
5. **Aksi per kotak** — Terima, Isi manual, Lewati / Batal lewati, Ukur ulang.
6. **Selesai otomatis** — saat semua alat terdaftar selesai atau dilewati:
   hitung mundur 3 dtk (Batalkan), simpan ke `health_records_v1.json`, struk
   masuk antrean cetak di latar belakang, kembali ke beranda siap lansia
   berikutnya. Simpan sebagian = ketuk Simpan dua kali.
7. **Antrean cetak** — gagal cetak tidak menghapus data; chip "N struk gagal ·
   Coba lagi" di beranda.
8. **Riwayat** — cari nama, buka hasil, cetak ulang, ekspor CSV (titik koma,
   desimal koma, kolom **Durasi (detik)**). Beranda menampilkan rata-rata
   durasi per lansia hari ini.

Pengaturan: **Simpan otomatis saat semua alat selesai** dan **Cetak otomatis**
bisa dimatikan.

## Tampilan v1.2

- **Tombol besar**: aksi di kotak alat ≥ 52 dp (ikon + label), seluruh kotak
  bisa diketuk untuk lembar pilihan (tombol 60 dp), tombol Mulai di beranda
  68 dp, bilah bawah 60 dp dengan cincin progres.
- **Avatar 3D lansia** (`lib/widgets/avatar3d.dart`): renderer kecil tanpa paket
  tambahan (permukaan sapuan & elipsoid, Gouraud, `Canvas.drawVertices`). Pose mengikuti
  langkah: berdiri di timbangan → duduk + manset lengan kiri → meremas dengan
  tangan yang aktif → selesai. Titik ukur menyala biru (sedang), oranye (lepas
  dulu), hijau (selesai). Bisa diputar dengan geser; ketuk dua kali untuk reset.
- **Grafik** (`lib/widgets/charts.dart`, zona di `lib/utils/health_zones.dart`):
  gauge zona per alat (batas normal = `HealthRanges`, BMI Kemenkes, genggam
  AWGS 2019: L < 28 kg, P < 18 kg), sparkline nadi oksimeter, kurva tenaga
  genggam live, ringkasan visual + tren per lansia di halaman hasil, grafik
  lansia per jam di beranda. Kategori hanya alat bantu baca, bukan diagnosis.
- `Motion.enabled = false` mematikan animasi terus-menerus untuk test/screenshot.

## v1.4 — Kunci alat & mode periksa Bluetooth

**Kunci alat** (Pengaturan → Alat Bluetooth, atau ikon Bluetooth di layar ukur):

| | Kunci MATI (bawaan) | Kunci NYALA |
|---|---|---|
| Nilai dari alat terdaftar | diterima | diterima |
| Pemancar alat lain sejenis | ditawarkan bila alat terdaftar tidak tersambung: **Pakai alat ini** (didaftarkan menggantikan) atau **Tolak** (diingat, tidak ditawarkan lagi) | diabaikan, tanpa tawaran |
| Daftar / ganti / hapus alat | boleh | ditolak sampai kunci dimatikan (mematikan perlu konfirmasi) |

- Alat terdaftar diberi 8 detik untuk tersambung sebelum alat lain ditawarkan;
  pindaian pencarian paling sering tiap 20 detik dan tidak saat alat sedang
  mengirim data. Satu tawaran sekaligus; tawaran hilang sendiri bila alat
  terdaftar tersambung lagi.
- Posyandu dengan beberapa meja/stasiun berdekatan: **nyalakan kunci** setelah
  semua alat didaftarkan, supaya alat meja sebelah tidak pernah ditawarkan.
- Daftar alat yang ditolak bisa dikosongkan: Pengaturan → "Tawarkan lagi".

**Mode periksa** (selama layar pengukuran terbuka, Android):

- Pindaian siklus penuh (`lowLatency`) di semua PHY yang didukung radio
  (termasuk iklan BLE 5).
- Kemampuan radio dibaca sekali per sesi (`getPhySupport`: PHY 2M / coded).
- Setelah alat tersambung: prioritas koneksi tinggi (interval koneksi
  terpendek) dan PHY 2M bila radio mendukung; dikembalikan ke normal saat
  keluar dari layar pengukuran.
- Frekuensi/kanal BLE tidak bisa dipaku dari aplikasi — chip Bluetooth memakai
  lompatan frekuensi adaptif (37 kanal data) yang justru menjaga sambungan
  tahan gangguan WiFi. Yang dipaku adalah **alatnya**: sambung langsung ke
  alamat alat terdaftar (+ kunci alat).

## v1.3.1 — avatar 3D baru

- Badan, lengan, dan kaki satu permukaan menerus (sapuan penampang elips di
  sepanjang kurva), bukan bola + tabung: tidak ada sambungan seperti manekin.
- Kepala satu permukaan dengan rahang, rambut uban bervolume bermotif sisiran
  (konde untuk perempuan, kumis untuk laki-laki), alis, kacamata, hidung, mata
  yang sesekali berkedip; kardigan berkerah V, kancing, manset rajut; tangan
  dengan ibu jari; sepatu bersol; kursi kayu berbantal.
- Kamera menyesuaikan pose (duduk diperbesar), pencahayaan lampu utama hangat +
  lampu isi sejuk + kilap; kursi/timbangan berganti di tengah gerakan.
- Lebih ringan dari v1.3.0 walau geometri ±3× lebih detail: mesh hanya dibangun
  saat pose berubah, badan digambar ulang hanya saat putarannya berubah, titik
  ukur yang berdenyut di lapisan terpisah.
- Uji tampilan di Impeller (simulator iOS):
  `fvm flutter test integration_test/avatar_view_test.dart -d <device>`.

## v1.3 — NIK & SATUSEHAT, QA 6 putaran

- **NIK (opsional)** di beranda; L/P dan umur terisi otomatis dari NIK. Struk
  tidak mencetak NIK, layar menampilkan `3201********0001`.
- **Ekspor SATUSEHAT (FHIR R4)** dari Riwayat (`.ndjson`, satu Bundle per
  pemeriksaan) atau dari halaman Hasil (`.json`). Aplikasi tetap offline; file
  dikirim dari komputer online dengan `docs/satusehat_upload.py`.
  Panduan & pemetaan LOINC: **[docs/SATUSEHAT.md](docs/SATUSEHAT.md)**.
- **Pengaturan → SATUSEHAT**: ID Organisasi, Lokasi, Nakes.
- Laporan QA (38 temuan diperbaiki): **[docs/QA_v1.3.md](docs/QA_v1.3.md)**.

## Alat yang dikenali (nama Bluetooth)

| Jenis | Model |
|---|---|
| Tensimeter | Yuwell BP-YE670D, Yuwell BP-YE670CR |
| Oksimeter | KS M6100P, Yuwell BO-YX110, Yuwell CM100 |
| Termometer | Yuwell HT-YHW, Bluetooth BP |
| Timbangan | IF_B8B (OneMed 825 / Senssun) |
| Kekuatan genggam | Squegg (`weixin-nini`) |

Daftarkan alat sekali di **Pengaturan → Alat Bluetooth → Kelola** (atau ikon
Bluetooth di layar pengukuran). Nyalakan hanya unit yang mau didaftarkan.

## Printer iMin

Memakai paket resmi [`imin_printer`](https://pub.dev/packages/imin_printer)
(SDK 1.0 untuk Android ≤ 11, SDK 2.0 untuk Android 13+).

- **Pengaturan → Printer iMin**: lebar kertas (58 mm untuk Swift/M2, 80 mm untuk
  D4/Falcon/Crane), nama lokasi di kepala struk, cetak otomatis, **Cek printer**,
  **Tes cetak**.
- Nilai di luar rentang normal diberi tanda `*` (rentang mengikuti
  `HealthUtils` di caritacore).

## Build

Flutter **3.41.1** (lihat `.fvmrc`).

```bash
fvm flutter pub get
fvm flutter test                      # unit + widget + QA (135 test, termasuk test/qa/)
fvm flutter test integration_test/flow_test.dart -d <device>   # alur lengkap
fvm flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
```

Screenshot & contoh struk (font asli):

```bash
fvm flutter test test/visual_test.dart --update-goldens   # hasil di test/goldens/
```

Tampilan alur per langkah (beranda + NIK → berdiri → genggam → selesai →
tersimpan → gerbang lansia berikutnya → hasil & tren → SATUSEHAT, layar meja &
genggam, plus struk):

```bash
fvm flutter test test_showcase/showcase_test.dart --update-goldens   # hasil di test_showcase/screens/
```

> Build release saat ini masih ditandatangani dengan debug key. Untuk distribusi
> resmi, tambahkan keystore perusahaan di `android/app/build.gradle.kts`.

## Asal kode

| File | Sumber |
|---|---|
| `lib/ble/measurement_session.dart` | Logika BLE dari `health_measurement_screen.dart` (branch `health-device`) |
| `lib/ble/health_device_models.dart` | `caritacore` health_parser_utils (mobile-core @ d22c334) |
| `lib/ble/weight_scale_parser.dart` | `health_station/utils/weight_scale_parser.dart` |
| `lib/widgets/*` | Kartu ukur, dialog Bluetooth, dialog genggam dari `health_station/widgets` |
| `packages/squegg_core` | `caritahub-kit-cores/squegg_core` @ 6cd297d (disalin karena repo privat) |

Tidak ada token atau kredensial di proyek ini. Kredensial SATUSEHAT hanya lewat
variabel lingkungan `SATUSEHAT_CLIENT_ID` / `SATUSEHAT_CLIENT_SECRET` di komputer
pengirim.
