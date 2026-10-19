// Logika BLE di file ini di-port dari Staff Ops (branch health-device):
//   lib/features/health_station/screens/health_measurement_screen.dart
// Perilaku koneksi (auto-connect by remoteId, supervisor 8 detik, fallback
// scan, polling oksimeter, protokol timbangan IF_B8B, Squegg) dipertahankan.
// Yang dihapus: server, roster, outbox/sinkronisasi, dan state UI tablet.

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:squegg_core/squegg_core.dart';

import '../data/device_registry_store.dart';
import '../models/device_models.dart';
import '../models/health_record.dart';
import '../models/measurements.dart';
import '../utils/plausibility.dart';
import 'health_device_models.dart';
import 'weight_scale_parser.dart';

void _bleLog(String message) {
  if (kDebugMode) debugPrint(message);
}

/// Alat baru sejenis yang terdeteksi saat alat terdaftar tidak tersambung
/// (hanya bila kunci alat mati). Petugas memilih: pakai atau tolak.
@immutable
class NewDeviceOffer {
  final DeviceType type;
  final String remoteId;
  final String name;

  /// Alat terdaftar yang sedang tidak aktif.
  final RegisteredDevice replaces;

  const NewDeviceOffer({
    required this.type,
    required this.remoteId,
    required this.name,
    required this.replaces,
  });
}

/// Kemampuan radio Bluetooth perangkat ini (Android), dibaca sekali per sesi.
@immutable
class BleRadioInfo {
  /// PHY 2M (BLE 5, laju data 2×).
  final bool le2M;

  /// PHY coded (BLE 5, jangkauan jauh).
  final bool leCoded;
  const BleRadioInfo({required this.le2M, required this.leCoded});

  String get label => [
    'pencarian intensif',
    'koneksi prioritas tinggi',
    if (le2M) 'PHY 2M',
    if (leCoded) 'scan BLE 5 (coded)',
  ].join(' · ');
}

/// Satu sesi pengukuran untuk satu orang. Dibuat saat layar pengukuran dibuka
/// dan dibuang saat layar ditutup.
class MeasurementSession extends ChangeNotifier with WidgetsBindingObserver {
  MeasurementSession({
    required this.profile,
    DeviceRegistryStore? registry,
    @visibleForTesting AllMeasurements? initialMeasurements,
  }) : _registry = registry ?? DeviceRegistryStore.instance,
       _measurements =
           initialMeasurements ??
           AllMeasurements(
             others: OthersMeasurementData(height: profile.heightCm),
           );

  final PersonProfile profile;
  final DeviceRegistryStore _registry;

  /// Dipanggil untuk pesan singkat ke petugas (snackbar).
  ValueChanged<String>? onMessage;

  // ── Squegg ────────────────────────────────────────────────────────────────
  final SqueggCore _squegg = SqueggCore();
  StreamSubscription<SqueggData>? _squeggDataSub;
  StreamSubscription<SqueggConnectionState>? _squeggConnectionSub;
  double _squeggMaxStrength = 0.0;
  bool _squeggWasSqueezing = false;
  GripSide _activeGripSide = GripSide.left;

  /// Tenaga genggam live (kg) — dipisah dari notifyListeners supaya paket
  /// Squegg yang cepat tidak membangun ulang seluruh layar.
  final ValueNotifier<double> gripLive = ValueNotifier(0);

  // ── Pengukuran paralel: status per alat & gerbang anti-bocor ──────────────

  /// Waktu sesi dimulai — dipakai untuk durasi per lansia.
  final DateTime startedAt = DateTime.now();

  final Map<DeviceType, MeasureStep> _steps = {
    for (final t in DeviceType.values) t: MeasureStep.waiting,
  };

  /// Oksimeter, lintas sesi: bacaan terakhir masih "jari terpasang" (belum
  /// ada frame kosong, jeda diam, atau alat mati sesudahnya). Sesi baru
  /// menahan bacaan sampai jari dilepas — berapa pun jeda antar-sesi, karena
  /// tanpa sesi tidak ada yang mendengar alat (jari bisa masih di alat).
  static bool _oxFingerOn = false;

  /// Kapan terakhir timbangan memberi bacaan berisi, lintas sesi. Bila sesi
  /// baru dimulai < 3 detik sesudahnya, kaki lansia sebelumnya kemungkinan
  /// masih di timbangan — bacaan ditahan sampai turun.
  static DateTime? _lastScaleLoadAt;
  static const Duration _carryOverWindow = Duration(seconds: 3);
  static const Duration _releaseGap = Duration(seconds: 2);

  // Dihitung saat sesi dibuat (bukan lazy) — harus memotret keadaan alat
  // tepat ketika lansia baru dimulai.
  bool _oxArmed = !_oxFingerOn;
  bool _scaleArmed = !_recent(_lastScaleLoadAt);
  DateTime? _lastOxPacketAt;

  /// Oksimeter sudah terlihat tersambung di sesi ini.
  bool _oxLinkSeen = false;

  /// Oksimeter tersambung tapi diam selama ini → aliran datanya macet
  /// (terlihat di Yuwell BO-YX110 setelah GATT 133): putus & sambung ulang.
  /// Alat yang menyala mengirim paket tiap detik, juga saat jari dilepas.
  static const _oxStaleAfter = Duration(seconds: 6);
  DateTime? _lastOxKickAt;

  /// Paket oksimeter apa pun (termasuk frame tanpa nilai) — dasar watchdog.
  DateTime? _lastOxAnyAt;

  /// Protokol pencarian data oksimeter: 0 = normal; 1 = pasang ulang
  /// langganan; 2 = putus & sambung ulang; 3 = hapus cache GATT & sambung
  /// ulang, plus petunjuk untuk petugas. Kembali 0 begitu paket masuk.
  int _oxSearchStage = 0;
  static const oxSearchSteps = 3;

  /// Langkah pencarian yang sedang berjalan (0 = tidak mencari).
  int get oxSearchStage => _oxSearchStage;
  DateTime? _lastScalePacketAt;

  /// Kapan jalur data alat benar-benar tersambung di sesi INI. Gerbang
  /// "lepas dulu" hanya boleh terbuka karena diam setelah titik ini — sebelum
  /// tersambung, diam berarti "belum terdengar", bukan "sudah dilepas".
  final Map<DeviceType, DateTime> _attachedAt = {};

  /// Tinggi & jenis kelamin yang dikirim ke timbangan untuk analisa komposisi.
  double? _compositionHeightCm;
  Gender? _compositionGender;

  /// Jendela bacaan oksimeter untuk deteksi stabil.
  final List<(double, int)> _oxWindow = [];

  /// Riwayat nadi dari oksimeter (untuk grafik di kotak Oksigen).
  final List<double> _hrTrace = [];
  List<double> get heartRateTrace => List.unmodifiable(_hrTrace);
  static const int oxStableCount = 5;

  /// Ambang remasan genggam (kg): mulai & lepas.
  static const double gripStartKg = 3.0;
  static const double gripReleaseKg = 1.0;

  Timer? _scaleDoneTimer;
  Timer? _gateTicker;

  /// Bacaan terakhir dari alat mana pun — scan latar ditunda saat alat
  /// sedang mengirim data supaya radio tidak berebut (tidak saling ganggu).
  DateTime? _lastAnyDataAt;

  static bool _recent(DateTime? t) =>
      t != null && DateTime.now().difference(t) < _carryOverWindow;

  // ── BLE state ─────────────────────────────────────────────────────────────
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final Map<String, StreamSubscription<BluetoothConnectionState>>
  _connectionSubs = {};
  final Map<String, StreamSubscription<List<int>>> _characteristicSubs = {};

  /// Karakteristik data per alat (untuk protokol pencarian data).
  final Map<String, BluetoothCharacteristic> _dataChars = {};

  /// Alat yang autoConnect-nya sudah diminta selama aplikasi hidup (lintas
  /// sesi). Dihapus saat aplikasi sengaja memutus alat itu atau Bluetooth mati.
  static final Set<String> _autoLinked = {};

  /// Putus sengaja: autoConnect perlu diminta lagi sesudahnya.
  Future<void> _dropLink(BluetoothDevice device) async {
    _autoLinked.remove(device.remoteId.str);
    await device.disconnect().catchError((_) {});
  }

  final Map<String, Timer> _readTimers = {};
  final Map<String, BleDeviceModel> _connectedDeviceModels = {};
  final Map<String, int> _readFailures = {};
  static const int _maxReadFailures = 4;
  final Set<String> _linking = {};
  final Set<String> _scanFallback = {};
  static const Duration _sweepInterval = Duration(seconds: 8);
  static const Duration _scanWindow = Duration(seconds: 6);

  // ── Kunci alat & alat pengganti ────────────────────────────────────────
  NewDeviceOffer? _offer;
  DateTime? _lastDiscoveryAt;
  static const Duration _discoveryEvery = Duration(seconds: 20);

  /// Alat terdaftar diberi waktu tersambung dulu sebelum alat lain ditawarkan.
  @visibleForTesting
  static Duration offerGrace = const Duration(seconds: 8);

  /// Kunci alat aktif: hanya alat terdaftar yang dipakai.
  bool get deviceLocked => _registry.locked;

  /// Tawaran alat pengganti yang menunggu jawaban petugas (null bila tidak
  /// ada, atau alat terdaftar sudah tersambung lagi).
  NewDeviceOffer? get newDeviceOffer {
    final o = _offer;
    if (o == null || _registry.locked || _isLinked(o.replaces)) return null;
    return o;
  }

