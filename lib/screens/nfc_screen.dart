import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../app/nfc_reader.dart';
import '../app/sound.dart';
import '../app/theme.dart';
import '../widgets/common.dart';

/// Pembaca NFC untuk analisa kartu (e-KTP, kartu anggota, dsb.): tampilkan
/// semua data teknis yang bisa dibaca tanpa kunci. Tidak menulis ke kartu.
class NfcScreen extends StatefulWidget {
  const NfcScreen({super.key});

  @override
  State<NfcScreen> createState() => _NfcScreenState();
}

class _NfcScreenState extends State<NfcScreen> with WidgetsBindingObserver {
  final _scans = <NfcScan>[];
  StreamSubscription<NfcScan>? _sub;
  NfcStatus? _status;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = NfcReader.scans.listen((s) {
      HapticFeedback.mediumImpact();
      Sound.play(Sfx.card);
      if (mounted) setState(() => _scans.insert(0, s));
    }, onError: (_) {});
    unawaited(_begin());
  }

  bool _started = false;

  Future<void> _begin() async {
    final st = await NfcReader.status();
    var ok = _reading;
    if (st.enabled && !_started) {
      _started = true;
      ok = await NfcReader.start();
    }
    if (mounted) {
      setState(() {
        _status = st;
        _reading = st.enabled && ok;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // NFC bisa dinyalakan di Pengaturan Android lalu kembali ke sini.
    if (state == AppLifecycleState.resumed) unawaited(_begin());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    if (_started) unawaited(NfcReader.stop());
    super.dispose();
  }

  String get _json => const JsonEncoder.withIndent(
    '  ',
  ).convert([for (final s in _scans) _plain(s.data)]);

  /// Peta dari kanal platform → tipe JSON biasa.
  static Object? _plain(Object? v) => switch (v) {
    Map() => {for (final e in v.entries) '${e.key}': _plain(e.value)},
    List() => [for (final x in v) _plain(x)],
    _ => v,
  };

  @override
  Widget build(BuildContext context) {
    final st = _status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembaca NFC'),
        actions: [
          if (_scans.isNotEmpty) ...[
            IconButton(
              tooltip: 'Bagikan hasil (JSON)',
              onPressed: () => Share.share(_json, subject: 'Hasil scan NFC'),
              icon: const Icon(Icons.share_rounded),
            ),
            IconButton(
              tooltip: 'Hapus daftar',
              onPressed: () => setState(_scans.clear),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ],
      ),
      body: MaxWidth(
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusBanner(status: st, reading: _reading, onRetry: _begin),
            const Gap(16),
            if (_scans.isEmpty && _reading)
              Text(
                'Belum ada kartu. Tempelkan kartu (e-KTP, kartu anggota, '
                'kartu bank) di area NFC tablet dan tahan 1–2 detik.',
                textAlign: TextAlign.center,
                style: AppText.w400(14, AppColors.grey4),
              ),
            for (var i = 0; i < _scans.length; i++) ...[
              _ScanCard(scan: _scans[i], index: _scans.length - i),
              const Gap(12),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final NfcStatus? status;
  final bool reading;
  final VoidCallback onRetry;
  const _StatusBanner({
    required this.status,
    required this.reading,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final st = status;
    final (icon, color, bg, text) = st == null
        ? (
            Icons.hourglass_empty_rounded,
            AppColors.grey1,
            AppColors.lightGrey,
            'Memeriksa NFC…',
          )
        : !st.available
        ? (
            Icons.nfc_rounded,
            AppColors.red,
            AppColors.redSoft,
            'Perangkat ini tidak punya NFC.',
          )
        : !st.enabled
        ? (
            Icons.nfc_rounded,
            AppColors.orangeAction,
            AppColors.orangeActionBg,
            'NFC mati. Nyalakan di Pengaturan Android → Koneksi → NFC.',
          )
        : reading
        ? (
            Icons.contactless_rounded,
            AppColors.primary,
            AppColors.primarySoft,
            'Siap membaca — tempelkan kartu di area NFC tablet.',
          )
        : (
            Icons.error_outline_rounded,
            AppColors.red,
            AppColors.redSoft,
            'Mode pembaca gagal dimulai.',
          );
    return Container(
      key: const Key('nfc_status'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 36, color: color),
          const Gap(12),
          Expanded(child: Text(text, style: AppText.w600(16, color))),
          if (st != null && (!st.enabled || !reading))
            TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  final NfcScan scan;
  final int index;
  const _ScanCard({required this.scan, required this.index});

  /// Ratakan peta bersarang jadi baris "nfcA.atqa: 44 00".
  static List<(String, String)> _flatten(Object? v, [String prefix = '']) {
    if (v is Map) {
      return [
        for (final e in v.entries)
          if (!{'uid', 'techs', 'time'}.contains('${e.key}') || prefix != '')
            ..._flatten(
              e.value,
              prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}',
            ),
      ];
    }
    if (v is List) {
      if (v.isEmpty) return [(prefix, '[]')];
      return [
        for (var i = 0; i < v.length; i++) ..._flatten(v[i], '$prefix[$i]'),
      ];
    }
    return [(prefix, '$v')];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _flatten(scan.data);
    return SectionCard(
      title: 'Kartu #$index · UID ${scan.uid}',
      subtitle: [
        DateFormat('HH.mm.ss', 'id_ID').format(scan.time),
        if (scan.randomUid)
          'UID ACAK — berubah tiap tempel, tidak bisa jadi kartu anggota'
        else
          'UID tetap — bisa jadi kartu anggota',
      ].join(' · '),
      trailing: IconButton(
        tooltip: 'Salin',
        onPressed: () {
          Clipboard.setData(
            ClipboardData(
              text: const JsonEncoder.withIndent(
                '  ',
              ).convert(_NfcScreenState._plain(scan.data)),
            ),
          );
          showSnack(context, 'Data kartu disalin');
        },
        icon: const Icon(Icons.copy_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in scan.techs)
                Chip(
                  label: Text(t, style: AppText.w600(12, AppColors.primary)),
                  backgroundColor: AppColors.primarySoft,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const Gap(8),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 220,
                    child: Text(k, style: AppText.w500(13, AppColors.grey1)),
                  ),
                  Expanded(
                    child: SelectableText(
                      v,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
