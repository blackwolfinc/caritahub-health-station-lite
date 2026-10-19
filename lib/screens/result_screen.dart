import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:share_plus/share_plus.dart';

import '../app/sound.dart';
import '../app/theme.dart';
import '../data/app_settings.dart';
import '../data/record_store.dart';
import '../models/health_record.dart';
import '../printing/printer_service.dart';
import '../printing/receipt_content.dart';
import '../printing/receipt_renderer.dart';
import '../satusehat/satusehat_export.dart';
import '../utils/health_analysis.dart';
import '../utils/health_ranges.dart';
import '../utils/health_zones.dart';
import '../utils/nik.dart';
import '../widgets/after_save_dialogs.dart';
import '../widgets/analysis_card.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'measurement_screen.dart';

/// Hasil tersimpan + pratinjau struk persis seperti yang dicetak.
class ResultScreen extends StatefulWidget {
  final String recordId;
  final bool autoPrint;
  final bool justSaved;

  /// Setelah cetak pertama berhasil, tanya lanjut ukur lansia berikutnya.
  final bool askNextAfterPrint;

  const ResultScreen({
    super.key,
    required this.recordId,
    this.autoPrint = false,
    this.justSaved = false,
    this.askNextAfterPrint = false,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Uint8List? _png;
  bool _rendering = true;
  bool _printing = false;
  bool _autoPrintDone = false;
  bool _askedNext = false;
  String? _lastPrintError;

  HealthRecord? get _record => RecordStore.instance.byId(widget.recordId);

  int? _renderedPrintCount;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_render);
    RecordStore.instance.addListener(_onRecords);
    _render();
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_render);
    RecordStore.instance.removeListener(_onRecords);
    super.dispose();
  }

  /// Hasil bisa berubah dari luar (antrean cetak menaikkan jumlah cetak).
  void _onRecords() {
    if (!mounted) return;
    setState(() {});
    final r = _record;
    if (r != null && r.printCount != _renderedPrintCount) unawaited(_render());
  }

  Future<void> _render() async {
    final r = _record;
    if (r == null) return;
    _renderedPrintCount = r.printCount;
    if (_png != null) setState(() => _rendering = true);
    final settings = AppSettings.instance;
    final content = buildReceipt(r, locationName: settings.locationName);
    final png = await ReceiptRenderer.renderPng(content, paper: settings.paper);
    if (!mounted) return;
    setState(() {
      _png = png;
      _rendering = false;
    });
    if (widget.autoPrint && !_autoPrintDone && r.printCount == 0) {
      _autoPrintDone = true;
      unawaited(_print());
    }
  }

  Future<void> _print() async {
    final r = _record;
    final png = _png;
    if (r == null || png == null || _printing) return;
    setState(() {
      _printing = true;
      _lastPrintError = null;
    });
    final result = await PrinterService.instance.printReceipt(png);
    // Struk sudah keluar: catat walau petugas sudah meninggalkan layar,
    // supaya tidak tercetak ganda dari Riwayat.
    if (result.ok) {
      await RecordStore.instance.modify(
        r.id,
        (latest) => latest.copyWith(
          printCount: latest.printCount + 1,
          lastPrintedAt: DateTime.now(),
        ),
      );
    }
    Sound.play(result.ok ? Sfx.done : Sfx.error);
    if (!mounted) return;
    setState(() => _printing = false);
    if (result.ok) {
      showSnack(
        context,
        result.warning == null
            ? result.message
            : '${result.message} · ${result.warning}',
      );
      unawaited(_render()); // nomor cetak ulang untuk berikutnya
      if (widget.askNextAfterPrint && !_askedNext) {
        _askedNext = true;
        if (await showNextPersonDialog(context) && mounted) _nextPerson();
      }
    } else {
      setState(() => _lastPrintError = result.message);
    }
  }

  Future<void> _delete() async {
    final r = _record;
    if (r == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Hapus hasil ini?',
      message:
          'Hasil pemeriksaan ${r.profile.name} akan dihapus dari perangkat '
          'dan tidak bisa dikembalikan.',
      confirmLabel: 'Hapus',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    await RecordStore.instance.delete(r.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _editNik(HealthRecord r) async {
    final c = TextEditingController(text: r.profile.nik ?? '');
    String? error;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('NIK ${r.profile.name}'),
          content: TextField(
            key: const Key('nik_dialog_field'),
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 16,
            style: AppText.w600(18),
            decoration: InputDecoration(
              labelText: 'NIK 16 angka',
              errorText: error,
              helperText: 'Kosongkan untuk menghapus',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              key: const Key('nik_dialog_save'),
              onPressed: () {
                final v = Nik.normalize(c.text);
                final err = v.isEmpty ? null : Nik.validate(v);
                if (err != null) {
                  setLocal(() => error = err);
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    // Controller tidak di-dispose di sini: dialog masih beranimasi menutup.
    if (saved == null) return;
    // Dari versi terbaru: jangan menimpa jumlah cetak yang berubah saat dialog terbuka.
    await RecordStore.instance.modify(
      r.id,
      (latest) => latest.copyWith(
        profile: latest.profile.withNik(
          saved.isEmpty ? null : saved,
          saved.isEmpty ? null : Nik.decode(saved)?.birthDate,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _exportOne(HealthRecord r) async {
    final cfg = SatusehatConfig.fromSettings();
    final problems = SatusehatExport.problems(r, cfg);
    if (problems.isNotEmpty) {
      showSnack(
        context,
        'Belum siap SATUSEHAT: ${problems.join(', ')}',
        error: true,
      );
      return;
    }
    try {
      final file = await SatusehatExport.writeOne(r, cfg);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/fhir+json'),
      ], subject: 'SATUSEHAT Bundle ${r.id}');
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal ekspor: $e', error: true);
    }
  }

  void _nextPerson() =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  void _measureAgain(PersonProfile p) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MeasurementScreen(profile: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Data tidak ditemukan.')),
      );
    }
    final wide = context.isMedium;
    final preview = _buildPreview();
    final panel = _buildPanel(r);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hasil pemeriksaan'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete();
              if (v == 'again') _measureAgain(r.profile);
              if (v == 'nik') _editNik(r);
              if (v == 'satusehat') _exportOne(r);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'again',
                child: Text('Ukur ulang orang ini'),
              ),
              PopupMenuItem(value: 'nik', child: Text('Isi / ubah NIK')),
              PopupMenuItem(
                value: 'satusehat',
                child: Text('Ekspor SATUSEHAT (JSON)'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Hapus hasil',
                  style: TextStyle(color: AppColors.red),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 460,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: panel,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: preview),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  panel,
                  const Gap(16),
                  SizedBox(height: 640, child: preview),
                ],
              ),
      ),
    );
  }

  Widget _buildPanel(HealthRecord r) {
    final platformOk = PrinterService.instance.platformSupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.justSaved)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.greenSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.darkGreen,
                ),
                const Gap(10),
                Expanded(
                  child: Text(
                    'Tersimpan di perangkat ini',
                    style: AppText.w600(14, StatusInk.good),
                  ),
                ),
              ],
            ),
          ),
        if (widget.justSaved) const Gap(16),
        Text(r.profile.name, style: AppText.w700(22)),
        const Gap(2),
        Text(
          '${formatDateTime(r.createdAt)} · No. ${r.id}',
          style: AppText.w400(13, AppColors.grey4),
        ),
        const Gap(6),
        Text(
          r.printCount == 0
              ? 'Belum dicetak'
              : 'Sudah dicetak ${r.printCount}× · terakhir ${formatDateTime(r.lastPrintedAt!)}',
          style: AppText.w500(
            13,
            r.printCount == 0 ? StatusInk.low : StatusInk.good,
          ),
        ),
        const Gap(6),
        _SatusehatStatus(record: r, onFixNik: () => _editNik(r)),
        const Gap(20),
        if (_lastPrintError != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.redSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.print_disabled_rounded, color: AppColors.red),
                const Gap(10),
                Expanded(
                  child: Text(
                    '$_lastPrintError\nData tetap tersimpan — cetak ulang kapan saja dari Riwayat.',
                    style: AppText.w500(13, StatusInk.high),
                  ),
                ),
              ],
            ),
          ),
          const Gap(12),
        ],
        FilledButton.icon(
          key: const Key('print_button'),
          onPressed: (_printing || _rendering || _png == null) ? null : _print,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          icon: _printing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.print_rounded),
          label: Text(
            _printing
                ? 'Mencetak…'
                : r.printCount == 0
                ? 'Cetak catatan tes kesehatan'
                : 'Cetak ulang',
          ),
        ),
        if (!platformOk) ...[
          const Gap(8),
          Text(
            'Printer iMin hanya tersedia saat aplikasi berjalan di perangkat iMin.',
            style: AppText.w400(12, AppColors.grey4),
          ),
        ],
        const Gap(12),
        OutlinedButton.icon(
          key: const Key('next_person_button'),
          onPressed: _nextPerson,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Pemeriksaan berikutnya'),
        ),
        const Gap(20),
        AnalysisCard(record: r),
        const Gap(16),
        _buildSummary(r),
        _buildTrend(r),
      ],
    );
  }

  /// Posisi tiap hasil terhadap rentang normal.
  Widget _buildSummary(HealthRecord r) {
    final m = r.measurements;
    final best = [m.gripStrength.gripLeft, m.gripStrength.gripRight]
        .whereType<double>()
        .fold<double?>(null, (a, b) => a == null || b > a ? b : a);
    final hr = pulseOf(m);
    final t = m.tensimeter;
    final items = <(GaugeSpec, double, String)>[
      if (t.systolic != null)
        (HealthZones.systolic, t.systolic!.toDouble(), '${t.systolic} mmHg'),
      if (t.diastolic != null)
        (HealthZones.diastolic, t.diastolic!.toDouble(), '${t.diastolic} mmHg'),
      if (hr != null) (HealthZones.heartRate, hr.toDouble(), '$hr bpm'),
      if (m.pulseOximeter.spo2 != null)
        (
          HealthZones.spo2,
          m.pulseOximeter.spo2!,
          '${fmt0(m.pulseOximeter.spo2)} %',
        ),
      if (m.thermometer.temperature != null)
        (
          HealthZones.temperature,
          m.thermometer.temperature!,
          '${fmt1(m.thermometer.temperature)} °C',
        ),
      if (m.weightScale.bmi != null)
        (HealthZones.bmi, m.weightScale.bmi!, fmt1(m.weightScale.bmi)),
      if (best != null)
        (HealthZones.grip(r.profile.gender), best, '${fmt1(best)} kg'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      key: const Key('summary_card'),
      title: 'Ringkasan visual',
      subtitle: 'Posisi hasil terhadap rentang normal',
      child: Column(
        children: [
          for (final (spec, v, text) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RangeGauge(spec: spec, value: v, valueText: text),
            ),
        ],
      ),
    );
  }

  /// Tren beberapa kunjungan terakhir orang yang sama: NIK sama bila
  /// keduanya punya NIK (dua lansia senama tidak tercampur), selain itu
  /// nama sama.
  Widget _buildTrend(HealthRecord r) {
    final visits =
        RecordStore.instance.records
            .where(
              (x) =>
                  samePerson(x.profile, r.profile) &&
                  !x.createdAt.isAfter(r.createdAt),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final last = visits.length > 8 ? visits.sublist(visits.length - 8) : visits;
    final sys = [
      for (final v in last)
        if (v.measurements.tensimeter.systolic != null)
          (v.createdAt, v.measurements.tensimeter.systolic!.toDouble()),
    ];
    final dia = [
      for (final v in last)
        if (v.measurements.tensimeter.diastolic != null)
          (v.createdAt, v.measurements.tensimeter.diastolic!.toDouble()),
    ];
    final weight = [
      for (final v in last)
        if (v.measurements.weightScale.weight != null)
          (v.createdAt, v.measurements.weightScale.weight!),
    ];
    if (sys.length < 2 && weight.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SectionCard(
        key: const Key('trend_card'),
        title: 'Tren ${r.profile.name}',
        subtitle: '${last.length} kunjungan terakhir',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sys.length >= 2) ...[
              Text(
                'Tekanan darah (mmHg)',
                style: AppText.w600(13, AppColors.grey1),
              ),
              const Gap(8),
              TrendChart(
                series: [
                  TrendSeries('Sistolik', ZoneColors.danger, sys),
                  TrendSeries('Diastolik', AppColors.blueDenim, dia),
                ],
                // Rentang normal Kemenkes (PNPK Hipertensi 2021).
                normalBands: [
                  (
                    HealthRanges.minSystolic.toDouble(),
                    HealthRanges.maxSystolic.toDouble(),
                  ),
                  (
                    HealthRanges.minDiastolic.toDouble(),
                    HealthRanges.maxDiastolic.toDouble(),
                  ),
                ],
              ),
              const Gap(16),
            ],
            if (weight.length >= 2) ...[
              Text(
                'Berat badan (kg)',
                style: AppText.w600(13, AppColors.grey1),
              ),
              const Gap(8),
              TrendChart(
                series: [TrendSeries('Berat', const Color(0xFF8B6CD9), weight)],
                height: 130,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final paper = AppSettings.instance.paper;
    return Container(
      color: const Color(0xFFE9EBF1),
      child: _png == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Text(
                    'Pratinjau catatan tes kesehatan · kertas ${paper.label}',
                    style: AppText.w500(12, AppColors.grey4),
                  ),
                  const Gap(12),
                  Center(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: paper.dots * 0.9),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Image.memory(
                        _png!,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Kesiapan kirim ke SATUSEHAT untuk satu hasil.
class _SatusehatStatus extends StatelessWidget {
  final HealthRecord record;
  final VoidCallback onFixNik;
  const _SatusehatStatus({required this.record, required this.onFixNik});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final problems = SatusehatExport.problems(
          record,
          SatusehatConfig.fromSettings(),
        );
        final ok = problems.isEmpty;
        final nikIssue = problems.any((p) => p.startsWith('NIK'));
        return InkWell(
          key: const Key('satusehat_status'),
          onTap: nikIssue ? onFixNik : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  ok ? Icons.verified_outlined : Icons.info_outline_rounded,
                  size: 18,
                  color: ok ? AppColors.darkGreen : AppColors.orangeAction,
                ),
                const Gap(6),
                Expanded(
                  child: Text(
                    ok
                        ? 'Siap SATUSEHAT · NIK ${Nik.mask(record.profile.nik!)}'
                        : 'SATUSEHAT: ${problems.join(', ')}${nikIssue ? ' · ketuk untuk isi' : ''}',
                    style: AppText.w500(
                      13,
                      ok ? StatusInk.good : StatusInk.low,
                    ),
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

String _normName(String n) =>
    n.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Orang yang sama untuk grafik tren.
@visibleForTesting
bool samePerson(PersonProfile a, PersonProfile b) {
  final na = a.nik == null ? '' : Nik.normalize(a.nik!);
  final nb = b.nik == null ? '' : Nik.normalize(b.nik!);
  if (na.isNotEmpty && nb.isNotEmpty) return na == nb;
  return _normName(a.name) == _normName(b.name);
}