  // ── Mode periksa: radio dipaksa maksimal ─────────────────────────────
  BleRadioInfo? _radio;

  /// Null di luar Android / bila belum terbaca.
  BleRadioInfo? get radio => _radio;
  final Set<String> _boosted = {};
  Timer? _supervisor;
  bool _scanSuspended = false;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  BleGate _gate = BleGate.ok;
  bool _gateChecked = false;
  bool _initInFlight = false;
  DeviceType? _manualConnectFor;
  static const Duration _manualConnectTimeout = Duration(seconds: 15);

  static final List<Guid> _healthServiceGuids = {
    for (final m in BleDeviceModel.values) Guid(m.serviceUUID),
  }.toList();

  // ── UI state ──────────────────────────────────────────────────────────────
  List<DeviceInfo> _devices = [
    for (final t in DeviceType.values)
      DeviceInfo(type: t, status: DeviceStatus.unregistered),
  ];

  AllMeasurements _measurements;

  /// Status kunci berat IF_B8B (byte[6] paket 0x33 0xCC): 0x80 = masih
  /// berubah, 0x81/0x82 = terkunci. Komposisi tubuh baru diisi setelah kunci.
  bool _isWeightLocked = false;

  bool _disposed = false;
  bool _started = false;
  bool get _alive => !_disposed;

  // ── Getters untuk UI ───────────────────────────────────────────────────────
  AllMeasurements get measurements => _measurements;
  List<DeviceInfo> get devices => List.unmodifiable(_devices);
  GripSide get activeGripSide => _activeGripSide;
  BleGate get gate => _gate;
  bool get gateChecked => _gateChecked;
  DeviceType? get connectingDevice => _manualConnectFor;
  bool get isRegistryEmpty => _registry.isEmpty;
  DeviceInfo deviceOf(DeviceType t) => _devices.firstWhere((d) => d.type == t);

  MeasureStep stepOf(DeviceType t) => _steps[t]!;
  bool get oxArmed => _oxArmed;
  bool get scaleArmed => _scaleArmed;
  bool get isWeightLocked => _isWeightLocked;

  /// Berapa bacaan stabil berturut-turut yang sudah terkumpul (0..5).
  int get oxStableProgress => _oxStableRun();

  /// Alat yang pernah tersambung atau pernah mengirim/diisi hasil selama
  /// sesi ini. Alat seperti termometer memutus sambungan setelah mengirim
  /// hasil, dan "ukur ulang" mengosongkan hasil — keduanya tetap wajib.
  final Set<DeviceType> _used = {};

  /// Alat sedang dipakai: terdaftar dan tersambung (atau pernah dipakai di
  /// sesi ini). Alat lain ditaruh di bawah layar dan tidak ikut dicek.
  /// Alat yang sempat "menghubungkan" (tersambung fisik) tetap wajib walau
  /// setup GATT gagal lalu kembali menunggu — kecuali dilewati.
  bool isActive(DeviceType t) =>
      _registry.of(t) != null &&
      (_used.contains(t) ||
          deviceOf(t).status == DeviceStatus.connected ||
          // Sedang menyambung (mis. oksimeter baru dinyalakan saat jari
          // dipasang) → sudah dihitung, supaya tidak tersimpan duluan.
          deviceOf(t).status == DeviceStatus.connecting ||
          _steps[t] != MeasureStep.waiting);

  /// Ada alat terdaftar yang belum tersambung sama sekali di sesi ini.
  bool get hasIdleRegistered =>
      DeviceType.values.any((t) => _registry.of(t) != null && !isActive(t));

  /// Alat yang wajib selesai: hanya alat yang sedang dipakai ([isActive]).
  Set<DeviceType> get requiredDevices => {
    for (final t in DeviceType.values)
      if (isActive(t)) t,
  };

  int get doneCount =>
      DeviceType.values.where((t) => _steps[t] == MeasureStep.done).length;

  /// Semua alat wajib sudah selesai atau dilewati (minimal satu selesai).
  bool get allRequiredDone {
    final req = requiredDevices;
    if (req.isEmpty) return false;
    return req.every(
          (t) =>
              _steps[t] == MeasureStep.done || _steps[t] == MeasureStep.skipped,
        ) &&
        req.any((t) => _steps[t] == MeasureStep.done);
  }

  static bool _validHeight(double? h) => h != null && h >= 50 && h <= 250;

  /// Tinggi yang dipakai untuk BMI & komposisi tubuh. Nilai tidak wajar
  /// (mis. salah ketik "0") diabaikan supaya BMI tidak jadi tak hingga.
  double get effectiveHeightCm {
    final typed = _measurements.others.height;
    if (_validHeight(typed)) return typed!;
    if (_validHeight(profile.heightCm)) return profile.heightCm!;
    return PersonProfile.defaultHeightCm;
  }

  bool get heightMissing =>
      !_validHeight(_measurements.others.height) &&
      !_validHeight(profile.heightCm);

  /// BMI hanya dari tinggi yang benar-benar diisi — BMI dari tinggi
  /// pengganti 160 cm bisa tampak "obesitas" padahal tidak.
  double? _bmiFor(double? weight) {
    if (weight == null || weight <= 0 || heightMissing) return null;
    final hm = effectiveHeightCm / 100.0;
    final bmi = weight / (hm * hm);
    return bmi.isFinite ? bmi : null;
  }

  bool _othersEdited = false;

  /// Ada hasil alat, atau petugas mengisi kartu "Lainnya" sendiri.
  /// Tinggi yang terisi otomatis dari profil tidak dihitung.
  bool get hasUnsavedData => _measurements.hasAnyData || _othersEdited;

  /// Ada yang benar-benar akan tersimpan: hasil selesai/terhitung atau isian
  /// manual. Nilai sementara (SpO2 tanpa nadi, berat belum terkunci) tampil
  /// tapi tidak dihitung — lihat [measurementsForSave].
  bool get hasSavableData => measurementsForSave().hasAnyData || _othersEdited;

