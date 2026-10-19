part of 'home_screen.dart';

/// Alur kartu NFC di beranda:
/// - kartu terdaftar → data anggota terisi, pengukuran mulai otomatis (tanpa
///   mengetik);
/// - kartu baru → daftarkan / tautkan ke data yang ada;
/// - "Tautkan kartu" → kartu berikutnya disimpan untuk orang di form.
/// Satu kartu hanya untuk satu akun ([CardInUseException]).
extension _CardFlow on _HomeScreenState {
  bool get _homeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  /// Identitas dari isian form sekarang.
  PersonProfile _formProfile() {
    final age = int.tryParse(_age.text.trim());
    final height = parseNum(_height.text);
    final nik = Nik.normalize(_nik.text);
    return PersonProfile(
      name: _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      gender: _gender,
      age: (age != null && age > 0 && age < 130) ? age : null,
      heightCm: (height != null && height >= 50 && height <= 250)
          ? height
          : null,
      nik: nik.isEmpty ? null : nik,
      birthDate: Nik.decode(_nik.text)?.birthDate,
    );
  }

  Future<void> _onCardScan(NfcScan scan) async {
    if (_cardBusy) return;
    final uid = normalizeUid(scan.uid);
    if (uid.isEmpty) return;
    _setCardBusy(true);
    try {
      if (_awaitingCard) {
        if (scan.randomUid) {
          await _showRandomUidCard();
        } else {
          await _linkCardToForm(uid);
        }
        return;
      }
      final member = MemberStore.instance.byUid(uid);
      if (member != null) {
        await _startForMember(member);
      } else if (scan.randomUid) {
        await _showRandomUidCard();
      } else {
        await _askUnknownCard(uid);
      }
    } finally {
      _setCardBusy(false);
    }
  }

  /// "Tautkan": cek isian dulu supaya data salah tidak ikut ke kartu.
  void _toggleAwaitingCard() {
    if (!_awaitingCard && _validateForm() != null) return;
    _setAwaitingCard(!_awaitingCard);
  }

  /// Kartu dikenal: isi form lalu mulai setelah jeda singkat (bisa dibatalkan).
  Future<void> _startForMember(Member m) async {
    final p = m.profileOn(DateTime.now());
    _fillFromProfile(p, cardUid: m.uid, fromTap: true);
    // Data anggota salah (mis. NIK tidak lengkap): jangan hitung mundur lalu
    // gagal diam-diam — beri tahu, form sudah terisi untuk diperbaiki.
    final problem = _validateForm();
    if (problem != null) {
      await _invalidCardDialog(m, problem);
      return;
    }
    final go = await _countdownDialog(p);
    if (!mounted) return;
    if (go) await _start();
  }

