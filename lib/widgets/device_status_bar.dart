import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/device_registry_store.dart';
import '../models/device_models.dart';
import 'measurement_cards.dart' show DeviceIcon;

/// Deretan ikon alat di bilah atas beranda: berwarna + centang hijau bila
/// alat sudah TERDAFTAR di perangkat ini (bukan berarti sedang tersambung),
/// redup + tanda silang bila belum. Ketuk → kelola alat.
class DeviceStatusBar extends StatelessWidget {
  final VoidCallback onManage;
  final double iconSize;

  const DeviceStatusBar({
    super.key,
    required this.onManage,
    this.iconSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DeviceRegistryStore.instance,
      builder: (context, _) {
        final reg = DeviceRegistryStore.instance.registry;
        final count = reg.length;
        return Semantics(
          label: '$count dari ${DeviceType.values.length} alat terdaftar',
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: const Key('device_status_bar'),
              borderRadius: BorderRadius.circular(14),
              onTap: onManage,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final t in DeviceType.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _DeviceDot(
                          key: Key('device_status_${t.name}'),
                          type: t,
                          registered: reg.containsKey(t),
                          size: iconSize,
                        ),
                      ),
                    const SizedBox(width: 6),
                    // "terdaftar", bukan "tersambung/siap": status sambungan
                    // baru terlihat di layar ukur. Dua baris supaya ringkas.
                    Column(
                      key: const Key('device_status_count'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$count/${DeviceType.values.length}',
                          style: AppText.w700(
                            14,
                            AppColors.grey1,
                          ).copyWith(height: 1.1),
                        ),
                        Text(
                          'terdaftar',
                          style: AppText.w500(
                            14,
                            AppColors.grey1,
                          ).copyWith(height: 1.1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeviceDot extends StatelessWidget {
  final DeviceType type;
  final bool registered;
  final double size;

  const _DeviceDot({
    super.key,
    required this.type,
    required this.registered,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: registered
          ? '${type.label} terdaftar'
          : '${type.label} belum terdaftar',
      child: SizedBox(
        width: size + 6,
        height: size + 6,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: registered ? 1 : 0.3,
              child: DeviceIcon(type: type, size: size),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: registered ? AppColors.darkGreen : AppColors.grey3,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child: Icon(
                  registered ? Icons.check_rounded : Icons.close_rounded,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
