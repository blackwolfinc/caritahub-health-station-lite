import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../app/sound.dart';
import '../app/theme.dart';
import '../ble/measurement_session.dart';
import '../data/app_settings.dart';
import '../data/device_registry_store.dart';
import '../data/record_store.dart';
import '../models/device_models.dart';
import '../models/health_record.dart';
import '../models/measurements.dart';
import '../printing/receipt_content.dart' show fmt0, fmt1;
import '../utils/health_ranges.dart';
import '../utils/health_zones.dart';
import '../widgets/after_save_dialogs.dart';
import '../widgets/avatar3d.dart';
import '../widgets/bluetooth_settings_dialog.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/grip_dialogs.dart' show showGripStrengthEditDialog;
import '../widgets/measurement_cards.dart';
import 'result_screen.dart';

/// Hasil layar ukur yang dikembalikan ke beranda.
class MeasurementOutcome {
  final String recordId;
  final String name;
  final bool printing;
  const MeasurementOutcome(this.recordId, this.name, {required this.printing});
}

/// Satu lansia, semua alat sekaligus. Setiap alat mengunci hasilnya sendiri;
/// tidak ada dialog yang menghalangi alat lain.
class MeasurementScreen extends StatefulWidget {
  final PersonProfile profile;

  /// Hanya untuk test/screenshot.
  @visibleForTesting
  final AllMeasurements? initialMeasurements;

  const MeasurementScreen({
    super.key,
    required this.profile,
    this.initialMeasurements,
  });

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

/// Teks peringatan oranye: orangeAction di orangeActionBg hanya 3,55:1 →
/// digelapkan ke arah charcoal (±6,9:1).
final _orangeText = Color.lerp(
  AppColors.orangeAction,
  AppColors.charcoal,
  0.5,
)!;

/// Urutan tampil = urutan kerja yang disarankan (jalur kritis).
const _tileOrder = [
  DeviceType.weightScale,
  DeviceType.thermometer,
  DeviceType.pulseOximeter,
  DeviceType.tensimeter,
  DeviceType.gripStrength,
];

/// Sesi terakhir yang dibuat layar ini — hanya untuk test/screenshot.
@visibleForTesting
MeasurementSession? debugLastMeasurementSession;

/// Untuk screenshot: geser jam "Waktu" di bilah bawah.
@visibleForTesting
Duration debugElapsedOffset = Duration.zero;

class _MeasurementScreenState extends State<MeasurementScreen> {
  late final MeasurementSession _s = debugLastMeasurementSession =
      MeasurementSession(
        profile: widget.profile,
        // ignore: invalid_use_of_visible_for_testing_member
        initialMeasurements: widget.initialMeasurements,
      );
  bool _saving = false;

  // Selesai otomatis
  Timer? _countdown;
  int _secondsLeft = 0;
  bool _autoCancelled = false;

  // Konfirmasi simpan sebagian tanpa dialog: ketuk dua kali.
  bool _confirmPartial = false;
  Timer? _confirmTimer;

  Map<DeviceType, MeasureStep> _lastSteps = {};
  late final Timer _clock;

  /// Detak jam "Waktu". Hanya teks jam yang ikut digambar ulang tiap detik,
  /// bukan seluruh layar (avatar 3D & semua kotak alat).
  final _tick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _s.onMessage = (m) {
      if (mounted) showSnack(context, m);
    };
    _s.addListener(_onSessionChanged);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick.value++);
    unawaited(_s.start());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _confirmTimer?.cancel();
    _clock.cancel();
    _tick.dispose();
    _s.removeListener(_onSessionChanged);
    _s.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    // Getar singkat setiap ada alat yang baru selesai.
    final now = {for (final t in DeviceType.values) t: _s.stepOf(t)};
    final newlyDone = now.entries.any(
      (e) =>
          e.value == MeasureStep.done && _lastSteps[e.key] != MeasureStep.done,
    );
    final anyReset = now.entries.any(
      (e) =>
          e.value != MeasureStep.done && _lastSteps[e.key] == MeasureStep.done,
    );
    _lastSteps = now;
    if (newlyDone) {
      HapticFeedback.mediumImpact();
      Sound.play(Sfx.done);
    }
    if (anyReset) _autoCancelled = false;