  Future<void> _invalidCardDialog(Member m, String problem) async {
    final edit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('card_invalid_dialog'),
        backgroundColor: AppColors.surface,
        icon: const Icon(
          Icons.error_outline_rounded,
          size: 44,
          color: AppColors.orangeAction,
        ),
        title: Text(
          'Data ${m.profile.name} perlu diperbaiki',
          textAlign: TextAlign.center,
          style: AppText.w700(21),
        ),
        content: Text(
          '$problem. Pengukuran belum dimulai — perbaiki di form lalu tekan '
          'Mulai, atau ubah data anggotanya supaya kartu ini langsung bisa '
          'dipakai lagi.',
          textAlign: TextAlign.center,
          style: AppText.w500(16, AppColors.grey1),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            key: const Key('card_invalid_form'),
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
            child: const Text('Perbaiki di form'),
          ),
          FilledButton(
            key: const Key('card_invalid_edit'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
            child: const Text('Ubah data anggota'),
          ),
        ],
      ),
    );
    if (edit != true || !mounted) return;
    final saved = await Navigator.of(context).push<Member>(
      MaterialPageRoute(builder: (_) => MemberFormScreen(existing: m)),
    );
    if (saved != null && mounted) await _startForMember(saved);
  }

  /// "Halo, …" + L/P · umur · NIK tersamar supaya orangnya bisa dipastikan;
  /// 4 detik supaya lansia sempat bereaksi.
  Future<bool> _countdownDialog(PersonProfile p) async {
    final identity = memberProfileLine(p);
    var left = 4;
    Timer? timer;
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            left--;
            if (left <= 0) {
              t.cancel();
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop(true);
            } else {
              Sound.play(Sfx.tick);
              setLocal(() {});
            }
          });
          return AlertDialog(
            key: const Key('card_start_dialog'),
            backgroundColor: AppColors.surface,
            icon: const Icon(
              Icons.contactless_rounded,
              size: 44,
              color: AppColors.darkGreen,
            ),
            title: Text(
              'Halo, ${p.name}',
              textAlign: TextAlign.center,
              style: AppText.w700(24),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (identity.isNotEmpty) ...[
                  Text(
                    identity,
                    key: const Key('card_start_identity'),
                    textAlign: TextAlign.center,
                    style: AppText.w600(19, AppColors.charcoal),
                  ),
                  const Gap(12),
                ],
                Text(
                  'Pengukuran dimulai dalam $left…',
                  textAlign: TextAlign.center,
                  style: AppText.w500(16, AppColors.grey1),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              OutlinedButton(
                key: const Key('card_start_cancel'),
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, 56),
                ),
                child: const Text('Batal'),
              ),
              FilledButton(
                key: const Key('card_start_now'),
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(minimumSize: const Size(160, 56)),
                child: const Text('Mulai sekarang'),
              ),
            ],
          );
        },
      ),
    );
    timer?.cancel();
    return go ?? false;
  }

  /// Kartu ber-UID acak tidak bisa jadi kartu anggota: nomornya lain setiap
  /// ditempel, jadi tidak akan pernah dikenali lagi.
  Future<void> _showRandomUidCard() async {
    Sound.play(Sfx.error);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('random_uid_dialog'),
        backgroundColor: AppColors.surface,
        icon: const Icon(
          Icons.credit_card_off_rounded,
          size: 40,
          color: AppColors.orangeAction,
        ),
        title: Text(
          'Kartu ini tidak bisa dipakai',
          textAlign: TextAlign.center,
          style: AppText.w700(20),
        ),
        content: Text(
          'Nomor kartu ini berubah setiap kali ditempel (e\u2011KTP, kartu '
          'bank, e-money), jadi tidak bisa dikenali lagi. Gunakan kartu '
          'anggota, atau ketik nama.',
          textAlign: TextAlign.center,
          style: AppText.w500(16, AppColors.grey1),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            key: const Key('random_uid_ok'),
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(minimumSize: const Size(160, 56)),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  /// Kartu belum terdaftar: daftarkan / tautkan, atau pakai untuk isian form.
  Future<void> _askUnknownCard(String uid) async {
    final name = _name.text.trim();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('unknown_card_dialog'),
        backgroundColor: AppColors.surface,
        icon: const Icon(
          Icons.credit_card_rounded,
          size: 40,
          color: AppColors.primary,
        ),
        title: Text(
          'Kartu belum terdaftar',
          textAlign: TextAlign.center,
          style: AppText.w700(20),
        ),
        content: Text(
          'UID ${formatUid(uid)}',
          textAlign: TextAlign.center,
          style: AppText.w500(14, AppColors.grey1),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          if (name.isNotEmpty)
            FilledButton.icon(
              key: const Key('card_use_for_form'),
              onPressed: () => Navigator.pop(ctx, 'form'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
              icon: const Icon(Icons.link_rounded),
              label: Text('Kartu untuk $name'),
            ),
          FilledButton.tonalIcon(
            key: const Key('card_register'),
            onPressed: () => Navigator.pop(ctx, 'register'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Daftar / tautkan anggota'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'form') {
      await _linkCardToForm(uid);
    } else if (choice == 'register') {
      final m = await Navigator.of(context).push<Member>(
        MaterialPageRoute(builder: (_) => MembersScreen(pendingUid: uid)),
      );
      if (m != null && mounted) await _startForMember(m);
    }
  }

  /// Orang yang sama: NIK sama; tanpa NIK di form → nama sama.
  bool _samePerson(PersonProfile owner, PersonProfile form) {
    final nik = Nik.normalize(form.nik ?? '');
    if (nik.isNotEmpty) return Nik.normalize(owner.nik ?? '') == nik;
    String key(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return key(owner.name) == key(form.name);
  }

  /// Simpan kartu [uid] untuk orang yang sedang diisi di form.
  Future<void> _linkCardToForm(String uid) async {
    _setAwaitingCard(false);
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'Isi nama dulu, lalu tempelkan kartunya.');
      return;
    }
    // Data salah tidak boleh tersimpan di kartu: kartu itu lalu tidak pernah
    // bisa memulai pengukuran.
    final problem = _validateForm();
    if (problem != null) {
      showSnack(
        context,
        '$problem — perbaiki dulu, lalu tempelkan kartunya lagi.',
        error: true,
      );
      return;
    }
    final p = _formProfile();
    final store = MemberStore.instance;
    // Kartu ini memang milik orang di form → sudah tertaut, bukan konflik.
    final owner = store.byUid(uid);
    if (owner != null && _samePerson(owner.profile, p)) {
      _applyCardUid(uid);
      showSnack(
        context,
        'Kartu ${formatUid(uid)} sudah terhubung dengan ${owner.profile.name}',
      );
      return;
    }
    final now = DateTime.now();
    try {
      // NIK sama = orang yang sama → pindahkan akunnya ke kartu ini.
      final sameNik = p.nik == null ? null : store.byNik(p.nik!);
      if (sameNik != null && sameNik.uid != uid) {
        final ok = await confirmDialog(
          context,
          title: 'NIK sudah terdaftar',
          message:
              'NIK ini milik ${sameNik.profile.name} (kartu '
              '${formatUid(sameNik.uid)}). Pindahkan ke kartu baru ini?',
          confirmLabel: 'Pindahkan',
          icon: Icons.swap_horiz_rounded,
        );
        if (!ok || !mounted) return;
        await store.relink(sameNik.uid, uid);
      } else {
        await store.add(
          Member(uid: uid, profile: p, createdAt: now, updatedAt: now),
        );
      }
      if (!mounted) return;
      _applyCardUid(uid);
      showSnack(context, 'Kartu ${formatUid(uid)} tersimpan untuk ${p.name}');
    } on CardInUseException catch (e) {
      if (mounted) {
        showSnack(
          context,
          'Kartu ini sudah terdaftar untuk ${e.owner.profile.name}',
          error: true,
        );
      }
    }
  }
}
