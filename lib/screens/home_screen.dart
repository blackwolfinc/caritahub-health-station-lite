import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../app/kiosk.dart';
import '../app/nfc_reader.dart';
import '../app/sound.dart';
import '../app/theme.dart';
import '../data/app_settings.dart';
import '../data/member_store.dart';
import '../data/patient_lookup.dart';
import '../data/record_store.dart';
import '../models/health_record.dart';
import '../printing/print_queue.dart';
import '../utils/nik.dart';
import '../widgets/common.dart';
import '../widgets/device_status_bar.dart';
import '../widgets/measurement_cards.dart' show parseNum;
import '../widgets/member_widgets.dart';
import '../widgets/nfc_tap_box.dart';
import '../widgets/onscreen_keyboard.dart';
import '../widgets/patient_suggestions.dart';
import 'history_screen.dart';
import 'members_screen.dart';
import 'measurement_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

part 'home_card_flow.dart';

/// Layar awal: ketik nama → Enter → langsung ukur. Setelah selesai, layar
/// kembali ke sini dengan kolom nama siap untuk lansia berikutnya.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Kolom isian awal, urut sesuai tombol "Lanjut" di keyboard layar.
enum _Field {
  name('Nama', KeypadLayout.letters),
  nik('NIK', KeypadLayout.digits),
  age('Umur', KeypadLayout.digits),
  height('Tinggi', KeypadLayout.decimal);

  final String label;
  final KeypadLayout layout;
  const _Field(this.label, this.layout);
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _nik = TextEditingController();
  final _nameFocus = FocusNode();
  final _nikFocus = FocusNode();
  final _ageFocus = FocusNode();
  final _heightFocus = FocusNode();
  Gender? _gender;
  String? _nikError;
  bool _fromNik = false;

  /// NIK hanya diisi bila lansia membawa KTP; kolomnya disembunyikan dulu.
  bool _hasKtp = false;

  /// Nama yang terakhir diisi dari saran riwayat — saran disembunyikan
  /// selama nama belum diubah lagi.
  String? _pickedName;

  // ── Kartu NFC ──
  /// Kartu anggota yang terhubung dengan orang di form (bila ada).
  String? _cardUid;

  /// Menunggu kartu untuk ditautkan ke orang di form.
  bool _awaitingCard = false;

  /// Form diisi dari kartu yang ditempel (bukan dari saran yang kebetulan
  /// punya kartu) — batal ukur lalu mengosongkan form untuk lansia berikutnya.
  bool _fromCardTap = false;

  /// Umur / tinggi di luar rentang (ditampilkan, tidak dibuang diam-diam).
  String? _bodyError;

  /// Sedang memproses satu tempelan kartu (tempelan lain diabaikan).
  bool _cardBusy = false;

  /// NFC perangkat (null = belum dicek).
  NfcStatus? _nfc;

  /// Tablet ber-NFC: kotak kartu besar di atas antena NFC dan kolom nama
  /// dalam satu tampilan.
  bool _cardHome(bool wide) => wide && (_nfc?.available ?? false);

  void _setCardBusy(bool v) => _cardBusy = v;
  void _setAwaitingCard(bool v) => setState(() => _awaitingCard = v);
  void _applyCardUid(String? uid) => setState(() {
    _cardUid = uid;
    _cardName = _name.text.trim();
  });

  /// Nama saat kartu dihubungkan (untuk mendeteksi nama diganti).
  String? _cardName;

  /// Pakai identitas lansia yang pernah diperiksa.
  void _applyMatch(PatientMatch m) {
    final p = m.carriedTo(DateTime.now());
    final member = p.nik == null ? null : MemberStore.instance.byNik(p.nik!);
    _fillFromProfile(p, cardUid: member?.uid);
  }

  void _fillFromProfile(
    PersonProfile p, {
    String? cardUid,
    bool fromTap = false,
  }) {
    setState(() {
      _cardUid = cardUid;
      _fromCardTap = fromTap;
      _cardName = p.name;
      _awaitingCard = false;
      _name.text = p.name;
      _name.selection = TextSelection.collapsed(offset: p.name.length);
      _pickedName = p.name;
      _gender = p.gender;
      _age.text = p.age?.toString() ?? '';
      _height.text = p.heightCm == null ? '' : _heightText(p.heightCm!);
      _bodyError = null;
      _autoGender = null;
      _autoAge = null;
      _fromNik = false;
      _nikError = null;
      _hasKtp = p.nik != null;
      _nik.text = p.nik ?? '';
      _active = _Field.name;
    });
  }

