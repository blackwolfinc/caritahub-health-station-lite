import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../app/theme.dart';
import '../data/app_settings.dart';
import '../data/member_store.dart';
import '../models/health_record.dart';
import '../utils/nik.dart';
import '../widgets/common.dart';
import '../widgets/measurement_cards.dart' show parseNum;
import '../widgets/member_widgets.dart';
import '../widgets/onscreen_keyboard.dart';

/// Kolom isian anggota, urut sesuai tombol "Lanjut" di keyboard layar.
enum _Field {
  name('Nama', KeypadLayout.letters),
  nik('NIK', KeypadLayout.digits),
  age('Umur', KeypadLayout.digits),
  height('Tinggi', KeypadLayout.decimal);

  final String label;
  final KeypadLayout layout;
  const _Field(this.label, this.layout);
}

/// Tambah / ubah anggota kartu NFC. Selalu terikat ke satu UID kartu:
/// [existing] (ubah) atau [uid] (kartu baru yang baru saja ditempel).
/// Selesai → `Navigator.pop` dengan [Member] yang tersimpan (null bila dihapus
/// atau dibatalkan).
class MemberFormScreen extends StatefulWidget {
  const MemberFormScreen({super.key, this.existing, this.uid})
    : assert(existing != null || uid != null, 'Butuh UID kartu');

  final Member? existing;
  final String? uid;

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _name = TextEditingController();
  final _nik = TextEditingController();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _focus = {for (final f in _Field.values) f: FocusNode()};
  Gender? _gender;
  String? _nikError;

  /// Tanggal lahir dari NIK yang valid; umur lalu dihitung otomatis.
  DateTime? _birthDate;
  bool _saving = false;

  _Field _active = _Field.name;

  late final String _uid = normalizeUid(
    widget.existing?.uid ?? widget.uid ?? '',
  );

