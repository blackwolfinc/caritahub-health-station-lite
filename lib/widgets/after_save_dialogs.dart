import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../app/theme.dart';

/// Pilihan setelah hasil tersimpan.
enum AfterSave { print, next }

/// Hasil tersimpan → cetak struk dulu, atau langsung lanjut lansia berikutnya.
/// Tidak bisa ditutup dengan ketuk di luar supaya pilihan selalu jelas.
Future<AfterSave> showAfterSaveDialog(
  BuildContext context, {
  required String name,
}) async {
  final choice = await showDialog<AfterSave>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ChoiceDialog(
      key: const Key('after_save_dialog'),
      icon: Icons.check_circle_rounded,
      iconColor: AppColors.darkGreen,
      title: 'Hasil $name tersimpan',
      message:
          'Cetak catatan tes kesehatan sekarang, atau langsung lanjut ke '
          'pemeriksaan berikutnya?',
      primaryKey: const Key('after_save_print'),
      primaryIcon: Icons.print_rounded,
      primaryLabel: 'Cetak catatan',
      onPrimary: () => Navigator.pop(ctx, AfterSave.print),
      secondaryKey: const Key('after_save_next'),
      secondaryIcon: Icons.arrow_forward_rounded,
      secondaryLabel: 'Lanjut ukur',
      onSecondary: () => Navigator.pop(ctx, AfterSave.next),
    ),
  );
  return choice ?? AfterSave.next;
}

/// Struk selesai dicetak → lanjut pemeriksaan berikutnya atau tetap di hasil.
/// true = lanjut.
Future<bool> showNextPersonDialog(BuildContext context) async {
  final next = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ChoiceDialog(
      key: const Key('next_person_dialog'),
      icon: Icons.print_rounded,
      iconColor: AppColors.primary,
      title: 'Catatan tes kesehatan sudah dicetak',
      message: 'Lanjut ke pemeriksaan berikutnya?',
      primaryKey: const Key('next_person_yes'),
      primaryIcon: Icons.person_add_alt_1_rounded,
      primaryLabel: 'Lanjut ukur',
      onPrimary: () => Navigator.pop(ctx, true),
      secondaryKey: const Key('next_person_no'),
      secondaryIcon: Icons.receipt_long_rounded,
      secondaryLabel: 'Tetap di sini',
      onSecondary: () => Navigator.pop(ctx, false),
    ),
  );
  return next ?? false;
}

class _ChoiceDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final Key primaryKey;
  final IconData primaryIcon;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final Key secondaryKey;
  final IconData secondaryIcon;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  const _ChoiceDialog({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.primaryKey,
    required this.primaryIcon,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryKey,
    required this.secondaryIcon,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      Expanded(
        child: OutlinedButton.icon(
          key: secondaryKey,
          onPressed: onSecondary,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 64)),
          icon: Icon(secondaryIcon, size: 26),
          label: Text(secondaryLabel, style: AppText.w700(18)),
        ),
      ),
      const Gap(12),
      Expanded(
        child: FilledButton.icon(
          key: primaryKey,
          onPressed: onPrimary,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 64)),
          icon: Icon(primaryIcon, size: 26),
          label: Text(primaryLabel, style: AppText.w700(18, Colors.white)),
        ),
      ),
    ];
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: iconColor),
              const Gap(12),
              Text(title, textAlign: TextAlign.center, style: AppText.w700(22)),
              const Gap(6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.w400(16, AppColors.grey1),
              ),
              const Gap(24),
              Row(children: buttons),
            ],
          ),
        ),
      ),
    );
  }
}
