// Port dari Staff Ops (branch health-device):
//   widgets/grip_session_dialog.dart, widgets/grip_strength_edit_dialog.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:squegg_core/squegg_core.dart';

import '../app/sound.dart';
import '../app/theme.dart';
import '../models/measurements.dart';
import '../printing/receipt_content.dart' show fmt1;
import '../utils/plausibility.dart';
import 'measurement_cards.dart' show parseNum;

/// Enam percobaan berurutan: kiri 1-3 lalu kanan 1-3.
enum _GripStep {
  left1,
  left2,
  left3,
  right1,
  right2,
  right3;

  GripSide get side => index < 3 ? GripSide.left : GripSide.right;
  int get attemptNumber => (index % 3) + 1;
}

/// Memandu petugas melalui 6 percobaan genggam, langsung membaca data live
/// SqueggCore sehingga puncak tenaga terlihat saat meremas.
///
/// [onChanged] dipanggil setiap percobaan tersimpan, jadi menutup dialog di
/// tengah jalan tidak menghilangkan data. Pemanggil wajib mematikan auto-fill
/// Squegg miliknya selama dialog terbuka.
Future<void> showGripSessionDialog({
  required BuildContext context,
  required GripStrengthData data,
  required ValueChanged<GripStrengthData> onChanged,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _GripSessionDialog(data: data, onChanged: onChanged),
  );
}

class _GripSessionDialog extends StatefulWidget {
  final GripStrengthData data;
  final ValueChanged<GripStrengthData> onChanged;
  const _GripSessionDialog({required this.data, required this.onChanged});

  @override
  State<_GripSessionDialog> createState() => _GripSessionDialogState();
}

class _GripSessionDialogState extends State<_GripSessionDialog> {
  static const _steps = _GripStep.values;
  static const double _gaugeMaxKg = 60.0;

  final SqueggCore _squegg = SqueggCore();
  StreamSubscription<SqueggData>? _dataSub;
  StreamSubscription<SqueggConnectionState>? _connectionSub;

  late GripStrengthData _data = widget.data;
  late int _stepIndex = _findStartIndex(_data);
  double _liveStrength = 0.0;
  bool _isSqueezing = false;
  bool _wasSqueezing = false;
  double _sessionMax = 0.0;
  late bool _isConnected = _squegg.isConnected;

  _GripStep get _currentStep => _steps[_stepIndex];

  @override
  void initState() {
    super.initState();
    _dataSub = _squegg.dataStream.listen(_onData);
    _connectionSub = _squegg.connectionStream.listen((state) {
      if (!mounted) return;
      setState(() => _isConnected = state == SqueggConnectionState.connected);
    });
  }

  static int _findStartIndex(GripStrengthData data) {
    for (var i = 0; i < _steps.length; i++) {
      if (_valueFor(data, _steps[i]) == null) return i;
    }
    return 0;
  }

  void _onData(SqueggData packet) {
    if (!mounted) return;
    setState(() {
      _liveStrength = packet.strength;
      _isSqueezing = packet.isSqueezing;
      if (packet.isSqueezing) {
        _sessionMax = _sessionMax > packet.strength
            ? _sessionMax
            : packet.strength;
        _wasSqueezing = true;
      } else if (_wasSqueezing) {
        _commit(_sessionMax);
        _sessionMax = 0.0;
        _wasSqueezing = false;
      }
    });
  }

  void _commit(double value) {
    _data = _applyValue(_data, _currentStep, value);
    widget.onChanged(_data);
    HapticFeedback.mediumImpact();
    Sound.play(Sfx.done);
    if (_stepIndex < _steps.length - 1) _stepIndex++;
  }

  void _skip() {
    if (_stepIndex < _steps.length - 1) setState(() => _stepIndex++);
  }

  void _retry() {
    if (_stepIndex == 0) return;
    setState(() {
      _stepIndex--;
      _data = _applyValue(_data, _currentStep, null);
    });
    widget.onChanged(_data);
  }

  static GripStrengthData _applyValue(
    GripStrengthData d,
    _GripStep step,
    double? v,
  ) => switch (step) {
    _GripStep.left1 => d.copyWith(gripLeft1: v),
    _GripStep.left2 => d.copyWith(gripLeft2: v),
    _GripStep.left3 => d.copyWith(gripLeft3: v),
    _GripStep.right1 => d.copyWith(gripRight1: v),
    _GripStep.right2 => d.copyWith(gripRight2: v),
    _GripStep.right3 => d.copyWith(gripRight3: v),
  };

  static double? _valueFor(GripStrengthData d, _GripStep step) =>
      switch (step) {
        _GripStep.left1 => d.gripLeft1,
        _GripStep.left2 => d.gripLeft2,
        _GripStep.left3 => d.gripLeft3,
        _GripStep.right1 => d.gripRight1,
        _GripStep.right2 => d.gripRight2,
        _GripStep.right3 => d.gripRight3,
      };

