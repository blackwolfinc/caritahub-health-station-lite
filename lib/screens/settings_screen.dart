import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../app/sound.dart';
import '../app/theme.dart';
import '../app/version.dart';
import '../ble/measurement_session.dart';
import '../data/app_settings.dart';
import '../data/device_registry_store.dart';
import '../data/record_store.dart';
import '../models/device_models.dart';
import '../models/health_record.dart';
import '../models/measurements.dart';
import '../printing/printer_service.dart';
import '../printing/receipt_content.dart';
import '../printing/receipt_renderer.dart';
import '../widgets/bluetooth_settings_dialog.dart';
import '../satusehat/satusehat_export.dart';
import '../widgets/common.dart';
import 'nfc_screen.dart';
import '../widgets/measurement_cards.dart' show DeviceIcon;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _location = TextEditingController(
    text: AppSettings.instance.locationName,
  );
  bool _busy = false;
  String? _printerStatus;

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  Future<void> _manageDevices() async {
    final reg = DeviceRegistryStore.instance;
    await showBluetoothSettingsDialog(
      context: context,
      devices: [
        for (final t in DeviceType.values)
          DeviceInfo(
            type: t,
            status: reg.of(t) == null
                ? DeviceStatus.unregistered
                : DeviceStatus.waiting,
            macAddress: reg.of(t)?.remoteId,
          ),
      ],
      matchesType: MeasurementSession.nameMatchesDeviceType,
      onRegister: (type, d) => reg.register(
        RegisteredDevice(type: type, remoteId: d.remoteId, name: d.name),
      ),
      onUnregister: reg.unregister,
    );
  }

  Future<void> _checkPrinter() async {
    setState(() => _busy = true);
    final r = await PrinterService.instance.check();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _printerStatus = r.message;
    });
  }

  Future<void> _testPrint() async {
    setState(() => _busy = true);
    final now = DateTime.now();
    final sample = HealthRecord(
      id: 'TES-CETAK',
      createdAt: now,
      profile: const PersonProfile(
        name: 'Contoh Cetak',
        gender: Gender.female,
        age: 67,
      ),
      measurements: const AllMeasurements(
        tensimeter: TensimeterData(systolic: 128, diastolic: 82, pulse: 76),
        pulseOximeter: PulseOximeterData(spo2: 97, heartRate: 75),
        thermometer: ThermometerData(temperature: 36.6),
        weightScale: WeightScaleData(weight: 58.4, bmi: 23.4),
        others: OthersMeasurementData(height: 158),
      ),
    );
    final settings = AppSettings.instance;
    final png = await ReceiptRenderer.renderPng(
      buildReceipt(sample, locationName: settings.locationName, printNumber: 1),
      paper: settings.paper,
    );
    final r = await PrinterService.instance.printReceipt(png);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _printerStatus = r.message;
    });
    showSnack(context, r.message, error: !r.ok);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          AppSettings.instance,
          DeviceRegistryStore.instance,
          RecordStore.instance,
        ]),
        builder: (context, _) {
          final s = AppSettings.instance;
          final reg = DeviceRegistryStore.instance;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MaxWidth(
              maxWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    title: 'Alat Bluetooth',
                    subtitle:
                        'Satu alat per jenis; tersambung otomatis saat menyala',
                    trailing: FilledButton.icon(
                      onPressed: _manageDevices,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      icon: const Icon(Icons.bluetooth_rounded, size: 18),
                      label: const Text('Kelola'),
                    ),
                    child: Column(
                      children: [
                        for (final t in DeviceType.values)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: DeviceIcon(type: t, size: 40),
                            title: Text(t.label, style: AppText.w600(14)),
                            subtitle: Text(
                              reg.of(t) == null
                                  ? 'Belum didaftarkan'
                                  : '${reg.of(t)!.name} · ${reg.of(t)!.remoteId}',
                              style: AppText.w400(12, AppColors.grey4),
                            ),
                            trailing: reg.locked && reg.of(t) != null
                                ? const Icon(
                                    Icons.lock_rounded,
                                    size: 18,
                                    color: AppColors.darkGreen,
                                  )
                                : null,
                          ),
                        const Divider(height: 16),
                        const DeviceLockTile(),
                        if (!reg.locked && reg.ignored.isNotEmpty)
                          Row(
                            children: [
                              const Gap(4),
                              Expanded(
                                child: Text(
                                  '${reg.ignored.length} alat pernah ditolak dan '
                                  'tidak ditawarkan lagi.',
                                  style: AppText.w400(12, AppColors.grey4),
                                ),
                              ),
                              TextButton(
                                key: const Key('clear_ignored'),
                                onPressed: reg.clearIgnored,
                                child: const Text('Tawarkan lagi'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const Gap(16),
                  SectionCard(
                    title: 'Printer iMin',
                    subtitle: 'Printer thermal bawaan perangkat iMin',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Lebar kertas',
                          style: AppText.w500(13, AppColors.grey1),
                        ),
                        const Gap(8),
                        SegmentedButton<PaperWidth>(
                          segments: const [
                            ButtonSegment(
                              value: PaperWidth.mm58,
                              label: Text('58 mm'),
                              tooltip: 'iMin Swift / M2 (genggam)',
                            ),
                            ButtonSegment(
                              value: PaperWidth.mm80,
                              label: Text('80 mm'),
                              tooltip: 'iMin D4 / Falcon / Crane (meja)',
                            ),
                          ],
                          selected: {s.paper},
                          onSelectionChanged: (v) => s.setPaper(v.first),
                        ),
                        const Gap(4),
                        Text(
                          'Genggam (Swift, M2) umumnya 58 mm; meja (D4, Falcon) 80 mm.',
                          style: AppText.w400(12, AppColors.grey4),
                        ),
                        const Gap(16),
                        TextField(
                          controller: _location,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nama lokasi / kegiatan (opsional)',
                            hintText: 'mis. Posyandu Lansia Melati',
                          ),
                          onChanged: s.setLocationName,
                        ),
                        const Gap(4),
                        Text(
                          'Dicetak di bawah judul catatan tes kesehatan.',
                          style: AppText.w400(12, AppColors.grey4),
                        ),
                        const Gap(8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: s.autoFinish,
                          onChanged: s.setAutoFinish,
                          title: Text(
                            'Simpan otomatis saat semua alat selesai',
                            style: AppText.w500(14),
                          ),
                          subtitle: Text(
                            'Jeda 3 detik untuk dibatalkan (15 detik bila masih '
                            'ada alat terdaftar yang belum tersambung). Alat '
                            'yang dihitung: yang tersambung saat pemeriksaan.',
                            style: AppText.w400(12, AppColors.grey4),
                          ),
                        ),
                        const Gap(8),
                        if (_printerStatus != null) ...[
                          Text(
                            'Status: $_printerStatus',
                            style: AppText.w500(13),
                          ),
                          const Gap(8),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _checkPrinter,
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('Cek printer'),
                              ),
                            ),
                            const Gap(12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _testPrint,
                                icon: const Icon(Icons.print_rounded),
                                label: const Text('Tes cetak'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Gap(16),
                  SectionCard(
                    key: const Key('sound_card'),
                    title: 'Suara',
                    subtitle:
                        'Nada lembut; volume mengikuti volume suara sistem perangkat',
                    trailing: OutlinedButton.icon(
                      key: const Key('test_sound'),
                      onPressed: s.sound ? () => Sound.play(Sfx.success) : null,
                      icon: const Icon(Icons.volume_up_rounded),
                      label: const Text('Coba'),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          key: const Key('sound_switch'),
                          contentPadding: EdgeInsets.zero,
                          value: s.sound,
                          onChanged: s.setSound,
                          title: Text('Efek suara', style: AppText.w500(14)),
                          subtitle: Text(
                            'Kartu terbaca, alat selesai mengukur, hasil '
                            'tersimpan, dan saat ada masalah.',
                            style: AppText.w400(12, AppColors.grey4),
                          ),
                        ),
                        SwitchListTile(
                          key: const Key('key_sound_switch'),
                          contentPadding: EdgeInsets.zero,
                          value: s.sound && s.keySound,
                          onChanged: s.sound ? s.setKeySound : null,
                          title: Text(
                            'Bunyi tombol keyboard',
                            style: AppText.w500(14),
                          ),
                          subtitle: Text(
                            'Ketukan pelan setiap huruf/angka ditekan.',
                            style: AppText.w400(12, AppColors.grey4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(16),
                  SectionCard(
                    title: 'NFC',
                    subtitle: 'Baca kartu untuk analisa (tidak menulis kartu)',
                    trailing: FilledButton.icon(
                      key: const Key('open_nfc'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NfcScreen()),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      icon: const Icon(Icons.contactless_rounded, size: 18),
                      label: const Text('Pembaca NFC'),
                    ),
                    child: Text(
                      'Tempel e-KTP atau kartu lain untuk melihat UID, jenis '
                      'chip, dan data yang bisa dibaca. Isi e-KTP (NIK, nama) '
                      'terenkripsi dan hanya bisa dibaca dengan izin Dukcapil.',
                      style: AppText.w400(13, AppColors.grey1),
                    ),
                  ),
                  const Gap(16),
                  const _SatusehatCard(),
                  const Gap(16),
                  SectionCard(
                    title: 'Data',
                    child: Text(
                      '${RecordStore.instance.records.length} hasil pemeriksaan tersimpan di '
                      'penyimpanan internal aplikasi. Tidak ada data yang dikirim ke internet. '
                      'Ekspor ke CSV atau format SATUSEHAT (FHIR) dari halaman Riwayat. '
                      'Menghapus aplikasi akan menghapus semua data.',
                      style: AppText.w400(13, AppColors.grey1),
                    ),
                  ),
                  const Gap(16),
                  Center(
                    child: Text(
                      'CaritaHub Health Station Lite · versi $appVersion',
                      style: AppText.w400(12, AppColors.grey4),
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
}

/// Pengaturan SATUSEHAT untuk ekspor FHIR (aplikasi tetap offline).
class _SatusehatCard extends StatefulWidget {
  const _SatusehatCard();

  @override
  State<_SatusehatCard> createState() => _SatusehatCardState();
}

class _SatusehatCardState extends State<_SatusehatCard> {
  final s = AppSettings.instance;
  late final _org = TextEditingController(text: s.ssOrgId);
  late final _locId = TextEditingController(text: s.ssLocationId);
  late final _locName = TextEditingController(text: s.ssLocationName);
  late final _pracId = TextEditingController(text: s.ssPractitionerId);
  late final _pracName = TextEditingController(text: s.ssPractitionerName);

  @override
  void dispose() {
    for (final c in [_org, _locId, _locName, _pracId, _pracName]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint,
    Key key,
    void Function(String) onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: key,
      controller: c,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final missing = SatusehatConfig.fromSettings().missing;
    return SectionCard(
      key: const Key('satusehat_card'),
      title: 'SATUSEHAT',
      subtitle:
          'Untuk ekspor format FHIR R4. Aplikasi tetap offline; file '
          'dikirim lewat sistem yang terhubung SATUSEHAT.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            _org,
            'ID Organisasi (IHS)',
            'mis. 10000004',
            const Key('ss_org'),
            (v) => s.setSatusehat(orgId: v),
          ),
          _field(
            _locId,
            'ID Lokasi SATUSEHAT',
            'UUID Location tempat pemeriksaan',
            const Key('ss_loc_id'),
            (v) => s.setSatusehat(locationId: v),
          ),
          _field(
            _locName,
            'Nama lokasi (opsional)',
            'mis. Posyandu Lansia Melati',
            const Key('ss_loc_name'),
            (v) => s.setSatusehat(locationName: v),
          ),
          _field(
            _pracId,
            'ID Nakes (IHS Practitioner)',
            'mis. N10000001',
            const Key('ss_prac_id'),
            (v) => s.setSatusehat(practitionerId: v),
          ),
          _field(
            _pracName,
            'Nama nakes (opsional)',
            'mis. Ns. Dewi',
            const Key('ss_prac_name'),
            (v) => s.setSatusehat(practitionerName: v),
          ),
          Row(
            children: [
              Icon(
                missing.isEmpty
                    ? Icons.verified_outlined
                    : Icons.info_outline_rounded,
                size: 18,
                color: missing.isEmpty
                    ? AppColors.darkGreen
                    : AppColors.orangeAction,
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  missing.isEmpty
                      ? 'Siap ekspor. Pasien dikenali dari NIK.'
                      : 'Belum lengkap: ${missing.join(', ')}',
                  style: AppText.w500(
                    13,
                    missing.isEmpty
                        ? AppColors.darkGreen
                        : AppColors.orangeAction,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
