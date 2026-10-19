import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import '../data/member_store.dart';
import '../data/patient_lookup.dart';
import '../models/health_record.dart';
import '../utils/nik.dart';
import 'common.dart';

/// "Siti Aminah" / "3201" → cocok dengan nama atau NIK anggota.
List<Member> filterMembers(Iterable<Member> members, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return members.toList();
  final digits = Nik.normalize(q);
  return [
    for (final m in members)
      if (m.profile.name.toLowerCase().contains(q) ||
          (digits.length >= 3 &&
              digits.length == q.replaceAll(' ', '').length &&
              Nik.normalize(m.profile.nik ?? '').contains(digits)))
        m,
  ];
}

/// "P · 67 th · NIK 3201********0001" — NIK selalu disamarkan (UU PDP).
String memberProfileLine(PersonProfile p) => [
  if (p.gender != null) p.gender!.short,
  if (p.age != null) '${p.age} th',
  if (p.nik != null) 'NIK ${Nik.mask(p.nik!)}',
].join(' · ');

/// File anggota rusak saat dimuat: tanpa peringatan semua kartu tampil
/// "belum terdaftar". Kosong bila file baik.
class MemberStoreWarning extends StatelessWidget {
  const MemberStoreWarning({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: MemberStore.instance,
    builder: (context, _) {
      final n = MemberStore.instance.skippedOnLoad;
      if (n == 0) return const SizedBox.shrink();
      return Container(
        key: const Key('member_corrupt_banner'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.orangeActionBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          n > 0
              ? '$n data anggota kartu rusak dan dilewati — kartunya tampil '
                    '"belum terdaftar". Salinan file asli disimpan di perangkat.'
              : 'File anggota kartu tidak terbaca — semua kartu tampil "belum '
                    'terdaftar". Salinan file asli disimpan; hubungi tim IT '
                    'sebelum mendaftarkan ulang.',
          style: AppText.w500(14, AppColors.orangeAction),
        ),
      );
    },
  );
}

/// Kartu belum terdaftar: daftar baru atau tautkan ke data yang sudah ada.
class PendingCardBanner extends StatelessWidget {
  final String uid;
  final VoidCallback onRegister;
  final VoidCallback onLink;

  const PendingCardBanner({
    super.key,
    required this.uid,
    required this.onRegister,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final register = FilledButton.icon(
      key: const Key('register_new_button'),
      onPressed: onRegister,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 68)),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 26),
      label: Text(
        'Daftarkan anggota baru',
        style: AppText.w700(17, Colors.white),
      ),
    );
    final link = OutlinedButton.icon(
      key: const Key('link_existing_button'),
      onPressed: onLink,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 68),
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        foregroundColor: AppColors.primary,
      ),
      icon: const Icon(Icons.link_rounded, size: 26),
      label: Text(
        'Tautkan ke data yang ada',
        style: AppText.w700(17, AppColors.primary),
      ),
    );
    return Container(
      key: const Key('pending_banner'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.contactless_rounded,
                size: 40,
                color: AppColors.primary,
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kartu belum terdaftar · UID ${formatUid(uid)}',
                      style: AppText.w700(19, AppColors.navyBlue),
                    ),
                    const Gap(2),
                    Text(
                      'Daftarkan sebagai anggota baru, atau tautkan ke lansia '
                      'yang sudah terdaftar / pernah diperiksa.',
                      style: AppText.w400(14, AppColors.grey1),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(16),
          if (context.isMedium)
            Row(
              children: [
                Expanded(child: register),
                const Gap(12),
                Expanded(child: link),
              ],
            )
          else ...[
            register,
            const Gap(10),
            link,
          ],
        ],
      ),
    );
  }
}

/// Satu baris anggota: nama, L/P · umur · NIK tersamar, UID kartu.
class MemberTile extends StatelessWidget {
  final Member member;
  final VoidCallback onTap;

