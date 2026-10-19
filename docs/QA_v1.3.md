# QA v1.3.0 — 6 putaran

Tanggal: 18 Oktober 2026 · Versi: 1.3.0 (versionCode 5)

## Ringkasan

| | |
|---|---|
| Putaran QA | 6 (regresi, BLE, data & ekspor, tata letak, SATUSEHAT, ujung-ke-ujung) |
| Temuan diperbaiki | 38 (tidak ada temuan terbuka) |
| Test otomatis | 123 unit/widget lulus di Linux dan macOS · 17 tampilan · 1 integrasi di simulator iPhone 17 Pro · 2 skrip Python (aturan SATUSEHAT, pengunggah) |
| `flutter analyze` | 0 isu |
| SATUSEHAT | 40/40 Bundle diterima server tiruan berisi aturan SATUSEHAT, 41/41 valid FHIR R4; validator HL7 resmi: lihat [SATUSEHAT.md](SATUSEHAT.md#6-hasil-validasi-qa-putaran-56) |
| APK | `HealthStationLite-v1.3.0.apk`, versionName 1.3.0, **tanpa** izin INTERNET |

## Putaran 1 — regresi penuh

Seluruh test lama + test baru NIK & ekspor SATUSEHAT (`test/satusehat_test.dart`)
dan `flutter analyze`. Menjadi garis dasar putaran berikutnya.

## Putaran 2 — sesi ukur BLE (review independen)

Reviewer terpisah membaca `measurement_session.dart` dan membuktikan tiap
temuan dengan test yang gagal sebelum diperbaiki (`test/qa/r2_*`).

| # | Temuan | Perbaikan |
|---|---|---|
| 1 | Nilai lansia sebelumnya terulang di sesi baru (`lastValueStream` memutar ulang nilai terakhir) | pakai `onValueReceived` |
| 2 | Gerbang "lepas dulu" terbuka sebelum alat tersambung ulang | jeda 2 dtk dihitung sejak jalur data terpasang |
| 3 | Selesai otomatis menutup layar saat lembar/dialog terbuka | hitung mundur berhenti bila layar tertutup lembar |
| 4 | Getaran sensor di sekitar 2 kg = remasan ganda | histeresis mulai 3 kg / lepas 1 kg |
| 5 | Remasan dibuang bila sisi aktif sudah penuh | pindah sisi tanpa membuang nilai |
| 6 | IMT dari tinggi pengganti 160 cm tercetak sebagai nilai asli | IMT hanya dari tinggi yang diisi |
| 7 | Komposisi tubuh dari profil pengganti ikut tersimpan | dibuang saat simpan; profil dikirim ulang bila tinggi diubah |
| 8 | Timer kunci timbangan mengunci berat yang sudah goyah lagi | timer dibatalkan saat berat goyah / turun |
| 9 | Simpan sebagian ikut menyimpan nilai yang belum stabil | alat yang masih mengukur dikosongkan |
| 10 | Tensi NaN (SFLOAT 0x07FF) & komposisi absurd tersimpan | batas wajar `lib/utils/plausibility.dart` |
| 11 | "Terima" muncul padahal belum ada nilai (no-op) | tombol hanya bila ada data |
| 12 | Panggilan async setelah layar ditutup (bocor) | cek `_alive` setelah setiap `await` |
| 13 | Petunjuk & avatar menyebut alat yang tidak terdaftar | disaring ke alat terdaftar |

## Putaran 3 — data, cetak, ekspor (review independen)

`test/qa/r3_*`, `test/qa/r3_uploader_qa.py`.

| # | Temuan | Perbaikan |
|---|---|---|
| 14 | Dua simpan bersamaan saling menimpa file riwayat | antrean tulis berurutan + rollback |
| 15 | Satu baris rusak membuat semua riwayat hilang saat dibuka | muat per baris, salinan `.corrupt-`, banner peringatan |
| 16 | Halaman Hasil menulis salinan lama (printCount/NIK hilang) | `RecordStore.modify` dari versi terbaru |
| 17 | Struk sudah keluar tetapi gagal simpan printCount → cetak ganda saat ulang | status cetak dipisah dari status simpan |
| 18 | Id pemeriksaan bisa bentrok (detik yang sama) | 4 karakter acak aman + cek ganda |
| 19 | NIK dengan tanggal tidak ada (31/04) lolos | validasi tanggal kalender |
| 20 | Tanggal lahir abad salah (masa depan) | tahun masa depan → 19xx |
| 21 | Tanggal lahir lama tertinggal saat NIK dihapus | dihapus bersama NIK |
| 22 | L/P & umur dari NIK menimpa isian petugas | isi otomatis hanya bila belum diubah petugas |
| 23 | Angka CSV, struk, dan FHIR beda 0,1 | pembulatan sama di ketiganya |
| 24 | Sel CSV diawali `= + - @` bisa jadi rumus Excel | diberi awalan `'`; NIK sebagai teks |
| 25 | Kirim ulang file → Encounter ganda di SATUSEHAT | catatan `satusehat_terkirim.json` |
| 26 | Pengunggah berhenti total saat jaringan putus / token habis / file ber-BOM | status per Bundle, login ulang sekali, `utf-8-sig` |
| 27 | ID Organisasi ditempel lengkap dengan `Organization/` | awalan & spasi dibuang |

## Putaran 4 — tata letak (matriks layar)

`test/qa/r4_layout_matrix_test.dart`: 5 ukuran iMin (Swift 2, M2 Pro, D1,
Falcon, D4) × skala huruf 1,0 / 1,3 × 4 kelompok layar = 40 kombinasi.

| # | Temuan | Perbaikan |
|---|---|---|
| 28 | Bilah bawah overflow pada skala huruf 1,3 | lebar tombol simpan dibatasi, label menyesuaikan |
| 29 | Panel panduan overflow di layar pendek | teks panduan bisa digulir |
| 30 | Kartu panduan terpotong | tinggi minimum + avatar tinggi tetap |

Hasil: 40/40 tanpa overflow, tombol utama ≥ 48 dp.

## Putaran 5 — kesesuaian SATUSEHAT

| Pemeriksa | Hasil |
|---|---|
| Aturan dokumentasi SATUSEHAT + server tiruan (`r5_satusehat_rules.py`) | lulus |
| `fhir.resources` R4B | valid |
| HL7 FHIR Validator resmi 4.0.1 | hanya profil vital-signs internasional (lihat bawah) |

| # | Temuan | Perbaikan |
|---|---|---|
| 31 | IMT gagal profil BMI HL7 (kategori `vital-signs` tidak ada) | `vital-signs` ditambahkan sebagai kategori kedua; utama tetap `exam` |
| — | Profil BP HL7 meminta panel 85354-9 | **dipertahankan sesuai format SATUSEHAT** (sistolik & diastolik terpisah) — keputusan sadar, didokumentasikan |

## Putaran 6 — ujung ke ujung & rilis

- **Stres 40 lansia berturut-turut** (`test/qa/r6_stress_40_test.dart`):
  paket BLE mentah semua alat bersamaan, lansia sebelumnya masih menjepit
  oksimeter / berdiri di timbangan, termometer dilewati, genggam sebagian,
  tanpa tinggi, tanpa NIK. Lalu simpan → 40 struk → tutup/buka aplikasi →
  CSV → SATUSEHAT. Hasil: 0 nilai bocor/tertukar, 40 struk tepat sekali,
  riwayat utuh setelah dibuka ulang, 36 Bundle + 4 dilewati (tanpa NIK),
  identifier Encounter unik, ekspor "belum diekspor" berikutnya kosong.
  Waktu proses aplikasi ±2 dtk untuk 40 orang.
- **Integrasi di simulator iPhone 17 Pro** (`integration_test/flow_test.dart`):
  NIK → L/P & umur otomatis → nama + Enter → suhu manual → simpan → kembali ke
  beranda. Lulus.

| # | Temuan | Perbaikan |
|---|---|---|
| 32 | Riwayat tidak urut bila jam perangkat sempat mundur (dua judul "Hari ini") | simpan selalu di posisi urut waktu |
| 33 | Grafik tren mencampur dua lansia bernama sama | cocokkan NIK bila keduanya punya NIK |
| 34 | Menu ekspor menyebut "6 pemeriksaan" padahal 0 yang siap | tampil "N baru · M siap kirim" |
| 35 | Skrip QA pengunggah salah path setelah dipindah ke `test/qa` | diperbaiki |
| 36 | Tangkapan layar dokumentasi: bayangan tergambar garis hitam | bayangan asli di showcase |
| 37 | Showcase macet: antrean tulis test sebelumnya tertinggal | `debugReset` di awal tiap test |
| 38 | 8 test golden gagal di Mac (anti-aliasing huruf macOS beda 1–5 % dari Linux) | toleransi 6 % di luar Linux; 123/123 lulus di Mac |

Rilis: `flutter analyze` 0 isu · 123 test lulus · APK release v1.3.0
diperiksa `aapt2` (versionName 1.3.0, izin hanya Bluetooth/lokasi ≤ Android 11,
tanpa INTERNET).

## Yang belum bisa diuji di sini

- Kiriman ke server **SATUSEHAT staging** — perlu client ID/secret fasyankes.
  Langkahnya di [SATUSEHAT.md](SATUSEHAT.md#4-kirim-ke-satusehat).
- Alat Bluetooth fisik & printer iMin — sudah ditiru dengan paket mentah dan
  printer tiruan; uji lapangan tetap dianjurkan sebelum dipakai di posyandu.

## Lanjutan v1.3.1 – v1.4.0

| Versi | Perubahan | Uji |
|---|---|---|
| 1.3.1 | Avatar 3D digambar ulang (badan menyatu, rambut uban, wajah, kardigan, kursi); lebih ringan per frame | Matriks tata letak 40/40, golden, simulator iPhone (Impeller) |
| 1.3.1 | Antrean cetak menandai "selesai" setelah jumlah cetak tersimpan (sebelumnya bisa belum tertulis saat aplikasi ditutup) | `r6_stress_40_test` lulus di Linux & Mac |
| 1.4.0 | Kunci alat & tawaran alat pengganti; mode periksa Bluetooth | `r7_device_lock_test` (12 test: kunci nyala/mati, pakai/tolak, alat terdaftar aktif, masa tunggu, satu tawaran, banner di layar genggam ×1,3 & meja, pengaturan) |
| 1.4.0 | Penyelarasan koneksi tidak lagi menyentuh radio sebelum cek izin/adaptor selesai, dan galatnya ditangkap | suite penuh 135 test |
