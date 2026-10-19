import 'dart:math';

import 'package:flutter/foundation.dart';

import 'measurements.dart';

enum Gender {
  male,
  female;

  String get label => this == Gender.male ? 'Laki-laki' : 'Perempuan';
  String get short => this == Gender.male ? 'L' : 'P';

  static Gender? fromName(String? v) => switch (v) {
    'male' => Gender.male,
    'female' => Gender.female,
    _ => null,
  };
}

/// Identitas orang yang diukur. Hanya [name] yang wajib — sisanya opsional
/// dan dipakai timbangan untuk menghitung komposisi tubuh.
@immutable
class PersonProfile {
  final String name;
  final Gender? gender;
  final int? age;
  final double? heightCm;

  /// NIK 16 digit (opsional) — kunci pasien untuk SATUSEHAT.
  final String? nik;

  /// Tanggal lahir (dari NIK bila ada).
  final DateTime? birthDate;

  const PersonProfile({
    required this.name,
    this.gender,
    this.age,
    this.heightCm,
    this.nik,
    this.birthDate,
  });

  /// Nilai pengganti untuk perhitungan timbangan bila data tidak diisi.
  static const int defaultAge = 60;
  static const double defaultHeightCm = 160;

  int get effectiveAge => (age ?? defaultAge).clamp(10, 99);

  /// NIK baru beserta tanggal lahirnya (null = hapus keduanya).
  PersonProfile withNik(String? nik, DateTime? birthDate) => PersonProfile(
    name: name,
    gender: gender,
    age: age,
    heightCm: heightCm,
    nik: nik,
    birthDate: birthDate,
  );
  bool get isFemale => gender == Gender.female;

  Map<String, dynamic> toJson() => {
    'name': name,
    'gender': gender?.name,
    'age': age,
    'heightCm': heightCm,
    if (nik != null) 'nik': nik,
    if (birthDate != null)
      'birthDate': birthDate!.toIso8601String().substring(0, 10),
  };

  factory PersonProfile.fromJson(Map<String, dynamic>? j) => PersonProfile(
    name: (j?['name'] as String?) ?? '',
    gender: Gender.fromName(j?['gender'] as String?),
    age: (j?['age'] as num?)?.toInt(),
    heightCm: (j?['heightCm'] as num?)?.toDouble(),
    nik: j?['nik'] as String?,
    birthDate: DateTime.tryParse((j?['birthDate'] as String?) ?? ''),
  );
}

/// Satu hasil pengukuran yang disimpan di perangkat.
@immutable
class HealthRecord {
  final String id;
  final DateTime createdAt;
  final PersonProfile profile;
  final AllMeasurements measurements;
  final int printCount;
  final DateTime? lastPrintedAt;

  /// Kapan pengukuran dimulai (untuk durasi per lansia).
  final DateTime? startedAt;

  /// Terakhir diekspor ke file SATUSEHAT (bukan bukti terkirim).
  final DateTime? satusehatExportedAt;

  const HealthRecord({
    required this.id,
    required this.createdAt,
    required this.profile,
    required this.measurements,
    this.printCount = 0,
    this.lastPrintedAt,
    this.startedAt,
    this.satusehatExportedAt,
  });

  /// Lama pengukuran (detik), bila tercatat.
  int? get durationSeconds {
    final s = startedAt;
    if (s == null) return null;
    final d = createdAt.difference(s).inSeconds;
    return d >= 0 ? d : null;
  }

  /// ID pendek yang mudah dibaca: `YYMMDD-HHMM-XXXX`.
  static String newId(DateTime now) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final suffix = List.generate(
      4,
      (_) => chars[r.nextInt(chars.length)],
    ).join();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.year % 100)}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}-$suffix';
  }

  HealthRecord copyWith({
    PersonProfile? profile,
    AllMeasurements? measurements,
    int? printCount,
    DateTime? lastPrintedAt,
    DateTime? satusehatExportedAt,
  }) => HealthRecord(
    id: id,
    createdAt: createdAt,
    profile: profile ?? this.profile,
    measurements: measurements ?? this.measurements,
    printCount: printCount ?? this.printCount,
    lastPrintedAt: lastPrintedAt ?? this.lastPrintedAt,
    startedAt: startedAt,
    satusehatExportedAt: satusehatExportedAt ?? this.satusehatExportedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'profile': profile.toJson(),
    'measurements': measurements.toJson(),
    'printCount': printCount,
    'lastPrintedAt': lastPrintedAt?.toIso8601String(),
    'startedAt': startedAt?.toIso8601String(),
    if (satusehatExportedAt != null)
      'satusehatExportedAt': satusehatExportedAt!.toIso8601String(),
  };

  static HealthRecord? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final created = DateTime.tryParse((j['createdAt'] as String?) ?? '');
    if (id == null || created == null) return null;
    return HealthRecord(
      id: id,
      createdAt: created,
      profile: PersonProfile.fromJson(
        (j['profile'] as Map?)?.cast<String, dynamic>(),
      ),
      measurements: AllMeasurements.fromJson(
        (j['measurements'] as Map?)?.cast<String, dynamic>(),
      ),
      printCount: (j['printCount'] as num?)?.toInt() ?? 0,
      lastPrintedAt: DateTime.tryParse((j['lastPrintedAt'] as String?) ?? ''),
      startedAt: DateTime.tryParse((j['startedAt'] as String?) ?? ''),
      satusehatExportedAt: DateTime.tryParse(
        (j['satusehatExportedAt'] as String?) ?? '',
      ),
    );
  }
}
