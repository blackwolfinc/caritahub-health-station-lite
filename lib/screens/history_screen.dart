import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../app/theme.dart';
import '../data/csv_export.dart';
import '../data/record_store.dart';
import '../models/health_record.dart';
import '../printing/receipt_content.dart';
import '../satusehat/satusehat_export.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _dayLabel(DateTime d, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    return DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(d);
  }

  Future<void> _export(List<HealthRecord> records) async {
    if (records.isEmpty) {
      showSnack(context, 'Belum ada data untuk diekspor.');
      return;
    }
    try {
      final file = await CsvExport.writeFile(records);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv'),
      ], subject: 'Data Health Station Lite');
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal ekspor: $e', error: true);
    }
  }

  Future<void> _exportSatusehat(List<HealthRecord> records) async {
    final cfg = SatusehatConfig.fromSettings();
    if (!cfg.isComplete) {
      showSnack(
        context,
        'Lengkapi di Pengaturan → SATUSEHAT: ${cfg.missing.join(', ')}',
        error: true,
      );
      return;
    }
    final batch = SatusehatExport.batch(records, cfg);
    if (batch.bundles.isEmpty) {
      showSnack(
        context,
        records.isEmpty
            ? 'Tidak ada pemeriksaan baru untuk diekspor.'
            : 'Tidak ada hasil yang siap: ${_reasons(batch)}',
        error: true,
      );
      return;
    }
    try {
      final file = await SatusehatExport.writeNdjson(batch);
      // Tandai sudah diekspor (ekspor berikutnya default hanya yang baru).
      await RecordStore.instance.markSatusehatExported({
        for (final b in batch.bundles)
          ((b['entry'] as List).first['resource']['identifier'] as List)
                  .first['value']
              as String,
      }, DateTime.now());
      if (!mounted) return;
      showSnack(
        context,
        '${batch.bundles.length} pemeriksaan siap dikirim ke SATUSEHAT'
        '${batch.skipped.isEmpty ? '' : ' · ${batch.skipped.length} dilewati (${_reasons(batch)})'}',
      );
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/fhir+ndjson'),
      ], subject: 'SATUSEHAT FHIR Bundle · Health Station Lite');
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal ekspor: $e', error: true);
    }
  }

  static String _reasons(SatusehatBatch b) {
    final counts = <String, int>{};
    for (final list in b.skipped.values) {
      for (final r in list) {
        counts[r] = (counts[r] ?? 0) + 1;
      }
    }
    return counts.entries.map((e) => '${e.key} ${e.value}').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    // DayTicker: "Hari ini"/"Kemarin" & rekap ikut berganti lewat tengah malam.
    return DayTicker(builder: (context, now) => _build(context, now));
  }

  Widget _build(BuildContext context, DateTime now) {
    return ListenableBuilder(
      listenable: RecordStore.instance,
      builder: (context, _) {
        final q = _search.text.trim().toLowerCase();
        final all = RecordStore.instance.records;
        final records = q.isEmpty
            ? all
            : all
                  .where((r) => r.profile.name.toLowerCase().contains(q))
                  .toList();

        final items = <Widget>[
          // Rekap hari ini (dulu di beranda) — hanya saat tidak mencari.
          if (q.isEmpty) ...[const Gap(12), _TodayCard(now: now)],
        ];
        String? currentDay;
        for (final r in records) {
          final day = _dayLabel(r.createdAt, now);
          if (day != currentDay) {
            currentDay = day;
            items.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Text(day, style: AppText.w600(13, AppColors.grey1)),
              ),
            );
          }
          items.add(_RecordTile(record: r));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text('Riwayat (${all.length})'),
            actions: [
              PopupMenuButton<String>(
                key: const Key('export_menu'),
                tooltip: 'Ekspor',
                onSelected: (v) => switch (v) {
                  'csv' => _export(records),
                  'ss_new' => _exportSatusehat(
                    records
                        .where((r) => r.satusehatExportedAt == null)
                        .toList(),
                  ),
                  _ => _exportSatusehat(records),
                },
                itemBuilder: (_) {
                  final cfg = SatusehatConfig.fromSettings();
                  final fresh = records.where(
                    (r) => r.satusehatExportedAt == null,
                  );
                  final ready = fresh
                      .where((r) => SatusehatExport.problems(r, cfg).isEmpty)
                      .length;
                  return [
                    const PopupMenuItem(
                      value: 'csv',
                      height: 56,
                      child: ListTile(
                        leading: Icon(Icons.table_chart_outlined),
                        title: Text('Ekspor CSV (Excel)'),
                      ),
                    ),
                    PopupMenuItem(
                      key: const Key('export_satusehat'),
                      value: 'ss_new',
                      height: 56,
                      child: ListTile(
                        leading: const Icon(Icons.health_and_safety_outlined),
                        title: const Text('SATUSEHAT: belum diekspor'),
                        subtitle: Text(
                          cfg.isComplete
                              ? '${fresh.length} baru · $ready siap kirim'
                              : 'Isi dulu Pengaturan → SATUSEHAT',
                        ),
                      ),
                    ),
                    const PopupMenuItem(
                      key: Key('export_satusehat_all'),
                      value: 'ss_all',
                      height: 56,
                      child: ListTile(
                        leading: Icon(Icons.restart_alt_rounded),
                        title: Text('SATUSEHAT: semua (kirim ulang)'),
                      ),
                    ),
                  ];
                },
                // Tinggi 48 dp: target sentuh minimum.
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.file_download_outlined,
                        color: AppColors.primary,
                      ),
                      const Gap(6),
                      Text(
                        'Ekspor',
                        style: AppText.w600(15, AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ),
              const Gap(8),
            ],
          ),
          body: MaxWidth(
            maxWidth: 820,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Cari nama',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
                // File riwayat rusak: petugas diberi tahu, bukan hanya
                // "Belum ada pemeriksaan".
                if (RecordStore.instance.corruptWarning != null)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: CorruptHistoryBanner(
                      key: Key('corrupt_banner'),
                      dismissible: true,
                    ),
                  ),
                Expanded(
                  child: records.isEmpty
                      ? Center(
                          child: Text(
                            q.isEmpty
                                ? 'Belum ada pemeriksaan tersimpan.'
                                : 'Tidak ada nama yang cocok.',
                            style: AppText.w400(14, AppColors.grey4),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: items,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecordTile extends StatelessWidget {
  final HealthRecord record;
  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ResultScreen(recordId: r.id)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.w600(15),
                      ),
                      const Gap(2),
                      Text(
                        summarize(r.measurements),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.w400(12, AppColors.grey1),
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat('HH.mm').format(r.createdAt),
                      style: AppText.w500(13, AppColors.grey1),
                    ),
                    const Gap(4),
                    Icon(
                      r.printCount > 0
                          ? Icons.print_rounded
                          : Icons.print_disabled_outlined,
                      size: 16,
                      color: r.printCount > 0
                          ? AppColors.darkGreen
                          : AppColors.orangeAction,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Durasi singkat Bahasa Indonesia: "18 detik", "2 mnt", "1 mnt 20 dtk".
String formatDurationId(int seconds) {
  final m = seconds ~/ 60, d = seconds % 60;
  if (m == 0) return '$d detik';
  if (d == 0) return '$m mnt';
  return '$m mnt $d dtk';
}

/// Jumlah lansia (orang berbeda) & pemeriksaan hari ini, rata-rata lama
/// periksa, dan sebaran per jam.
class _TodayCard extends StatelessWidget {
  final DateTime now;
  const _TodayCard({required this.now});

  @override
  Widget build(BuildContext context) {
    final today = RecordStore.instance.recordsOn(now);
    final people = RecordStore.countPeople(today);
    final durations = today.map((r) => r.durationSeconds).whereType<int>();
    final avg = durations.isEmpty
        ? null
        : durations.reduce((a, b) => a + b) ~/ durations.length;
    final counts = <int, int>{};
    for (final r in today) {
      counts[r.createdAt.hour] = (counts[r.createdAt.hour] ?? 0) + 1;
    }
    return SectionCard(
      key: const Key('today_card'),
      title: 'Hari ini',
      subtitle: today.isEmpty
          ? 'Belum ada lansia diperiksa'
          : '$people lansia · ${today.length} pemeriksaan'
                '${avg == null ? '' : ' · rata-rata ${formatDurationId(avg)}'}',
      child: HourlyBars(counts: counts, currentHour: now.hour, height: 96),
    );
  }
}
