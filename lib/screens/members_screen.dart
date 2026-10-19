import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../app/nfc_reader.dart';
import '../app/sound.dart';
import '../app/theme.dart';
import '../data/member_store.dart';
import '../data/patient_lookup.dart';
import '../data/record_store.dart';
import '../widgets/common.dart';
import '../widgets/member_widgets.dart';
import '../widgets/nfc_tap_box.dart';
import 'member_form_screen.dart';

export 'member_form_screen.dart' show MemberFormScreen;

/// Daftar anggota kartu NFC. Bila dibuka dari kartu yang belum terdaftar
/// ([pendingUid]), petugas mendaftarkan anggota baru atau menautkan kartu ke
/// data yang sudah ada; setelah berhasil layar ditutup dengan [Member]-nya.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, this.pendingUid});

  /// UID kartu yang baru ditempel dan belum terdaftar.
  final String? pendingUid;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _search = TextEditingController();

  String? get _pending {
    final p = widget.pendingUid;
    return p == null || normalizeUid(p).isEmpty ? null : normalizeUid(p);
  }

  @override
  void initState() {
    super.initState();
    unawaited(MemberStore.instance.load());
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Kartu tertaut ke anggota → kembali ke pemanggil (beranda).
  void _done(Member m) {
    if (!mounted) return;
    Navigator.pop(context, m);
  }

  Future<void> _openForm({Member? existing, String? uid}) async {
    final saved = await Navigator.of(context).push<Member>(
      MaterialPageRoute(
        builder: (_) => MemberFormScreen(existing: existing, uid: uid),
      ),
    );
    if (!mounted || saved == null) return;
    if (_pending != null && saved.uid == _pending) {
      _done(saved);
    } else {
      showSnack(context, '${saved.profile.name} tersimpan');
    }
  }

  /// Anggota baru: kartu yang tertunda, atau tunggu kartu ditempel di sini.
  Future<void> _newMember() async {
    final pending = _pending;
    if (pending != null) return _openForm(uid: pending);
    final st = await NfcReader.status();
    if (!mounted) return;
    if (!st.available) {
      showSnack(
        context,
        'Perangkat ini tidak punya NFC — kartu anggota tidak bisa dibaca',
        error: true,
      );
      return;
    }
    final uid = await showDialog<String>(
      context: context,
      builder: (_) => _NewCardDialog(inScreen: hasInScreenNfc(st.model)),
    );
    if (!mounted || uid == null) return;
    await _openForm(uid: uid);
  }

  Future<void> _link() async {
    final uid = _pending;
    if (uid == null) return;
    final choice = await Navigator.of(context).push<Object>(
      MaterialPageRoute(builder: (_) => _LinkPickerScreen(pendingUid: uid)),
    );
    if (!mounted || choice == null) return;
    final store = MemberStore.instance;
    try {
      if (choice is PatientMatch) {
        final profile = choice.carriedTo(DateTime.now());
        // Satu orang = satu anggota: NIK sudah terdaftar → tawarkan pindah
        // kartu anggota itu, bukan membuat anggota kedua.
        final owner = profile.nik == null ? null : store.byNik(profile.nik!);
        if (owner != null) {
          final moved = await offerRelinkByNik(context, owner, uid);
          if (moved != null) _done(moved);
          return;
        }
        final now = DateTime.now();
        final m = Member(
          uid: uid,
          profile: profile,
          createdAt: now,
          updatedAt: now,
        );
        await store.add(m);
        _done(m);
        return;
      }
      if (choice is! Member || !mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Ganti kartu ${choice.profile.name}?',
        message:
            'Kartu lama (UID ${formatUid(choice.uid)}) tidak berlaku lagi. '
            'Kartu baru: ${formatUid(uid)}.',
        confirmLabel: 'Tautkan',
        icon: Icons.contactless_outlined,
      );
      if (!ok) return;
      _done(await store.relink(choice.uid, uid));
    } on CardInUseException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal menautkan kartu: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hPad = context.isMedium ? 28.0 : 16.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Pendaftaran Anggota')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: MemberStore.instance,
          builder: (context, _) {
            final all = MemberStore.instance.members;
            final shown = filterMembers(all, _search.text);
            return ListView(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
              children: [
                MaxWidth(
                  maxWidth: 900,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const MemberStoreWarning(),
                      if (_pending != null) ...[
                        PendingCardBanner(
                          uid: _pending!,
                          onRegister: _newMember,
                          onLink: _link,
                        ),
                        const Gap(20),
                      ],
                      _toolbar(),
                      const Gap(16),
                      SectionCard(
                        title: 'Anggota terdaftar',
                        subtitle: '${all.length} kartu',
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: shown.isEmpty
                            ? _empty(all.isEmpty)
                            : Column(
                                children: [
                                  for (var i = 0; i < shown.length; i++) ...[
                                    if (i > 0) const Divider(),
                                    MemberTile(
                                      key: Key('member_tile_${shown[i].uid}'),
                                      member: shown[i],
                                      onTap: () =>
                                          _openForm(existing: shown[i]),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _toolbar() {
    final search = TextField(
      key: const Key('member_search'),
      controller: _search,
      style: AppText.w500(17),
      decoration: InputDecoration(
        hintText: 'Cari nama / NIK',
        prefixIcon: const Icon(Icons.search_rounded, size: 26),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Hapus pencarian',
                onPressed: _search.clear,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
    final add = FilledButton.icon(
      key: const Key('new_member_button'),
      onPressed: _newMember,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 60)),
      icon: const Icon(Icons.person_add_alt_1_rounded),
      label: const Text('Anggota baru'),
    );
    if (!context.isMedium) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [search, const Gap(10), add],
      );
    }
    return Row(
      children: [
        Expanded(child: search),
        const Gap(12),
        add,
      ],
    );
  }

  Widget _empty(bool noMembers) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Icon(
          noMembers ? Icons.contactless_outlined : Icons.search_off_rounded,
          size: 40,
          color: AppColors.grey3,
        ),
        const Gap(10),
        Text(
          noMembers
              ? 'Belum ada anggota. Ketuk "Anggota baru" lalu tempelkan '
                    'kartu NFC.'
              : 'Tidak ada anggota yang cocok.',
          textAlign: TextAlign.center,
          style: AppText.w500(15, AppColors.grey4),
        ),
      ],
    ),
  );
}

/// Menunggu kartu baru ditempel. Kartu yang sudah dipakai anggota lain
/// ditolak di sini (satu kartu = satu anggota); kartu baru → UID-nya.
class _NewCardDialog extends StatefulWidget {
  /// Falcon2: dialog digeser ke atas antena NFC (tengah-kiri layar).
  final bool inScreen;
  const _NewCardDialog({required this.inScreen});

  @override
  State<_NewCardDialog> createState() => _NewCardDialogState();
}

class _NewCardDialogState extends State<_NewCardDialog> {
  String? _message;
  bool _done = false;

  void _onScan(NfcScan s) {
    final uid = normalizeUid(s.uid);
    if (_done || uid.isEmpty) return;
    if (s.randomUid) {
      Sound.play(Sfx.error);
      setState(
        () => _message =
            'Nomor kartu ini berubah setiap ditempel (e-KTP, kartu bank, '
            'e-money) · pakai kartu anggota',
      );
      return;
    }
    final owner = MemberStore.instance.byUid(uid);
    if (owner != null) {
      setState(
        () => _message =
            '${CardInUseException(owner).message} · pakai kartu lain',
      );
      return;
    }
    _done = true;
    Navigator.pop(context, uid);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('new_card_dialog'),
      alignment: widget.inScreen ? const Alignment(-0.5, 0) : null,
      backgroundColor: AppColors.surface,
      title: Text(
        'Tempelkan kartu anggota baru',
        textAlign: TextAlign.center,
        style: AppText.w700(20),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 230,
              child: NfcTapBox(
                large: true,
                onScan: _onScan,
                active: () => mounted && !_done,
              ),
            ),
            if (_message != null) ...[
              const Gap(12),
              Text(
                _message!,
                key: const Key('new_card_message'),
                textAlign: TextAlign.center,
                style: AppText.w600(15, AppColors.red),
              ),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          key: const Key('new_card_cancel'),
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(minimumSize: const Size(160, 56)),
          child: const Text('Batal'),
        ),
      ],
    );
  }
}

/// Pilih anggota terdaftar ([Member]) atau lansia dari riwayat
/// ([PatientMatch]) untuk ditautkan ke kartu baru.
class _LinkPickerScreen extends StatefulWidget {
  final String pendingUid;
  const _LinkPickerScreen({required this.pendingUid});

  @override
  State<_LinkPickerScreen> createState() => _LinkPickerScreenState();
}

class _LinkPickerScreenState extends State<_LinkPickerScreen> {
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

  @override
  Widget build(BuildContext context) {
    final q = _search.text;
    final members = filterMembers(MemberStore.instance.members, q);
    final store = MemberStore.instance;
    // Lansia di riwayat yang sudah jadi anggota (NIK sama) tidak diulang.
    final history = [
      for (final h in findPatients(q, RecordStore.instance.records, limit: 8))
        if (h.profile.nik == null || store.byNik(h.profile.nik!) == null) h,
    ];
    final now = DateTime.now();
    final hPad = context.isMedium ? 28.0 : 16.0;
    return Scaffold(
      appBar: AppBar(
        title: Text('Tautkan kartu ${formatUid(widget.pendingUid)}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
          children: [
            MaxWidth(
              maxWidth: 900,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('link_search'),
                    controller: _search,
                    autofocus: true,
                    style: AppText.w500(17),
                    decoration: const InputDecoration(
                      hintText: 'Cari nama / NIK',
                      prefixIcon: Icon(Icons.search_rounded, size: 26),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  ),
                  const Gap(16),
                  SectionCard(
                    title: 'Anggota terdaftar',
                    subtitle: 'Kartu lama diganti dengan kartu ini',
                    child: members.isEmpty
                        ? _none('Tidak ada anggota yang cocok')
                        : Column(
                            children: [
                              for (var i = 0; i < members.length; i++) ...[
                                if (i > 0) const Divider(),
                                MemberTile(
                                  key: Key('link_member_$i'),
                                  member: members[i],
                                  onTap: () =>
                                      Navigator.pop(context, members[i]),
                                ),
                              ],
                            ],
                          ),
                  ),
                  const Gap(16),
                  SectionCard(
                    title: 'Pernah diperiksa',
                    subtitle: 'Dari riwayat di perangkat ini',
                    child: history.isEmpty
                        ? _none(
                            q.trim().length < 2
                                ? 'Ketik minimal 2 huruf nama'
                                : 'Tidak ada di riwayat',
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < history.length; i++) ...[
                                if (i > 0) const Divider(),
                                HistoryPersonTile(
                                  key: Key('link_history_$i'),
                                  match: history[i],
                                  now: now,
                                  onTap: () =>
                                      Navigator.pop(context, history[i]),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _none(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(text, style: AppText.w400(14, AppColors.grey4)),
  );
}
