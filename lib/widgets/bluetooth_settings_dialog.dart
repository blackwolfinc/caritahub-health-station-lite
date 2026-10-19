// Port dari Staff Ops (branch health-device): widgets/bluetooth_settings_dialog.dart
// Dialog ini mengelola *pendaftaran* alat, bukan koneksi: alat terdaftar
// tersambung sendiri begitu dinyalakan.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:gap/gap.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app/theme.dart';
import '../data/device_registry_store.dart';
import '../models/device_models.dart';
import 'common.dart' show confirmDialog;
import 'measurement_cards.dart' show DeviceIcon;

/// Nyalakan/matikan kunci alat. Mematikan perlu konfirmasi, karena alat lain
/// di sekitar lalu bisa ditawarkan untuk menggantikan alat terdaftar.
Future<void> setDeviceLock(BuildContext context, bool value) async {
  if (!value) {
    final ok = await confirmDialog(
      context,
      title: 'Matikan kunci alat?',
      message:
          'Alat terdaftar bisa diganti atau dihapus, dan alat baru sejenis '
          'di sekitar akan ditawarkan saat alat terdaftar tidak tersambung.',
      confirmLabel: 'Matikan kunci',
      icon: Icons.lock_open_rounded,
    );
    if (!ok) return;
  }
  await DeviceRegistryStore.instance.setLocked(value);
}

/// Baris sakelar kunci alat (dipakai di dialog alat & Pengaturan).
class DeviceLockTile extends StatelessWidget {
  const DeviceLockTile({super.key});

  @override
  Widget build(BuildContext context) {
    final reg = DeviceRegistryStore.instance;
    return ListenableBuilder(
      listenable: reg,
      builder: (context, _) => SwitchListTile(
        key: const Key('device_lock_switch'),
        contentPadding: EdgeInsets.zero,
        value: reg.locked,
        onChanged: (v) => setDeviceLock(context, v),
        secondary: Icon(
          reg.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
          color: reg.locked ? AppColors.darkGreen : AppColors.grey4,
        ),
        title: Text('Kunci alat', style: AppText.w600(14)),
        subtitle: Text(
          reg.locked
              ? 'Hanya alat terdaftar yang dipakai. Pemancar alat lain diabaikan; '
                    'alat tidak bisa diganti sampai kunci dimatikan.'
              : 'Bila alat terdaftar tidak tersambung, alat baru sejenis yang '
                    'terdeteksi ditawarkan: pakai atau tolak.',
          style: AppText.w400(12, AppColors.grey4),
        ),
      ),
    );
  }
}

/// Minta izin BLE dan pastikan adapter menyala. Dipakai sebelum memindai
/// dari layar Pengaturan (di luar sesi pengukuran).
Future<bool> ensureBleReady() async {
  try {
    if (!await FlutterBluePlus.isSupported) return false;
    if (Platform.isAndroid) {
      final r = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      final ble = [
        r[Permission.bluetoothScan],
        r[Permission.bluetoothConnect],
      ].whereType<PermissionStatus>();
      if (ble.any((s) => !s.isGranted)) return false;
    }
    var state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on && Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
        state = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    return state == BluetoothAdapterState.on;
  } catch (_) {
    return false;
  }
}

Future<void> showBluetoothSettingsDialog({
  required BuildContext context,
  required List<DeviceInfo> devices,
  required bool Function(DeviceType type, String name) matchesType,
  required Future<void> Function(DeviceType type, ScannedBleDevice device)
  onRegister,
  required Future<void> Function(DeviceType type) onUnregister,
  Future<void> Function(DeviceType type)? onRelink,
  String? radioNote,
}) {
  return showDialog(
    context: context,
    builder: (_) => _BluetoothSettingsDialog(
      devices: devices,
      matchesType: matchesType,
      onRegister: onRegister,
      onUnregister: onUnregister,
      onRelink: onRelink,
      radioNote: radioNote,
    ),
  );
}

class _BluetoothSettingsDialog extends StatefulWidget {
  final List<DeviceInfo> devices;
  final bool Function(DeviceType type, String name) matchesType;
  final Future<void> Function(DeviceType type, ScannedBleDevice device)
  onRegister;
  final Future<void> Function(DeviceType type) onUnregister;
  final Future<void> Function(DeviceType type)? onRelink;
  final String? radioNote;