  /// Kolom yang menerima ketikan keyboard layar.
  _Field _active = _Field.name;

  /// 152 → "152", 152.5 → "152,5".
  static String _heightText(double cm) => cm % 1 == 0
      ? cm.toStringAsFixed(0)
      : cm.toStringAsFixed(1).replaceAll('.', ',');

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

  /// Bawaan: nyala di tablet (sisi terpendek ≥ 600), mati di genggam.
  bool get _keyboardMode =>
      AppSettings.instance.onScreenKeyboard ??
      MediaQuery.sizeOf(context).shortestSide >= 600;

  TextEditingController _controllerOf(_Field f) => switch (f) {
    _Field.name => _name,
    _Field.nik => _nik,
    _Field.age => _age,
    _Field.height => _height,
  };

  FocusNode _focusOf(_Field f) => switch (f) {
    _Field.name => _nameFocus,
    _Field.nik => _nikFocus,
    _Field.age => _ageFocus,
    _Field.height => _heightFocus,
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
    _name.addListener(
      () => setState(() {
        // Nama diganti → bukan lagi pemilik kartu yang tadi ditempel.
        if (_cardUid != null && _name.text.trim() != _cardName) {
          _cardUid = null;
          _fromCardTap = false;
        }
        // Nama dihapus → tidak ada orang untuk ditautkan; batalkan tunggu.
        if (_awaitingCard && _name.text.trim().isEmpty) _awaitingCard = false;
      }),
    );
    for (final c in [_age, _height]) {
      c.addListener(() {
        if (_bodyError != null) setState(() => _bodyError = null);
      });
    }
    for (final f in _Field.values) {
      _focusOf(f).addListener(() {
        if (_focusOf(f).hasFocus && _active != f) setState(() => _active = f);
      });
    }
    AppSettings.instance.addListener(_onSettings);
    unawaited(
      NfcReader.status().then((s) {
        if (mounted) setState(() => _nfc = s);
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _keyboardMode) _nameFocus.requestFocus();
    });
  }

  void _onSettings() => setState(() {});

  /// Mode kiosk: masuk langsung; keluar minta konfirmasi supaya tidak
  /// tersentuh tak sengaja oleh pengunjung.
  Future<void> _toggleKiosk() async {
    final on = AppSettings.instance.kioskMode;
    if (on) {
      final ok = await confirmDialog(
        context,
        title: 'Keluar dari mode kiosk?',
        message:
            'Bilah sistem muncul lagi dan aplikasi bisa ditinggalkan. '
            'Untuk petugas saja.',
        confirmLabel: 'Keluar kiosk',
        icon: Icons.lock_open_rounded,
      );
      if (!ok) return;
    }
    await Kiosk.setEnabled(!on);
  }

  Future<void> _toggleKeyboardMode() async {
    final on = !_keyboardMode;
    // Lepas fokus dulu supaya jenis keyboard sistem ikut berganti.
    FocusScope.of(context).unfocus();
    await AppSettings.instance.setOnScreenKeyboard(on);
    if (!mounted) return;
    if (on) _focusOf(_active).requestFocus();
  }

  /// Ketikan dari keyboard layar masuk ke kolom yang aktif.
  void _edit(bool Function(TextEditingController c) apply) {
    final f = _active;
    final focus = _focusOf(f);
    if (!focus.hasFocus) focus.requestFocus();
    if (!apply(_controllerOf(f))) return;
    if (f == _Field.nik) _onNikChanged(_nik.text);
    if (f == _Field.age) _onAgeChanged(_age.text);
  }

  /// Umur lengkap → langsung ke Tinggi. Dua angka sudah pasti lengkap,
  /// kecuali 10–12 yang masih bisa menjadi 100–129.
  void _onAgeChanged(String v) {
    final n = int.tryParse(v.trim());
    final complete = v.trim().length >= 3 || (n != null && n >= 13);
    if (complete && _ageFocus.hasFocus) _heightFocus.requestFocus();
  }

