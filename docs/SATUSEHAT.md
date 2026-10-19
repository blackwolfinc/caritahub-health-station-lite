# Ekspor SATUSEHAT (FHIR R4)

Health Station Lite tetap **offline** (APK tanpa izin INTERNET). Hasil ukur
diekspor sebagai file FHIR R4, lalu dikirim ke SATUSEHAT oleh komputer/server
yang online memakai `docs/satusehat_upload.py` (atau backend/SiKlinik sendiri).

```
iMin (offline) ──ekspor .ndjson──▶ PC/server online ──satusehat_upload.py──▶ SATUSEHAT
                                   (cari IHS dari NIK, POST Bundle)
```

## 1. Siapkan sekali di aplikasi

**Pengaturan → SATUSEHAT**

| Isian | Contoh | Keterangan |
|---|---|---|
| ID Organisasi (IHS) | `10000004` | Organization ID dari portal SATUSEHAT |
| ID Lokasi SATUSEHAT | `ef011065-…` | Location ID ruang/pos pemeriksaan |
| Nama lokasi | Posyandu Lansia Melati | opsional, tampil sebagai `display` |
| ID Nakes (IHS Practitioner) | `N10000001` | petugas yang memeriksa |
| Nama nakes | Ns. Rina | opsional |

Awalan `Organization/`, `Location/`, `Practitioner/` dan spasi dibuang otomatis.

## 2. Saat pemeriksaan

- Isi **NIK** di beranda (opsional, tetapi **wajib bila hasil dikirim ke
  SATUSEHAT**). L/P dan umur terisi otomatis dari NIK.
- NIK diperiksa: 16 angka, kode provinsi 11–96, tanggal lahir ada di
  kalender, nomor urut bukan 0000.
- NIK lupa diisi? Halaman **Hasil → ⋮ → Isi / ubah NIK**.
- Privasi: struk **tidak** mencetak NIK; layar menampilkan `3201********0001`;
  NIK utuh hanya ada di file ekspor.

## 3. Ekspor

- **Riwayat → Ekspor → SATUSEHAT: belum diekspor** — semua hasil yang belum
  pernah diekspor, satu file `satusehat_YYYYMMDD_HHMM.ndjson` (satu Bundle per
  baris). Menu menampilkan jumlah yang siap kirim.
- **SATUSEHAT: semua (kirim ulang)** — termasuk yang sudah pernah diekspor.
- **Hasil → ⋮ → Ekspor SATUSEHAT (JSON)** — satu pemeriksaan.

Hasil yang **dilewati** (dengan alasan di notifikasi): pengaturan belum lengkap,
NIK kosong/tidak valid, tidak ada hasil ukur, atau nilai di luar batas wajar.

## 4. Kirim ke SATUSEHAT

Di komputer yang online (Python 3.8+, tanpa paket tambahan):

```bash
export SATUSEHAT_CLIENT_ID=...        # jangan ditulis di file/skrip
export SATUSEHAT_CLIENT_SECRET=...
python3 satusehat_upload.py satusehat_20261018_1930.ndjson --dry-run   # cek isi
python3 satusehat_upload.py satusehat_20261018_1930.ndjson --env stg   # uji di staging
python3 satusehat_upload.py satusehat_20261018_1930.ndjson --env prod  # produksi
```

Per Bundle skrip ini:

1. login `POST {base}/oauth2/v1/accesstoken?grant_type=client_credentials`
   (login ulang otomatis sekali bila token kedaluwarsa / 401);
2. mencari IHS pasien: `GET {base}/fhir-r4/v1/Patient?identifier=https://fhir.kemkes.go.id/id/nik|<NIK>`;
3. mengganti `subject` NIK menjadi `{"reference": "Patient/<IHS>"}`;
4. `POST {base}/fhir-r4/v1` (Bundle transaction).

Hasil per pemeriksaan ditulis ke `<file>.hasil.json` setelah **setiap** Bundle.
Yang sudah berhasil dicatat di `satusehat_terkirim.json`, sehingga menjalankan
ulang file yang sama **tidak** membuat Encounter/Observation ganda.

| `--env` | URL dasar |
|---|---|
| `dev` | https://api-satusehat-dev.dto.kemkes.go.id |
| `stg` (default) | https://api-satusehat-stg.dto.kemkes.go.id |
| `prod` | https://api-satusehat.kemkes.go.id |

## 5. Isi Bundle