  static final _nikFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(16),
  ];
  static final _ageFormatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(3),
  ];
  static final _heightFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
  ];

  /// Sama dengan beranda: nyala di tablet (sisi terpendek ≥ 600).
  bool get _keyboardMode =>
      AppSettings.instance.onScreenKeyboard ??
      MediaQuery.sizeOf(context).shortestSide >= 600;

  TextEditingController _controllerOf(_Field f) => switch (f) {
    _Field.name => _name,
    _Field.nik => _nik,
    _Field.age => _age,
    _Field.height => _height,
  };

  List<TextInputFormatter> _formattersOf(_Field f) => switch (f) {
    _Field.name => const [],
    _Field.nik => _nikFormatters,
    _Field.age => _ageFormatters,
    _Field.height => _heightFormatters,
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      final p = e.profileOn(DateTime.now());
      _name.text = p.name;
      _nik.text = p.nik ?? '';
      _gender = p.gender;
      _birthDate = p.birthDate;
      _age.text = p.age?.toString() ?? '';
      _height.text = p.heightCm == null
          ? ''
          : (p.heightCm! % 1 == 0
                ? p.heightCm!.toStringAsFixed(0)
                : p.heightCm!.toStringAsFixed(1).replaceAll('.', ','));
    }
    _initial = _snapshot();
    _name.addListener(() => setState(() {}));
    for (final c in [_nik, _age, _height]) {
      c.addListener(_onEdited);
    }
    for (final f in _Field.values) {
      _focus[f]!.addListener(() {
        if (_focus[f]!.hasFocus && _active != f) setState(() => _active = f);
      });
    }
    AppSettings.instance.addListener(_onSettings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _keyboardMode && e == null) {
        _focus[_Field.name]!.requestFocus();
      }
    });
  }

  void _onSettings() => setState(() {});

  /// Isian saat layar dibuka — pembanding untuk "ada perubahan".
  late final String _initial;
  String _snapshot() => [
    _name.text.trim(),
    Nik.normalize(_nik.text),
    _age.text.trim(),
    _height.text.trim(),
    _gender?.name ?? '',
  ].join('|');
  bool get _dirty => _snapshot() != _initial;
  bool _wasDirty = false;

  /// Bangun ulang hanya bila status "ada perubahan" berganti (PopScope).
  void _onEdited() {
    if (_dirty != _wasDirty) setState(() => _wasDirty = _dirty);
  }

  /// Keluar dengan isian belum disimpan → konfirmasi dulu.
  Future<void> _confirmLeave() async {
    final ok = await confirmDialog(
      context,
      title: 'Buang perubahan?',
      message: 'Data anggota yang sudah diisi belum disimpan.',
      confirmLabel: 'Buang',
      cancelLabel: 'Lanjut mengisi',
      destructive: true,
      icon: Icons.edit_off_rounded,
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    for (final c in [_name, _nik, _age, _height]) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    AppSettings.instance.removeListener(_onSettings);
    super.dispose();
  }

  /// NIK lengkap & valid → L/P dan tanggal lahir diisi dari NIK.
  void _onNikChanged(String v) {
    final digits = Nik.normalize(v);
    setState(() {
      _nikError = digits.length == 16 ? Nik.validate(digits) : null;
      final d = digits.length == 16 ? Nik.decode(digits) : null;
      _birthDate = d?.birthDate;
      if (d != null) {
        _gender = d.gender;
        _age.text = '${Nik.ageOn(d.birthDate, DateTime.now())}';
      }
      // Kolom umur disembunyikan bila tanggal lahir sudah dari NIK.
      if (_birthDate != null && _active == _Field.age) _active = _Field.nik;
    });
  }

  Future<void> _toggleKeyboardMode() async {
    final on = !_keyboardMode;
    FocusScope.of(context).unfocus();
    await AppSettings.instance.setOnScreenKeyboard(on);
    if (!mounted) return;
    if (on) _focus[_active]!.requestFocus();
  }

  /// Ketikan dari keyboard layar masuk ke kolom yang aktif.
  void _edit(bool Function(TextEditingController c) apply) {
    final f = _active;
    final focus = _focus[f]!;
    if (!focus.hasFocus) focus.requestFocus();
    if (!apply(_controllerOf(f))) return;
    if (f == _Field.nik) _onNikChanged(_nik.text);
  }

  void _typeKey(String text) => _edit(
    (c) => typeInto(
      c,
      text,
      formatters: _formattersOf(_active),
      capitalizeWords: _active == _Field.name,
    ),
  );

  void _clearField() => _edit((c) {
    if (c.text.isEmpty) return false;
    c.clear();
    return true;
  });

  /// Umur tidak diisi manual bila tanggal lahir sudah diketahui dari NIK.
  _Field? get _nextField {
    for (var i = _active.index + 1; i < _Field.values.length; i++) {
      final f = _Field.values[i];
      if (f != _Field.age || _birthDate == null) return f;
    }
    return null;
  }

  bool get _canSave => _name.text.trim().isNotEmpty && !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    final store = MemberStore.instance;
    final nik = Nik.normalize(_nik.text);
    final nikError = nik.isEmpty ? null : Nik.validate(nik);
    setState(() => _nikError = nikError);
    if (nikError != null) return;
    // Satu orang = satu anggota: NIK milik anggota lain.
    final sameNik = nik.isEmpty ? null : store.byNik(nik);
    if (sameNik != null && sameNik.uid != _uid) {
      setState(() => _nikError = nikInUseMessage(sameNik));
      if (widget.existing != null) return;
      final moved = await offerRelinkByNik(context, sameNik, _uid);
      if (moved != null && mounted) Navigator.pop(context, moved);
      return;
    }
    final now = DateTime.now();
    final birth = nik.isEmpty ? null : Nik.decode(nik)?.birthDate;
    final age = birth != null
        ? Nik.ageOn(birth, now)
        : int.tryParse(_age.text.trim());
    final height = parseNum(_height.text);
    final member = Member(
      uid: _uid,
      profile: PersonProfile(
        name: _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
        gender: _gender,
        age: (age != null && age > 0 && age < 130) ? age : null,
        heightCm: (height != null && height >= 50 && height <= 250)
            ? height
            : null,
        nik: nik.isEmpty ? null : nik,
        birthDate: birth,
      ),
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      // Anggota baru tidak boleh menimpa pemilik kartu (satu kartu = satu
      // anggota); ubah data memakai UID & tanggal daftar yang sama.
      await (widget.existing == null
          ? store.add(member)
          : store.upsert(member));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(
        context,
        e is CardInUseException ? e.message : 'Gagal menyimpan anggota: $e',
        error: true,
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, member);
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Hapus anggota?',
      message:
          '${e.profile.name} dihapus dari daftar anggota dan kartunya tidak '
          'berlaku lagi. Riwayat pemeriksaan tetap tersimpan.',
      confirmLabel: 'Hapus',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    try {
      await MemberStore.instance.delete(e.uid);
    } catch (err) {
      if (mounted) showSnack(context, 'Gagal menghapus: $err', error: true);
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = _keyboardMode ? _buildKeyboard() : null;
    final form = _buildForm();
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Anggota baru' : 'Ubah data anggota',
        ),
        actions: [
          IconButton(
            key: const Key('keyboard_mode_toggle'),
            tooltip: _keyboardMode
                ? 'Pakai keyboard sistem'
                : 'Pakai keyboard layar (tablet)',
            iconSize: 28,
            isSelected: _keyboardMode,
            onPressed: _toggleKeyboardMode,
            icon: const Icon(Icons.keyboard_alt_outlined),
            selectedIcon: const Icon(Icons.keyboard_alt_rounded),
          ),
          const Gap(8),
        ],
      ),
      body: KeyboardSplitLayout(form: form, keyboard: keyboard),
    );
    return PopScope(
      canPop: _saving || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: scaffold,
    );
  }

  InputDecoration _decoration(String label, {String? suffix}) =>
      InputDecoration(
        labelText: label,
        suffixText: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      );

  Widget _buildForm() {
    final numberType = _keyboardMode
        ? TextInputType.none
        : TextInputType.number;
    return SectionCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MemberCardChip(uid: _uid),
          const Gap(16),
          TextField(
            key: const Key('member_name_field'),
            controller: _name,
            focusNode: _focus[_Field.name],
            keyboardType: _keyboardMode ? TextInputType.none : null,
            textCapitalization: TextCapitalization.words,
            style: AppText.w600(22),
            decoration: const InputDecoration(
              labelText: 'Nama',
              hintText: 'mis. Siti Aminah',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 28),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 22,
              ),
            ),
          ),
          const Gap(12),
          TextField(
            key: const Key('member_nik_field'),
            controller: _nik,
            focusNode: _focus[_Field.nik],
            keyboardType: numberType,
            inputFormatters: _nikFormatters,
            onChanged: _onNikChanged,
            style: AppText.w600(18),
            decoration: InputDecoration(
              labelText: 'NIK (opsional)',
              prefixIcon: const Icon(Icons.badge_outlined),
              errorText: _nikError,
              helperText: _birthDate != null
                  ? 'L/P dan tanggal lahir diisi dari NIK'
                  : 'Wajib bila hasil dikirim ke SATUSEHAT',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
          ),
          const Gap(14),
          LayoutBuilder(
            builder: (context, c) {
              final gender = SegmentedButton<Gender?>(
                key: const Key('member_gender'),
                segments: const [
                  ButtonSegment(value: Gender.male, label: Text('L')),
                  ButtonSegment(value: Gender.female, label: Text('P')),
                ],
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(64, 60)),
                  textStyle: WidgetStatePropertyAll(AppText.w700(18)),
                ),
                selected: {_gender},
                onSelectionChanged: (s) => setState(() {
                  _gender = s.isEmpty ? null : s.first;
                  _wasDirty = _dirty;
                }),
              );
              final age = _birthDate != null
                  ? BirthDateInfo(birthDate: _birthDate!)
                  : TextField(
                      key: const Key('member_age_field'),
                      controller: _age,
                      focusNode: _focus[_Field.age],
                      keyboardType: numberType,
                      inputFormatters: _ageFormatters,
                      style: AppText.w600(18),
                      decoration: _decoration('Umur', suffix: 'th'),
                    );
              final height = TextField(
                key: const Key('member_height_field'),
                controller: _height,
                focusNode: _focus[_Field.height],
                keyboardType: _keyboardMode
                    ? TextInputType.none
                    : const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _heightFormatters,
                style: AppText.w600(18),
                decoration: _decoration('Tinggi', suffix: 'cm'),
              );
              final fields = Row(
                children: [
                  Expanded(child: age),
                  const Gap(12),
                  Expanded(child: height),
                ],
              );
              return c.maxWidth >= 420
                  ? Row(
                      children: [
                        gender,
                        const Gap(12),
                        Expanded(child: fields),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [gender, const Gap(10), fields],
                    );
            },
          ),
          const Gap(20),
          FilledButton.icon(
            key: const Key('member_save_button'),
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 68),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.save_outlined, size: 28),
            label: Text(
              'Simpan anggota',
              style: AppText.w700(19, Colors.white),
            ),
          ),
          if (widget.existing != null) ...[
            const Gap(12),
            OutlinedButton.icon(
              key: const Key('member_delete_button'),
              onPressed: _saving ? null : _delete,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 56),
                foregroundColor: AppColors.red,
                side: const BorderSide(color: AppColors.red),
              ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Hapus anggota'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKeyboard() {
    final next = _nextField;
    return OnScreenKeyboard(
      layout: _active.layout,
      fieldLabel: _active.label,
      onKey: _typeKey,
      onBackspace: () => _edit(backspaceIn),
      onClear: _clearField,
      onNext: next == null ? null : () => _focus[next]!.requestFocus(),
      onSubmit: _canSave ? _save : null,
      onClose: _toggleKeyboardMode,
      keyHeight: context.isWide ? 72 : 60,
      submitLabel: 'Simpan',
      submitIcon: Icons.save_outlined,
    );
  }
}