  const _BluetoothSettingsDialog({
    required this.devices,
    required this.matchesType,
    required this.onRegister,
    required this.onUnregister,
    this.onRelink,
    this.radioNote,
  });

  @override
  State<_BluetoothSettingsDialog> createState() =>
      _BluetoothSettingsDialogState();
}

class _BluetoothSettingsDialogState extends State<_BluetoothSettingsDialog> {
  late final List<DeviceInfo> _devices = List.of(widget.devices);

  void _setDevice(DeviceType type, DeviceInfo Function(DeviceInfo) fn) {
    setState(() {
      final idx = _devices.indexWhere((d) => d.type == type);
      if (idx >= 0) _devices[idx] = fn(_devices[idx]);
    });
  }

  Future<void> _relink(DeviceType type) async {
    _setDevice(type, (d) => d.copyWith(status: DeviceStatus.waiting));
    await widget.onRelink?.call(type);
  }

  Future<void> _openRegisterPicker(DeviceType type) async {
    final picked = await showDialog<ScannedBleDevice>(
      context: context,
      builder: (_) => _DeviceRegistrationPicker(
        type: type,
        matchesType: (name) => widget.matchesType(type, name),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await widget.onRegister(type, picked);
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;
    _setDevice(
      type,
      (d) =>
          d.copyWith(status: DeviceStatus.waiting, macAddress: picked.remoteId),
    );
  }

  Future<void> _unregister(DeviceType type) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus ${type.label}?', style: AppText.w600(16)),
        content: Text(
          'Alat ini tidak akan tersambung otomatis lagi sampai didaftarkan ulang.',
          style: AppText.w400(14, AppColors.grey1),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.onUnregister(type);
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;
    _setDevice(
      type,
      (d) => d.copyWith(status: DeviceStatus.unregistered, macAddress: null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final registered = _devices
        .where((d) => d.status != DeviceStatus.unregistered)
        .length;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.bluetooth_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Alat terdaftar', style: AppText.w700(16)),
                        Text(
                          'Alat tersambung otomatis setelah didaftarkan dan dinyalakan',
                          style: AppText.w400(12, AppColors.grey4),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: _devices.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) {
                  final d = _devices[i];
                  return ListenableBuilder(
                    listenable: DeviceRegistryStore.instance,
                    builder: (context, _) => _DeviceRow(
                      device: d,
                      locked: DeviceRegistryStore.instance.locked,
                      onRegister: () => _openRegisterPicker(d.type),
                      onRemove: () => _unregister(d.type),
                      onRelink: widget.onRelink == null
                          ? null
                          : () => _relink(d.type),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DeviceLockTile(),
                  if (widget.radioNote != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.network_check_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const Gap(8),
                          Expanded(
                            child: Text(
                              'Mode periksa: ${widget.radioNote}',
                              key: const Key('radio_note'),
                              style: AppText.w500(12, AppColors.grey1),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$registered dari ${_devices.length} alat terdaftar',
                      style: AppText.w400(13, AppColors.grey4),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Selesai'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final DeviceInfo device;
  final bool locked;
  final VoidCallback onRegister;
  final VoidCallback onRemove;
  final VoidCallback? onRelink;

  const _DeviceRow({
    required this.device,
    required this.onRegister,
    required this.onRemove,
    this.locked = false,
    this.onRelink,
  });

  @override
  Widget build(BuildContext context) {
    final unregistered = device.status == DeviceStatus.unregistered;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          DeviceIcon(type: device.type, size: 44),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.type.label, style: AppText.w600(14)),
                Text(
                  device.type.subtitle,
                  style: AppText.w400(12, AppColors.grey4),
                ),
                if (device.macAddress != null)
                  Text(
                    device.macAddress!,
                    style: AppText.w400(11, AppColors.grey4),
                  ),
                const Gap(2),
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: device.status == DeviceStatus.connected
                          ? AppColors.darkGreen
                          : AppColors.grey3,
                    ),
                    const Gap(6),
                    Flexible(
                      child: Text(
                        device.status.label,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.w500(12, device.status.color),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(8),
          if (unregistered)
            FilledButton.icon(
              onPressed: locked ? null : onRegister,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: Icon(
                locked ? Icons.lock_rounded : Icons.add_link_rounded,
                size: 18,
              ),
              label: Text(locked ? 'Terkunci' : 'Daftarkan'),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Opsi',
              onSelected: (v) {
                switch (v) {
                  case 'relink':
                    onRelink?.call();
                  case 'change':
                    onRegister();
                  case 'remove':
                    onRemove();
                }
              },
              itemBuilder: (_) => [
                if (onRelink != null)
                  const PopupMenuItem(
                    value: 'relink',
                    child: Text('Sambung ulang'),
                  ),
                PopupMenuItem(
                  value: 'change',
                  enabled: !locked,
                  child: Text(locked ? 'Ganti alat (terkunci)' : 'Ganti alat'),
                ),
                PopupMenuItem(
                  value: 'remove',
                  enabled: !locked,
                  child: Text(
                    locked ? 'Hapus (terkunci)' : 'Hapus',
                    style: TextStyle(
                      color: locked ? AppColors.grey3 : AppColors.red,
                    ),
                  ),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_vert_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceRegistrationPicker extends StatefulWidget {
  final DeviceType type;
  final bool Function(String name) matchesType;

  const _DeviceRegistrationPicker({
    required this.type,
    required this.matchesType,
  });

  @override
  State<_DeviceRegistrationPicker> createState() =>
      _DeviceRegistrationPickerState();
}

class _DeviceRegistrationPickerState extends State<_DeviceRegistrationPicker> {
  static const _scanDuration = Duration(seconds: 10);

  final List<ScannedBleDevice> _found = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _scanning = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      if (!await ensureBleReady()) {
        if (mounted) {
          setState(() {
            _error =
                'Bluetooth belum siap. Nyalakan Bluetooth dan beri izin, '
                'lalu ketuk "Pindai lagi".';
            _scanning = false;
          });
        }
        return;
      }
      // Hanya satu scan BLE yang bisa berjalan — ambil alih radio dulu.
      await FlutterBluePlus.stopScan();
      if (!mounted) return;
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          for (final r in results) {
            final platformName = r.device.platformName;
            final name = platformName.isNotEmpty
                ? platformName
                : r.advertisementData.advName;
            if (name.isEmpty || !widget.matchesType(name)) continue;
            final d = ScannedBleDevice(
              remoteId: r.device.remoteId.str,
              name: name,
              rssi: r.rssi,
            );
            final idx = _found.indexWhere((e) => e.remoteId == d.remoteId);
            if (idx == -1) {
              _found.add(d);
            } else {
              _found[idx] = d;
            }
          }
        });
      });
      // Default flutter_blue_plus memeriksa layanan Lokasi (Android ≤ 11
      // butuh Lokasi menyala untuk scan) — sama dengan aplikasi asli.
      await FlutterBluePlus.startScan(timeout: _scanDuration);
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (mounted) {
        setState(
          () => _error = msg.contains('location')
              ? 'Nyalakan Lokasi (GPS) di perangkat — Android 11 ke bawah '
                    'membutuhkannya untuk memindai Bluetooth.'
              : 'Tidak bisa memindai: $e',
        );
      }
    }
    if (mounted) setState(() => _scanning = false);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    FlutterBluePlus.stopScan().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List.of(_found)..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pilih ${widget.type.label}',
                      style: AppText.w700(16),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const Gap(8),
                    Expanded(
                      child: Text(
                        'Nyalakan hanya unit yang ingin didaftarkan — matikan unit lain '
                        'dengan model sama di sekitar.',
                        style: AppText.w400(12, AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 260,
              child: sorted.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _error ??
                              (_scanning
                                  ? 'Memindai alat di sekitar…'
                                  : 'Tidak ada alat ditemukan.\nPastikan alat menyala dan dekat.'),
                          textAlign: TextAlign.center,
                          style: AppText.w400(13, AppColors.grey4),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 20),
                      itemBuilder: (_, i) {
                        final d = sorted[i];
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(d),
                          title: Text(d.name, style: AppText.w600(14)),
                          subtitle: Text(
                            d.remoteId,
                            style: AppText.w400(12, AppColors.grey4),
                          ),
                          trailing: Text(
                            '${d.rssi} dBm',
                            style: AppText.w400(12, AppColors.grey4),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _scanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton.icon(
                      onPressed: _startScan,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Pindai lagi'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