Satu pemeriksaan = satu Bundle `transaction` (semua `fullUrl` berupa
`urn:uuid` v4, `request` = `POST <resourceType>`):

| Resource | Isi |
|---|---|
| Encounter | `identifier` `http://sys-ids.kemkes.go.id/encounter/{org}` = no. pemeriksaan; `status` finished; `statusHistory` arrived → in-progress → finished; `class` AMB (v3-ActCode); `participant` ATND → Practitioner; `location` → Location; `serviceProvider` → Organization; `period` mulai–selesai ukur |
| Condition | ICD-10 **Z00.0** *General medical examination* (pemeriksaan kesehatan rutin, bukan diagnosis penyakit), `encounter-diagnosis` |
| Observation | satu per nilai, `status` final, `performer` nakes, `effectiveDateTime` = waktu simpan |

Waktu ditulis UTC `yyyy-MM-ddTHH:mm:ss+00:00`.

### Pemetaan hasil ukur

| Alat | Nilai | LOINC | Satuan (UCUM) | Kategori |
|---|---|---|---|---|
| Tensimeter | Sistolik | 8480-6 | mm[Hg] | vital-signs |
| Tensimeter | Diastolik | 8462-4 | mm[Hg] | vital-signs |
| Tensimeter / oksimeter | Nadi | 8867-4 | beats/min (`/min`) | vital-signs |
| Oksimeter | SpO2 | 59408-5 + 2708-6 | % | vital-signs |
| Termometer | Suhu | 8310-5 | C (`Cel`) | vital-signs |
| Timbangan | Berat | 29463-7 | kg | vital-signs |
| Diisi petugas | Tinggi | 8302-2 | cm | vital-signs |
| Timbangan | IMT | 39156-5 | kg/m2 | exam (+ vital-signs) |
| Timbangan | Lemak tubuh | 41982-0 | % | exam |
| Hand grip | Genggam kiri / kanan (terbaik) | 83173-5 / 83174-3 | kgf | exam |

Aturan:

- Nadi dari tensimeter bila ada (diukur duduk tenang), selain itu dari oksimeter.
- **IMT, lemak tubuh, dan tinggi hanya diekspor bila tinggi benar-benar diisi.**
  IMT dari tinggi pengganti 160 cm tidak pernah dikirim.
- Angka dibulatkan sama dengan struk & CSV (1 desimal), jadi angka di
  SATUSEHAT sama dengan yang dicetak.
- Nilai di luar batas fisiologis (mis. sistolik > 260) membuat pemeriksaan
  dilewati, bukan dikirim.

## 6. Hasil validasi (QA putaran 5–6)

| Pemeriksa | Hasil |
|---|---|
| Aturan SATUSEHAT (`test/qa/r5_satusehat_rules.py`) + server tiruan | 40/40 Bundle diterima, 0 ditolak, kirim ulang menambah 0 |
| `fhir.resources` (R4B, struktur & tipe data) | 41/41 valid |
| HL7 FHIR Validator resmi 4.0.1 + terminologi tx.fhir.org | 0 galat struktur/terminologi; lihat catatan |

**Catatan validator HL7.** Validator resmi otomatis menerapkan profil
*vital signs* internasional HL7. Satu-satunya galat tersisa: profil itu meminta
tekanan darah sebagai **satu** Observation panel 85354-9 dengan komponen
sistolik/diastolik, sedangkan aplikasi ini mengirim **dua** Observation
terpisah (8480-6 dan 8462-4) seperti format SATUSEHAT. Format SATUSEHAT
dipertahankan dengan sengaja. Untuk IMT, kategori `vital-signs` ditambahkan
sebagai kategori kedua (kategori utama tetap `exam`), sehingga IMT lolos kedua
aturan. Peringatan `dom-6` (resource tanpa narasi) hanya saran *best practice*.

Jalankan ulang:

```bash
fvm flutter test test/qa/r5_satusehat_samples_test.dart test/qa/r6_stress_40_test.dart
python3 test/qa/r5_satusehat_rules.py build/satusehat_samples/*.json build/satusehat_samples/stress40.ndjson
python3 test/qa/r3_uploader_qa.py
```

> Sebelum produksi: uji sekali di **staging** dengan kredensial fasyankes
> sendiri, karena hanya server SATUSEHAT yang bisa memastikan ID Organisasi,
> Lokasi, Nakes, dan NIK pasien terdaftar.
