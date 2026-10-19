import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../app/theme.dart';
import '../data/patient_lookup.dart';
import '../utils/nik.dart';

/// Daftar lansia yang pernah diperiksa dan namanya cocok dengan ketikan.
/// Ketuk → identitasnya (L/P, umur, tinggi, NIK) dipakai lagi.
class PatientSuggestions extends StatelessWidget {
  final List<PatientMatch> matches;
  final ValueChanged<PatientMatch> onPick;

  const PatientSuggestions({
    super.key,
    required this.matches,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      key: const Key('patient_suggestions'),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primarySoft),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const Gap(6),
              Expanded(
                child: Text(
                  'Pernah diperiksa · ketuk untuk pakai datanya',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.w600(12.5, AppColors.primary),
                ),
              ),
            ],
          ),
          const Gap(4),
          for (var i = 0; i < matches.length; i++)
            _Row(
              key: Key('patient_suggestion_$i'),
              match: matches[i],
              now: now,
              onTap: () => onPick(matches[i]),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final PatientMatch match;
  final DateTime now;
  final VoidCallback onTap;

  const _Row({
    super.key,
    required this.match,
    required this.now,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = match.carriedTo(now);
    final meta = [
      if (p.gender != null) p.gender!.short,
      if (p.age != null) '${p.age} th',
      if (p.heightCm != null) '${p.heightCm!.toStringAsFixed(0)} cm',
      if (p.nik != null) 'NIK ${Nik.mask(p.nik!)}',
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.w700(16),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.w400(12.5, AppColors.grey1),
                    ),
                ],
              ),
            ),
            const Gap(8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  lastVisitLabel(match.lastVisit, now),
                  style: AppText.w600(13, AppColors.charcoal),
                ),
                Text(
                  '${match.visits}× diperiksa',
                  style: AppText.w400(12, AppColors.grey4),
                ),
              ],
            ),
            const Gap(4),
            const Icon(
              Icons.north_west_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