  @override
  void dispose() {
    _dataSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _currentStep;
    final isLast = _stepIndex == _steps.length - 1;
    final sideLabel = step.side == GripSide.left
        ? 'Tangan kiri'
        : 'Tangan kanan';
    final sideValues = step.side == GripSide.left
        ? [_data.gripLeft1, _data.gripLeft2, _data.gripLeft3]
        : [_data.gripRight1, _data.gripRight2, _data.gripRight3];
    final shown = _isSqueezing ? _liveStrength : _sessionMax;

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ukur kekuatan genggam',
                      style: AppText.w700(16),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              _StepDots(currentIndex: _stepIndex),
              const Gap(18),
              if (!_isConnected) ...[
                const Icon(
                  Icons.bluetooth_disabled_rounded,
                  size: 40,
                  color: AppColors.grey3,
                ),
                const Gap(8),
                Text(
                  'Alat genggam belum tersambung',
                  style: AppText.w400(14, AppColors.grey4),
                ),
              ] else ...[
                Text(
                  '$sideLabel · percobaan ${step.attemptNumber} dari 3',
                  style: AppText.w600(14),
                ),
                const Gap(10),
                Text(
                  '${fmt1(shown)} kg',
                  style: AppText.w700(44, AppColors.navyBlue),
                ),
                const Gap(10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (_liveStrength / _gaugeMaxKg).clamp(0.0, 1.0),
                    minHeight: 16,
                    backgroundColor: AppColors.lightGrey,
                    color: AppColors.darkGreen,
                  ),
                ),
                const Gap(14),
                Text(
                  'Remas sekuat mungkin, lalu lepaskan',
                  textAlign: TextAlign.center,
                  style: AppText.w400(13, AppColors.grey4),
                ),
              ],
              const Gap(16),
              Wrap(
                spacing: 14,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Text(
                      '${i + 1}) ${sideValues[i] == null ? '—' : fmt1(sideValues[i])}',
                      style: AppText.w400(12, AppColors.grey4),
                    ),
                ],
              ),
              const Gap(18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _stepIndex > 0 ? _retry : null,
                      child: const Text('Ulangi'),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isLast ? null : _skip,
                      child: const Text('Lewati'),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Selesai'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int currentIndex;
  const _StepDots({required this.currentIndex});

  Widget _dot(int i) => Container(
    width: 8,
    height: 8,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: i <= currentIndex ? AppColors.primary : AppColors.greyBorder,
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < 3; i++) _dot(i),
      const Gap(10),
      for (var i = 3; i < 6; i++) _dot(i),
    ],
  );
}

// ─── Edit manual 6 percobaan ─────────────────────────────────────────────────

Future<void> showGripStrengthEditDialog({
  required BuildContext context,
  required GripStrengthData data,
  required ValueChanged<GripStrengthData> onSaved,
}) {
  return showDialog(
    context: context,
    builder: (_) => _GripStrengthEditDialog(data: data, onSaved: onSaved),
  );
}

class _GripStrengthEditDialog extends StatefulWidget {
  final GripStrengthData data;
  final ValueChanged<GripStrengthData> onSaved;
  const _GripStrengthEditDialog({required this.data, required this.onSaved});

  @override
  State<_GripStrengthEditDialog> createState() =>
      _GripStrengthEditDialogState();
}

class _GripStrengthEditDialogState extends State<_GripStrengthEditDialog> {
  late final List<TextEditingController> _left = [
    for (final v in [
      widget.data.gripLeft1,
      widget.data.gripLeft2,
      widget.data.gripLeft3,
    ])
      TextEditingController(text: v == null ? '' : fmt1(v)),
  ];
  late final List<TextEditingController> _right = [
    for (final v in [
      widget.data.gripRight1,
      widget.data.gripRight2,
      widget.data.gripRight3,
    ])
      TextEditingController(text: v == null ? '' : fmt1(v)),
  ];

  @override
  void initState() {
    super.initState();
    for (final c in [..._left, ..._right]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [..._left, ..._right]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _best(List<TextEditingController> cs) {
    final v = cs.map((c) => parseNum(c.text)).whereType<double>();
    return v.isEmpty ? null : v.reduce((a, b) => a > b ? a : b);
  }

  void _save() {
    // Nilai genggam di luar 0,5–100 kg hampir pasti salah ketik.
    final bad = [..._left, ..._right]
        .map((c) => c.text.trim())
        .where(
          (t) => t.isNotEmpty && !Plausible.ok(parseNum(t), Plausible.grip),
        );
    if (bad.isNotEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Nilai genggam ${bad.first} di luar batas wajar '
            '${Plausible.rangeText(Plausible.grip)} kg',
          ),
        ),
      );
      return;
    }
    widget.onSaved(
      widget.data.copyWith(
        gripLeft1: parseNum(_left[0].text),
        gripLeft2: parseNum(_left[1].text),
        gripLeft3: parseNum(_left[2].text),
        gripRight1: parseNum(_right[0].text),
        gripRight2: parseNum(_right[1].text),
        gripRight3: parseNum(_right[2].text),
      ),
    );
    Navigator.of(context).pop();
  }

  Widget _column(String label, List<TextEditingController> cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppText.w600(13)),
      const Gap(8),
      for (var i = 0; i < 3; i++) ...[
        TextField(
          controller: cs[i],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            isDense: true,
            prefixText: '${i + 1}.  ',
            suffixText: 'kg',
          ),
          style: AppText.w500(15),
        ),
        if (i < 2) const Gap(8),
      ],
      const Gap(10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Terbaik', style: AppText.w400(12, AppColors.grey4)),
          Text(
            _best(cs) == null ? '—' : '${fmt1(_best(cs))} kg',
            style: AppText.w600(13, AppColors.navyBlue),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Isi kekuatan genggam', style: AppText.w700(16)),
              const Gap(16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _column('Tangan kiri', _left)),
                  const Gap(16),
                  Expanded(child: _column('Tangan kanan', _right)),
                ],
              ),
              const Gap(20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  const Gap(8),
                  FilledButton(onPressed: _save, child: const Text('Simpan')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
