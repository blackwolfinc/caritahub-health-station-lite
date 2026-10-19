import 'package:intl/intl.dart';

import '../models/health_record.dart';
import '../utils/nik.dart';

/// Lansia yang pernah diperiksa di perangkat ini, ringkasan dari riwayat.
class PatientMatch {
  /// Identitas dari pemeriksaan terakhir.
  final PersonProfile profile;
  final DateTime lastVisit;
  final int visits;

  const PatientMatch({
    required this.profile,
    required this.lastVisit,
    required this.visits,
  });

  /// Identitas untuk pemeriksaan hari ini: umur dihitung ulang dari tanggal
  /// lahir (NIK) atau ditambah tahun yang sudah lewat sejak kunjungan terakhir.
  PersonProfile carriedTo(DateTime now) {
    final p = profile;
    int? age;
    if (p.birthDate != null) {
      age = Nik.ageOn(p.birthDate!, now);
    } else if (p.age != null) {
      age = p.age! + (now.difference(lastVisit).inDays ~/ 365.25);
    }
    return PersonProfile(
      name: p.name,
      gender: p.gender,
      age: age,
      heightCm: p.heightCm,
      nik: p.nik,
      birthDate: p.birthDate,
    );
  }
}

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Kunci orang: NIK bila ada, selain itu nama (sama dengan grafik tren).
String _personKey(PersonProfile p) {
  final nik = p.nik == null ? '' : Nik.normalize(p.nik!);
  return nik.isNotEmpty ? 'nik:$nik' : 'nama:${_norm(p.name)}';
}

/// Cari lansia di riwayat yang namanya cocok dengan [query] (minimal 2 huruf).
/// Urutan: awal nama cocok → awal salah satu kata → mengandung; lalu yang
/// terakhir diperiksa paling baru.
List<PatientMatch> findPatients(
  String query,
  Iterable<HealthRecord> records, {
  int limit = 4,
}) {
  final q = _norm(query);
  if (q.length < 2) return const [];
  final latest = <String, HealthRecord>{};
  final counts = <String, int>{};
  for (final r in records) {
    final key = _personKey(r.profile);
    counts[key] = (counts[key] ?? 0) + 1;
    final cur = latest[key];
    if (cur == null || r.createdAt.isAfter(cur.createdAt)) latest[key] = r;
  }
  int rank(String name) {
    final n = _norm(name);
    if (n.startsWith(q)) return 0;
    if (n.split(' ').any((w) => w.startsWith(q))) return 1;
    if (n.contains(q)) return 2;
    return -1;
  }

  final hits =
      [
        for (final e in latest.entries)
          if (rank(e.value.profile.name) >= 0)
            (
              rank(e.value.profile.name),
              PatientMatch(
                profile: e.value.profile,
                lastVisit: e.value.createdAt,
                visits: counts[e.key]!,
              ),
            ),
      ]..sort((a, b) {
        final byRank = a.$1.compareTo(b.$1);
        return byRank != 0 ? byRank : b.$2.lastVisit.compareTo(a.$2.lastVisit);
      });
  return [for (final h in hits.take(limit)) h.$2];
}

/// "Hari ini, 10.15" · "Kemarin, 09.02" · "3 hari lalu" · "12 Okt 2026".
String lastVisitLabel(DateTime t, DateTime now) {
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  final hm = DateFormat('HH.mm', 'id_ID').format(t);
  if (days <= 0) return 'Hari ini, $hm';
  if (days == 1) return 'Kemarin, $hm';
  if (days < 7) return '$days hari lalu';
  return DateFormat('d MMM yyyy', 'id_ID').format(t);
}