  void _update(VoidCallback fn) {
    if (!_alive) return;
    fn();
    for (final d in _devices) {
      if (d.status == DeviceStatus.connected) _used.add(d.type);
    }
    for (final e in _steps.entries) {
      if (e.value != MeasureStep.waiting) _used.add(e.key);
    }
    notifyListeners();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _squeggConnectionSub = _squegg.connectionStream.listen(
      _onSqueggConnectionChanged,
    );
    _squeggDataSub = _squegg.dataStream.listen(_onSqueggData);
    // Status awal Squegg: singleton bisa saja masih tersambung dari sesi
    // sebelumnya (sengaja tidak diputus antar-orang).
    _registry.addListener(_onRegistryChanged);
    await _registry.load();
    if (!_alive) return;
    _update(_applyRegistrySnapshot);
    if (_squegg.isConnected) {
      _onSqueggConnectionChanged(SqueggConnectionState.connected);
    }
    _gateTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickGates(),
    );
    unawaited(_initBluetooth());
  }

  /// Alat yang diam ≥ 2 detik dianggap sudah dilepas lansia sebelumnya.
  void _tickGates() {
    if (!_alive) return;
    final now = DateTime.now();
    var changed = false;
    DateTime? quietSince(DeviceType t, DateTime? lastPacket) {
      final attached = _attachedAt[t];
      if (attached == null) return null;
      return lastPacket != null && lastPacket.isAfter(attached)
          ? lastPacket
          : attached;
    }

    final ox = quietSince(DeviceType.pulseOximeter, _lastOxPacketAt);
    if (!_oxArmed && ox != null && now.difference(ox) >= _releaseGap) {
      _oxArmed = true;
      _oxFingerOn = false;
      changed = true;
    }
    final sc = quietSince(DeviceType.weightScale, _lastScalePacketAt);
    if (!_scaleArmed && sc != null && now.difference(sc) >= _releaseGap) {
      _scaleArmed = true;
      changed = true;
    }
    if (changed) notifyListeners();
    _kickStaleOximeter(now, quietSince(DeviceType.pulseOximeter, _lastOxAnyAt));
  }

  bool _oxStale(DateTime now, DateTime? quiet) =>
      quiet != null && now.difference(quiet) >= _oxStaleAfter;

  void _kickStaleOximeter(DateTime now, DateTime? quiet) {
    if (_isFinished(DeviceType.pulseOximeter)) return;
    if (!_oxStale(now, quiet)) return;
    // Hanya saat jalur data sudah terpasang ("Siap"); selama sambungan
    // masih disiapkan, diamnya alat itu wajar.
    if (deviceOf(DeviceType.pulseOximeter).status != DeviceStatus.connected) {
      return;
    }
    final kicked = _lastOxKickAt;
    if (kicked != null && now.difference(kicked) < _oxStaleAfter) return;
    final id = _connectedDeviceModels.entries
        .firstWhereOrNull((e) => e.value.kind?.isOxymeter == true)
        ?.key;
    if (id == null) return;
    _lastOxKickAt = now;
    final stage = _oxSearchStage < oxSearchSteps
        ? _oxSearchStage + 1
        : oxSearchSteps;
    _update(() => _oxSearchStage = stage);
    _bleLog('BLE [ox] tersambung tapi diam → pencarian langkah $stage');
    final device = BluetoothDevice.fromId(id);
    final attachedAt = _attachedAt[DeviceType.pulseOximeter];
    // Masih macet di sambungan yang sama? (Paket bisa masuk selagi menunggu
    // antrean GATT FBP.)
    bool stillStale() =>
        _alive &&
        _attachedAt[DeviceType.pulseOximeter] == attachedAt &&
        _oxStale(
          DateTime.now(),
          _lastOxAnyAt != null &&
                  attachedAt != null &&
                  _lastOxAnyAt!.isAfter(attachedAt)
              ? _lastOxAnyAt
              : attachedAt,
        );
    unawaited(() async {
      try {
        switch (stage) {
          case 1:
            // Ringan: pasang ulang langganan di sambungan yang sama.
            final char = _dataChars[id];
            if (char == null) {
              if (stillStale()) await _dropLink(device);
              return;
            }
            await char.setNotifyValue(false);
            await char.setNotifyValue(true);
          case 2:
            if (stillStale()) await _dropLink(device);
          default:
            if (!stillStale()) return;
            // Berat: tabel layanan Android bisa basi → buang lalu sambung baru.
            try {
              await device.clearGattCache();
            } catch (_) {}
            await _dropLink(device);
        }
      } catch (e) {
        _bleLog('BLE [ox] pencarian langkah $stage gagal: $e');
        if (stillStale()) await _dropLink(device);
      }
    }());
  }

  void _onRegistryChanged() {
    if (!_alive) return;
    _update(() {
      _applyRegistrySnapshot();
      final o = _offer;
      if (o != null &&
          (_registry.locked ||
              _registry.of(o.type)?.remoteId != o.replaces.remoteId)) {
        _offer = null;
      }
    });
    // Squegg singleton bisa tetap tersambung saat didaftar ulang — tidak ada
    // event koneksi baru, jadi status kartunya disamakan di sini.
    if (_squegg.isConnected && _registry.of(DeviceType.gripStrength) != null) {
      _onSqueggConnectionChanged(SqueggConnectionState.connected);
    }
    unawaited(_reconcile());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _alive) {
      unawaited(_initBluetooth());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _registry.removeListener(_onRegistryChanged);
    _supervisor?.cancel();
    _gateTicker?.cancel();
    _scaleDoneTimer?.cancel();
    gripLive.dispose();
    _adapterSub?.cancel();
    _squeggDataSub?.cancel();
    _squeggConnectionSub?.cancel();
    // Squegg sengaja TIDAK diputus: SqueggCore singleton, memutusnya di tiap
    // sesi memaksa pairing ulang untuk setiap orang.
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan().catchError((_) {});
    // Keluar dari mode periksa: kembalikan prioritas koneksi ke normal.
    if (!kIsWeb && Platform.isAndroid) {
      for (final id in _boosted) {
        BluetoothDevice.fromId(id)
            .requestConnectionPriority(
              connectionPriorityRequest: ConnectionPriority.balanced,
            )
            .catchError((Object _) {});
      }
    }
    _boosted.clear();
    for (final s in _connectionSubs.values) {
      s.cancel();
    }
    _connectionSubs.clear();
    for (final s in _characteristicSubs.values) {
      s.cancel();
    }
    _characteristicSubs.clear();
    for (final t in _readTimers.values) {
      t.cancel();
    }
    _readTimers.clear();
    super.dispose();
  }

  // ── Device registry ───────────────────────────────────────────────────────

  void _applyRegistrySnapshot() {
    final registry = _registry.registry;
    _devices = [
      for (final d in _devices)
        registry[d.type] == null
            ? d.copyWith(status: DeviceStatus.unregistered, macAddress: null)
            : (d.status == DeviceStatus.unregistered
                      ? d.copyWith(
                          status: _gate.isOk
                              ? DeviceStatus.waiting
                              : DeviceStatus.unavailable,
                        )
                      : d)
                  .copyWith(macAddress: registry[d.type]!.remoteId),
    ];
  }

  void _markPending() {
    _update(() {
      _devices = [
        for (final d in _devices)
          (d.status == DeviceStatus.connected ||
                  d.status == DeviceStatus.unregistered)
              ? d
              : d.copyWith(status: DeviceStatus.waiting),
      ];
    });
  }

  void _setStatusFor(DeviceType type, DeviceStatus status) {
    if (!_alive) return;
    if (_manualConnectFor == type && status == DeviceStatus.waiting) return;
    _update(() {
      final idx = _devices.indexWhere((d) => d.type == type);
      if (idx < 0 || _devices[idx].status == DeviceStatus.unregistered) return;
      _devices[idx] = _devices[idx].copyWith(status: status);
      // Coba sambung manual belum berarti tersambung fisik.
      if (status == DeviceStatus.connecting && _manualConnectFor != type) {
        _used.add(type);
      }
    });
  }

  DeviceType? _registeredTypeFor(String remoteId) {
    for (final entry in _registry.registry.entries) {
      if (entry.value.remoteId == remoteId) return entry.key;
    }
    return null;
  }

  bool _matchesRegisteredType(DeviceType type, BleDeviceKind kind) {
    return (type == DeviceType.tensimeter && kind.isBloodPressure) ||
        (type == DeviceType.pulseOximeter && kind.isOxymeter) ||
        (type == DeviceType.thermometer && kind.isTemperature) ||
        (type == DeviceType.weightScale && kind.isWeightScale);
  }

  /// Apakah nama yang diiklankan cocok untuk [type]. Dipakai juga oleh
  /// dialog pendaftaran supaya tidak menawarkan alat yang tidak akan diterima.
  static bool nameMatchesDeviceType(DeviceType type, String name) {
    if (type == DeviceType.gripStrength) {
      final n = name.toLowerCase();
      return n.contains('weixin-nini') || n.startsWith('squegg');
    }
    final model = BleDeviceModel.fromDeviceName(name);
    final kind = model?.kind;
    // Model tanpa parser (CM100) "Siap" tapi tak pernah memberi nilai.
    if (kind == null || kind.isDoppler || !model!.hasParser) return false;
    return (type == DeviceType.tensimeter && kind.isBloodPressure) ||
        (type == DeviceType.pulseOximeter && kind.isOxymeter) ||
        (type == DeviceType.thermometer && kind.isTemperature) ||
        (type == DeviceType.weightScale && kind.isWeightScale);
  }

  // ── BLE ───────────────────────────────────────────────────────────────────

  void _tryConnectSquegg(String deviceId, String name) {
    final lower = name.toLowerCase();
    if (!lower.contains('weixin-nini') && !lower.startsWith('squegg')) return;
    if (_registeredTypeFor(deviceId) != DeviceType.gripStrength) return;
    if (_squegg.isConnected) return;
    _squegg
        .connect(deviceId)
        .catchError((Object e) => _bleLog('BLE [Squegg] connect error: $e'));
  }

  /// Cek dukungan hardware, izin, dan daya adapter.
  Future<bool> _preflight() async {
    if (!await FlutterBluePlus.isSupported) {
      _setGate(BleGate.unsupported);
      return false;
    }

    if (Platform.isAndroid) {
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        // Android ≤ 11 (API 30) masih butuh lokasi untuk scan BLE.
        Permission.locationWhenInUse,
      ].request();
      final ble = [
        results[Permission.bluetoothScan],
        results[Permission.bluetoothConnect],
      ].whereType<PermissionStatus>();
      if (ble.any((s) => s.isPermanentlyDenied)) {
        _setGate(BleGate.permissionPermanentlyDenied);
        return false;
      }
      if (ble.any((s) => !s.isGranted)) {
        _setGate(BleGate.permissionDenied);
        return false;
      }
    }

    if (!_alive) return false;
    _adapterSub ??= FlutterBluePlus.adapterState.listen((s) {
      final on = s == BluetoothAdapterState.on;
      // Bluetooth mati → semua autoConnect yang menunggu ikut hilang.
      if (!on) _autoLinked.clear();
      _setGate(on ? BleGate.ok : BleGate.adapterOff);
      if (on) unawaited(_initBluetooth());
    });

    final on =
        await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
    _setGate(on ? BleGate.ok : BleGate.adapterOff);
    return on;
  }

  void _setGate(BleGate gate) {
    if (!_alive || (_gateChecked && _gate == gate)) return;
    _gateChecked = true;
    _update(() {
      _gate = gate;
      _devices = [
        for (final d in _devices)
          if (d.status == DeviceStatus.unregistered)
            d
          else if (!gate.isOk)
            d.copyWith(status: DeviceStatus.unavailable)
          else if (d.status == DeviceStatus.unavailable)
            d.copyWith(status: DeviceStatus.waiting)
          else
            d,
      ];
    });
  }

  Future<void> _initBluetooth() async {
    if (_initInFlight || !_alive) return;
    _initInFlight = true;
    try {
      await _initBluetoothInner();
    } catch (e) {
      _bleLog('BLE [Session] init failed: $e');
    } finally {
      _initInFlight = false;
    }
  }

  Future<void> _initBluetoothInner() async {
    _bleLog('BLE [Session] initBluetooth');
    _markPending();
    if (!await _preflight()) return;
    if (!_alive) return;
    await _readRadio();
    if (!_alive) return;
    _listenForFallbackScanResults();
    await _sweepSystemDevices();
    if (!_alive) return;
    _armSupervisor();
    await _reconcile();
  }

  void _armSupervisor() {
    _supervisor?.cancel();
    _supervisor = Timer.periodic(
      _sweepInterval,
      (_) => unawaited(_reconcile()),
    );
  }

  /// Alat yang sudah tersambung di level OS tidak lagi beriklan, jadi tidak
  /// akan muncul di hasil scan — tautkan langsung.
  Future<void> _sweepSystemDevices() async {
    final byId = {for (final r in _registry.registry.values) r.remoteId: r};
    if (byId.isEmpty) return;
    for (final d in FlutterBluePlus.connectedDevices) {
      final reg = byId[d.remoteId.str];
      if (reg != null) unawaited(_linkRegisteredDevice(reg));
    }
    try {
      for (final d in await FlutterBluePlus.systemDevices(
        _healthServiceGuids,
      )) {
        final reg = byId[d.remoteId.str];
        if (reg != null) unawaited(_linkRegisteredDevice(reg));
      }
    } catch (e) {
      _bleLog('BLE [Session] systemDevices sweep failed: $e');
    }
  }

  bool _isLinked(RegisteredDevice reg) => reg.type == DeviceType.gripStrength
      ? _squegg.isConnected
      : _connectedDeviceModels.containsKey(reg.remoteId);

  /// Menyelaraskan koneksi dengan daftar alat terdaftar. Berjalan tiap tick
  /// supervisor, saat adapter menyala, dan saat muat ulang manual.
  Future<void> _reconcile() async {
    // Belum lolos cek izin/adaptor → jangan sentuh radio dulu.
    if (!_alive || !_gateChecked || !_gate.isOk || _scanSuspended) return;
    try {
      await _reconcileInner();
    } catch (e) {
      _bleLog('BLE [Session] reconcile failed: $e');
    }
  }

  Future<void> _reconcileInner() async {
    final registry = _registry.registry;
    if (registry.isEmpty) return;

    final pending = [
      for (final reg in registry.values)
        if (!_isLinked(reg)) reg,
    ];

    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    if (pending.isEmpty) return;

    for (final reg in pending) {
      unawaited(_linkRegisteredDevice(reg));
    }

    final chase = [
      for (final reg in pending)
        if (_scanFallback.contains(reg.remoteId)) reg.remoteId,
    ];
    // Kunci mati & alat terdaftar belum tersambung: sesekali pindai tanpa
    // saringan untuk menemukan alat pengganti sejenis.
    final now = DateTime.now();
    final discover =
        !_registry.locked &&
        _offer == null &&
        now.difference(startedAt) >= offerGrace &&
        (_lastDiscoveryAt == null ||
            now.difference(_lastDiscoveryAt!) >= _discoveryEvery);
    if (chase.isEmpty && !discover) return;
    // Jangan memindai saat ada alat yang sedang mengirim hasil: scan berebut
    // radio dengan polling oksimeter/notify tensi. Perintah sambung langsung
    // (autoConnect) di atas tetap berjalan.
    final last = _lastAnyDataAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 10)) {
      return;
    }
    try {
      if (discover) _lastDiscoveryAt = now;
      // Mode periksa: pindai dengan siklus penuh (low latency) di semua PHY
      // yang didukung (androidLegacy: false → termasuk iklan BLE 5).
      await FlutterBluePlus.startScan(
        withRemoteIds: discover ? const [] : chase,
        timeout: _scanWindow,
        androidScanMode: AndroidScanMode.lowLatency,
        androidLegacy: false,
      );
    } catch (e) {
      _bleLog('BLE [Session] fallback scan failed: $e');
    }
  }

  void _listenForFallbackScanResults() {
    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final deviceId = r.device.remoteId.str;
        final reg = _registry.registry.values.firstWhereOrNull(
          (e) => e.remoteId == deviceId,
        );
        if (reg == null) {
          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.advertisementData.advName;
          _considerNewDevice(deviceId, name);
          continue;
        }
        _scanFallback.remove(deviceId);
        unawaited(_linkRegisteredDevice(reg));
      }
    });
  }

  /// Satu-satunya aksi di banner Bluetooth; tergantung apa penghalangnya.
  Future<void> fixGate() async {
    switch (_gate) {
      case BleGate.adapterOff:
        if (!Platform.isAndroid) {
          await openAppSettings();
          return;
        }
        try {
          await FlutterBluePlus.turnOn();
        } catch (e) {
          _bleLog('BLE [Session] turnOn declined: $e');
        }
      case BleGate.permissionPermanentlyDenied:
        await openAppSettings();
      case BleGate.permissionDenied:
        await _initBluetooth();
      case BleGate.unsupported:
      case BleGate.ok:
        break;
    }
  }

  void rescanAll() {
    _bleLog('BLE [Session] manual reload');
    _scanFallback.clear();
    if (!_gate.isOk || !_gateChecked) {
      unawaited(_initBluetooth());
      return;
    }
    unawaited(_reconcile());
  }

  /// Percobaan sambung yang dimulai petugas, dibatasi waktu.
  Future<void> retryConnectNow(DeviceType type) async {
    if (_manualConnectFor != null) return;
    final reg = _registry.of(type);
    if (reg == null) return;

    if (!_gate.isOk) {
      await fixGate();
      return;
    }

    _update(() => _manualConnectFor = type);
    _setStatusFor(type, DeviceStatus.connecting);

    final model = BleDeviceModel.fromDeviceName(reg.name);
    if (model != null && _connectedDeviceModels.containsKey(reg.remoteId)) {
      _abandonLink(reg.remoteId, model);
      _setStatusFor(type, DeviceStatus.connecting);
    }
    _scanFallback.add(reg.remoteId);

    await _linkRegisteredDevice(reg);

    try {
      await Future<void>.delayed(_manualConnectTimeout);
    } finally {
      _update(() => _manualConnectFor = null);
    }
    if (!_alive) return;

    if (!_isLinked(reg)) {
      _setStatusFor(type, DeviceStatus.waiting);
      onMessage?.call(
        'Belum bisa terhubung. Pastikan alat menyala dan dekat dengan perangkat.',
      );
    }
  }

  void suspendAutoScan() {
    _scanSuspended = true;
    _supervisor?.cancel();
    _supervisor = null;
    FlutterBluePlus.stopScan().catchError((_) {});
  }

  void resumeAutoScan() {
    if (!_alive) return;
    _scanFallback.clear();
    _scanSuspended = false;
    if (_gate.isOk && _gateChecked) {
      _armSupervisor();
      unawaited(_reconcile());
    } else {
      unawaited(_initBluetooth());
    }
  }

  /// Sambung ke alat terdaftar berdasarkan remoteId tanpa menunggu iklan.
  Future<void> _linkRegisteredDevice(RegisteredDevice reg) async {
    final id = reg.remoteId;

    if (reg.type == DeviceType.gripStrength) {
      _tryConnectSquegg(id, reg.name);
      return;
    }

    if (_linking.contains(id) || _connectedDeviceModels.containsKey(id)) return;

    final model = BleDeviceModel.fromDeviceName(reg.name);
    final kind = model?.kind;
    if (model == null || kind == null || kind.isDoppler) return;
    if (!_matchesRegisteredType(reg.type, kind)) return;

    _linking.add(id);
    final device = BluetoothDevice.fromId(id);
    try {
      // Status tidak diubah ke "menghubungkan" di sini: autoConnect hanya
      // menunggu alat menyala. "Menghubungkan" baru saat sambungan nyata
      // sedang disiapkan (lihat _attachConnectionListener).
      _bleLog('BLE [${reg.name}] linking $id');
      await _attachConnectionListener(device, model);
      // autoConnect cukup diminta SEKALI per alat selama aplikasi hidup: OS
      // menyambung sendiri tiap alat menyala. Meminta ulang tiap tick
      // menumpuk klien GATT ke alat yang sama sampai data berhenti mengalir.
      if (!device.isConnected && _autoLinked.add(id)) {
        await device.connect(autoConnect: true, mtu: null);
      }
      _scanFallback.remove(id);
    } catch (e) {
      _bleLog('BLE [${reg.name}] link failed: $e');
      _autoLinked.remove(id);
      _scanFallback.add(id);
      _setStatusFor(reg.type, DeviceStatus.waiting);
    } finally {
      _linking.remove(id);
    }
  }

  Future<void> _attachConnectionListener(
    BluetoothDevice device,
    BleDeviceModel model,
  ) async {
    final deviceId = device.remoteId.str;
    await _connectionSubs[deviceId]?.cancel();
    if (!_alive) return;
    _connectionSubs[deviceId] = device.connectionState.listen((state) async {
      _bleLog('BLE [${device.platformName}] state=${state.name}');

      if (state == BluetoothConnectionState.disconnected) {
        _readTimers[deviceId]?.cancel();
        _readTimers.remove(deviceId);
        _readFailures.remove(deviceId);
        _cancelDeviceCharSubs(deviceId);
        _connectedDeviceModels.remove(deviceId);
        if (model.kind?.isWeightScale == true) _isWeightLocked = false;
        // Jam watchdog oksimeter mulai lagi dari sambungan berikutnya.
        if (model.kind?.isOxymeter == true) {
          _attachedAt.remove(DeviceType.pulseOximeter);
          // Belum pernah tersambung di sesi ini = alat mati sejak sesi lalu
          // → jari lansia sebelumnya sudah dilepas.
          if (!_oxLinkSeen && !_oxArmed) {
            _oxFingerOn = false;
            _oxArmed = true;
          }
        }
        _updateDeviceStatus(model, DeviceStatus.waiting);
        return;
      }

      if (state != BluetoothConnectionState.connected) return;
      if (model.kind?.isOxymeter == true) _oxLinkSeen = true;

      try {
        _connectedDeviceModels[deviceId] = model;
        _scanFallback.remove(deviceId);
        // Hijau ("Siap") baru setelah jalur data terpasang di bawah — kalau
        // berlangganan gagal, ikon tidak boleh hijau padahal data tak masuk.
        _updateDeviceStatus(model, DeviceStatus.connecting);

        final services = await device.discoverServices();
        // Sesi bisa sudah ditutup selama menunggu — jangan buat timer atau
        // subscription baru yang tidak akan pernah dibatalkan.
        if (!_alive) return;

        if (model.kind?.isWeightScale == true) {
          await _initWeightScale(services, device, model);
          if (!_alive) return;
        }

        final service = services.firstWhereOrNull(
          (s) => s.uuid.str == model.serviceUUID,
        );
        final char = service?.characteristics.firstWhereOrNull(
          (c) => c.uuid.str == model.characteristicUUID,
        );
        if (char == null) {
          _bleLog('BLE [${device.platformName}] characteristic not found');
          _abandonLink(deviceId, model);
          return;
        }

        if (model.isRead) {
          _readTimers[deviceId]?.cancel();
          _readFailures[deviceId] = 0;
          _readTimers[deviceId] = Timer.periodic(const Duration(seconds: 1), (
            _,
          ) async {
            if (!_alive) return;
            try {
              final value = await char.read();
              _readFailures[deviceId] = 0;
              _handleBleData(value, model);
            } catch (e) {
              final failures = (_readFailures[deviceId] ?? 0) + 1;
              _readFailures[deviceId] = failures;
              _bleLog(
                'BLE [${device.platformName}] read failed '
                '($failures/$_maxReadFailures): $e',
              );
              if (failures >= _maxReadFailures) {
                _abandonLink(deviceId, model);
              }
            }
          });
        }

        if (model.isSubscribe) {
          // Sambungan dari sesi sebelumnya masih hidup dengan notifikasi aktif
          // → jangan tulis ulang CCCD: Yuwell BO-YX110 menjawab GATT 133 lalu
          // memutus sambungan (siklus putus-sambung di awal tiap sesi).
          if (!char.isNotifying) await char.setNotifyValue(true);
          if (!_alive) return;
          _dataChars[deviceId] = char;
          await _characteristicSubs[deviceId]?.cancel();
          // onValueReceived (bukan lastValueStream): lastValueStream langsung
          // memutar ulang nilai terakhir yang tersimpan — hasil lansia
          // SEBELUMNYA bisa terkunci untuk lansia baru.
          _characteristicSubs[deviceId] = char.onValueReceived.listen((value) {
            if (!_alive || value.isEmpty) return;
            _handleBleData(value, model);
          });
        }
        _markAttached(model);
        _updateDeviceStatus(model, DeviceStatus.connected);
        unawaited(_boostLink(device));
      } catch (e) {
        // discoverServices / setNotifyValue bisa melempar GATT 133 tepat
        // setelah autoConnect — gulung balik dan putus bersih, supaya
        // percobaan berikutnya mulai dari sambungan baru (bukan sambungan
        // rusak yang tampak tersambung tapi tidak mengirim data).
        _bleLog('BLE [${device.platformName}] setup failed: $e');
        _abandonLink(deviceId, model);
        unawaited(_dropLink(device));
      }
    });
  }

  /// Baca kemampuan radio (PHY 2M / coded) — Android saja.
  Future<void> _readRadio() async {
    if (_radio != null || kIsWeb || !Platform.isAndroid) return;
    try {
      final phy = await FlutterBluePlus.getPhySupport();
      if (!_alive) return;
      _update(
        () => _radio = BleRadioInfo(le2M: phy.le2M, leCoded: phy.leCoded),
      );
    } catch (e) {
      _bleLog('BLE [Session] PHY support unknown: $e');
      _update(() => _radio = const BleRadioInfo(le2M: false, leCoded: false));
    }
  }

  /// Mode periksa: minta interval koneksi terpendek (prioritas tinggi) dan
  /// PHY 2M bila radio mendukung. Frekuensi kanal tidak bisa dipaku dari
  /// aplikasi (diatur lompatan frekuensi adaptif di chip) — yang dipaku adalah
  /// alatnya: tersambung langsung ke alamat alat terdaftar.
  Future<void> _boostLink(BluetoothDevice device) async {
    if (kIsWeb || !Platform.isAndroid || !_alive) return;
    final id = device.remoteId.str;
    try {
      await device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.high,
      );
      _boosted.add(id);
    } catch (e) {
      _bleLog('BLE [${device.platformName}] priority high failed: $e');
    }
    if (_radio?.le2M == true && _alive) {
      try {
        await device.setPreferredPhy(
          txPhy: Phy.le2m.mask,
          rxPhy: Phy.le2m.mask,
          option: PhyCoding.noPreferred,
        );
      } catch (e) {
        _bleLog('BLE [${device.platformName}] PHY 2M not applied: $e');
      }
    }
  }

  static DeviceType? _typeForName(String name) {
    if (name.isEmpty) return null;
    for (final t in DeviceType.values) {
      if (nameMatchesDeviceType(t, name)) return t;
    }
    return null;
  }

  /// Pemancar alat yang tidak terdaftar. Kunci nyala → diabaikan. Kunci mati
  /// → ditawarkan sebagai pengganti hanya bila alat terdaftar sejenis sedang
  /// tidak tersambung, belum pernah ditolak, dan tidak ada tawaran lain.
  void _considerNewDevice(String remoteId, String name) {
    // _scanSuspended: petugas sedang mendaftarkan alat di dialog (pindaian
    // milik dialog) — jangan menawarkan apa pun di tengahnya.
    if (!_alive || _scanSuspended || _registry.locked || _offer != null) return;
    if (_registeredTypeFor(remoteId) != null) return;
    final type = _typeForName(name);
    if (type == null) return;
    final reg = _registry.of(type);
    if (reg == null || _isLinked(reg)) return;
    if (_registry.isIgnored(remoteId)) return;
    if (DateTime.now().difference(startedAt) < offerGrace) return;
    _update(
      () => _offer = NewDeviceOffer(
        type: type,
        remoteId: remoteId,
        name: name,
        replaces: reg,
      ),
    );
  }

  /// Pakai alat yang ditawarkan: didaftarkan menggantikan alat lama.
  Future<void> acceptNewDevice() async {
    final o = newDeviceOffer;
    _update(() => _offer = null);
    if (o == null || _registry.locked) return;
    final oldModel = BleDeviceModel.fromDeviceName(o.replaces.name);
    if (oldModel != null &&
        _connectedDeviceModels.containsKey(o.replaces.remoteId)) {
      _abandonLink(o.replaces.remoteId, oldModel);
    }
    _scanFallback.remove(o.replaces.remoteId);
    await _registry.register(
      RegisteredDevice(type: o.type, remoteId: o.remoteId, name: o.name),
    );
    onMessage?.call('${o.type.label}: sekarang memakai ${o.name}');
  }

  /// Tolak alat yang ditawarkan: tidak akan ditawarkan lagi.
  Future<void> rejectNewDevice() async {
    final o = _offer;
    _update(() => _offer = null);
    if (o == null) return;
    await _registry.ignore(o.remoteId);
  }

  /// Untuk test: iklan BLE dari alat [remoteId] bernama [name].
  @visibleForTesting
  void debugScanResult(String remoteId, String name) {
    final reg = _registry.registry.values.firstWhereOrNull(
      (e) => e.remoteId == remoteId,
    );
    if (reg == null) _considerNewDevice(remoteId, name);
  }

  /// Untuk test: tandai alat terdaftar sudah tersambung.
  @visibleForTesting
  void debugMarkLinked(String remoteId, BleDeviceModel model) =>
      _connectedDeviceModels[remoteId] = model;

  void _markAttached(BleDeviceModel model) {
    final kind = model.kind;
    if (kind == null) return;
    if (kind.isOxymeter) _attachedAt[DeviceType.pulseOximeter] = DateTime.now();
    if (kind.isWeightScale) {
      _attachedAt[DeviceType.weightScale] = DateTime.now();
    }
  }

  /// Untuk test: tandai jalur data alat sudah tersambung di sesi ini.
  @visibleForTesting
  void debugMarkAttached(DeviceType t, [DateTime? at]) =>
      _attachedAt[t] = at ?? DateTime.now();

  void _abandonLink(String deviceId, BleDeviceModel model) {
    _readTimers[deviceId]?.cancel();
    _readTimers.remove(deviceId);
    _readFailures.remove(deviceId);
    _cancelDeviceCharSubs(deviceId);
    _connectedDeviceModels.remove(deviceId);
    _updateDeviceStatus(model, DeviceStatus.waiting);
  }

  bool _isFinished(DeviceType t) =>
      _steps[t] == MeasureStep.done || _steps[t] == MeasureStep.skipped;

  /// Dipanggil oleh test untuk menyuntik paket mentah seperti dari BLE.
  @visibleForTesting
  void debugInjectPacket(List<int> value, BleDeviceModel model) =>
      _handleBleData(value, model);

  @visibleForTesting
  void debugInjectGrip(double strength) => _onSqueggData(
    SqueggData.now(
      strength: strength,
      isSqueezing: strength >= 2.0,
      batteryCharge: 100,
    ),
  );

  @visibleForTesting
  void debugTickGates() => _tickGates();

  /// Untuk screenshot: tampilkan alat seolah sudah tersambung.
  @visibleForTesting
  void debugSetStatus(DeviceType type, DeviceStatus status) =>
      _setStatusFor(type, status);

  @visibleForTesting
  static void debugResetCarryOver() {
    _oxFingerOn = false;
    _lastScaleLoadAt = null;
  }

  void _handleBleData(List<int> value, BleDeviceModel model) {
    if (!_alive) return;
    final kind = model.kind;
    if (kind == null) return;
    _lastAnyDataAt = DateTime.now();

    if (kind.isOxymeter) {
      _lastOxAnyAt = DateTime.now();
      _lastOxKickAt = null;
      if (_oxSearchStage != 0) _update(() => _oxSearchStage = 0);
      final ox = HealthParserUtils.parseOxymeter(value, model);
      if (ox.oxygen == null && ox.heartRate == null) {
        // Bukan frame nilai (mis. gelombang/status) — bukan tanda jari lepas.
        _bleLog('BLE [${model.deviceName}] paket tanpa nilai: $value');
      } else {
        _onOximeter(ox);
      }
    }

    if (kind.isTemperature) {
      final temp = HealthParserUtils.parseTemperature(value, model);
      if (Plausible.ok(temp, Plausible.temperature) &&
          !_isFinished(DeviceType.thermometer)) {
        _update(() {
          _measurements = _measurements.copyWith(
            thermometer: _measurements.thermometer.copyWith(temperature: temp),
          );
          // Satu bacaan termometer = satu pengukuran selesai.
          _steps[DeviceType.thermometer] = MeasureStep.done;
        });
      }
    }

    if (kind.isBloodPressure) {
      final bp = HealthParserUtils.parseBloodPressure(value);
      // Nilai di luar batas fisiologis (mis. SFLOAT NaN 2047) = salah baca.
      final sysOk = bp != null && Plausible.ok(bp.systolic, Plausible.systolic);
      final diaOk =
          bp != null && Plausible.ok(bp.diastolic, Plausible.diastolic);
      if (bp != null &&
          (sysOk || diaOk) &&
          !_isFinished(DeviceType.tensimeter)) {
        final cur = _measurements.tensimeter;
        _update(() {
          final next = TensimeterData(
            systolic: sysOk ? bp.systolic : cur.systolic,
            diastolic: diaOk ? bp.diastolic : cur.diastolic,
            pulse: Plausible.ok(bp.pulse, Plausible.heartRate)
                ? bp.pulse
                : cur.pulse,
          );
          _measurements = _measurements.copyWith(tensimeter: next);
          // Tensimeter mengirim hasil akhir setelah manset selesai.
          _steps[DeviceType.tensimeter] =
              (next.systolic != null && next.diastolic != null)
              ? MeasureStep.done
              : MeasureStep.measuring;
        });
      }
    }

    if (kind.isWeightScale) {
      _handleWeightScale(value, model);
    }
  }

  /// Nilai 0 / 127 / 255 = tidak ada jari (penanda tidak valid dari alat).
  static bool _validOx(int? spo2, int? hr) =>
      spo2 != null &&
      hr != null &&
      spo2 >= Plausible.spo2.$1 &&
      spo2 <= 100 &&
      hr >= Plausible.heartRate.$1 &&
      hr <= Plausible.heartRate.$2;

  int _oxStableRun() {
    if (_oxWindow.length < 2) return _oxWindow.length;
    final last = _oxWindow.last;
    var run = 1;
    for (var i = _oxWindow.length - 2; i >= 0; i--) {
      final (s, h) = _oxWindow[i];
      if ((s - last.$1).abs() <= 1 && (h - last.$2).abs() <= 3) {
        run++;
      } else {
        break;
      }
    }
    return run;
  }

  void _onOximeter(OxymeterReading ox) {
    final now = DateTime.now();
    _lastOxPacketAt = now;
    final valid = _validOx(ox.oxygen, ox.heartRate);
    // Jari baru dipasang: SpO2 sudah keluar, nadi masih 0 beberapa detik.
    // Tampilkan SpO2-nya dulu (alat sudah menunjukkan angka), tapi belum
    // dihitung menuju stabil sampai nadi ikut terbaca.
    final o2 = ox.oxygen;
    final partial =
        !valid &&
        o2 != null &&
        o2 >= Plausible.spo2.$1 &&
        o2 <= 100 &&
        (ox.heartRate ?? 0) == 0;
    _oxFingerOn = valid || partial;
    if (_isFinished(DeviceType.pulseOximeter)) return;

    if (partial) {
      if (!_oxArmed) return;
      _update(() {
        _steps[DeviceType.pulseOximeter] = MeasureStep.measuring;
        _measurements = _measurements.copyWith(
          pulseOximeter: PulseOximeterData(spo2: o2.toDouble()),
        );
      });
      return;
    }

    if (!valid) {
      // Jari dilepas → siap menerima bacaan baru.
      if (!_oxArmed || _oxWindow.isNotEmpty) {
        _update(() {
          _oxArmed = true;
          _oxWindow.clear();
        });
      }
      return;
    }
    // Masih jari lansia sebelumnya — tunggu dilepas dulu.
    if (!_oxArmed) return;

    _update(() {
      _steps[DeviceType.pulseOximeter] = MeasureStep.measuring;
      _measurements = _measurements.copyWith(
        pulseOximeter: PulseOximeterData(
          spo2: ox.oxygen!.toDouble(),
          heartRate: ox.heartRate,
        ),
      );
      _oxWindow.add((ox.oxygen!.toDouble(), ox.heartRate!));
      if (_oxWindow.length > oxStableCount) _oxWindow.removeAt(0);
      _hrTrace.add(ox.heartRate!.toDouble());
      if (_hrTrace.length > 30) _hrTrace.removeAt(0);
      // Stabil: 5 bacaan berturut-turut dengan SpO2 ±1 % dan nadi ±3 bpm.
      if (_oxStableRun() >= oxStableCount) {
        _steps[DeviceType.pulseOximeter] = MeasureStep.done;
      }
    });
  }

  void _handleWeightScale(List<int> value, BleDeviceModel model) {
    final now = DateTime.now();
    _lastScalePacketAt = now;

    // Deteksi kunci berat IF_B8B dari paket utama 0x33 0xCC.
    if (value.length >= 7 && value[0] == 0x33 && value[1] == 0xcc) {
      final statusByte = value[6] & 0xFF;
      _isWeightLocked = statusByte != 0x80;
    }

    // Gerbang: lansia sebelumnya harus turun dulu dari timbangan. Dibaca dari
    // paket utama mentah, karena parser membuang berat < 1 kg (timbangan kosong).
    if (value.length >= 12 && value[0] == 0x33 && value[1] == 0xcc) {
      final rawIdx = value.length == 17 ? 8 : 10;
      final kg =
          (((value[rawIdx] & 0xFF) << 8) | (value[rawIdx + 1] & 0xFF)) / 100.0;
      if (kg < 5) {
        // Turun sebelum terkunci → batalkan penguncian tertunda.
        if (!_isFinished(DeviceType.weightScale)) _scaleDoneTimer?.cancel();
        if (!_scaleArmed) _update(() => _scaleArmed = true);
        return; // timbangan kosong
      }
      _lastScaleLoadAt = now;
    }

    final bodyComp = WeightScaleParser.parse(
      value,
      deviceName: model.deviceName,
    );
    if (bodyComp == null) return;
    if (!_scaleArmed || _isFinished(DeviceType.weightScale)) return;

    final ws = _measurements.weightScale;
    final w = Plausible.keep(bodyComp.weight, Plausible.weight) ?? ws.weight;
    if (w == null) return;

    // BMI selalu dari berat/tinggi² memakai tinggi orang ini.
    final bmi = _bmiFor(w) ?? ws.bmi;

    // Selama berat belum stabil, hanya berat + BMI yang diperbarui.
    if (!_isWeightLocked) {
      // Berat goyah lagi → jangan kunci nilai lama setelah 6 detik.
      _scaleDoneTimer?.cancel();
      _update(() {
        _steps[DeviceType.weightScale] = MeasureStep.measuring;
        _measurements = _measurements.copyWith(
          weightScale: ws.copyWith(weight: w, bmi: bmi),
        );
      });
      return;
    }

    // Nilai komposisi yang mustahil (mis. lemak -47,9 %) = paket rusak.
    final fat =
        Plausible.keep(bodyComp.bodyFat, Plausible.bodyFat) ??
        ws.bodyFatPercent;
    final water =
        Plausible.keep(bodyComp.water, Plausible.bodyWater) ??
        ws.bodyWaterPercent;
    final muscle =
        Plausible.keep(bodyComp.muscle, Plausible.muscle) ?? ws.musclePercent;
    final bone =
        Plausible.keep(bodyComp.bone, Plausible.bone) ?? ws.boneMineralPercent;
    final protein =
        Plausible.keep(bodyComp.protein, Plausible.protein) ??
        ws.proteinPercent;
    final visceral =
        Plausible.keep(bodyComp.visceralFat?.toDouble(), Plausible.visceral) ??
        ws.visceralFatRate;
    final bmr = Plausible.ok(bodyComp.bmr, Plausible.bmr)
        ? bodyComp.bmr
        : ws.bmr;

    String? bodyType = ws.bodyType;
    if (fat != null && bmi != null) {
      if (bmi < 18.5) {
        bodyType = 'Kurus';
      } else if (bmi > 25 && fat > 25) {
        bodyType = 'Sedikit gemuk';
      } else if (bmi >= 25 && fat <= 25) {
        bodyType = 'Berotot';
      } else if (bmi < 25 && fat < 20) {
        bodyType = 'Ramping';
      } else {
        bodyType = 'Normal';
      }
    }

    double? kg(double? pct) => pct != null ? pct * w / 100 : null;

    _update(() {
      _steps[DeviceType.weightScale] = MeasureStep.measuring;
      _measurements = _measurements.copyWith(
        weightScale: ws.copyWith(
          weight: w,
          bmi: bmi,
          bmr: bmr,
          bodyScore: bodyComp.bodyScore?.toDouble() ?? ws.bodyScore,
          bodyFatPercent: fat,
          bodyFatKg: kg(fat) ?? ws.bodyFatKg,
          bodyWaterPercent: water,
          bodyWater: kg(water) ?? ws.bodyWater,
          musclePercent: muscle,
          muscleMass: kg(muscle) ?? ws.muscleMass,
          boneMineralPercent: bone,
          boneMineral: kg(bone) ?? ws.boneMineral,
          visceralFatRate: visceral,
          proteinPercent: protein,
          proteinMass: kg(protein) ?? ws.proteinMass,
          bodyType: bodyType,
        ),
      );
      // Paket akhir (skor tubuh) = analisa selesai. Bila tidak datang,
      // berat yang sudah terkunci diterima setelah 6 detik.
      if (bodyComp.bodyScore != null) {
        _scaleDoneTimer?.cancel();
        _steps[DeviceType.weightScale] = MeasureStep.done;
      } else {
        _scaleDoneTimer?.cancel();
        _scaleDoneTimer = Timer(const Duration(seconds: 6), () {
          if (!_alive || _isFinished(DeviceType.weightScale)) return;
          if (_measurements.weightScale.weight == null) return;
          _update(() => _steps[DeviceType.weightScale] = MeasureStep.done);
        });
      }
    });
  }

  void _updateDeviceStatus(BleDeviceModel model, DeviceStatus status) {
    if (!_alive) return;
    final kind = model.kind;
    if (kind == null) return;

    DeviceType? target;
    if (kind.isBloodPressure) {
      target = DeviceType.tensimeter;
    } else if (kind.isOxymeter) {
      target = DeviceType.pulseOximeter;
    } else if (kind.isTemperature) {
      target = DeviceType.thermometer;
    } else if (kind.isWeightScale) {
      target = DeviceType.weightScale;
    }
    if (target == null) return;
    if (_manualConnectFor == target && status == DeviceStatus.waiting) return;

    final t = target;
    _update(() {
      final idx = _devices.indexWhere((d) => d.type == t);
      if (idx >= 0) _devices[idx] = _devices[idx].copyWith(status: status);
      // "Menghubungkan" di sini = sambungan fisik nyata → tetap wajib.
      if (status == DeviceStatus.connecting) _used.add(t);
    });
  }

  // ── Squegg ────────────────────────────────────────────────────────────────

  void _onSqueggData(SqueggData data) {
    if (!_alive) return;
    _lastAnyDataAt = DateTime.now();
    if (_isFinished(DeviceType.gripStrength)) return;
    gripLive.value = data.strength;

    // Histeresis: remasan dimulai ≥ 3 kg dan dianggap lepas < 1 kg, supaya
    // getaran di sekitar ambang tidak terhitung sebagai remasan baru.
    // Puncak dicatat saat dilepas; 3 percobaan per sisi lalu pindah.
    final v = data.strength;
    if (!_squeggWasSqueezing) {
      if (v < gripStartKg) return;
      _squeggWasSqueezing = true;
      _squeggMaxStrength = v;
      _update(() => _steps[DeviceType.gripStrength] = MeasureStep.measuring);
      return;
    }
    _squeggMaxStrength = math.max(_squeggMaxStrength, v);
    if (v >= gripReleaseKg) return;

    final maxVal = _squeggMaxStrength;
    _squeggMaxStrength = 0.0;
    _squeggWasSqueezing = false;
    if (!Plausible.ok(maxVal, Plausible.grip)) return;
    _update(() {
      var c = _measurements.gripStrength;
      bool full(GripSide side) => side == GripSide.left
          ? c.gripLeft1 != null && c.gripLeft2 != null && c.gripLeft3 != null
          : c.gripRight1 != null &&
                c.gripRight2 != null &&
                c.gripRight3 != null;
      GripSide other(GripSide side) =>
          side == GripSide.left ? GripSide.right : GripSide.left;
      GripStrengthData place(GripSide side) => side == GripSide.left
          ? (c.gripLeft1 == null
                ? c.copyWith(gripLeft1: maxVal)
                : c.gripLeft2 == null
                ? c.copyWith(gripLeft2: maxVal)
                : c.copyWith(gripLeft3: maxVal))
          : (c.gripRight1 == null
                ? c.copyWith(gripRight1: maxVal)
                : c.gripRight2 == null
                ? c.copyWith(gripRight2: maxVal)
                : c.copyWith(gripRight3: maxVal));

      // Sisi aktif sudah penuh → pindah dulu, nilai tidak dibuang.
      if (full(_activeGripSide) && !full(other(_activeGripSide))) {
        _activeGripSide = other(_activeGripSide);
      }
      if (!full(_activeGripSide)) {
        c = place(_activeGripSide);
        _measurements = _measurements.copyWith(gripStrength: c);
      }
      if (full(_activeGripSide) && !full(other(_activeGripSide))) {
        _activeGripSide = other(_activeGripSide);
      }
      // 3 percobaan per tangan lengkap → selesai.
      if (gripAttempts == 6) {
        _steps[DeviceType.gripStrength] = MeasureStep.done;
      }
    });
  }

  /// Jumlah percobaan genggam yang sudah tercatat (0..6).
  int get gripAttempts {
    final g = _measurements.gripStrength;
    return [
      g.gripLeft1,
      g.gripLeft2,
      g.gripLeft3,
      g.gripRight1,
      g.gripRight2,
      g.gripRight3,
    ].whereType<double>().length;
  }

  Future<void> _initWeightScale(
    List<BluetoothService> services,
    BluetoothDevice device,
    BleDeviceModel model,
  ) async {
    final deviceId = device.remoteId.str;
    final name = device.platformName;

    final fff0 = services.firstWhereOrNull((s) => s.uuid.str == 'fff0');
    if (fff0 == null) {
      _bleLog('BLE [$name] fff0 service not found');
      return;
    }

    // fff1 (notify): berat + komposisi tubuh IF_B8B.
    final fff1 = fff0.characteristics.firstWhereOrNull(
      (c) => c.uuid.str == 'fff1',
    );
    if (fff1 != null) {
      try {
        await fff1.setNotifyValue(true);
        if (!_alive) return;
        final subKey = '$deviceId-fff1';
        await _characteristicSubs[subKey]?.cancel();
        _characteristicSubs[subKey] = fff1.onValueReceived.listen((value) {
          if (!_alive || value.isEmpty) return;
          _handleBleData(value, model);
        });
      } catch (e) {
        _bleLog('BLE [$name] fff1 subscribe error: $e');
      }
    }

    // fff2 (write): profil pengguna untuk mengaktifkan komposisi tubuh.
    final fff2 = fff0.characteristics.firstWhereOrNull(
      (c) => c.uuid.str == 'fff2',
    );
    if (fff2 == null) {
      _bleLog('BLE [$name] fff2 not found — body composition unavailable');
      return;
    }

    try {
      final now = DateTime.now();
      final dateCmd = WeightScaleCommands.createSyncDateCommand(
        year: now.year,
        dayOfYear: int.parse(
          '${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}',
        ),
      );
      await fff2.write(dateCmd, withoutResponse: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final timeCmd = WeightScaleCommands.createSyncTimeCommand(
        hour: now.hour,
        minute: now.minute,
        second: now.second,
      );
      await fff2.write(timeCmd, withoutResponse: false);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      _fatWriter = (cmd) => fff2.write(cmd, withoutResponse: false);
      await _sendFatProfile();
    } catch (e) {
      _bleLog('BLE [$name] fff2 write error: $e');
    }
  }

  Future<void> Function(List<int>)? _fatWriter;

  /// Kirim profil (L/P, umur, tinggi) ke timbangan untuk analisa komposisi.
  /// Diulang bila tinggi diubah di tengah sesi.
  Future<void> _sendFatProfile() async {
    final write = _fatWriter;
    if (write == null || !_alive) return;
    final fatCmd = WeightScaleCommands.createFatTestCommand(
      gender: profile.isFemale
          ? WeightScaleCommands.genderFemale
          : WeightScaleCommands.genderMale,
      age: profile.effectiveAge.clamp(1, 99),
      height: effectiveHeightCm.round().clamp(100, 220),
    );
    try {
      await write(fatCmd);
      _compositionHeightCm = heightMissing ? null : effectiveHeightCm;
      _compositionGender = profile.gender;
    } catch (e) {
      _bleLog('BLE fat profile write error: $e');
    }
  }

  /// Untuk test: anggap profil komposisi sudah dikirim ke timbangan.
  @visibleForTesting
  void debugMarkCompositionProfileSent() {
    _compositionHeightCm = heightMissing ? null : effectiveHeightCm;
    _compositionGender = profile.gender;
  }

  /// Komposisi tubuh dari timbangan hanya sahih bila timbangan memakai tinggi
  /// asli & jenis kelamin orang ini (bukan pengganti 160 cm / laki-laki).
  bool get compositionValid =>
      !heightMissing &&
      profile.gender != null &&
      _compositionHeightCm != null &&
      (_compositionHeightCm! - effectiveHeightCm).abs() < 0.5 &&
      _compositionGender == profile.gender;

  /// Data yang disimpan: tanpa nilai yang belum stabil (simpan sebagian) dan
  /// tanpa komposisi tubuh yang dihitung dari profil pengganti.
  AllMeasurements measurementsForSave() {
    var m = _measurements;
    for (final t in DeviceType.values) {
      if (_steps[t] != MeasureStep.measuring) continue;
      m = switch (t) {
        DeviceType.tensimeter => m.copyWith(tensimeter: const TensimeterData()),
        DeviceType.pulseOximeter => m.copyWith(
          pulseOximeter: const PulseOximeterData(),
        ),
        DeviceType.thermometer => m.copyWith(
          thermometer: const ThermometerData(),
        ),
        DeviceType.weightScale => m.copyWith(
          weightScale: const WeightScaleData(),
        ),
        // Tiap remasan yang tercatat sudah merupakan percobaan utuh.
        DeviceType.gripStrength => m,
      };
    }
    final ws = m.weightScale;
    if (ws.weight != null && !compositionValid) {
      m = m.copyWith(
        weightScale: WeightScaleData(
          weight: ws.weight,
          bmi: _bmiFor(ws.weight),
        ),
      );
    }
    return m;
  }

  void _cancelDeviceCharSubs(String deviceId) {
    _dataChars.remove(deviceId);
    final keys = _characteristicSubs.keys
        .where((k) => k == deviceId || k.startsWith('$deviceId-'))
        .toList();
    for (final key in keys) {
      _characteristicSubs[key]?.cancel();
      _characteristicSubs.remove(key);
    }
  }

  void _onSqueggConnectionChanged(SqueggConnectionState state) {
    _update(() {
      final idx = _devices.indexWhere((d) => d.type == DeviceType.gripStrength);
      if (idx < 0 || _devices[idx].status == DeviceStatus.unregistered) return;
      _devices[idx] = _devices[idx].copyWith(
        status: switch (state) {
          SqueggConnectionState.connected => DeviceStatus.connected,
          SqueggConnectionState.connecting => DeviceStatus.connecting,
          _ => DeviceStatus.waiting,
        },
      );
    });
  }

  /// Putus lalu pasang ulang koneksi alat yang macet.
  Future<void> relinkDevice(DeviceType type) async {
    final reg = _registry.of(type);
    if (reg == null) return;

    if (type == DeviceType.gripStrength) {
      await _squegg.disconnect();
      _tryConnectSquegg(reg.remoteId, reg.name);
      return;
    }

    final id = reg.remoteId;
    _readTimers[id]?.cancel();
    _readTimers.remove(id);
    _cancelDeviceCharSubs(id);
    await _connectionSubs[id]?.cancel();
    _connectionSubs.remove(id);
    _connectedDeviceModels.remove(id);
    _setStatusFor(type, DeviceStatus.waiting);

    await _dropLink(BluetoothDevice.fromId(id));
    await _linkRegisteredDevice(reg);
  }

  // ── Aksi dari UI ──────────────────────────────────────────────────────────

  void setGripSide(GripSide side) => _update(() => _activeGripSide = side);

  /// Status alat ikut isian manual: lengkap → selesai, kosong → menunggu.
  void _stepFromData(
    DeviceType t, {
    required bool complete,
    required bool empty,
  }) {
    if (_steps[t] == MeasureStep.skipped) return;
    _steps[t] = complete
        ? MeasureStep.done
        : empty
        ? MeasureStep.waiting
        : MeasureStep.measuring;
  }

  void updateTensimeter(TensimeterData v) => _update(() {
    _measurements = _measurements.copyWith(tensimeter: v);
    _stepFromData(
      DeviceType.tensimeter,
      complete: v.systolic != null && v.diastolic != null,
      empty: v.isEmpty,
    );
  });

  void updatePulseOximeter(PulseOximeterData v) => _update(() {
    _measurements = _measurements.copyWith(pulseOximeter: v);
    _oxWindow.clear();
    _stepFromData(
      DeviceType.pulseOximeter,
      complete: v.spo2 != null,
      empty: v.isEmpty,
    );
  });

  void updateThermometer(ThermometerData v) => _update(() {
    _measurements = _measurements.copyWith(thermometer: v);
    _stepFromData(
      DeviceType.thermometer,
      complete: v.temperature != null,
      empty: v.isEmpty,
    );
  });

  void updateGripStrength(GripStrengthData v) => _update(() {
    _measurements = _measurements.copyWith(gripStrength: v);
    _stepFromData(
      DeviceType.gripStrength,
      complete: v.gripLeft != null && v.gripRight != null,
      empty: v.isEmpty,
    );
  });

  void updateWeightScale(WeightScaleData v) {
    // Berat diubah manual → hitung ulang BMI dari tinggi.
    var next = v;
    if (v.weight != _measurements.weightScale.weight) {
      next = v.copyWith(bmi: _bmiFor(v.weight));
    }
    _update(() {
      _measurements = _measurements.copyWith(weightScale: next);
      _stepFromData(
        DeviceType.weightScale,
        complete: next.weight != null,
        empty: next.isEmpty,
      );
    });
  }

  void updateOthers(OthersMeasurementData v) {
    final heightChanged = v.height != _measurements.others.height;
    if (heightChanged) {
      // Kirim tinggi baru ke timbangan untuk penimbangan berikutnya.
      scheduleMicrotask(() => unawaited(_sendFatProfile()));
    }
    _update(() {
      _othersEdited = true;
      _measurements = _measurements.copyWith(others: v);
      // Tinggi berubah → BMI ikut disesuaikan.
      final w = _measurements.weightScale.weight;
      if (w != null) {
        _measurements = _measurements.copyWith(
          weightScale: _measurements.weightScale.copyWith(bmi: _bmiFor(w)),
        );
      }
    });
  }

  /// Hapus hasil satu alat dan ukur lagi (mis. tensi tinggi pada lansia cemas).
  void remeasure(DeviceType t) => _update(() {
    _steps[t] = MeasureStep.waiting;
    switch (t) {
      case DeviceType.tensimeter:
        _measurements = _measurements.copyWith(
          tensimeter: const TensimeterData(),
        );
      case DeviceType.pulseOximeter:
        _measurements = _measurements.copyWith(
          pulseOximeter: const PulseOximeterData(),
        );
        _oxWindow.clear();
        _hrTrace.clear();
        _oxArmed = true; // orang yang sama, jari boleh tetap terpasang
      case DeviceType.thermometer:
        _measurements = _measurements.copyWith(
          thermometer: const ThermometerData(),
        );
      case DeviceType.weightScale:
        _measurements = _measurements.copyWith(
          weightScale: const WeightScaleData(),
        );
        _scaleDoneTimer?.cancel();
        _scaleArmed = true;
      case DeviceType.gripStrength:
        _measurements = _measurements.copyWith(
          gripStrength: const GripStrengthData(),
        );
        _activeGripSide = GripSide.left;
        gripLive.value = 0;
    }
  });

  /// Lewati alat untuk lansia ini (mis. kursi roda tidak bisa ditimbang).
  void skip(DeviceType t) => _update(() => _steps[t] = MeasureStep.skipped);

  void unskip(DeviceType t) => _update(() {
    _steps[t] = MeasureStep.waiting;
    _refreshStepFromData(t);
  });

  /// Terima nilai yang sedang tampil sebagai hasil akhir.
  void acceptNow(DeviceType t) => _update(() {
    if (_hasData(t)) _steps[t] = MeasureStep.done;
  });

  /// Paksa alat menerima bacaan sekarang (bila gerbang "lepas dulu" keliru).
  void armNow(DeviceType t) => _update(() {
    if (t == DeviceType.pulseOximeter) _oxArmed = true;
    if (t == DeviceType.weightScale) _scaleArmed = true;
  });

  /// Ada bacaan yang bisa diterima untuk alat ini.
  bool hasData(DeviceType t) => _hasData(t);

  bool _hasData(DeviceType t) => switch (t) {
    DeviceType.tensimeter => _measurements.tensimeter.systolic != null,
    DeviceType.pulseOximeter => _measurements.pulseOximeter.spo2 != null,
    DeviceType.thermometer => _measurements.thermometer.temperature != null,
    DeviceType.weightScale => _measurements.weightScale.weight != null,
    DeviceType.gripStrength => gripAttempts > 0,
  };

  void _refreshStepFromData(DeviceType t) {
    if (_hasData(t)) _steps[t] = MeasureStep.measuring;
  }

  /// Ketuk status alat: daftarkan bila belum, atau coba sambung sekarang.
  /// Mengembalikan true bila alat belum terdaftar (UI membuka dialog).
  bool startMeasurementFor(DeviceType type) {
    final info = deviceOf(type);
    switch (info.status) {
      case DeviceStatus.unregistered:
        return true;
      case DeviceStatus.waiting:
      case DeviceStatus.unavailable:
        unawaited(retryConnectNow(type));
      case DeviceStatus.connecting:
      case DeviceStatus.connected:
        break;
    }
    return false;
  }
}