  const MemberTile({super.key, required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = member.profileOn(DateTime.now());
    final line = memberProfileLine(p);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase(),
                  style: AppText.w700(18, AppColors.primary),
                ),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.w600(17),
                    ),
                    if (line.isNotEmpty)
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.w400(13, AppColors.grey4),
                      ),
                    Row(
                      children: [
                        const Icon(
                          Icons.contactless_outlined,
                          size: 15,
                          color: AppColors.primary,
                        ),
                        const Gap(4),
                        Flexible(
                          child: Text(
                            formatUid(member.uid),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.w500(12.5, AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.grey3),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryPersonTile extends StatelessWidget {
  final PatientMatch match;
  final DateTime now;
  final VoidCallback onTap;

  const HistoryPersonTile({
    super.key,
    required this.match,
    required this.now,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = match.carriedTo(now);
    final line = memberProfileLine(p);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.lightGrey,
                child: Icon(Icons.history_rounded, color: AppColors.grey1),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.w600(17),
                    ),
                    Text(
                      [
                        if (line.isNotEmpty) line,
                        '${match.visits}× · '
                            '${lastVisitLabel(match.lastVisit, now)}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.w400(13, AppColors.grey4),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.link_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// UID kartu, hanya dibaca.
class MemberCardChip extends StatelessWidget {
  final String uid;
  const MemberCardChip({super.key, required this.uid});

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('member_uid'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.contactless_outlined, color: AppColors.primary),
        const Gap(10),
        Text('Kartu', style: AppText.w500(14, AppColors.grey1)),
        const Gap(10),
        Expanded(
          child: Text(
            formatUid(uid),
            overflow: TextOverflow.ellipsis,
            style: AppText.w700(17, AppColors.primary),
          ),
        ),
      ],
    ),
  );
}

/// Pengganti kolom umur bila tanggal lahir diketahui dari NIK.
class BirthDateInfo extends StatelessWidget {
  final DateTime birthDate;
  const BirthDateInfo({super.key, required this.birthDate});

  @override
  Widget build(BuildContext context) {
    final age = Nik.ageOn(birthDate, DateTime.now());
    return Container(
      key: const Key('member_birth_info'),
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$age th', style: AppText.w600(18)),
          Text(
            'Lahir ${DateFormat('d MMM yyyy', 'id_ID').format(birthDate)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.w400(12, AppColors.grey4),
          ),
        ],
      ),
    );
  }
}

/// Form + keyboard layar seperti beranda: tablet lebar → form kiri, keyboard
/// kanan; layar sempit → keyboard menempel di bawah, form tetap bisa digulir.
class KeyboardSplitLayout extends StatelessWidget {
  final Widget form;
  final Widget? keyboard;

  const KeyboardSplitLayout({super.key, required this.form, this.keyboard});

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    final hPad = context.isMedium ? 28.0 : 16.0;
    final kb = keyboard;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
              child: MaxWidth(
                child: kb != null && wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: form),
                          const Gap(20),
                          Expanded(flex: 6, child: kb),
                        ],
                      )
                    : Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: form,
                        ),
                      ),
              ),
            ),
          ),
          if (kb != null && !wide)
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
              child: MaxWidth(maxWidth: 900, child: kb),
            ),
        ],
      ),
    );
  }
}

/// "NIK ini sudah terdaftar untuk Siti (kartu 0E 5E …)".
String nikInUseMessage(Member owner) =>
    'NIK ini sudah terdaftar untuk ${owner.profile.name} '
    '(kartu ${formatUid(owner.uid)})';

/// Satu orang = satu anggota: NIK sudah dimiliki [owner] → tawarkan
/// memindahkan [owner] ke kartu [newUid]. Mengembalikan anggota yang sudah
/// dipindah, atau null bila dibatalkan / gagal (pesan sudah ditampilkan).
Future<Member?> offerRelinkByNik(
  BuildContext context,
  Member owner,
  String newUid,
) async {
  final ok = await confirmDialog(
    context,
    title: 'NIK sudah terdaftar',
    message:
        '${nikInUseMessage(owner)}. Pindahkan ${owner.profile.name} ke kartu '
        '${formatUid(newUid)}? Kartu lama tidak berlaku lagi.',
    confirmLabel: 'Pindahkan ke kartu ini',
    icon: Icons.contactless_outlined,
  );
  if (!ok || !context.mounted) return null;
  try {
    return await MemberStore.instance.relink(owner.uid, newUid);
  } on CardInUseException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) {
      showSnack(context, 'Gagal menautkan kartu: $e', error: true);
    }
  }
  return null;
}
