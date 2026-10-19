import 'package:flutter/foundation.dart';

import '../models/squegg_data.dart';
import '../constants/squegg_constants.dart';

/// Parses raw BLE notification bytes from a Squegg device into [SqueggData].
///
/// ## Packet layout (reverse-engineered from the unofficial JS SDK + Squegg_1 captures)
///
/// The device sends bytes that, when interpreted as ASCII char codes, form a
/// decimal string like `"19119.627"`:
///
/// ```
/// Index 0     → unknown / version byte (always '1' = 0x31, discarded)
/// Index 1     → battery level raw digit  (0–9 → 10–100 %)
/// Index 2     → device squeeze flag  ('0' / '1') — NOT used for isSqueezing,
///               see note below
/// Index 3..N  → strength digits/decimal  (e.g. "16.049" → 16.0 kg)
/// Index N+1.. → \x00 null-padding bytes
/// ```
///
/// ## isSqueezing — derived from force, not the device flag
///
/// The device flag at byte[2] rapidly alternates `'0'`/`'1'` during a
/// sustained hold (observed: every 1–2 packets).  Using it directly for
/// [SqueggData.isSqueezing] causes spurious rep counts (many reps per
/// actual squeeze).  We therefore derive [isSqueezing] from a force
/// threshold ([SqueggConstants.squeezeThreshold] = 2.0 kg), which gives
/// exactly one clean false→true→false transition per squeeze cycle.
class SqueggParser {
  SqueggParser._();

  /// Parse a raw BLE notification [bytes] into [SqueggData].
  ///
  /// Returns `null` if the packet is too short or malformed.
  static SqueggData? parse(List<int> bytes) {
    if (bytes.length < SqueggConstants.minPacketLength) return null;

    // Convert raw bytes to their ASCII character representations.
    final chars = bytes.map((b) => String.fromCharCode(b & 0xFF)).toList();

    // Skip the first character — its meaning is undocumented (always '1').
    chars.removeAt(0);

    if (chars.length < 2) return null;

    // ── Battery ───────────────────────────────────────────────────────────────
    // Battery charge: (digit + 1) × 10  →  range 10–100 %
    final batteryRaw = int.tryParse(chars.removeAt(0)) ?? 0;
    final batteryCharge =
        ((batteryRaw + 1) * SqueggConstants.batteryStep).clamp(0, 100);

    if (chars.isEmpty) return null;

    // ── Device squeeze flag (logging only) ────────────────────────────────────
    // Stored for the debug log but NOT used for SqueggData.isSqueezing.
    final squeezeChar = chars.removeAt(0);
    final deviceSqueezeBit = int.tryParse(squeezeChar) != 0; // for log only

    // ── Strength ──────────────────────────────────────────────────────────────
    // Join remaining chars up to the first null byte (device pads with \x00).
    final strengthStr = chars.takeWhile((c) => c != '\x00').join();
    final rawStrength = double.tryParse(strengthStr) ?? 0.0;
    final strength = double.parse(rawStrength.toStringAsFixed(1));

    // ── isSqueezing — threshold-based ─────────────────────────────────────────
    // See class-level doc.  The device flag (byte[2]) is unreliable for this.
    final isSqueezing = strength >= SqueggConstants.squeezeThreshold;

    // ── Debug log ─────────────────────────────────────────────────────────────
    if (kDebugMode) {
      debugPrint(
        '[SqueggParser]'
        '  bat=$batteryCharge%'
        '  |  devFlag="$squeezeChar"($deviceSqueezeBit)'
        '  |  str="$strengthStr" → ${strength}kg'
        '  |  isSqueezing=$isSqueezing',
      );
    }

    return SqueggData.now(
      strength: strength,
      isSqueezing: isSqueezing,
      batteryCharge: batteryCharge,
    );
  }

  /// Parse a [DataView]-style byte array (signed Int8 values, as returned by
  /// [flutter_blue_plus]) — identical to [parse] but documents the BLE source.
  static SqueggData? parseNotification(List<int> value) => parse(value);
}