  /// L/P dipilih → lanjut isi umur.
  void _onGenderChanged(Set<Gender?> s) {
    setState(() => _gender = s.isEmpty ? null : s.first);
    if (_gender != null) _ageFocus.requestFocus();
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

  _Field? get _nextField {
    for (var i = _active.index + 1; i < _Field.values.length; i++) {
      final f = _Field.values[i];
      if (f != _Field.nik || _hasKtp) return f;
    }
    return null;
  }

  /// Saklar KTP dimatikan → NIK & isian otomatis dari NIK ikut dihapus.
  void _setHasKtp(bool v) {
    if (!v) {
      _nik.clear();
      _onNikChanged('');
      if (_active == _Field.nik) _active = _Field.name;
    }
    setState(() {
      _hasKtp = v;
      if (v) _active = _Field.nik;
    });
    // Kolom NIK baru ada setelah frame ini dibangun.
    if (v) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hasKtp) _nikFocus.requestFocus();
      });
    }
  }

  // Nilai L/P & umur yang terakhir diisi otomatis dari NIK. Bila NIK
  // dikoreksi, nilai itu ikut diperbarui — kecuali petugas sudah mengubahnya.
  Gender? _autoGender;
  String? _autoAge;

  /// NIK lengkap → isi L/P dan umur otomatis bila masih kosong.
  void _onNikChanged(String v) {
    final digits = Nik.normalize(v);
    setState(() {
      _nikError = digits.length == 16 ? Nik.validate(digits) : null;
      // Hapus isian otomatis dari NIK sebelumnya yang belum diubah petugas.
      if (_autoGender != null && _gender == _autoGender) _gender = null;
      if (_autoAge != null && _age.text.trim() == _autoAge) _age.clear();
      _autoGender = null;
      _autoAge = null;
      _fromNik = false;
      final d = digits.length == 16 ? Nik.decode(digits) : null;
      if (d != null) {
        if (_gender == null) {
          _gender = _autoGender = d.gender;
          _fromNik = true;
        }
        final age = Nik.ageOn(d.birthDate, DateTime.now());
        if (_age.text.trim().isEmpty && age >= 0 && age < 130) {
          _age.text = _autoAge = '$age';
          _fromNik = true;
        }
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _nik.dispose();
    _nameFocus.dispose();
    _nikFocus.dispose();
    _ageFocus.dispose();
    _heightFocus.dispose();
    AppSettings.instance.removeListener(_onSettings);
    super.dispose();
  }

  bool get _canStart => _name.text.trim().isNotEmpty;

  /// L/P yang dipilih bertentangan dengan NIK (tanggal lahir > 40 = P).
  String? get _genderMismatch {
    final d = Nik.decode(_nik.text);
    if (d == null || _gender == null || _gender == d.gender) return null;
    return 'L/P tidak sesuai NIK (NIK: ${d.gender.label.toLowerCase()})';
  }

  /// "1,55" (meter) → "155" (cm).
  void _metresToCm() {
    final h = parseNum(_height.text);
    if (h == null || h <= 0 || h >= 3) return;
    _height.text = _heightText((h * 1000).round() / 10);
  }

  /// Umur / tinggi terisi tapi di luar rentang.
  ({_Field field, String message})? _bodyProblem() {
    final a = _age.text.trim();
    final age = int.tryParse(a);
    if (a.isNotEmpty && (age == null || age < 1 || age > 129)) {
      return (field: _Field.age, message: 'Umur 1–129 th');
    }
    final h = _height.text.trim();
    final cm = parseNum(h);
    if (h.isNotEmpty && (cm == null || cm < 50 || cm > 250)) {
      return (field: _Field.height, message: 'Tinggi 50–250 cm');
    }
    return null;
  }

  /// Cek isian sebelum mulai / menautkan kartu: pesan tampil di form dan
  /// kursor ke kolom yang salah. null = semua benar.
  String? _validateForm() {
    _metresToCm();
    final digits = Nik.normalize(_nik.text);
    final nikError = digits.isEmpty ? null : Nik.validate(digits);
    final body = _bodyProblem();
    setState(() {
      _nikError = nikError;
      _bodyError = body?.message;
    });
    final bad = nikError != null ? _Field.nik : body?.field;
    if (bad != null) _focusOf(bad).requestFocus();
    return nikError ?? _genderMismatch ?? body?.message;
  }

  Future<void> _start() async {
    if (!_canStart) return;
    if (_validateForm() != null) return;
    FocusScope.of(context).unfocus();
    final age = int.tryParse(_age.text.trim());
    final height = parseNum(_height.text);
    final profile = PersonProfile(
      name: _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      gender: _gender,
      age: (age != null && age > 0 && age < 130) ? age : null,
      heightCm: (height != null && height >= 50 && height <= 250)
          ? height
          : null,
      nik: Nik.normalize(_nik.text).isEmpty ? null : Nik.normalize(_nik.text),
      birthDate: Nik.decode(_nik.text)?.birthDate,
    );
    final outcome = await Navigator.of(context).push<MeasurementOutcome>(
      MaterialPageRoute(builder: (_) => MeasurementScreen(profile: profile)),
    );
    if (!mounted) return;
    if (outcome == null) {
      // Dibatalkan. Dari tempelan kartu → form bersih untuk lansia
      // berikutnya; dari ketikan / saran → data tetap untuk diperbaiki.
      if (_fromCardTap) _reset();
      return;
    }
    _reset();
    // Pilih "Cetak": halaman hasil sudah terbuka di atas beranda — jangan
    // tampilkan snackbar/fokus di bawahnya (tombol LIHAT akan menggandakan
    // halaman hasil).
    if (outcome.printing) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.charcoal,
          content: Text('${outcome.name} tersimpan'),
          action: SnackBarAction(
            label: 'LIHAT',
            textColor: Colors.white,
            onPressed: () => _open(ResultScreen(recordId: outcome.recordId)),
          ),
        ),
      );
    // Siap untuk lansia berikutnya.
    _nameFocus.requestFocus();
  }

  void _reset() {
    setState(() {
      _name.clear();
      _age.clear();
      _height.clear();
      _nik.clear();
      _hasKtp = false;
      _pickedName = null;
      _cardUid = null;
      _fromCardTap = false;
      _awaitingCard = false;
      _nikError = null;
      _bodyError = null;
      _fromNik = false;
      _autoGender = null;
      _autoAge = null;
      _gender = null;
      _active = _Field.name;
    });
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    // Kotak tempel kartu di atas form: cara tercepat — tanpa mengetik.
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NfcTapBox(
          onScan: _onCardScan,
          active: () => _homeIsCurrent && !_cardBusy,
          prompt: _awaitingCard
              ? 'Tempelkan kartu untuk ${_name.text.trim()}'
              : null,
          lastResult: _awaitingCard
              ? 'Kartu ini akan menjadi kartu anggotanya'
              : null,
        ),
        const Gap(12),
        _buildForm(),
      ],
    );
    final keyboard = _keyboardMode ? _buildKeyboard() : null;
    final hPad = context.isMedium ? 28.0 : 16.0;
    final content = SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
      child: MaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(wide),
            const Gap(16),
            const CorruptHistoryBanner(key: Key('corrupt_banner')),
            const MemberStoreWarning(),
            const Gap(8),
            // Beranda khusus pendaftaran pemeriksaan baru; riwayat & rekap
            // harian ada di halaman Riwayat (tombol di atas).
            if (keyboard != null && wide)
              // Mode tablet: form kiri, keyboard kanan.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: form),
                  const Gap(20),
                  Expanded(flex: 6, child: keyboard),
                ],
              )
            else ...[
              if (!context.isMedium) ...[
                DeviceStatusBar(
                  iconSize: 28,
                  onManage: () => _open(const SettingsScreen()),
                ),
                const Gap(12),
              ],
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: form,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (_cardHome(wide)) {
      return Scaffold(body: SafeArea(child: _buildCardHome(wide, hPad)));
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: content),
            // Layar sempit/potret: keyboard menempel di bawah, form tetap
            // bisa digulir di atasnya.
            if (keyboard != null && !wide)
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
                child: MaxWidth(maxWidth: 900, child: keyboard),
              ),
          ],
        ),
      ),
    );
  }

  /// Satu tampilan untuk tablet ber-NFC: kotak seukuran kartu asli
  /// (86 × 54 mm) tepat di atas antena NFC (Falcon2: tengah-kiri layar),
  /// kolom nama di bawahnya, data lain + keyboard di kanan. Lansia cukup
  /// tempel kartu; tanpa kartu, nama langsung diketik di layar yang sama.
  Widget _buildCardHome(bool wide, double hPad) {
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final inScreen = hasInScreenNfc(_nfc?.model ?? '');
    // Falcon2 11,6": ±4,4 dp per mm → kartu ±378 × 238 dp.
    final card = inScreen ? const Size(378, 238) : const Size(340, 214);
    final cy = screen.height * 0.5 - pad.top;
    // Satu kartu putih berisi semua isian. Area tempel kartu (tengah-kiri,
    // di atas antena NFC) menjadi latar di belakang Nama, L/P, umur, dan
    // tinggi — selebar kartu asli + margin kecil; sisa lebar untuk keyboard.
    const inset = 20.0;
    final innerLeft = hPad + inset;
    // Minimal 402 dp supaya L/P, umur, tinggi muat satu baris.
    final innerWidth = card.width + 24 < 402 ? 402.0 : card.width + 24;
    final panelWidth = innerWidth + 2 * inset;
    final top = (cy - card.height / 2).clamp(170.0, screen.height);
    const contentTop = 86.0;
    final contentBottom = screen.height - pad.vertical - 20;
    const startH = 60.0;
    final zoneTop = top - 14;
    final zoneBottom = top + card.height + 14;
    // Kolom isian di atas latar biru: isi putih + garis tipis.
    final theme = Theme.of(context);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    );
    final onZone = theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        fillColor: AppColors.surface,
        border: fieldBorder,
        enabledBorder: fieldBorder,
      ),
    );
    final startTop = (contentBottom - inset - startH).clamp(
      zoneBottom + 12,
      double.infinity,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(wide),
                const Gap(12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        key: const Key('card_name_panel'),
                        width: panelWidth,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                        ),
                      ),
                      const Gap(16),
                      Expanded(child: _buildSidePanel()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: innerLeft,
          width: innerWidth,
          top: contentTop + 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pemeriksaan baru', style: AppText.w700(24)),
                    const Gap(2),
                    Text(
                      'Tempel kartu anggota, atau ketik nama.',
                      style: AppText.w400(15, AppColors.grey1),
                    ),
                  ],
                ),
              ),
              _ktpChip(),
            ],
          ),
        ),
        // Latar area kartu (seukuran kartu asli + margin).
        Positioned(
          left: innerLeft,
          top: zoneTop,
          width: innerWidth,
          height: zoneBottom - zoneTop,
          child: NfcTapBox(
            large: true,
            subtle: true,
            onScan: _onCardScan,
            active: () => _homeIsCurrent && !_cardBusy,
            prompt: _awaitingCard ? '' : null,
          ),
        ),
        // Isian di atas latar kartu.
        Positioned(
          left: innerLeft + 14,
          width: innerWidth - 28,
          top: zoneTop + 12,
          height: zoneBottom - zoneTop - 20,
          child: Theme(
            data: onZone,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cardZoneLabel(),
                const Gap(8),
                _nameField(),
                const Gap(12),
                _bodyFields(),
                const Spacer(),
                if (_bodyError != null)
                  _bodyErrorText()
                else
                  Text(
                    'Kartu anggota · tahan sebentar di area biru',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.w500(13, AppColors.grey1),
                  ),
              ],
            ),
          ),
        ),
        if (_hasKtp)
          Positioned(
            left: innerLeft,
            width: innerWidth,
            top: zoneBottom + 12,
            child: _nikField(),
          ),
        Positioned(
          left: innerLeft,
          width: innerWidth,
          top: startTop,
          child: _startButton(height: startH),
        ),
      ],
    );
  }

  /// Label kecil area kartu: ajakan tempel, tautkan, atau kartu terhubung.
  Widget _cardZoneLabel() {
    final name = _name.text.trim();
    if (_cardUid != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _CardLinkedChip(uid: _cardUid!),
      );
    }
    final color = _awaitingCard ? AppColors.orangeAction : AppColors.primary;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Icon(Icons.contactless_rounded, size: 24, color: color),
          const Gap(8),
          Expanded(
            child: Text(
              _awaitingCard
                  ? 'Tempelkan kartu untuk $name'
                  : 'Tempelkan kartu di sini',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.w700(16, color),
            ),
          ),
          if (name.isNotEmpty)
            TextButton.icon(
              key: const Key('link_card_button'),
              onPressed: _toggleAwaitingCard,
              style: TextButton.styleFrom(
                foregroundColor: color,
                minimumSize: const Size(0, 40),
              ),
              icon: Icon(
                _awaitingCard ? Icons.close_rounded : Icons.link_rounded,
                size: 20,
              ),
              label: Text(_awaitingCard ? 'Batal' : 'Tautkan'),
            ),
        ],
      ),
    );
  }

  /// Kanan: lansia yang pernah diperiksa (saat mengetik) — lalu keyboard.
  Widget _buildSidePanel() {
    final keyboard = _keyboardMode ? _buildKeyboard(keyHeight: 64) : null;
    final matches = _matches;
    final info = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CorruptHistoryBanner(key: Key('corrupt_banner')),
            const MemberStoreWarning(),
            if (matches.isNotEmpty)
              PatientSuggestions(matches: matches, onPick: _applyMatch)
            else
              const _HomeGuide(),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (keyboard != null) ...[
          Expanded(child: info),
          const Gap(12),
          keyboard,
        ] else
          Flexible(child: info),
      ],
    );
  }

  Widget _buildHeader(bool wide) {
    return Row(
      children: [
        // Tablet potret / sempit: logo bertumpuk supaya ikon alat muat.
        Expanded(child: BrandHeader(compact: !wide)),
        // Alat terpasang / belum, langsung terlihat sebelum mulai.
        if (context.isMedium)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DeviceStatusBar(
              iconSize: wide ? 34 : 28,
              onManage: () => _open(const SettingsScreen()),
            ),
          ),
        const _PrintStatusChip(),
        IconButton(
          key: const Key('keyboard_mode_toggle'),
          tooltip: _keyboardMode
              ? 'Pakai keyboard sistem'
              : 'Pakai keyboard layar (tablet)',
          iconSize: 28,
          isSelected: _keyboardMode,
          style: _keyboardMode
              ? IconButton.styleFrom(
                  backgroundColor: AppColors.primarySoft,
                  foregroundColor: AppColors.primary,
                )
              : null,
          onPressed: _toggleKeyboardMode,
          icon: const Icon(Icons.keyboard_alt_outlined),
          selectedIcon: const Icon(Icons.keyboard_alt_rounded),
        ),
        _HistoryButton(onPressed: () => _open(const HistoryScreen())),
        IconButton(
          key: const Key('members_button'),
          tooltip: 'Pendaftaran anggota (kartu)',
          iconSize: 28,
          onPressed: () => _open(const MembersScreen()),
          icon: const Icon(Icons.badge_outlined),
        ),
        _KioskButton(onToggle: _toggleKiosk),
        IconButton(
          tooltip: 'Pengaturan',
          iconSize: 28,
          onPressed: () => _open(const SettingsScreen()),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }

  /// Lansia yang pernah diperiksa & namanya cocok dengan ketikan.
  List<PatientMatch> get _matches {
    final typed = _name.text.trim();
    return typed == _pickedName
        ? const <PatientMatch>[]
        : findPatients(typed, RecordStore.instance.records, limit: 3);
  }

  Widget _buildForm() {
    final matches = _matches;
    return SectionCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Pemeriksaan baru', style: AppText.w700(22)),
              ),
              _ktpChip(),
            ],
          ),
          const Gap(16),
          _nameField(),
          if (matches.isNotEmpty) ...[
            const Gap(8),
            PatientSuggestions(matches: matches, onPick: _applyMatch),
          ],
          ..._cardLink(_name.text.trim()),
          if (_hasKtp) ...[const Gap(12), _nikField()],
          const Gap(14),
          Text(
            'Opsional — untuk komposisi tubuh di timbangan',
            style: AppText.w500(12, AppColors.grey4),
          ),
          const Gap(8),
          _bodyFields(),
          if (_bodyError != null) ...[const Gap(8), _bodyErrorText()],
          const Gap(20),
          _startButton(),
        ],
      ),
    );
  }

  /// NIK hanya bila lansia membawa KTP.
  Widget _ktpChip() => FilterChip(
    key: const Key('ktp_switch'),
    selected: _hasKtp,
    onSelected: _setHasKtp,
    showCheckmark: false,
    avatar: Icon(
      _hasKtp ? Icons.badge_rounded : Icons.badge_outlined,
      size: 20,
      color: _hasKtp ? Colors.white : AppColors.grey1,
    ),
    label: Text(
      'NIK',
      style: AppText.w700(15, _hasKtp ? Colors.white : AppColors.grey1),
    ),
    selectedColor: AppColors.primary,
    backgroundColor: AppColors.lightGrey,
    side: BorderSide.none,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    tooltip: 'Isi NIK (bawa KTP) · wajib untuk SATUSEHAT',
  );

  Widget _nameField() => TextField(
    key: const Key('name_field'),
    controller: _name,
    focusNode: _nameFocus,
    keyboardType: _keyboardMode ? TextInputType.none : null,
    textCapitalization: TextCapitalization.words,
    textInputAction: TextInputAction.go,
    onSubmitted: (_) => _start(),
    style: AppText.w600(22),
    decoration: const InputDecoration(
      labelText: 'Nama',
      hintText: 'mis. Siti Aminah',
      prefixIcon: Icon(Icons.person_outline_rounded, size: 28),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 22),
    ),
  );

  /// Kartu anggota untuk orang ini: sudah terhubung, atau tautkan.
  List<Widget> _cardLink(String typed) => [
    if (_cardUid != null) ...[
      const Gap(8),
      _CardLinkedChip(uid: _cardUid!),
    ] else if (typed.isNotEmpty) ...[
      const Gap(8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('link_card_button'),
          onPressed: _toggleAwaitingCard,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            foregroundColor: _awaitingCard
                ? AppColors.orangeAction
                : AppColors.primary,
          ),
          icon: Icon(
            _awaitingCard ? Icons.close_rounded : Icons.contactless_rounded,
          ),
          label: Text(
            _awaitingCard ? 'Batal tautkan kartu' : 'Tautkan kartu anggota',
          ),
        ),
      ),
    ],
  ];

  Widget _nikField() => TextField(
    key: const Key('nik_field'),
    controller: _nik,
    focusNode: _nikFocus,
    keyboardType: _keyboardMode ? TextInputType.none : TextInputType.number,
    inputFormatters: _nikFormatters,
    onChanged: _onNikChanged,
    onSubmitted: (_) => _start(),
    style: AppText.w600(18),
    decoration: InputDecoration(
      labelText: 'NIK (opsional)',
      prefixIcon: const Icon(Icons.badge_outlined),
      errorText: _nikError ?? _genderMismatch,
      helperText: _fromNik
          ? 'L/P dan umur diisi dari NIK'
          : 'Wajib bila hasil dikirim ke SATUSEHAT',
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      counterText: '',
    ),
  );

  /// Pesan umur / tinggi di luar rentang.
  Widget _bodyErrorText() => Row(
    key: const Key('body_error'),
    children: [
      const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.red),
      const Gap(6),
      Expanded(
        child: Text(
          _bodyError ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.w700(14, AppColors.red),
        ),
      ),
    ],
  );

  /// L/P, umur, tinggi.
  Widget _bodyFields() => LayoutBuilder(
    builder: (context, c) {
      final gender = SegmentedButton<Gender?>(
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
        onSelectionChanged: _onGenderChanged,
      );
      final age = TextField(
        key: const Key('age_field'),
        controller: _age,
        focusNode: _ageFocus,
        keyboardType: _keyboardMode ? TextInputType.none : TextInputType.number,
        inputFormatters: _ageFormatters,
        onChanged: _onAgeChanged,
        style: AppText.w600(18),
        decoration: const InputDecoration(
          labelText: 'Umur',
          suffixText: 'th',
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      );
      final height = TextField(
        key: const Key('height_field'),
        controller: _height,
        focusNode: _heightFocus,
        keyboardType: _keyboardMode
            ? TextInputType.none
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: _heightFormatters,
        style: AppText.w600(18),
        decoration: const InputDecoration(
          labelText: 'Tinggi',
          suffixText: 'cm',
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      );
      if (c.maxWidth >= 360) {
        return Row(
          children: [
            gender,
            const Gap(12),
            Expanded(child: age),
            const Gap(12),
            Expanded(child: height),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gender,
          const Gap(10),
          Row(
            children: [
              Expanded(child: age),
              const Gap(10),
              Expanded(child: height),
            ],
          ),
        ],
      );
    },
  );

  Widget _startButton({double height = 68}) => FilledButton.icon(
    key: const Key('start_button'),
    onPressed: _canStart ? _start : null,
    style: FilledButton.styleFrom(
      minimumSize: Size(0, height),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    icon: const Icon(Icons.monitor_heart_outlined, size: 28),
    label: Text('Mulai pengukuran', style: AppText.w700(19, Colors.white)),
  );

  Widget _buildKeyboard({double? keyHeight}) {
    final next = _nextField;
    return OnScreenKeyboard(
      layout: _active.layout,
      fieldLabel: _active.label,
      onKey: _typeKey,
      onBackspace: () => _edit(backspaceIn),
      onClear: _clearField,
      onNext: next == null ? null : () => _focusOf(next).requestFocus(),
      onSubmit: _canStart ? _start : null,
      onClose: _toggleKeyboardMode,
      keyHeight: keyHeight ?? (context.isWide ? 72 : 60),
    );
  }
}

/// Status antrean cetak latar belakang: diam saat tidak ada apa-apa.
class _PrintStatusChip extends StatelessWidget {
  const _PrintStatusChip();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PrintQueue.instance,
      builder: (context, _) {
        final q = PrintQueue.instance;
        final failed = q.failed;
        if (failed.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ActionChip(
              key: const Key('print_failed_chip'),
              avatar: const Icon(
                Icons.print_disabled_rounded,
                size: 18,
                color: AppColors.red,
              ),
              label: Text('${failed.length} catatan gagal dicetak · Coba lagi'),
              labelStyle: AppText.w600(12, AppColors.red),
              backgroundColor: AppColors.redSoft,
              side: BorderSide.none,
              tooltip: failed.first.message,
              onPressed: q.retryFailed,
            ),
          );
        }
        if (q.pending > 0) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Chip(
              avatar: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
              label: Text('Mencetak ${q.pending}'),
              labelStyle: AppText.w600(12, AppColors.primary),
              backgroundColor: AppColors.primarySoft,
              side: BorderSide.none,
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Tombol Riwayat dengan jumlah lansia yang diperiksa hari ini.
class _HistoryButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _HistoryButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // DayTicker: angka "hari ini" kembali 0 saat lewat tengah malam.
    return DayTicker(
      builder: (context, now) => ListenableBuilder(
        listenable: RecordStore.instance,
        builder: (context, _) {
          // Orang, bukan pemeriksaan (ukur ulang tidak dihitung dua kali).
          final today = RecordStore.countPeople(
            RecordStore.instance.recordsOn(now),
          );
          return IconButton(
            key: const Key('history_button'),
            tooltip: today == 0
                ? 'Riwayat'
                : 'Riwayat · $today lansia hari ini',
            iconSize: 28,
            onPressed: onPressed,
            icon: Badge(
              isLabelVisible: today > 0,
              label: Text('$today'),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.history_rounded),
            ),
          );
        },
      ),
    );
  }
}

/// Tombol mode kiosk (aplikasi dipin, layar penuh).
class _KioskButton extends StatelessWidget {
  final VoidCallback onToggle;
  const _KioskButton({required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final on = AppSettings.instance.kioskMode;
        return IconButton(
          key: const Key('kiosk_toggle'),
          tooltip: on ? 'Mode kiosk aktif · ketuk untuk keluar' : 'Mode kiosk',
          iconSize: 28,
          isSelected: on,
          style: on
              ? IconButton.styleFrom(
                  backgroundColor: AppColors.primarySoft,
                  foregroundColor: AppColors.primary,
                )
              : null,
          onPressed: onToggle,
          icon: const Icon(Icons.lock_open_rounded),
          selectedIcon: const Icon(Icons.lock_rounded),
        );
      },
    );
  }
}

/// Penanda: orang di form sudah punya kartu anggota.
/// Hijau tua yang cukup kontras di atas latar hijau muda (≥ 4,5:1).
final _greenInk = Color.lerp(AppColors.darkGreen, AppColors.charcoal, 0.5)!;

/// UID panjang diringkas ke 4 byte terakhir: "… 9A 23 EE 02".
String _shortUid(String uid) {
  final parts = formatUid(uid).split(' ');
  return parts.length <= 4
      ? parts.join(' ')
      : '… ${parts.sublist(parts.length - 4).join(' ')}';
}

class _CardLinkedChip extends StatelessWidget {
  final String uid;
  const _CardLinkedChip({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('card_linked_chip'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_rounded,
            size: 20,
            color: AppColors.darkGreen,
          ),
          const Gap(8),
          Expanded(
            child: Text(
              'Kartu anggota terhubung · ${_shortUid(uid)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.w600(14, _greenInk),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panduan singkat di panel kanan selama belum ada nama yang diketik.
class _HomeGuide extends StatelessWidget {
  const _HomeGuide();

  static const _steps = [
    (
      Icons.contactless_rounded,
      'Punya kartu anggota?',
      'Tempel di area biru — data terisi, pemeriksaan mulai sendiri.',
    ),
    (
      Icons.keyboard_alt_outlined,
      'Belum punya kartu?',
      'Ketik nama, lalu isi L/P, umur, dan tinggi bila ada.',
    ),
    (
      Icons.history_rounded,
      'Pernah diperiksa?',
      'Namanya muncul di sini saat diketik — ketuk untuk pakai datanya.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('home_guide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (icon, title, text) in _steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.primary),
                ),
                const Gap(12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: '$title ',
                      style: AppText.w700(15),
                      children: [
                        TextSpan(
                          text: text,
                          style: AppText.w400(15, AppColors.grey1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
