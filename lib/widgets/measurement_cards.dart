// Kartu hasil ukur — di-port dari Staff Ops (branch health-device):
// widgets/{measurement_card_base, tensimeter_*, pulse_oximeter_*,
// thermometer_*, weight_scale_*, grip_strength_*, others_*}.dart
// Teks diterjemahkan ke Bahasa Indonesia; status koneksi ditaruh di kepala
// kartu supaya tata letak bisa satu kolom di iMin handheld.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';

import '../app/theme.dart';
import '../utils/plausibility.dart';
import '../models/device_models.dart';
import '../models/measurements.dart';
import '../printing/receipt_content.dart' show fmt0, fmt1;
import '../utils/health_ranges.dart';

// ─── Kerangka kartu ──────────────────────────────────────────────────────────

class DeviceIcon extends StatelessWidget {
  final DeviceType type;
  final double size;
  const DeviceIcon({super.key, required this.type, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: type.iconBgColor,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      padding: EdgeInsets.all(size * 0.24),
      child: SvgPicture.asset(
        type.iconAsset,
        colorFilter: ColorFilter.mode(type.iconColor, BlendMode.srcIn),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final DeviceStatus status;
  final bool busy;
  final VoidCallback? onTap;
  const StatusChip({
    super.key,
    required this.status,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unregistered = status == DeviceStatus.unregistered;
    final label = unregistered ? 'Daftarkan alat' : status.label;
    final color = unregistered ? AppColors.primary : status.color;
    return Material(
      color: unregistered
          ? AppColors.primarySoft
          : color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy || status == DeviceStatus.connecting)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: color,
                  ),
                )
              else if (unregistered)
                Icon(Icons.add_link_rounded, size: 14, color: color)
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              const Gap(6),
              Text(label, style: AppText.w500(12, color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kerangka semua kartu hasil ukur.
class MeasurementCardBase extends StatelessWidget {
  final DeviceType? type;
  final String? customTitle;
  final String? customSubtitle;
  final Widget? customIcon;
  final DeviceInfo? device;
  final bool busy;
  final bool isActive;
  final bool isEditing;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onStatusTap;
  final List<Widget> children;

  const MeasurementCardBase({
    super.key,
    this.type,
    this.customTitle,
    this.customSubtitle,
    this.customIcon,
    this.device,
    this.busy = false,
    this.isActive = false,
    this.isEditing = false,
    this.onTap,
    this.onEdit,
    this.onStatusTap,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    Widget? chip() => device == null
        ? null
        : StatusChip(status: device!.status, busy: busy, onTap: onStatusTap);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              // Kartu sempit (iMin genggam): chip status turun ke bawah judul.
              child: LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 460;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (type != null) DeviceIcon(type: type!, size: 38),
                      if (customIcon != null) customIcon!,
                      const Gap(10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customTitle ?? type?.label ?? '',
                              style: AppText.w600(15),
                            ),
                            Text(
                              customSubtitle ?? type?.subtitle ?? '',
                              style: AppText.w400(12, AppColors.grey4),
                            ),
                            if (narrow && device != null) ...[
                              const Gap(6),
                              chip()!,
                            ],
                          ],
                        ),
                      ),
                      if (!narrow && device != null) ...[chip()!, const Gap(8)],
                      if (onEdit != null)
                        _EditToggle(
                          isEditing: isEditing,
                          onTap: onEdit!,
                          keyName: type?.name ?? customTitle ?? 'card',
                        ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditToggle extends StatelessWidget {
  final bool isEditing;
  final VoidCallback onTap;
  final String keyName;
  const _EditToggle({
    required this.isEditing,
    required this.onTap,
    required this.keyName,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isEditing ? 'Selesai isi manual' : 'Isi manual',
      child: Material(
        color: isEditing ? AppColors.primarySoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isEditing ? AppColors.primary : AppColors.greyBorder,
          ),
        ),
        child: InkWell(
          key: Key('card_edit_$keyName'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              isEditing ? Icons.check_rounded : Icons.edit_outlined,
              size: 18,
              color: isEditing ? AppColors.primary : AppColors.grey4,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Isian nilai ─────────────────────────────────────────────────────────────

/// Batas wajar per isian manual (label kartu → rentang).
const Map<String, (double, double)> manualRanges = {
  'Sistolik': Plausible.systolic,
  'Diastolik': Plausible.diastolic,
  'Denyut nadi': Plausible.heartRate,
  'SpO2': Plausible.spo2,
  'Suhu tubuh': Plausible.temperature,
  'Berat badan': Plausible.weight,
  'IMT (BMI)': Plausible.bmi,
  'Tinggi badan': Plausible.height,
  'Lingkar betis': Plausible.calf,
  'Lemak tubuh': Plausible.bodyFat,
  'Air tubuh': Plausible.bodyWater,
  'Otot': Plausible.muscle,
  'Mineral tulang': Plausible.bone,
  'Protein': Plausible.protein,
  'Lemak viseral': Plausible.visceral,
  'BMR': Plausible.bmr,
  'Skor tubuh': (0.0, 100.0),
};

/// Pesan bila isian angka di luar batas wajar (mis. "365" untuk 36,5).
String? manualRangeError(String label, String text) {
  final r = manualRanges[label];
  final t = text.trim();
  if (r == null || t.isEmpty) return null;
  final v = parseNum(t);
  if (v == null) return 'Angka tidak terbaca';
  if (!Plausible.ok(v, r)) {
    return 'Di luar batas wajar ${Plausible.rangeText(r)}';
  }
  return null;
}

Future<void> showFieldEditDialog({
  required BuildContext context,
  required String label,
  required String unit,
  required String? currentValue,
  required ValueChanged<String> onSaved,
  bool isText = false,
}) async {
  final ctrl = TextEditingController(
    text: (currentValue == null || currentValue == '—') ? '' : currentValue,
  );
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void submit() {
          final err = isText ? null : manualRangeError(label, ctrl.text);
          if (err != null) {
            setLocal(() => error = err);
            return;
          }
          Navigator.of(ctx).pop(ctrl.text.trim());
        }

        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(label, style: AppText.w600(16)),
          content: TextField(
            key: const Key('field_dialog_input'),
            controller: ctrl,
            autofocus: true,
            keyboardType: isText
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: isText
                ? const []
                : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              suffixText: unit.isNotEmpty ? unit : null,
              hintText: 'Kosongkan untuk menghapus',
              errorText: error,
            ),
            style: AppText.w600(18),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              key: const Key('field_dialog_save'),
              onPressed: submit,
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    ),
  );
  if (result != null) onSaved(result);
}

/// Angka dari isian petugas; koma diterima sebagai desimal.
double? parseNum(String v) => double.tryParse(v.replaceAll(',', '.').trim());
int? parseInt(String v) => parseNum(v)?.round();

class MeasurementField extends StatelessWidget {
  final String label;
  final String? rangeHint;
  final String? value;
  final String unit;
  final bool flagged;
  final ValueChanged<String>? onEdit;
  final bool isText;

  const MeasurementField({
    super.key,
    required this.label,
    this.rangeHint,
    this.value,
    required this.unit,
    this.flagged = false,
    this.onEdit,
    this.isText = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty && value != '—';
    final editable = onEdit != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppText.w400(13, AppColors.grey1),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (rangeHint != null)
              Text(rangeHint!, style: AppText.w400(11, AppColors.grey4)),
          ],
        ),
        const Gap(6),
        Material(
          color: editable ? AppColors.primarySoft : AppColors.lightGrey,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: Key('measurement_field_$label'),
            borderRadius: BorderRadius.circular(10),
            onTap: !editable
                ? null
                : () => showFieldEditDialog(
                    context: context,
                    label: label,
                    unit: unit,
                    currentValue: hasValue ? value : null,
                    isText: isText,
                    onSaved: onEdit!,
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasValue ? value! : '—',
                      style: AppText.w600(
                        20,
                        !hasValue
                            ? AppColors.grey3
                            : flagged
                            ? AppColors.red
                            : AppColors.charcoal,
                      ),
                    ),
                  ),
                  if (unit.isNotEmpty)
                    Text(unit, style: AppText.w400(13, AppColors.grey4)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pair extends StatelessWidget {
  final Widget a;
  final Widget b;
  const _Pair(this.a, this.b);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const Gap(12),
      Expanded(child: b),
    ],
  );
}

/// Info status alat + aksi kartu (dipasang oleh layar pengukuran).
class CardDeviceProps {
  final DeviceInfo? device;
  final bool busy;
  final bool isActive;
  final bool isEditing;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onStatusTap;

  const CardDeviceProps({
    this.device,
    this.busy = false,
    this.isActive = false,
    this.isEditing = false,
    this.onTap,
    this.onEdit,
    this.onStatusTap,
  });
}

// ─── Tensimeter ──────────────────────────────────────────────────────────────

class TensimeterCard extends StatelessWidget {
  final TensimeterData data;
  final CardDeviceProps props;
  final ValueChanged<TensimeterData>? onChanged;

  const TensimeterCard({
    super.key,
    required this.data,
    required this.props,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final edit = props.isEditing && onChanged != null;
    final bpOk = HealthRanges.bloodPressureNormal(
      data.systolic,
      data.diastolic,
    );
    return MeasurementCardBase(
      type: DeviceType.tensimeter,
      device: props.device,
      busy: props.busy,
      isActive: props.isActive,
      isEditing: props.isEditing,
      onTap: props.onTap,
      onEdit: props.onEdit,
      onStatusTap: props.onStatusTap,
      children: [
        _Pair(
          MeasurementField(
            label: 'Sistolik',
            rangeHint: HealthRanges.systolicRange,
            value: data.systolic == null ? null : fmt0(data.systolic),
            unit: 'mmHg',
            flagged: bpOk == false,
            onEdit: edit
                ? (v) => onChanged!(data.copyWith(systolic: parseInt(v)))
                : null,
          ),
          MeasurementField(
            label: 'Diastolik',
            rangeHint: HealthRanges.diastolicRange,
            value: data.diastolic == null ? null : fmt0(data.diastolic),
            unit: 'mmHg',
            flagged: bpOk == false,
            onEdit: edit
                ? (v) => onChanged!(data.copyWith(diastolic: parseInt(v)))
                : null,
          ),
        ),
        const Gap(12),
        MeasurementField(
          label: 'Denyut nadi',
          rangeHint: HealthRanges.heartRateRange,
          value: data.pulse == null ? null : fmt0(data.pulse),
          unit: 'bpm',
          flagged: HealthRanges.heartRateNormal(data.pulse) == false,
          onEdit: edit
              ? (v) => onChanged!(data.copyWith(pulse: parseInt(v)))
              : null,
        ),
      ],
    );
  }
}

// ─── Oksimeter ───────────────────────────────────────────────────────────────

class PulseOximeterCard extends StatelessWidget {
  final PulseOximeterData data;
  final CardDeviceProps props;
  final ValueChanged<PulseOximeterData>? onChanged;

  const PulseOximeterCard({
    super.key,
    required this.data,
    required this.props,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final edit = props.isEditing && onChanged != null;
    return MeasurementCardBase(
      type: DeviceType.pulseOximeter,
      device: props.device,
      busy: props.busy,
      isActive: props.isActive,
      isEditing: props.isEditing,
      onTap: props.onTap,
      onEdit: props.onEdit,
      onStatusTap: props.onStatusTap,
      children: [
        _Pair(
          MeasurementField(
            label: 'SpO2',
            rangeHint: HealthRanges.oxygenRange,
            value: data.spo2 == null ? null : fmt0(data.spo2),
            unit: '%',
            flagged: HealthRanges.oxygenNormal(data.spo2) == false,
            onEdit: edit
                ? (v) => onChanged!(data.copyWith(spo2: parseNum(v)))
                : null,
          ),
          MeasurementField(
            label: 'Denyut nadi',
            rangeHint: HealthRanges.heartRateRange,
            value: data.heartRate == null ? null : fmt0(data.heartRate),
            unit: 'bpm',
            flagged: HealthRanges.heartRateNormal(data.heartRate) == false,
            onEdit: edit
                ? (v) => onChanged!(data.copyWith(heartRate: parseInt(v)))
                : null,
          ),
        ),
      ],
    );
  }
}

// ─── Termometer ──────────────────────────────────────────────────────────────

class ThermometerCard extends StatelessWidget {
  final ThermometerData data;
  final CardDeviceProps props;
  final ValueChanged<ThermometerData>? onChanged;

  const ThermometerCard({
    super.key,
    required this.data,
    required this.props,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final edit = props.isEditing && onChanged != null;
    return MeasurementCardBase(
      type: DeviceType.thermometer,
      device: props.device,
      busy: props.busy,
      isActive: props.isActive,
      isEditing: props.isEditing,
      onTap: props.onTap,
      onEdit: props.onEdit,
      onStatusTap: props.onStatusTap,
      children: [
        MeasurementField(
          label: 'Suhu tubuh',
          rangeHint: HealthRanges.temperatureRange,
          value: data.temperature == null ? null : fmt1(data.temperature),
          unit: '°C',
          flagged: HealthRanges.temperatureNormal(data.temperature) == false,
          onEdit: edit
              ? (v) => onChanged!(data.copyWith(temperature: parseNum(v)))
              : null,
        ),
      ],
    );
  }
}

// ─── Timbangan ───────────────────────────────────────────────────────────────

class WeightScaleCard extends StatefulWidget {
  final WeightScaleData data;
  final CardDeviceProps props;
  final bool heightMissing;
  final ValueChanged<WeightScaleData>? onChanged;

  const WeightScaleCard({
    super.key,
    required this.data,
    required this.props,
    this.heightMissing = false,
    this.onChanged,
  });

  @override
  State<WeightScaleCard> createState() => _WeightScaleCardState();
}

class _WeightScaleCardState extends State<WeightScaleCard> {
  bool _showExtra = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final edit = widget.props.isEditing && widget.onChanged != null;
    void up(WeightScaleData v) => widget.onChanged?.call(v);
    String? s1(double? v) => v == null ? null : fmt1(v);

    final extra = <_FieldDef>[
      _FieldDef(
        'Lemak tubuh',
        s1(d.bodyFatPercent),
        '%',
        (v) => up(d.copyWith(bodyFatPercent: parseNum(v))),
      ),
      _FieldDef(
        'Air tubuh',
        s1(d.bodyWaterPercent),
        '%',
        (v) => up(d.copyWith(bodyWaterPercent: parseNum(v))),
      ),
      _FieldDef(
        'Otot',
        s1(d.musclePercent),
        '%',
        (v) => up(d.copyWith(musclePercent: parseNum(v))),
      ),
      _FieldDef(
        'Mineral tulang',
        s1(d.boneMineralPercent),
        '%',
        (v) => up(d.copyWith(boneMineralPercent: parseNum(v))),
      ),
      _FieldDef(
        'Protein',
        s1(d.proteinPercent),
        '%',
        (v) => up(d.copyWith(proteinPercent: parseNum(v))),
      ),
      _FieldDef(
        'Lemak viseral',
        d.visceralFatRate == null ? null : fmt0(d.visceralFatRate),
        '',
        (v) => up(d.copyWith(visceralFatRate: parseNum(v))),
      ),
      _FieldDef(
        'BMR',
        d.bmr == null ? null : fmt0(d.bmr),
        'kkal',
        (v) => up(d.copyWith(bmr: parseInt(v))),
      ),
      // "Tipe tubuh" timbangan tidak ditampilkan: penilaian non-Kemenkes
      // yang bisa bertentangan dengan IMT.
    ];

    return MeasurementCardBase(
      type: DeviceType.weightScale,
      device: widget.props.device,
      busy: widget.props.busy,
      isActive: widget.props.isActive,
      isEditing: widget.props.isEditing,
      onTap: widget.props.onTap,
      onEdit: widget.props.onEdit,
      onStatusTap: widget.props.onStatusTap,
      children: [
        if (widget.heightMissing) ...[
          const _InlineNote(
            'Tinggi badan belum diisi — IMT & komposisi tubuh memakai 160 cm. '
            'Isi di kartu "Lainnya" agar akurat.',
          ),
          const Gap(12),
        ],
        _Pair(
          MeasurementField(
            label: 'Berat badan',
            value: s1(d.weight),
            unit: 'kg',
            onEdit: edit ? (v) => up(d.copyWith(weight: parseNum(v))) : null,
          ),
          MeasurementField(
            label: 'IMT (BMI)',
            value: s1(d.bmi),
            unit: 'kg/m²',
            onEdit: edit ? (v) => up(d.copyWith(bmi: parseNum(v))) : null,
          ),
        ),
        const Gap(12),
        MeasurementField(
          label: 'Skor tubuh',
          value: d.bodyScore == null ? null : fmt0(d.bodyScore),
          unit: '',
          onEdit: edit ? (v) => up(d.copyWith(bodyScore: parseNum(v))) : null,
        ),
        const Gap(8),
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _showExtra = !_showExtra),
            icon: Icon(
              _showExtra
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
            label: Text(
              _showExtra
                  ? 'Sembunyikan komposisi tubuh'
                  : 'Lihat komposisi tubuh (${extra.length})',
            ),
          ),
        ),
        if (_showExtra) ...[
          const Gap(8),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 420 ? 3 : 2;
              final w = (c.maxWidth - (cols - 1) * 10) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  for (final f in extra)
                    SizedBox(
                      width: w,
                      child: MeasurementField(
                        label: f.label,
                        value: f.value,
                        unit: f.unit,
                        onEdit: edit ? f.onEdit : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _FieldDef {
  final String label;
  final String? value;
  final String unit;
  final ValueChanged<String> onEdit;
  const _FieldDef(this.label, this.value, this.unit, this.onEdit);
}

class _InlineNote extends StatelessWidget {
  final String text;
  const _InlineNote(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.orangeActionBg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppColors.orangeAction,
        ),
        const Gap(8),
        Expanded(
          child: Text(text, style: AppText.w400(12, AppColors.orangeAction)),
        ),
      ],
    ),
  );
}

// ─── Kekuatan genggam ────────────────────────────────────────────────────────

class GripStrengthCard extends StatelessWidget {
  final GripStrengthData data;
  final GripSide activeSide;
  final CardDeviceProps props;
  final ValueChanged<GripSide>? onSideChanged;
  final VoidCallback? onStartSession;
  final VoidCallback? onBulkEdit;

  const GripStrengthCard({
    super.key,
    required this.data,
    required this.activeSide,
    required this.props,
    this.onSideChanged,
    this.onStartSession,
    this.onBulkEdit,
  });

  @override
  Widget build(BuildContext context) {
    return MeasurementCardBase(
      type: DeviceType.gripStrength,
      device: props.device,
      busy: props.busy,
      isActive: props.isActive,
      isEditing: false,
      onTap: props.onTap,
      onEdit: onBulkEdit,
      onStatusTap: props.onStatusTap,
      children: [
        if (onStartSession != null) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStartSession,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Mulai ukur genggam'),
            ),
          ),
          const Gap(12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _GripSidePanel(
                label: 'Tangan kiri',
                readings: [data.gripLeft1, data.gripLeft2, data.gripLeft3],
                best: data.gripLeft,
                isActive: activeSide == GripSide.left,
                onTap: () => onSideChanged?.call(GripSide.left),
              ),
            ),
            const Gap(10),
            Expanded(
              child: _GripSidePanel(
                label: 'Tangan kanan',
                readings: [data.gripRight1, data.gripRight2, data.gripRight3],
                best: data.gripRight,
                isActive: activeSide == GripSide.right,
                onTap: () => onSideChanged?.call(GripSide.right),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GripSidePanel extends StatelessWidget {
  final String label;
  final List<double?> readings;
  final double? best;
  final bool isActive;
  final VoidCallback onTap;

  const _GripSidePanel({
    required this.label,
    required this.readings,
    required this.best,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.blueDenim.withValues(alpha: 0.08)
              : AppColors.lightGrey,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? AppColors.blueDenim : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: AppText.w500(13, AppColors.grey1)),
                ),
                if (isActive)
                  const Icon(Icons.circle, size: 8, color: AppColors.blueDenim),
              ],
            ),
            const Gap(6),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${i + 1}.', style: AppText.w400(12, AppColors.grey4)),
                    Text(
                      readings[i] == null ? '—' : '${fmt1(readings[i])} kg',
                      style: readings[i] == null
                          ? AppText.w400(13, AppColors.grey4)
                          : AppText.w500(13, AppColors.navyBlue),
                    ),
                  ],
                ),
              ),
            const Divider(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Terbaik', style: AppText.w400(12, AppColors.grey1)),
                Text(
                  best == null ? '—' : '${fmt1(best)} kg',
                  style: AppText.w700(15, AppColors.navyBlue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Lainnya ─────────────────────────────────────────────────────────────────

class OthersCard extends StatelessWidget {
  final OthersMeasurementData data;
  final bool isEditing;
  final bool showHeightWarning;
  final VoidCallback? onEdit;
  final ValueChanged<OthersMeasurementData>? onChanged;

  const OthersCard({
    super.key,
    required this.data,
    this.isEditing = false,
    this.showHeightWarning = false,
    this.onEdit,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final edit = isEditing && onChanged != null;
    return MeasurementCardBase(
      customTitle: 'Lainnya',
      customSubtitle: 'Diisi manual',
      customIcon: Container(
        width: 38,
        height: 38,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEFF9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SvgPicture.asset(
          'assets/icons/ic_ruler.svg',
          colorFilter: const ColorFilter.mode(
            Color(0xFF5E6AD2),
            BlendMode.srcIn,
          ),
        ),
      ),
      isEditing: isEditing,
      onEdit: onEdit,
      children: [
        if (showHeightWarning) ...[
          const _InlineNote(
            'Isi tinggi badan agar IMT & komposisi tubuh akurat.',
          ),
          const Gap(12),
        ],
        _Pair(
          MeasurementField(
            label: 'Tinggi badan',
            value: data.height == null ? null : fmt1(data.height),
            unit: 'cm',
            onEdit: edit
                ? (v) => onChanged!(data.copyWith(height: parseNum(v)))
                : null,
          ),
          MeasurementField(
            label: 'Lingkar betis',
            value: data.calfCircumference == null
                ? null
                : fmt1(data.calfCircumference),
            unit: 'cm',
            onEdit: edit
                ? (v) =>
                      onChanged!(data.copyWith(calfCircumference: parseNum(v)))
                : null,
          ),
        ),
      ],
    );
  }
}