    final shouldCount =
        AppSettings.instance.autoFinish &&
        _s.allRequiredDone &&
        !_autoCancelled;
    if (shouldCount && _countdown == null && !_saving) {
      _startCountdown();
    } else if (!shouldCount && _countdown != null) {
      _stopCountdown();
    }
  }

  void _startCountdown() {
    // Masih ada alat terdaftar yang belum tersambung → beri waktu lebih lama
    // (alat itu mungkin baru dinyalakan). Begitu tersambung, hitungan batal.
    _secondsLeft = _s.hasIdleRegistered ? 15 : 3;
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      // Lembar/dialog terbuka di atas layar ini → tunggu sampai ditutup.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        _stopCountdown();
        unawaited(_save(force: true));
      }
    });
    setState(() {});
  }

  void _stopCountdown() {
    _countdown?.cancel();
    _countdown = null;
    if (mounted) setState(() {});
  }

  void _cancelAuto() {
    _autoCancelled = true;
    _stopCountdown();
  }

  Future<void> _openDeviceSettings() async {
    _s.suspendAutoScan();
    try {
      await showBluetoothSettingsDialog(
        context: context,
        devices: _s.devices,
        matchesType: MeasurementSession.nameMatchesDeviceType,
        onRegister: (type, d) => DeviceRegistryStore.instance.register(
          RegisteredDevice(type: type, remoteId: d.remoteId, name: d.name),
        ),
        onUnregister: DeviceRegistryStore.instance.unregister,
        onRelink: _s.relinkDevice,
        radioNote: _s.radio?.label,
      );
    } finally {
      _s.resumeAutoScan();
    }
  }

  void _onStatusTap(DeviceType type) {
    if (_s.startMeasurementFor(type)) _openDeviceSettings();
  }

  Future<bool> _confirmLeave() async {
    if (!_s.hasUnsavedData) return true;
    return confirmDialog(
      context,
      title: 'Buang hasil pengukuran?',
      message:
          'Ada hasil yang belum disimpan. Kembali akan menghapus semua '
          'hasil untuk ${widget.profile.name}.',
      confirmLabel: 'Buang & kembali',
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
  }

  List<String> get _missing => [
    for (final t in _s.requiredDevices)
      if (!_s.stepOf(t).isFinished) t.shortLabel,
  ];

  Future<void> _save({bool force = false}) async {
    if (_saving) return;
    // Nilai sementara (SpO2 tanpa nadi, berat belum terkunci) tidak ikut
    // tersimpan → jangan simpan rekaman kosong.
    if (!_s.hasSavableData) {
      showSnack(
        context,
        'Belum ada hasil. Ukur dengan alat atau isi manual dulu.',
      );
      return;
    }
    if (!force && _missing.isNotEmpty && !_confirmPartial) {
      // Ketuk sekali lagi untuk menyimpan tanpa alat yang belum selesai.
      setState(() => _confirmPartial = true);
      _confirmTimer?.cancel();
      _confirmTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _confirmPartial = false);
      });
      return;
    }
    _confirmTimer?.cancel();
    _stopCountdown();
    setState(() => _saving = true);
    final now = DateTime.now();
    var id = HealthRecord.newId(now);
    while (RecordStore.instance.byId(id) != null) {
      id = HealthRecord.newId(now);
    }
    final record = HealthRecord(
      id: id,
      createdAt: now,
      startedAt: _s.startedAt,
      profile: widget.profile,
      // Tanpa nilai yang belum stabil & komposisi dari profil pengganti.
      measurements: _s.measurementsForSave(),
    );
    try {
      await RecordStore.instance.add(record);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _confirmPartial = false;
        // Jangan ulangi simpan otomatis yang gagal di setiap pembaruan alat.
        _autoCancelled = true;
      });
      showSnack(
        context,
        'Gagal menyimpan: $e. Coba lagi — data belum hilang.',
        error: true,
      );
      return;
    }
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final nav = Navigator.of(context);
    // Lembar/dialog masih terbuka di atas layar ini → tutup dulu, supaya yang
    // ditutup dengan hasil adalah layar ukur, bukan lembar itu.
    if (route != null && !route.isCurrent) nav.popUntil((r) => r == route);
    Sound.play(Sfx.success);
    // Tanya dulu: cetak struk, atau langsung lanjut lansia berikutnya.
    final choice = await showAfterSaveDialog(
      context,
      name: record.profile.name,
    );
    if (!mounted) return;
    final printing = choice == AfterSave.print;
    final outcome = MeasurementOutcome(
      record.id,
      record.profile.name,
      printing: printing,
    );
    if (printing) {
      // Halaman cetak: cetak otomatis, lalu tanya lanjut ukur atau tidak.
      unawaited(
        nav.pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              recordId: record.id,
              justSaved: true,
              autoPrint: true,
              askNextAfterPrint: true,
            ),
          ),
          result: outcome,
        ),
      );
    } else {
      nav.pop(outcome);
    }
  }

  Future<void> _openManual(DeviceType? type) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: _s,
              builder: (context, _) => _manualCard(type),
            ),
          ),
        ),
      ),
    );
  }

  Widget _manualCard(DeviceType? type) {
    final m = _s.measurements;
    const props = CardDeviceProps(isEditing: true);
    return switch (type) {
      DeviceType.tensimeter => TensimeterCard(
        data: m.tensimeter,
        props: props,
        onChanged: _s.updateTensimeter,
      ),
      DeviceType.pulseOximeter => PulseOximeterCard(
        data: m.pulseOximeter,
        props: props,
        onChanged: _s.updatePulseOximeter,
      ),
      DeviceType.thermometer => ThermometerCard(
        data: m.thermometer,
        props: props,
        onChanged: _s.updateThermometer,
      ),
      DeviceType.weightScale => WeightScaleCard(
        data: m.weightScale,
        props: props,
        heightMissing: _s.heightMissing,
        onChanged: _s.updateWeightScale,
      ),
      DeviceType.gripStrength => GripStrengthCard(
        data: m.gripStrength,
        activeSide: _s.activeGripSide,
        props: const CardDeviceProps(),
        onSideChanged: _s.setGripSide,
        onBulkEdit: () => showGripStrengthEditDialog(
          context: context,
          data: m.gripStrength,
          onSaved: _s.updateGripStrength,
        ),
      ),
      null => OthersCard(
        data: m.others,
        isEditing: true,
        showHeightWarning: _s.heightMissing,
        onChanged: _s.updateOthers,
      ),
    };
  }

  // ─── Pilihan per alat (ketuk kotak) ────────────────────────────────────────

  Future<void> _openActions(DeviceType type) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => ListenableBuilder(
        listenable: _s,
        builder: (ctx, _) {
          final actions = _actionsFor(type, compact: false, all: true);
          final device = _s.deviceOf(type);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      DeviceIcon(type: type, size: 44),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type.label, style: AppText.w700(18)),
                            Text(
                              device.status.label,
                              style: AppText.w500(14, device.status.color),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(16),
                  for (final a in actions) ...[
                    SizedBox(
                      height: 60,
                      child: _SheetButton(
                        action: a,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          a.onTap();
                        },
                      ),
                    ),
                    const Gap(10),
                  ],
                  SizedBox(
                    height: 56,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _onStatusTap(type);
                      },
                      icon: const Icon(Icons.bluetooth_searching_rounded),
                      label: Text(
                        device.status == DeviceStatus.unregistered
                            ? 'Daftarkan alat'
                            : 'Sambungkan ulang',
                        style: AppText.w600(15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Aksi untuk satu alat. Di kotak hanya 2 yang terpenting; lembar pilihan
  /// ([all]) menampilkan semuanya.
  List<_Action> _actionsFor(
    DeviceType type, {
    required bool compact,
    bool all = false,
  }) {
    final s = _s;
    final step = s.stepOf(type);
    final n = type.name;
    final list = <_Action>[];
    void manual() => list.add(
      _Action(
        'manual_$n',
        'Manual',
        'Isi manual',
        'Isi manual',
        Icons.edit_outlined,
        () => _openManual(type),
      ),
    );
    switch (step) {
      case MeasureStep.done:
        list.add(
          _Action(
            'remeasure_$n',
            'Ulangi',
            'Ukur ulang',
            'Ukur ulang',
            Icons.replay_rounded,
            () => s.remeasure(type),
          ),
        );
        list.add(
          _Action(
            'manual_$n',
            'Ubah',
            'Ubah',
            'Ubah hasil',
            Icons.edit_outlined,
            () => _openManual(type),
          ),
        );
      case MeasureStep.skipped:
        list.add(
          _Action(
            'unskip_$n',
            'Batal',
            'Batal lewati',
            'Batal lewati',
            Icons.undo_rounded,
            () => s.unskip(type),
            primary: true,
          ),
        );
      case MeasureStep.measuring:
        // "Terima" hanya bila ada bacaan (mis. genggam belum ada remasan).
        if (s.hasData(type)) {
          list.add(
            _Action(
              'accept_$n',
              'Terima',
              'Terima',
              'Terima hasil sekarang',
              Icons.check_rounded,
              () => s.acceptNow(type),
              primary: true,
            ),
          );
        }
        manual();
        if (all) {
          list.add(
            _Action(
              'remeasure_$n',
              'Ulangi',
              'Ukur ulang',
              'Ukur ulang',
              Icons.replay_rounded,
              () => s.remeasure(type),
            ),
          );
        }
      case MeasureStep.waiting:
        final gated =
            type == DeviceType.pulseOximeter && !s.oxArmed ||
            type == DeviceType.weightScale && !s.scaleArmed;
        if (gated) {
          list.add(
            _Action(
              'arm_$n',
              'Mulai',
              'Mulai',
              'Mulai sekarang',
              Icons.play_arrow_rounded,
              () => s.armNow(type),
              primary: true,
            ),
          );
        }
        manual();
        if (!gated || all) {
          list.add(
            _Action(
              'skip_$n',
              'Lewati',
              'Lewati',
              'Lewati alat ini',
              Icons.skip_next_rounded,
              () => s.skip(type),
            ),
          );
        }
    }
    return list;
  }

  /// Petunjuk langkah; untuk "selesai" mengikuti keadaan simpan sebenarnya.
  String _hintFor(AvatarPhase p) {
    if (p != AvatarPhase.finished) return _stepHint(p);
    if (_countdown != null) {
      return 'Semua alat selesai. Hasil disimpan sebentar lagi.';
    }
    return 'Semua langkah selesai. Tekan "Selesai" untuk menyimpan.';
  }

  // ─── Langkah sesuai alat yang aktif ───────────────────────────────────────

  bool _req(DeviceType t) => _s.requiredDevices.contains(t);
  String _names(List<DeviceType> ts) => [
    for (final t in ts)
      if (_req(t)) t.shortLabel.toLowerCase(),
  ].join(' · ');

  /// Langkah panduan untuk sesi ini: hanya fase yang punya alat tersambung.
  List<({AvatarPhase phase, String title, String subtitle})> get _guideSteps {
    final scale = _req(DeviceType.weightScale);
    const seatedAll = [
      DeviceType.tensimeter,
      DeviceType.pulseOximeter,
      DeviceType.thermometer,
    ];
    // Ada timbangan: suhu & oksigen sudah disebut di langkah berdiri.
    final seatedNames = scale && _req(DeviceType.tensimeter)
        ? _names(const [DeviceType.tensimeter])
        : _names(seatedAll);
    return [
      if (scale)
        (
          phase: AvatarPhase.standing,
          title: 'Berdiri',
          subtitle: _names([
            DeviceType.weightScale,
            DeviceType.thermometer,
            DeviceType.pulseOximeter,
          ]),
        ),
      if (seatedAll.any(_req))
        (
          phase: AvatarPhase.seated,
          title: 'Duduk tenang',
          subtitle: seatedNames,
        ),
      if (_req(DeviceType.gripStrength))
        (
          phase: AvatarPhase.gripping,
          title: 'Genggam terakhir',
          subtitle: 'Meremas menaikkan tensi',
        ),
    ];
  }

  /// Petunjuk fase, hanya menyebut alat yang tersambung.
  String _stepHint(AvatarPhase p) {
    if (_s.requiredDevices.isEmpty) {
      return 'Belum ada alat tersambung. Nyalakan alat, atau isi hasil manual '
          'dari kotak alat di bawah.';
    }
    final ox = _req(DeviceType.pulseOximeter);
    final temp = _req(DeviceType.thermometer);
    final scale = _req(DeviceType.weightScale);
    String join(List<String> parts) => parts.length <= 2
        ? parts.join(' dan ')
        : '${parts.sublist(0, parts.length - 1).join(', ')}, dan ${parts.last}';
    switch (p) {
      case AvatarPhase.standing:
        final also = [
          if (ox) 'jepit oksimeter di jari kanan',
          if (temp) 'ukur suhu dahi',
        ];
        return also.isEmpty
            ? 'Naik ke timbangan dan berdiri diam.'
            : 'Naik ke timbangan. Sambil berdiri, ${join(also)}.';
      case AvatarPhase.seated:
        final tensi = _req(DeviceType.tensimeter);
        final parts = [
          if (tensi) 'pasang manset di lengan kiri lalu tekan mulai',
          if ((!scale || !tensi) && ox) 'jepit oksimeter di jari',
          if ((!scale || !tensi) && temp) 'ukur suhu dahi',
        ];
        final tail = scale && tensi && ox ? ' Oksimeter boleh tetap.' : '';
        return 'Duduk tenang. ${_capitalize(join(parts))}.$tail';
      case AvatarPhase.gripping:
      case AvatarPhase.finished:
        return _phaseHint[p]!;
    }
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ─── Fase & sorotan avatar ─────────────────────────────────────────────────

  bool _fin(DeviceType t) =>
      _s.stepOf(t).isFinished || !_s.requiredDevices.contains(t);

  AvatarPhase get _phase {
    if (_s.requiredDevices.isEmpty) return AvatarPhase.standing;
    if (!_fin(DeviceType.weightScale)) return AvatarPhase.standing;
    if (!(_fin(DeviceType.tensimeter) &&
        _fin(DeviceType.pulseOximeter) &&
        _fin(DeviceType.thermometer))) {
      return AvatarPhase.seated;
    }
    if (!_fin(DeviceType.gripStrength)) return AvatarPhase.gripping;
    return AvatarPhase.finished;
  }

  static const _phaseDevices = {
    AvatarPhase.standing: {
      DeviceType.weightScale,
      DeviceType.thermometer,
      DeviceType.pulseOximeter,
    },
    AvatarPhase.seated: {
      DeviceType.tensimeter,
      DeviceType.pulseOximeter,
      DeviceType.thermometer,
    },
    AvatarPhase.gripping: {DeviceType.gripStrength},
    AvatarPhase.finished: <DeviceType>{},
  };

  Map<DeviceType, AvatarSpot> _spots(AvatarPhase phase) {
    final out = <DeviceType, AvatarSpot>{};
    for (final t in _phaseDevices[phase]!) {
      final step = _s.stepOf(t);
      final gated =
          t == DeviceType.pulseOximeter && !_s.oxArmed ||
          t == DeviceType.weightScale && !_s.scaleArmed;
      switch (step) {
        case MeasureStep.done:
          out[t] = AvatarSpot.done;
        case MeasureStep.measuring:
          out[t] = AvatarSpot.active;
        case MeasureStep.waiting:
          if (!_s.requiredDevices.contains(t)) continue;
          out[t] = gated ? AvatarSpot.gate : AvatarSpot.ready;
        case MeasureStep.skipped:
          continue;
      }
    }
    return out;
  }

  Set<DeviceType> _devicesOn(AvatarPhase phase) => {
    for (final t in _phaseDevices[phase]!)
      if (_s.requiredDevices.contains(t) &&
          _s.stepOf(t) != MeasureStep.skipped &&
          (_s.stepOf(t) != MeasureStep.done || t == DeviceType.tensimeter))
        t,
  };

  Widget _avatar(AvatarPhase phase) => ElderAvatar3D(
    key: const Key('avatar3d'),
    phase: phase,
    gender: widget.profile.gender,
    gripSide: _s.activeGripSide,
    spots: _spots(phase),
    devicesOn: _devicesOn(phase),
  );

  // ─── Tata letak ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) => PopScope(
        canPop: !_s.hasUnsavedData,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmLeave() && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: _buildAppBar(),
          body: Column(
            children: [
              _buildBanner(),
              _buildOfferBanner(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth >= 1000) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 360,
                            child: _GuidePanel(screen: this),
                          ),
                          Expanded(
                            child: _buildGrid(
                              c.maxWidth - 360,
                              withGuide: false,
                            ),
                          ),
                        ],
                      );
                    }
                    return _buildGrid(c.maxWidth, withGuide: true);
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomBar(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final p = widget.profile;
    final meta = [
      if (p.gender != null) p.gender!.label,
      if (p.age != null) '${p.age} th',
      if (p.heightCm != null) '${p.heightCm!.toStringAsFixed(0)} cm',
    ].join(' · ');
    return AppBar(
      toolbarHeight: 64,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.w700(19),
          ),
          Text(
            meta.isEmpty ? 'Ukur semua alat sekaligus' : meta,
            style: AppText.w400(14, AppColors.grey1),
          ),
        ],
      ),
      actions: [
        if (_s.deviceLocked)
          IconButton(
            key: const Key('lock_indicator'),
            tooltip: 'Kunci alat aktif — hanya alat terdaftar yang dipakai',
            onPressed: _openDeviceSettings,
            iconSize: 24,
            icon: const Icon(Icons.lock_rounded, color: AppColors.darkGreen),
          ),
        IconButton(
          tooltip: 'Cari ulang alat',
          onPressed: _s.rescanAll,
          iconSize: 26,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'Alat Bluetooth',
          onPressed: _openDeviceSettings,
          iconSize: 26,
          icon: const Icon(Icons.bluetooth_rounded),
        ),
        const Gap(8),
      ],
    );
  }

  /// Alat baru sejenis terdeteksi saat alat terdaftar tidak tersambung
  /// (kunci alat mati): pakai atau tolak.
  Widget _buildOfferBanner() {
    final o = _s.newDeviceOffer;
    if (o == null) return const SizedBox.shrink();
    String tail(String id) =>
        id.length > 5 ? '…${id.substring(id.length - 5)}' : id;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${o.type.label}: alat baru terdeteksi — ${o.name} (${tail(o.remoteId)})',
          style: AppText.w600(15, AppColors.charcoal),
        ),
        const Gap(2),
        Text(
          'Alat terdaftar (${tail(o.replaces.remoteId)}) tidak tersambung. '
          'Pakai alat baru ini?',
          style: AppText.w400(14, AppColors.grey1),
        ),
      ],
    );
    Widget buttons({required bool wide}) {
      final reject = SizedBox(
        height: 48,
        child: OutlinedButton(
          key: const Key('new_device_reject'),
          onPressed: _s.rejectNewDevice,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: FittedBox(
            child: Text('Tolak', style: AppText.w600(15, AppColors.primary)),
          ),
        ),
      );
      final accept = SizedBox(
        height: 48,
        child: FilledButton.icon(
          key: const Key('new_device_accept'),
          onPressed: _s.acceptNewDevice,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          icon: const Icon(Icons.check_rounded, size: 20),
          label: FittedBox(
            child: Text(
              'Pakai alat ini',
              style: AppText.w600(15, Colors.white),
            ),
          ),
        ),
      );
      if (wide) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [reject, const Gap(8), accept],
        );
      }
      return Row(
        children: [
          Expanded(child: reject),
          const Gap(8),
          Expanded(flex: 2, child: accept),
        ],
      );
    }

    return Container(
      key: const Key('new_device_banner'),
      width: double.infinity,
      color: AppColors.primarySoft,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, c) {
          const icon = Icon(
            Icons.bluetooth_searching_rounded,
            color: AppColors.primary,
            size: 28,
          );
          if (c.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const Gap(12),
                    Expanded(child: text),
                  ],
                ),
                const Gap(8),
                buttons(wide: false),
              ],
            );
          }
          return Row(
            children: [
              icon,
              const Gap(12),
              Expanded(child: text),
              const Gap(12),
              buttons(wide: true),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBanner() {
    String? text;
    String? action;
    VoidCallback? onAction;
    if (_s.gateChecked && !_s.gate.isOk) {
      text = _s.gate.message;
      action = _s.gate.actionLabel.isEmpty ? null : _s.gate.actionLabel;
      onAction = () => _s.fixGate();
    } else if (_s.isRegistryEmpty) {
      text =
          'Belum ada alat terdaftar. Daftarkan alat, atau isi hasil manual '
          'lewat tombol "Manual" di tiap kotak.';
      action = 'Daftarkan alat';
      onAction = _openDeviceSettings;
    }
    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.orangeActionBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.bluetooth_disabled_rounded,
            size: 20,
            color: AppColors.orangeAction,
          ),
          const Gap(10),
          Expanded(child: Text(text, style: AppText.w500(14, _orangeText))),
          if (action != null)
            SizedBox(
              height: 48,
              child: TextButton(onPressed: onAction, child: Text(action)),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(double width, {required bool withGuide}) {
    final compact = width < 600;
    final cols = width >= 820 ? 3 : 2;
    final pad = compact ? 10.0 : 14.0;
    final gap = compact ? 8.0 : 12.0;
    // Alat yang tersambung/sudah dipakai di atas; sisanya di bawah, redup.
    bool inUse(DeviceType t) =>
        _s.isActive(t) || _s.stepOf(t) != MeasureStep.waiting;
    Widget tile(DeviceType t) => _DeviceTile(
      key: Key('tile_${t.name}'),
      type: t,
      screen: this,
      compact: compact,
    );
    final tiles = <Widget>[
      for (final t in _tileOrder)
        if (inUse(t)) tile(t),
      _OthersTile(
        session: _s,
        compact: compact,
        onEdit: () => _openManual(null),
      ),
    ];
    final idle = [
      for (final t in _tileOrder)
        if (!inUse(t))
          _IdleTile(
            key: Key('idle_${t.name}'),
            registered: _s.deviceOf(t).status != DeviceStatus.unregistered,
            onTap: () => _openActions(t),
            child: tile(t),
          ),
    ];
    final tileW = (math.min(width, 1400) - pad * 2 - gap * (cols - 1)) / cols;
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: MaxWidth(
        maxWidth: 1400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (withGuide) ...[
              _GuideCard(screen: this, compact: compact),
              SizedBox(height: gap),
            ],
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in tiles) SizedBox(width: tileW, child: t),
              ],
            ),
            if (idle.isNotEmpty) ...[
              SizedBox(height: gap * 2),
              Row(
                children: [
                  const Icon(
                    Icons.bluetooth_disabled_rounded,
                    size: 18,
                    color: AppColors.grey4,
                  ),
                  const Gap(6),
                  Expanded(
                    child: Text(
                      'Belum tersambung · tidak ikut dicek (${idle.length})',
                      style: AppText.w600(14, AppColors.grey4),
                    ),
                  ),
                ],
              ),
              SizedBox(height: gap),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final t in idle) SizedBox(width: tileW, child: t),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _clockText(TextStyle style, {String prefix = ''}) =>
      ValueListenableBuilder<int>(
        valueListenable: _tick,
        builder: (_, _, _) => Text('$prefix$_elapsedText', style: style),
      );

  String get _elapsedText {
    final elapsed =
        DateTime.now().difference(_s.startedAt) + debugElapsedOffset;
    final mm = elapsed.inMinutes;
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Widget _buildBottomBar() {
    final req = _s.requiredDevices;
    final done = req.where((t) => _s.stepOf(t).isFinished).length;
    final missing = _missing;
    final narrow = MediaQuery.sizeOf(context).width < 600;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_countdown != null)
            Container(
              key: const Key('auto_finish_banner'),
              width: double.infinity,
              color: AppColors.greenSoft,
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.darkGreen,
                    size: 28,
                  ),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      '${_s.hasIdleRegistered ? 'Alat tersambung selesai' : 'Semua alat selesai'}'
                      ' · simpan dalam $_secondsLeft',
                      // charcoal di greenSoft: kontras ≥4,5:1 (darkGreen 2,5).
                      style: AppText.w600(narrow ? 15 : 17, AppColors.charcoal),
                    ),
                  ),
                  const Gap(8),
                  if (_s.hasIdleRegistered) ...[
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        key: const Key('save_now_button'),
                        onPressed: () => _save(force: true),
                        // Putih di darkGreen hanya 2,7:1 → primary.
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        child: Text(
                          'Simpan sekarang',
                          style: AppText.w600(16, Colors.white),
                        ),
                      ),
                    ),
                    const Gap(8),
                  ],
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _cancelAuto,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.darkGreen),
                        foregroundColor: AppColors.darkGreen,
                      ),
                      child: Text('Batalkan', style: AppText.w600(16)),
                    ),
                  ),
                ],
              ),
            ),
          if (_confirmPartial)
            Container(
              key: const Key('partial_banner'),
              width: double.infinity,
              color: AppColors.orangeActionBg,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(
                'Ketuk lagi untuk simpan tanpa ${missing.join(', ')}',
                style: AppText.w600(narrow ? 14 : 15, _orangeText),
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                if (req.isNotEmpty) ...[
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: done / req.length,
                          strokeWidth: 5,
                          backgroundColor: AppColors.lightGrey,
                          color: done == req.length
                              ? AppColors.darkGreen
                              : AppColors.primary,
                        ),
                        Text('$done/${req.length}', style: AppText.w700(14)),
                      ],
                    ),
                  ),
                  const Gap(12),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: narrow
                        ? [
                            Text(
                              'Waktu',
                              style: AppText.w500(14, AppColors.grey1),
                            ),
                            _clockText(AppText.w700(18)),
                          ]
                        : [
                            Text(
                              req.isEmpty
                                  ? '${_s.doneCount} alat selesai'
                                  : '$done dari ${req.length} alat selesai',
                              style: AppText.w600(16),
                            ),
                            _clockText(
                              AppText.w500(14, AppColors.grey1),
                              prefix: 'Waktu ',
                            ),
                          ],
                  ),
                ),
                const Gap(12),
                _saveButton(narrow),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Selesai": tampak sekunder bila belum ada yang bisa disimpan (tetap
  /// bisa diketuk untuk pesan "Belum ada hasil").
  Widget _saveButton(bool narrow) {
    final ready = _saving || _s.hasSavableData;
    final fg = ready ? Colors.white : AppColors.grey1;
    return ConstrainedBox(
      // Sisakan ruang untuk cincin progres & waktu di kiri.
      constraints: BoxConstraints(
        maxWidth: math.max(
          160,
          MediaQuery.sizeOf(context).width - 32 - 60 - 12 - 72,
        ),
      ),
      child: FilledButton.icon(
        key: const Key('save_button'),
        onPressed: _saving ? null : () => _save(),
        style: FilledButton.styleFrom(
          minimumSize: Size(narrow ? 0 : 240, 60),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          // Putih di orangeAction hanya 3,9:1 → navyBlue.
          backgroundColor: !ready
              ? AppColors.lightGrey
              : _confirmPartial
              ? AppColors.navyBlue
              : AppColors.primary,
          foregroundColor: fg,
          side: ready ? null : const BorderSide(color: AppColors.greyBorder),
        ),
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(Icons.save_rounded, size: 24, color: fg),
        // Teks besar / layar sempit: label mengecil, tidak meluber.
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _confirmPartial ? 'Ya, simpan' : 'Selesai',
            maxLines: 1,
            style: AppText.w700(narrow ? 16 : 18, fg),
          ),
        ),
      ),
    );
  }
}

