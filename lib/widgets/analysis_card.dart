import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../app/theme.dart';
import '../models/health_record.dart';
import '../utils/health_analysis.dart';
import 'common.dart';

/// Warna teks status di atas latar lembut (greenSoft/redSoft/orangeActionBg)
/// dan latar abu/putih. AppColors.darkGreen dkk. hanya 2,5–3,7:1 di latar
/// lembut; digelapkan ke charcoal supaya ≥ 4,5:1 (WCAG AA).
class StatusInk {
  StatusInk._();
  static final good = _dark(AppColors.darkGreen);
  static final high = _dark(AppColors.red);
  static final low = _dark(AppColors.orangeAction);

  static Color _dark(Color c) => Color.lerp(c, AppColors.charcoal, 0.5)!;

  /// (latar, teks) chip status per tingkat.
  static (Color, Color) chip(FindingLevel level) => switch (level) {
    FindingLevel.normal => (AppColors.greenSoft, good),
    FindingLevel.high => (AppColors.redSoft, high),
    FindingLevel.low => (AppColors.orangeActionBg, low),
  };
}

/// Analisa tiap hasil terhadap batas normal pedoman Kemenkes RI.
class AnalysisCard extends StatelessWidget {
  final HealthRecord record;
  const AnalysisCard({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final findings = analyze(record);
    if (findings.isEmpty) return const SizedBox.shrink();
    final bad = findings.where((f) => f.abnormal).length;
    return SectionCard(
      key: const Key('analysis_card'),
      title: 'Analisa hasil',
      subtitle: 'Batas normal pedoman Kemenkes RI',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bad == 0 ? AppColors.greenSoft : AppColors.orangeActionBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  bad == 0
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  color: bad == 0
                      ? AppColors.darkGreen
                      : AppColors.orangeAction,
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    analysisSummary(findings),
                    style: AppText.w600(
                      14,
                      bad == 0 ? StatusInk.good : StatusInk.low,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(8),
          for (final f in findings) _FindingRow(f),
          const Gap(4),
          Text(
            'Alat bantu baca, bukan diagnosis. Komposisi tubuh, genggam, dan '
            'lingkar betis belum punya batas resmi — tidak dinilai.',
            style: AppText.w400(14, AppColors.grey1),
          ),
        ],
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  final Finding f;
  const _FindingRow(this.f);

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = StatusInk.chip(f.level);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.label, style: AppText.w600(14)),
                // Rentang tidak dipotong di tanda "–" (90–139/60–89).
                Text(
                  'Normal ${f.normal.replaceAll('–', '\u2060–\u2060')}',
                  style: AppText.w400(14, AppColors.grey1),
                ),
              ],
            ),
          ),
          Text(f.value, style: AppText.w700(14)),
          const Gap(10),
          Container(
            constraints: const BoxConstraints(minWidth: 72),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(f.status, style: AppText.w700(14, fg)),
          ),
        ],
      ),
    );
  }
}
