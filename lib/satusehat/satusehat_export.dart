// Ekspor hasil ke format SATUSEHAT (HL7 FHIR R4).
//
// Satu pemeriksaan = satu Bundle `transaction`:
//   Encounter (AMB, finished) + Condition Z00.0 (alasan kunjungan: pemeriksaan
//   kesehatan umum) + Observation per besaran.
//
// Kode & satuan mengikuti dokumentasi SATUSEHAT (Rawat Inap/Rawat Jalan: tanda
// vital; Gizi: berat, tinggi, IMT) — lihat docs/SATUSEHAT.md. Aplikasi tetap
// offline: file ini dikirim oleh sistem yang online (mis. SiKlinik / backend
// CaritaHub / docs/satusehat_upload.py) yang mengganti NIK → IHS number pasien.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/health_analysis.dart' show pulseOf;
import '../data/app_settings.dart';
import '../models/health_record.dart';
import '../utils/nik.dart';
import '../utils/plausibility.dart';

class SatusehatConfig {
  final String orgId;
  final String locationId;
  final String locationName;
  final String practitionerId;
  final String practitionerName;

  const SatusehatConfig({
    required this.orgId,
    required this.locationId,
    this.locationName = '',
    required this.practitionerId,
    this.practitionerName = '',
  });

  factory SatusehatConfig.fromSettings([AppSettings? s]) {
    final a = s ?? AppSettings.instance;
    return SatusehatConfig(
      orgId: a.ssOrgId,
      locationId: a.ssLocationId,
      locationName: a.ssLocationName,
      practitionerId: a.ssPractitionerId,
      practitionerName: a.ssPractitionerName,
    );
  }

  /// Pengaturan yang belum diisi (menghalangi semua ekspor).
  List<String> get missing => [
    if (orgId.isEmpty) 'ID Organisasi',
    if (locationId.isEmpty) 'ID Lokasi',
    if (practitionerId.isEmpty) 'ID Nakes',
  ];

  bool get isComplete => missing.isEmpty;
}

/// Hasil ekspor banyak pemeriksaan.
class SatusehatBatch {
  final List<Map<String, dynamic>> bundles;
  final Map<String, List<String>> skipped; // id → alasan
  const SatusehatBatch(this.bundles, this.skipped);

  /// NDJSON: satu Bundle per baris.
  String get ndjson => bundles.map(jsonEncode).join('\n');
}

class SatusehatExport {
  SatusehatExport._();

  static const loinc = 'http://loinc.org';
  static const ucum = 'http://unitsofmeasure.org';
  static const obsCategory =
      'http://terminology.hl7.org/CodeSystem/observation-category';
  static const icd10 = 'http://hl7.org/fhir/sid/icd-10';

  static bool _validHeight(double? h) => h != null && h >= 50 && h <= 250;

  /// Tinggi yang benar-benar diukur/diisi (bukan nilai pengganti 160 cm).
  static double? heightOf(HealthRecord r) {
    final typed = r.measurements.others.height;
    if (_validHeight(typed)) return typed;
    if (_validHeight(r.profile.heightCm)) return r.profile.heightCm;
    return null;
  }

  /// Alasan sebuah pemeriksaan belum bisa dikirim (kosong = siap).
  static List<String> problems(HealthRecord r, SatusehatConfig c) => [
    ...c.missing.map((m) => '$m belum diisi di Pengaturan'),
    if ((r.profile.nik ?? '').isEmpty)
      'NIK kosong'
    else if (!Nik.isValid(r.profile.nik))
      'NIK tidak valid',
    ...implausible(r),
    // Tinggi dari isian profil saja belum dihitung sebagai hasil pemeriksaan.
    if (observations(r).every((o) => o.key == 'height')) 'Tidak ada hasil ukur',
  ];

  /// Format waktu SATUSEHAT: UTC dengan offset eksplisit, tanpa milidetik.
  static String time(DateTime t) =>
      '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(t.toUtc())}+00:00';