class _Action {
  final String key;

  /// Layar genggam (ikon di atas label).
  final String shortLabel;

  /// Layar meja.
  final String midLabel;

  /// Lembar pilihan.
  final String longLabel;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  const _Action(
    this.key,
    this.shortLabel,
    this.midLabel,
    this.longLabel,
    this.icon,
    this.onTap, {
    this.primary = false,
  });
}

class _SheetButton extends StatelessWidget {
  final _Action action;
  final VoidCallback onPressed;
  const _SheetButton({required this.action, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      alignment: Alignment.centerLeft,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    final icon = Icon(action.icon, size: 22);
    final label = Text(action.longLabel, style: AppText.w600(16));
    final key = Key('sheet_${action.key}');
    return action.primary
        ? FilledButton.tonalIcon(
            key: key,
            onPressed: onPressed,
            icon: icon,
            label: label,
            style: style,
          )
        : OutlinedButton.icon(
            key: key,
            onPressed: onPressed,
            icon: icon,
            label: label,
            style: style,
          );
  }
}

// ─── Panduan + avatar ────────────────────────────────────────────────────────

const _phaseTitle = {
  AvatarPhase.standing: 'Berdiri',
  AvatarPhase.seated: 'Duduk tenang',
  AvatarPhase.gripping: 'Genggam',
  AvatarPhase.finished: 'Selesai',
};

const _phaseHint = {
  AvatarPhase.standing:
      'Naik ke timbangan. Sambil berdiri, jepit oksimeter di jari kanan dan ukur suhu dahi.',
  AvatarPhase.seated:
      'Duduk tenang. Pasang manset di lengan kiri lalu tekan mulai. Oksimeter boleh tetap.',
  AvatarPhase.gripping:
      'Remas alat genggam sekuat mungkin, lalu lepas. 3× tangan kiri, lalu 3× kanan.',
  AvatarPhase.finished: 'Semua alat selesai. Tekan "Selesai" untuk menyimpan.',
};

class _GuidePanel extends StatelessWidget {
  final _MeasurementScreenState screen;
  const _GuidePanel({required this.screen});

