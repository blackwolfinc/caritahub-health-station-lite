import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lebar kertas printer thermal iMin.
enum PaperWidth {
  mm58(58, 384),
  mm80(80, 576);

  final int millimeters;

  /// Lebar area cetak dalam titik (dot) pada 203 dpi.
  final int dots;
  const PaperWidth(this.millimeters, this.dots);

  String get label => '$millimeters mm';
}

/// Pengaturan aplikasi, disimpan lokal.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kPaper = 'settings_paper_mm';
  static const _kLocation = 'settings_location_name';
  static const _kAutoPrint = 'settings_auto_print';
  static const _kAutoFinish = 'settings_auto_finish';
  static const _kOnScreenKeyboard = 'settings_onscreen_keyboard';
  static const _kKiosk = 'settings_kiosk_mode';
  static const _kSound = 'settings_sound';
  static const _kKeySound = 'settings_key_sound';
  static const _kSsOrg = 'settings_ss_org_id';
  static const _kSsLocId = 'settings_ss_location_id';
  static const _kSsLocName = 'settings_ss_location_name';
  static const _kSsPracId = 'settings_ss_practitioner_id';
  static const _kSsPracName = 'settings_ss_practitioner_name';

  PaperWidth _paper = PaperWidth.mm58;
  String _locationName = '';
  bool _autoPrint = true;
  bool _autoFinish = true;
  bool? _onScreenKeyboard;
  bool _kioskMode = false;
  bool _sound = true;
  bool _keySound = true;
  String _ssOrgId = '';
  String _ssLocationId = '';
  String _ssLocationName = '';
  String _ssPractitionerId = '';
  String _ssPractitionerName = '';

  PaperWidth get paper => _paper;

  /// Lebar kertas sudah disimpan (dipilih petugas atau hasil deteksi).
  bool get paperChosen => _paperChosen;
  bool _paperChosen = false;

  // ── SATUSEHAT (dipakai saat ekspor; aplikasi tetap offline) ──
  /// ID Organisasi (IHS) fasilitas, mis. 10000004.
  String get ssOrgId => _ssOrgId;

  /// ID Location SATUSEHAT tempat pemeriksaan (UUID).
  String get ssLocationId => _ssLocationId;
  String get ssLocationName => _ssLocationName;

  /// ID Practitioner (IHS) nakes penanggung jawab, mis. N10000001.
  String get ssPractitionerId => _ssPractitionerId;
  String get ssPractitionerName => _ssPractitionerName;

  /// Nama lokasi/kegiatan yang dicetak di kepala struk (opsional).
  String get locationName => _locationName;

  /// Langsung cetak setelah hasil disimpan.
  bool get autoPrint => _autoPrint;

  /// Simpan otomatis saat semua alat terdaftar selesai/dilewati.
  bool get autoFinish => _autoFinish;

  /// Isi data awal lewat keyboard di layar (form kiri, keyboard kanan)
  /// supaya keyboard sistem tidak menutupi form di tablet.
  /// null = belum dipilih petugas; beranda menyalakannya di layar tablet.
  bool? get onScreenKeyboard => _onScreenKeyboard;

  /// Mode kiosk (aplikasi dipin, layar penuh). Dipulihkan saat dibuka.
  bool get kioskMode => _kioskMode;

  /// Efek suara (kartu terbaca, alat selesai, tersimpan, ada masalah).
  bool get sound => _sound;

  /// Bunyi ketuk pelan pada keyboard layar (ikut [sound]).
  bool get keySound => _keySound;

  Future<void> load() async {
    final SharedPreferences p;
    try {
      p = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[Settings] load failed: $e');
      notifyListeners();
      return;
    }
    // Tiap kunci dibaca sendiri: satu nilai bertipe salah (mis. sisa versi
    // lama) hanya membuat kunci itu kembali ke default, bukan semuanya.
    T? read<T>(String key) {
      try {
        final v = p.get(key);
        if (v is T) return v;
        if (v != null) debugPrint('[Settings] $key bertipe salah: $v');
      } catch (e) {
        debugPrint('[Settings] $key gagal dibaca: $e');
      }
      return null;
    }

    final rawMm = read<Object>(_kPaper);
    final mm = rawMm is int ? rawMm : int.tryParse('${rawMm ?? ''}');
    _paperChosen = mm != null;
    _paper = mm == 80 ? PaperWidth.mm80 : PaperWidth.mm58;
    _locationName = read<String>(_kLocation) ?? '';
    _autoPrint = read<bool>(_kAutoPrint) ?? true;
    _autoFinish = read<bool>(_kAutoFinish) ?? true;
    _onScreenKeyboard = read<bool>(_kOnScreenKeyboard);
    _kioskMode = read<bool>(_kKiosk) ?? false;
    _sound = read<bool>(_kSound) ?? true;
    _keySound = read<bool>(_kKeySound) ?? true;
    _ssOrgId = read<String>(_kSsOrg) ?? '';
    _ssLocationId = read<String>(_kSsLocId) ?? '';
    _ssLocationName = read<String>(_kSsLocName) ?? '';
    _ssPractitionerId = read<String>(_kSsPracId) ?? '';
    _ssPractitionerName = read<String>(_kSsPracName) ?? '';
    notifyListeners();
  }

  Future<void> setPaper(PaperWidth v) async {
    _paper = v;
    _paperChosen = true;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPaper, v.millimeters);
  }

  Future<void> setLocationName(String v) async {
    _locationName = v.trim();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLocation, _locationName);
  }

  Future<void> setSatusehat({
    String? orgId,
    String? locationId,
    String? locationName,
    String? practitionerId,
    String? practitionerName,
  }) async {
    String clean(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');
    // ID saja: buang spasi & awalan referensi yang ikut tersalin
    // (mis. "Organization/10000004" → "10000004").
    String id(String v) => v
        .replaceAll(RegExp(r'\s'), '')
        .replaceFirst(RegExp(r'^(Organization|Location|Practitioner)/'), '');
    if (orgId != null) _ssOrgId = id(orgId);
    if (locationId != null) _ssLocationId = id(locationId);
    if (locationName != null) _ssLocationName = clean(locationName);
    if (practitionerId != null) _ssPractitionerId = id(practitionerId);
    if (practitionerName != null) _ssPractitionerName = clean(practitionerName);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSsOrg, _ssOrgId);
    await p.setString(_kSsLocId, _ssLocationId);
    await p.setString(_kSsLocName, _ssLocationName);
    await p.setString(_kSsPracId, _ssPractitionerId);
    await p.setString(_kSsPracName, _ssPractitionerName);
  }

  Future<void> setAutoFinish(bool v) async {
    _autoFinish = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoFinish, v);
  }

  Future<void> setAutoPrint(bool v) async {
    _autoPrint = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoPrint, v);
  }

  Future<void> setOnScreenKeyboard(bool v) async {
    _onScreenKeyboard = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnScreenKeyboard, v);
  }

  Future<void> setKioskMode(bool v) async {
    _kioskMode = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kKiosk, v);
  }

  Future<void> setSound(bool v) async {
    _sound = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSound, v);
  }

  Future<void> setKeySound(bool v) async {
    _keySound = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kKeySound, v);
  }
}