  /// UUID v4 deterministik dari [seed] supaya ekspor ulang menghasilkan
  /// fullUrl yang sama (mudah dilacak). Catatan: POST transaction selalu
  /// membuat resource baru — pencegahan kirim dobel ada di pengirim
  /// (docs/satusehat_upload.py mencatat yang sudah terkirim).
  static String uuid(String seed) {
    var h = 0xcbf29ce484222325;
    for (final c in utf8.encode(seed)) {
      h ^= c;
      h = (h * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    final rnd = Random(h);
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Daftar besaran yang diekspor: (kunci, kategori, coding, nilai, unit, kode UCUM).
  static List<SatusehatObs> observations(HealthRecord r) {
    final m = r.measurements;
    final out = <SatusehatObs>[];
    void add(
      String key,
      String cat,
      List<(String, String)> codes,
      num? v,
      String unit,
      String code,
    ) {
      if (v == null || (v is double && !v.isFinite)) return;
      out.add(SatusehatObs(key, cat, codes, v, unit, code));
    }

    final t = m.tensimeter;
    add(
      'sys',
      'vital-signs',
      [('8480-6', 'Systolic blood pressure')],
      t.systolic,
      'mm[Hg]',
      'mm[Hg]',
    );
    add(
      'dia',
      'vital-signs',
      [('8462-4', 'Diastolic blood pressure')],
      t.diastolic,
      'mm[Hg]',
      'mm[Hg]',
    );
    // Nadi: satu nilai yang sama dengan analisa & catatan cetak ([pulseOf]).
    add(
      'hr',
      'vital-signs',
      [('8867-4', 'Heart rate')],
      pulseOf(m),
      'beats/min',
      '/min',
    );
    add(
      'spo2',
      'vital-signs',
      [
        ('59408-5', 'Oxygen saturation in Arterial blood by Pulse oximetry'),
        ('2708-6', 'Oxygen saturation in Arterial blood'),
      ],
      m.pulseOximeter.spo2?.round(),
      '%',
      '%',
    );
    add(
      'temp',
      'vital-signs',
      [('8310-5', 'Body temperature')],
      _round(m.thermometer.temperature, 1),
      'C',
      'Cel',
    );
    add(
      'weight',
      'vital-signs',
      [('29463-7', 'Body weight')],
      _round(m.weightScale.weight, 1),
      'kg',
      'kg',
    );
    final h = heightOf(r);
    add(
      'height',
      'vital-signs',
      [('8302-2', 'Body height')],
      _round(h, 1),
      'cm',
      'cm',
    );
    // IMT & lemak tubuh hanya bila tinggi benar-benar diisi (bukan 160 cm pengganti).
    if (h != null) {
      add(
        'bmi',
        'exam',
        [('39156-5', 'Body mass index (BMI) [Ratio]')],
        _round(m.weightScale.bmi, 1),
        'kg/m2',
        'kg/m2',
      );
      // Kategori utama tetap "exam" (format SATUSEHAT); "vital-signs" sebagai
      // kategori kedua supaya juga lolos profil BMI HL7 internasional.
      if (out.isNotEmpty && out.last.key == 'bmi') {
        out[out.length - 1] = out.last.withExtraCategories(const [
          'vital-signs',
        ]);
      }
      add(
        'fat',
        'exam',
        [('41982-0', 'Percentage of body fat Measured')],
        _round(m.weightScale.bodyFatPercent, 1),
        '%',
        '%',
      );
    }
    add(
      'gripL',
      'exam',
      [('83173-5', 'Grip strength Hand - left Dynamometer')],
      _round(m.gripStrength.gripLeft, 1),
      'kgf',
      'kgf',
    );
    add(
      'gripR',
      'exam',
      [('83174-3', 'Grip strength Hand - right Dynamometer')],
      _round(m.gripStrength.gripRight, 1),
      'kgf',
      'kgf',
    );
    return out;
  }

  /// Pembulatan sama dengan struk & CSV (toStringAsFixed), supaya angka di
  /// SATUSEHAT tidak berbeda 0,1 dari yang dicetak.
  static double? _round(double? v, int d) {
    if (v == null || !v.isFinite) return null;
    return double.parse(v.toStringAsFixed(d));
  }

  static const _ranges = <String, (String, (double, double))>{
    'sys': ('Sistolik', Plausible.systolic),
    'dia': ('Diastolik', Plausible.diastolic),
    'hr': ('Nadi', Plausible.heartRate),
    'spo2': ('SpO2', Plausible.spo2),
    'temp': ('Suhu', Plausible.temperature),
    'weight': ('Berat', Plausible.weight),
    'height': ('Tinggi', Plausible.height),
    'bmi': ('BMI', Plausible.bmi),
    'fat': ('Lemak tubuh', Plausible.bodyFat),
    'gripL': ('Genggam kiri', Plausible.grip),
    'gripR': ('Genggam kanan', Plausible.grip),
  };

  /// Nilai di luar batas fisiologis (salah ketik/baca) — tidak boleh ke SATUSEHAT.
  static List<String> implausible(HealthRecord r) => [
    for (final o in observations(r))
      if (_ranges[o.key] case final range?
          when !Plausible.ok(o.value, range.$2))
        '${range.$1} ${o.value} tidak wajar',
  ];

  static Map<String, dynamic> _subject(HealthRecord r) => {
    // Referensi berbasis identifier (FHIR R4). Pengirim online mengganti
    // ini menjadi {"reference": "Patient/<IHS>"} lewat
    // GET /Patient?identifier=https://fhir.kemkes.go.id/id/nik|<NIK>.
    'identifier': {
      'system': Nik.system,
      'value': Nik.normalize(r.profile.nik ?? ''),
    },
    'display': r.profile.name,
  };

  /// Bundle transaction untuk satu pemeriksaan.
  static Map<String, dynamic> bundle(HealthRecord r, SatusehatConfig c) {
    final start = r.startedAt ?? r.createdAt;
    final end = r.createdAt.isBefore(start) ? start : r.createdAt;
    final encId = uuid('${r.id}/Encounter');
    final condId = uuid('${r.id}/Condition');
    final practitioner = {
      'reference': 'Practitioner/${c.practitionerId}',
      if (c.practitionerName.isNotEmpty) 'display': c.practitionerName,
    };
    final subject = _subject(r);

    final encounter = {
      'resourceType': 'Encounter',
      'identifier': [
        {
          'system': 'http://sys-ids.kemkes.go.id/encounter/${c.orgId}',
          'value': r.id,
        },
      ],
      'status': 'finished',
      'class': {
        'system': 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
        'code': 'AMB',
        'display': 'ambulatory',
      },
      'subject': subject,
      'participant': [
        {
          'type': [
            {
              'coding': [
                {
                  'system':
                      'http://terminology.hl7.org/CodeSystem/v3-ParticipationType',
                  'code': 'ATND',
                  'display': 'attender',
                },
              ],
            },
          ],
          'individual': practitioner,
        },
      ],
      'period': {'start': time(start), 'end': time(end)},
      'location': [
        {
          'location': {
            'reference': 'Location/${c.locationId}',
            if (c.locationName.isNotEmpty) 'display': c.locationName,
          },
        },
      ],
      'diagnosis': [
        {
          'condition': {
            'reference': 'urn:uuid:$condId',
            'display': 'General medical examination',
          },
          'use': {
            'coding': [
              {
                'system':
                    'http://terminology.hl7.org/CodeSystem/diagnosis-role',
                'code': 'DD',
                'display': 'Discharge diagnosis',
              },
            ],
          },
          'rank': 1,
        },
      ],
      'statusHistory': [
        {
          'status': 'arrived',
          'period': {'start': time(start), 'end': time(start)},
        },
        {
          'status': 'in-progress',
          'period': {'start': time(start), 'end': time(end)},
        },
        {
          'status': 'finished',
          'period': {'start': time(end), 'end': time(end)},
        },
      ],
      'serviceProvider': {'reference': 'Organization/${c.orgId}'},
    };

    final condition = {
      'resourceType': 'Condition',
      'clinicalStatus': {
        'coding': [
          {
            'system':
                'http://terminology.hl7.org/CodeSystem/condition-clinical',
            'code': 'active',
            'display': 'Active',
          },
        ],
      },
      'category': [
        {
          'coding': [
            {
              'system':
                  'http://terminology.hl7.org/CodeSystem/condition-category',
              'code': 'encounter-diagnosis',
              'display': 'Encounter Diagnosis',
            },
          ],
        },
      ],
      'code': {
        'coding': [
          {
            'system': icd10,
            'code': 'Z00.0',
            'display': 'General medical examination',
          },
        ],
      },
      'subject': subject,
      'encounter': {'reference': 'urn:uuid:$encId'},
      'recordedDate': time(end),
    };

    final entries = <Map<String, dynamic>>[
      _entry(encId, encounter),
      _entry(condId, condition),
    ];
    for (final o in observations(r)) {
      final id = uuid('${r.id}/Observation/${o.key}');
      entries.add(
        _entry(id, {
          'resourceType': 'Observation',
          'identifier': [
            {
              'system': 'http://sys-ids.kemkes.go.id/observation/${c.orgId}',
              'value': '${r.id}-${o.key}',
            },
          ],
          'status': 'final',
          'category': [
            for (final cat in [o.category, ...o.extraCategories])
              {
                'coding': [
                  {
                    'system': obsCategory,
                    'code': cat,
                    'display': cat == 'vital-signs' ? 'Vital Signs' : 'Exam',
                  },
                ],
              },
          ],
          'code': {
            'coding': [
              for (final (code, display) in o.codes)
                {'system': loinc, 'code': code, 'display': display},
            ],
          },
          'subject': subject,
          'performer': [practitioner],
          'encounter': {'reference': 'urn:uuid:$encId'},
          'effectiveDateTime': time(end),
          'issued': time(end),
          'valueQuantity': {
            'value': o.value,
            'unit': o.unit,
            'system': ucum,
            'code': o.ucum,
          },
        }),
      );
    }

    return {'resourceType': 'Bundle', 'type': 'transaction', 'entry': entries};
  }

  static Map<String, dynamic> _entry(
    String uuid,
    Map<String, dynamic> resource,
  ) => {
    'fullUrl': 'urn:uuid:$uuid',
    'resource': resource,
    'request': {'method': 'POST', 'url': resource['resourceType']},
  };

  static SatusehatBatch batch(List<HealthRecord> records, SatusehatConfig c) {
    final bundles = <Map<String, dynamic>>[];
    final skipped = <String, List<String>>{};
    for (final r in records) {
      final p = problems(r, c);
      if (p.isEmpty) {
        bundles.add(bundle(r, c));
      } else {
        skipped[r.id] = p;
      }
    }
    return SatusehatBatch(bundles, skipped);
  }

  static Future<File> writeNdjson(SatusehatBatch b) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = File('${dir.path}/satusehat_$stamp.ndjson');
    await file.writeAsString(b.ndjson.isEmpty ? '' : '${b.ndjson}\n');
    return file;
  }

  static Future<File> writeOne(HealthRecord r, SatusehatConfig c) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/satusehat_${r.id}.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(bundle(r, c)),
    );
    return file;
  }
}

class SatusehatObs {
  final String key;
  final String category;
  final List<(String, String)> codes;
  final num value;
  final String unit;
  final String ucum;

  /// Kategori tambahan sesudah [category] (kategori utama tidak berubah).
  final List<String> extraCategories;
  const SatusehatObs(
    this.key,
    this.category,
    this.codes,
    this.value,
    this.unit,
    this.ucum, [
    this.extraCategories = const [],
  ]);

  SatusehatObs withExtraCategories(List<String> extra) =>
      SatusehatObs(key, category, codes, value, unit, ucum, extra);
}