  @override
  Widget build(BuildContext context) {
    final phase = screen._phase;
    final steps = screen._guideSteps;
    final idx = phase == AvatarPhase.finished
        ? steps.length
        : steps.indexWhere((s) => s.phase == phase);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      // Layar meja pendek / teks besar: bagian teks bisa digulir, avatar
      // mengambil sisa ruang — tidak ada yang terpotong.
      child: LayoutBuilder(
        builder: (context, c) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: screen._avatar(phase)),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: c.maxHeight * 0.66),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (steps.isNotEmpty)
                      Text(
                        idx >= 0 && idx < steps.length
                            ? 'Langkah ${idx + 1} dari ${steps.length}'
                            : 'Semua langkah',
                        style: AppText.w600(14, AppColors.primary),
                      ),
                    const Gap(2),
                    Text(
                      steps.isEmpty ? 'Menunggu alat' : _phaseTitle[phase]!,
                      style: AppText.w700(22),
                    ),
                    const Gap(4),
                    Text(
                      screen._hintFor(phase),
                      style: AppText.w400(14, AppColors.grey1),
                    ),
                    const Gap(14),
                    for (var i = 0; i < steps.length; i++)
                      _StepRow(
                        key: Key('step_${steps[i].phase.name}'),
                        index: i,
                        title: steps[i].title,
                        subtitle: steps[i].subtitle,
                        done: idx > i,
                        active: idx == i,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final _MeasurementScreenState screen;
  final bool compact;
  const _GuideCard({required this.screen, required this.compact});

  @override
  Widget build(BuildContext context) {
    final phase = screen._phase;
    final steps = screen._guideSteps;
    final n = steps.length;
    final idx = phase == AvatarPhase.finished
        ? n
        : steps.indexWhere((s) => s.phase == phase);
    return Container(
      key: const Key('guide_card'),
      // Tinggi minimum; teks besar boleh menambah tinggi (tidak terpotong).
      constraints: BoxConstraints(minHeight: compact ? 172 : 200),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 128 : 170,
            height: compact ? 164 : 192,
            child: screen._avatar(phase),
          ),
          const Gap(6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < n; i++) ...[
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: idx > i
                                ? AppColors.darkGreen
                                : idx == i
                                ? AppColors.primary
                                : AppColors.lightGrey,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      if (i < n - 1) const Gap(4),
                    ],
                  ],
                ),
                const Gap(10),
                if (n > 0)
                  Text(
                    idx >= 0 && idx < n
                        ? 'Langkah ${idx + 1} dari $n'
                        : 'Semua langkah',
                    style: AppText.w600(14, AppColors.primary),
                  ),
                Text(
                  n == 0 ? 'Menunggu alat' : _phaseTitle[phase]!,
                  style: AppText.w700(compact ? 18 : 20),
                ),
                const Gap(2),
                Text(
                  screen._hintFor(phase),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.w400(compact ? 12.5 : 14, AppColors.grey1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;
  final bool done;
  final bool active;
  const _StepRow({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppColors.darkGreen
        : active
        ? AppColors.primary
        : AppColors.grey4;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? AppColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done || active ? color : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: AppText.w700(14, active ? Colors.white : color),
                  ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.w600(
                    15,
                    done || active ? AppColors.charcoal : AppColors.grey4,
                  ),
                ),
                Text(subtitle, style: AppText.w400(14, AppColors.grey1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Kotak alat ──────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final DeviceType type;
  final _MeasurementScreenState screen;
  final bool compact;

  const _DeviceTile({
    super.key,
    required this.type,
    required this.screen,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final s = screen._s;
    final step = s.stepOf(type);
    final device = s.deviceOf(type);
    final m = s.measurements;
    final gender = screen.widget.profile.gender;

    // Nilai utama + keterangan
    String? value;
    String unit = '';
    String? sub;
    bool flagged = false;
    switch (type) {
      case DeviceType.tensimeter:
        final t = m.tensimeter;
        if (t.systolic != null || t.diastolic != null) {
          value = '${fmt0(t.systolic)}/${fmt0(t.diastolic)}';
          unit = 'mmHg';
          flagged =
              HealthRanges.bloodPressureNormal(t.systolic, t.diastolic) ==
              false;
        }
        if (t.pulse != null) sub = 'Nadi ${fmt0(t.pulse)} bpm';
      case DeviceType.pulseOximeter:
        final o = m.pulseOximeter;
        if (o.spo2 != null) {
          value = fmt0(o.spo2);
          unit = '%';
          flagged = HealthRanges.oxygenNormal(o.spo2) == false;
        }
        if (o.heartRate != null) sub = 'Nadi ${fmt0(o.heartRate)} bpm';
      case DeviceType.thermometer:
        final th = m.thermometer;
        if (th.temperature != null) {
          value = fmt1(th.temperature);
          unit = '°C';
          flagged = HealthRanges.temperatureNormal(th.temperature) == false;
        }
      case DeviceType.weightScale:
        final w = m.weightScale;
        if (w.weight != null) {
          value = fmt1(w.weight);
          unit = 'kg';
        }
        if (w.bodyFatPercent != null) sub = 'Lemak ${fmt1(w.bodyFatPercent)}%';
      case DeviceType.gripStrength:
        final g = m.gripStrength;
        if (g.gripLeft != null || g.gripRight != null) {
          value = '${fmt1(g.gripLeft)} · ${fmt1(g.gripRight)}';
          unit = 'kg';
          sub = 'Kiri · kanan (terbaik)';
        }
    }

    // Petunjuk status
    String hint;
    Color hintColor = AppColors.grey4;
    switch (step) {
      case MeasureStep.done:
        hint = 'Selesai';
        hintColor = AppColors.darkGreen;
      case MeasureStep.skipped:
        hint = 'Dilewati';
      case MeasureStep.measuring:
        hintColor = AppColors.primary;
        hint = switch (type) {
          DeviceType.pulseOximeter =>
            s.oxSearchStage > 0
                ? 'Mencari data… (langkah ${s.oxSearchStage}/${MeasurementSession.oxSearchSteps})'
                : 'Menstabilkan ${s.oxStableProgress}/${MeasurementSession.oxStableCount}',
          DeviceType.weightScale =>
            s.isWeightLocked
                ? 'Menganalisa komposisi…'
                : 'Menimbang — berdiri diam',
          DeviceType.gripStrength =>
            '${s.activeGripSide == GripSide.left ? 'Kiri' : 'Kanan'} · ${s.gripAttempts}/6 remasan',
          _ => 'Mengukur…',
        };
      case MeasureStep.waiting:
        if (device.status == DeviceStatus.unregistered) {
          hint = 'Belum terdaftar — isi manual';
        } else if (device.status != DeviceStatus.connected) {
          hint = 'Nyalakan alat';
        } else if (type == DeviceType.pulseOximeter &&
            s.oxSearchStage >= MeasurementSession.oxSearchSteps) {
          hint =
              'Data belum masuk. Lepas jari, matikan oksimeter 5 detik, '
              'nyalakan lagi';
          hintColor = _orangeText;
        } else if (type == DeviceType.pulseOximeter && s.oxSearchStage > 0) {
          hint =
              'Mencari data… (langkah ${s.oxSearchStage}/${MeasurementSession.oxSearchSteps})';
          hintColor = _orangeText;
        } else if (type == DeviceType.pulseOximeter && !s.oxArmed) {
          hint = 'Lepas jari sebentar, lalu pasang';
          hintColor = _orangeText;
        } else if (type == DeviceType.weightScale && !s.scaleArmed) {
          hint = 'Turun dari timbangan dulu';
          hintColor = _orangeText;
        } else {
          hint = switch (type) {
            DeviceType.tensimeter => 'Pasang manset, tekan mulai',
            DeviceType.pulseOximeter => 'Jepit di jari',
            DeviceType.thermometer => 'Ukur suhu dahi',
            DeviceType.weightScale => 'Naik ke timbangan',
            DeviceType.gripStrength => 'Remas sekuat mungkin, lepas',
          };
        }
    }

    final borderColor = switch (step) {
      MeasureStep.done => AppColors.darkGreen,
      MeasureStep.measuring => AppColors.primary,
      _ => AppColors.border,
    };

    // Grafik per alat.
    Widget chart;
    if (type == DeviceType.gripStrength && step == MeasureStep.measuring) {
      chart = LiveForceChart(
        key: const Key('grip_live_chart'),
        source: s.gripLive,
        height: compact ? 54 : 52,
      );
    } else {
      final (spec, v) = switch (type) {
        DeviceType.tensimeter => (
          HealthZones.systolic,
          m.tensimeter.systolic?.toDouble(),
        ),
        DeviceType.pulseOximeter => (HealthZones.spo2, m.pulseOximeter.spo2),
        DeviceType.thermometer => (
          HealthZones.temperature,
          m.thermometer.temperature,
        ),
        DeviceType.weightScale => (HealthZones.bmi, m.weightScale.bmi),
        DeviceType.gripStrength => (
          HealthZones.grip(gender),
          [m.gripStrength.gripLeft, m.gripStrength.gripRight]
              .whereType<double>()
              .fold<double?>(null, (a, b) => a == null || b > a ? b : a),
        ),
      };
      chart = RangeGauge(spec: spec, value: v, compact: compact);
    }

    final trace = type == DeviceType.pulseOximeter
        ? s.heartRateTrace
        : const <double>[];
    final actions = screen._actionsFor(type, compact: compact).take(2).toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('tile_tap_${type.name}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => screen._openActions(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 14,
            compact ? 12 : 10,
            compact ? 12 : 14,
            compact ? 12 : 12,
          ),
          decoration: BoxDecoration(
            color: step == MeasureStep.done
                ? const Color(0xFFF3FCF7)
                : step == MeasureStep.skipped
                ? AppColors.lightGrey
                : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor,
              width: step == MeasureStep.waiting || step == MeasureStep.skipped
                  ? 1
                  : 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DeviceIcon(type: type, size: compact ? 30 : 36),
                  Gap(compact ? 8 : 10),
                  Expanded(
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        type.shortLabel,
                        maxLines: 1,
                        style: AppText.w600(compact ? 15 : 18),
                      ),
                    ),
                  ),
                  _ConnDot(
                    status: device.status,
                    busy: s.connectingDevice == type,
                    compact: compact,
                    onTap: () => screen._onStatusTap(type),
                  ),
                ],
              ),
              SizedBox(height: compact ? 6 : 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: compact ? 36 : 42,
                      child: FittedBox(
                        alignment: Alignment.bottomLeft,
                        fit: BoxFit.scaleDown,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              value ?? '—',
                              style: AppText.w700(
                                compact ? 28 : 36,
                                value == null
                                    ? AppColors.grey3
                                    : flagged
                                    ? AppColors.red
                                    : AppColors.charcoal,
                              ),
                            ),
                            if (value != null && unit.isNotEmpty) ...[
                              const Gap(4),
                              Text(
                                unit,
                                style: AppText.w500(
                                  compact ? 13 : 15,
                                  AppColors.grey4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (trace.length >= 2)
                    SizedBox(
                      key: const Key('hr_sparkline'),
                      width: compact ? 52 : 96,
                      height: compact ? 30 : 38,
                      child: Sparkline(values: trace, color: AppColors.red),
                    ),
                ],
              ),
              Text(
                sub ?? ' ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.w400(compact ? 12 : 14, AppColors.grey1),
              ),
              SizedBox(height: compact ? 6 : 4),
              chart,
              SizedBox(height: compact ? 6 : 4),
              Row(
                children: [
                  if (step == MeasureStep.done)
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppColors.darkGreen,
                    )
                  else if (step == MeasureStep.measuring)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: hintColor,
                      ),
                    ),
                  if (step == MeasureStep.done || step == MeasureStep.measuring)
                    const Gap(6),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.w600(compact ? 12 : 14, hintColor),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 8),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) Gap(compact ? 6 : 10),
                    Expanded(
                      child: _BigAction(action: actions[i], compact: compact),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kotak alat yang belum tersambung: redup, tidak bisa dipakai langsung,
/// dengan keterangan di atasnya. Ketuk → pilihan sambungkan / isi manual.
class _IdleTile extends StatelessWidget {
  final bool registered;
  final VoidCallback onTap;
  final Widget child;

  const _IdleTile({
    super.key,
    required this.registered,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IgnorePointer(
          child: ExcludeSemantics(child: Opacity(opacity: 0.35, child: child)),
        ),
        Positioned.fill(
          child: Material(
            color: AppColors.background.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              // Kotak genggam yang pendek: keterangan mengecil, tidak meluber.
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.bluetooth_disabled_rounded,
                              size: 20,
                              color: AppColors.grey1,
                            ),
                            const Gap(6),
                            Text(
                              registered
                                  ? 'Alat belum tersambung'
                                  : 'Alat belum terdaftar',
                              style: AppText.w700(15, AppColors.grey1),
                            ),
                          ],
                        ),
                        const Gap(2),
                        Text(
                          registered
                              ? 'Nyalakan alat · ketuk untuk isi manual'
                              : 'Ketuk untuk daftar / isi manual',
                          textAlign: TextAlign.center,
                          style: AppText.w400(14, AppColors.grey1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tombol aksi besar (≥ 52 dp): ikon + label. Di layar genggam ikon di atas
/// label supaya dua tombol muat berdampingan.
class _BigAction extends StatelessWidget {
  final _Action action;
  final bool compact;
  const _BigAction({required this.action, required this.compact});

  @override
  Widget build(BuildContext context) {
    final a = action;
    final fg = a.primary ? AppColors.primary : AppColors.charcoal;
    final bg = a.primary ? AppColors.primarySoft : AppColors.surface;
    final label = compact ? a.shortLabel : a.midLabel;
    final child = compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(a.icon, size: 22, color: fg),
              const Gap(2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: AppText.w600(13, fg)),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(a.icon, size: 22, color: fg),
              const Gap(8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppText.w600(15.5, fg),
                  ),
                ),
              ),
            ],
          );
    return SizedBox(
      height: compact ? 58 : 52,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: a.primary ? AppColors.primarySoft : AppColors.greyBorder,
            width: 1.2,
          ),
        ),
        child: InkWell(
          key: Key(a.key),
          borderRadius: BorderRadius.circular(14),
          onTap: a.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _ConnDot extends StatelessWidget {
  final DeviceStatus status;
  final bool busy;
  final bool compact;
  final VoidCallback onTap;
  const _ConnDot({
    required this.status,
    required this.busy,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = status == DeviceStatus.unregistered
        ? AppColors.grey3
        : status.color;
    return Tooltip(
      message: status == DeviceStatus.unregistered
          ? 'Daftarkan alat'
          : status.label,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        // Target sentuh ≥48 dp (lansia & kader).
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: busy || status == DeviceStatus.connecting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(
                    status == DeviceStatus.unregistered
                        ? Icons.add_link_rounded
                        : Icons.bluetooth_connected_rounded,
                    size: 22,
                    color: color,
                  ),
          ),
        ),
      ),
    );
  }
}

class _OthersTile extends StatelessWidget {
  final MeasurementSession session;
  final bool compact;
  final VoidCallback onEdit;
  const _OthersTile({
    required this.session,
    required this.compact,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final o = session.measurements.others;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 30 : 36,
                height: compact ? 30 : 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEFF9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.straighten_rounded,
                  size: 20,
                  color: Color(0xFF5E6AD2),
                ),
              ),
              const Gap(10),
              Expanded(
                child: Text('Lainnya', style: AppText.w600(compact ? 15 : 18)),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 6),
          SizedBox(
            height: compact ? 36 : 42,
            child: FittedBox(
              alignment: Alignment.bottomLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                o.height == null ? '—' : '${fmt1(o.height)} cm',
                style: AppText.w700(
                  compact ? 28 : 36,
                  o.height == null ? AppColors.grey3 : AppColors.charcoal,
                ),
              ),
            ),
          ),
          Text(
            o.calfCircumference == null
                ? 'Tinggi badan'
                : 'Tinggi · betis ${fmt1(o.calfCircumference)} cm',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.w400(compact ? 12 : 14, AppColors.grey1),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            session.heightMissing
                ? 'Isi tinggi agar IMT akurat'
                : 'Diisi manual (opsional)',
            style: AppText.w600(
              compact ? 12 : 14,
              session.heightMissing ? _orangeText : AppColors.grey1,
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          _BigAction(
            compact: compact,
            action: _Action(
              'manual_others',
              o.height == null ? 'Isi' : 'Ubah',
              o.height == null ? 'Isi tinggi' : 'Ubah tinggi',
              o.height == null ? 'Isi tinggi' : 'Ubah tinggi',
              Icons.edit_outlined,
              onEdit,
            ),
          ),
        ],
      ),
    );
  }
}
