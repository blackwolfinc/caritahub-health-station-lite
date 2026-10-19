import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../app/motion.dart';
import '../app/nfc_reader.dart';
import '../app/sound.dart';
import '../app/theme.dart';

/// Kotak "tempelkan kartu di sini" di beranda: membaca kartu NFC (e-KTP /
/// kartu anggota) selama beranda tampil, lalu memanggil [onScan] dengan UID.
/// Tidak tampil bila perangkat tidak punya NFC.
class NfcTapBox extends StatefulWidget {
  /// Dipanggil hanya saat [active] (beranda sedang di depan).
  final ValueChanged<NfcScan> onScan;
  final bool Function() active;

  /// Teks hasil terakhir, mis. "Siti Aminah · anggota".
  final String? lastResult;

  /// Menunggu kartu untuk ditautkan (judul diganti, bingkai oranye).
  final String? prompt;

  /// Bentuk kartu besar (seukuran kartu asli) — diletakkan tepat di atas
  /// antena NFC dalam layar (iMin Falcon2).
  final bool large;

  /// Bersama [large]: hanya bingkai + ikon samar (tanpa teks) — dipakai
  /// sebagai latar di belakang kolom isian.
  final bool subtle;

  /// Bersama [subtle]: posisi ikon kartu (tepat di atas antena NFC).
  final Alignment markAlignment;

  const NfcTapBox({
    super.key,
    required this.onScan,
    required this.active,
    this.lastResult,
    this.prompt,
    this.large = false,
    this.subtle = false,
    this.markAlignment = Alignment.center,
  });

  @override
  State<NfcTapBox> createState() => _NfcTapBoxState();
}

class _NfcTapBoxState extends State<NfcTapBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  StreamSubscription<NfcScan>? _sub;

  /// Status terakhir (dipakai lagi saat kotak dibuat ulang — tanpa kedip).
  static NfcStatus? _lastStatus;
  NfcStatus? _status = _lastStatus;
  bool _started = false;
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (Motion.enabled) _pulse.repeat();
    unawaited(_begin());
  }

  Future<void> _begin() async {
    final st = await NfcReader.status();
    _lastStatus = st;
    if (!mounted) return;
    // Dengarkan kanal hanya bila perangkat punya NFC (tanpa plugin, kanal
    // event melempar galat saat didengarkan).
    if (st.available) {
      _sub ??= NfcReader.scans.listen(_onScan, onError: (_) {});
    }
    if (st.enabled && !_started) {
      _started = true;
      await NfcReader.start();
    }
    if (mounted) setState(() => _status = st);
  }

  void _onScan(NfcScan s) {
    if (!mounted || !widget.active()) {
      // Tidak diproses → tidak memakai jendela kartu sama.
      NfcReader.ignore(s);
      return;
    }
    HapticFeedback.mediumImpact();
    Sound.play(Sfx.card);
    setState(() => _flash = true);
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flash = false);
    });
    widget.onScan(s);
  }

  /// Kotak seukuran kartu dengan gambar kartu & gelombang — "taruh di sini".
  Widget _buildLarge(bool off, Color color) {
    final waiting = widget.prompt != null && !off;
    return AnimatedBuilder(
      key: const Key('nfc_card_target'),
      animation: _pulse,
      builder: (context, _) {
        final glow = _flash ? 1.0 : 0.35 + 0.35 * (1 - _pulse.value);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: _flash
                ? AppColors.greenSoft
                : waiting
                ? AppColors.orangeActionBg
                : AppColors.primarySoft,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: (_flash ? AppColors.darkGreen : color).withValues(
                alpha: glow,
              ),
              width: 4,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.18 * glow),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _flash
                          ? Icons.check_circle_rounded
                          : Icons.contactless_rounded,
                      size: 72,
                      color: _flash ? AppColors.darkGreen : color,
                    ),
                    const Gap(10),
                    Text(
                      off
                          ? 'NFC mati'
                          : _flash
                          ? 'Kartu terbaca'
                          : widget.prompt ?? 'Tempelkan kartu di sini',
                      style: AppText.w700(
                        26,
                        _flash ? AppColors.darkGreen : color,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      off
                          ? 'Nyalakan NFC di Pengaturan Android'
                          : widget.lastResult ??
                                'Kartu anggota · tahan sebentar',
                      style: AppText.w500(15, AppColors.grey1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Latar area kartu: bingkai berdenyut + ikon besar samar; hijau saat
  /// kartu terbaca.
  Widget _buildSubtle(bool off, Color color) {
    return AnimatedBuilder(
      key: const Key('nfc_card_target'),
      animation: _pulse,
      builder: (context, _) {
        final glow = _flash ? 1.0 : 0.3 + 0.3 * (1 - _pulse.value);
        final c = _flash ? AppColors.darkGreen : color;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: _flash
                ? AppColors.greenSoft
                : c.withValues(alpha: off ? 0.04 : 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withValues(alpha: glow), width: 3),
          ),
          alignment: widget.markAlignment,
          child: Icon(
            _flash ? Icons.check_circle_rounded : Icons.contactless_rounded,
            size: 120,
            color: c.withValues(alpha: _flash ? 0.35 : 0.12),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _sub?.cancel();
    if (_started) unawaited(NfcReader.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    if (st == null || !st.available) return const SizedBox.shrink();
    final off = !st.enabled;
    final waiting = widget.prompt != null && !off;
    final color = off || waiting ? AppColors.orangeAction : AppColors.primary;
    if (widget.large && widget.subtle) return _buildSubtle(off, color);
    if (widget.large) return _buildLarge(off, color);
    return AnimatedContainer(
      key: const Key('nfc_tap_box'),
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _flash
            ? AppColors.greenSoft
            : waiting
            ? AppColors.orangeActionBg
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _flash ? AppColors.darkGreen : color.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Stack(
                alignment: Alignment.center,
                children: [
                  if (!off)
                    Container(
                      width: 30 + 22 * _pulse.value,
                      height: 30 + 22 * _pulse.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(
                          alpha: 0.25 * (1 - _pulse.value),
                        ),
                      ),
                    ),
                  child!,
                ],
              ),
              child: Icon(
                _flash ? Icons.check_circle_rounded : Icons.contactless_rounded,
                size: 34,
                color: _flash ? AppColors.darkGreen : color,
              ),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  off
                      ? 'NFC mati — nyalakan di Pengaturan Android'
                      : widget.prompt ?? 'Tempelkan kartu anggota di sini',
                  style: AppText.w700(
                    16,
                    off || waiting ? color : AppColors.charcoal,
                  ),
                ),
                Text(
                  widget.lastResult ??
                      (off
                          ? 'Kartu tidak bisa dibaca selama NFC mati'
                          : 'Data anggota terisi otomatis · kartu baru bisa didaftarkan'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.w400(13, AppColors.grey1),
                ),
              ],
            ),
          ),
          if (off) TextButton(onPressed: _begin, child: const Text('Cek lagi')),
        ],
      ),
    );
  }
}
