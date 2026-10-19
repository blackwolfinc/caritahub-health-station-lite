import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';

import '../app/sound.dart';
import '../app/theme.dart';
import '../data/record_store.dart';

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Ya',
  String cancelLabel = 'Batal',
  bool destructive = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      icon: Icon(
        icon,
        color: destructive ? AppColors.red : AppColors.orangeAction,
        size: 30,
      ),
      title: Text(title, style: AppText.w700(17), textAlign: TextAlign.center),
      content: Text(
        message,
        style: AppText.w400(14, AppColors.grey1),
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.red)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  if (error) Sound.play(Sfx.error);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.red : AppColors.charcoal,
      ),
    );
}

class SectionCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: AppText.w600(16)),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppText.w400(12, AppColors.grey4),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const Gap(14),
          ],
          child,
        ],
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  final bool compact;
  const BrandHeader({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final narrow = compact || !context.isMedium;
    final subtitle = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 15, color: AppColors.grey4),
        const Gap(4),
        Flexible(
          child: Text(
            narrow
                ? 'Offline · tersimpan di perangkat'
                : 'Offline · data tersimpan di perangkat ini',
            overflow: TextOverflow.ellipsis,
            style: AppText.w400(13, AppColors.grey4),
          ),
        ),
      ],
    );
    if (narrow) {
      // Layar genggam: logo di atas, nama aplikasi di bawahnya.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset('assets/images/caritahub_logo.svg', height: 30),
          const Gap(8),
          Text('Health Station Lite', style: AppText.w600(15)),
          subtitle,
        ],
      );
    }
    return Row(
      children: [
        SvgPicture.asset('assets/images/caritahub_logo.svg', height: 38),
        const Gap(12),
        Container(width: 1, height: 32, color: AppColors.border),
        const Gap(12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Health Station Lite', style: AppText.w600(16)),
              subtitle,
            ],
          ),
        ),
      ],
    );
  }
}

/// Konten dibatasi lebarnya supaya tetap rapi di layar iMin 15,6".
class MaxWidth extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  const MaxWidth({super.key, this.maxWidth = 1180, required this.child});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Peringatan file riwayat rusak / salinan rusak yang belum ditangani.
/// Tampil selama [RecordStore.corruptWarning] ada (juga setelah restart).
/// [dismissible] hanya untuk layar petugas: tombol "Sudah ditangani".
class CorruptHistoryBanner extends StatelessWidget {
  final bool dismissible;
  const CorruptHistoryBanner({super.key, this.dismissible = false});

  Future<void> _dismiss(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Tandai sudah ditangani?',
      message:
          'Salinan file rusak tetap disimpan di perangkat. Peringatan ini '
          'tidak muncul lagi.',
      confirmLabel: 'Sudah ditangani',
      icon: Icons.warning_amber_rounded,
    );
    if (!ok) return;
    try {
      await RecordStore.instance.dismissCorruptWarning();
    } catch (e) {
      if (context.mounted) showSnack(context, 'Gagal: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: RecordStore.instance,
    builder: (context, _) {
      final msg = RecordStore.instance.corruptWarning;
      if (msg == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: AppColors.orangeActionBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.orange),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.orangeAction,
              size: 26,
            ),
            const Gap(10),
            Expanded(
              child: Text(msg, style: AppText.w500(14, AppColors.charcoal)),
            ),
            if (dismissible) ...[
              const Gap(8),
              TextButton(
                key: const Key('corrupt_dismiss'),
                onPressed: () => _dismiss(context),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Sudah ditangani'),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Bangun ulang saat tanggal berganti (lewat tengah malam / aplikasi
/// dibuka lagi) — angka "hari ini" di layar yang menyala seharian.
class DayTicker extends StatefulWidget {
  final Widget Function(BuildContext context, DateTime now) builder;
  const DayTicker({super.key, required this.builder});

  /// Jam — bisa diganti di test.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<DayTicker> createState() => _DayTickerState();
}

class _DayTickerState extends State<DayTicker> with WidgetsBindingObserver {
  late DateTime _day;
  Timer? _timer;

  static DateTime _today() {
    final n = DayTicker.clock();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _day = _today();
    WidgetsBinding.instance.addObserver(this);
    // Cek tiap 30 detik: tahan jam perangkat yang disetel ulang.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  void _check() {
    final d = _today();
    if (d != _day && mounted) setState(() => _day = d);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, DayTicker.clock());
}
