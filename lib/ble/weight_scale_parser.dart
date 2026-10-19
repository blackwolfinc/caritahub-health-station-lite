// Port dari Staff Ops (branch health-device): lib/features/health_station/utils/weight_scale_parser.dart
// Hanya logger yang diganti; logika parsing tidak diubah.

import 'package:flutter/foundation.dart';

/// Model class for body composition measurement data from weight scale
/// Supports ONEMED Digital Bathroom Scale 825 with 8 Electrode + Dual-frequency Bio-Impedance
class BodyComposition {
  /// Weight in kg
  final double? weight;

  /// Body fat percentage (%)
  final double? bodyFat;

  /// Water percentage (%)
  final double? water;

  /// Muscle mass percentage (%)
  final double? muscle;

  /// Bone mass percentage (%)
  final double? bone;

  /// Body Mass Index
  final double? bmi;

  /// Basal Metabolic Rate (kcal)
  final int? bmr;

  /// Metabolic age (years)
  final int? metabolicAge;

  /// Visceral fat level
  final int? visceralFat;

  /// Protein percentage (%)
  final double? protein;

  /// Body score (0-100, fitness score from scale)
  final int? bodyScore;

  /// Body age
  final int? bodyAge;

  /// Ideal weight in kg
  final double? idealWeight;

  /// Obesity degree (%)
  final double? obesityDegree;

  /// Subcutaneous fat (%)
  final double? subcutaneousFat;

  /// Skeletal muscle mass (%)
  final double? skeletalMuscle;

  /// Timestamp of measurement
  final DateTime? timestamp;

  /// Raw data for debugging
  final List<int>? rawData;

  /// Decoded IEEE-754 float values from fff3 impedance packets.
  /// Non-null only for Senssun float packets; used by logger for analysis.
  final List<double>? rawFloats;

  BodyComposition({
    this.weight,
    this.bodyFat,
    this.water,
    this.muscle,
    this.bone,
    this.bmi,
    this.bmr,
    this.metabolicAge,
    this.visceralFat,
    this.protein,
    this.bodyScore,
    this.bodyAge,
    this.idealWeight,
    this.obesityDegree,
    this.subcutaneousFat,
    this.skeletalMuscle,
    this.timestamp,
    this.rawData,
    this.rawFloats,
  });

  /// Check if this is a valid measurement with at least weight data
  bool get isValid => weight != null && weight! > 0;

  /// Check if body composition data is available (not just weight)
  bool get hasBodyComposition =>
      bodyFat != null || muscle != null || water != null || bone != null;

  @override
  String toString() {
    return 'BodyComposition('
        'weight: $weight kg, '
        'bodyFat: $bodyFat%, '
        'water: $water%, '
        'muscle: $muscle%, '
        'bone: $bone%, '
        'bmi: $bmi, '
        'bmr: $bmr kcal, '
        'metabolicAge: $metabolicAge'
        ')';
  }

  BodyComposition copyWith({
    double? weight,
    double? bodyFat,
    double? water,
    double? muscle,
    double? bone,
    double? bmi,
    int? bmr,
    int? metabolicAge,
    int? visceralFat,
    double? protein,
    int? bodyScore,
    int? bodyAge,
    double? idealWeight,
    double? obesityDegree,
    double? subcutaneousFat,
    double? skeletalMuscle,
    DateTime? timestamp,
    List<int>? rawData,
  }) {
    return BodyComposition(
      weight: weight ?? this.weight,
      bodyFat: bodyFat ?? this.bodyFat,
      water: water ?? this.water,
      muscle: muscle ?? this.muscle,
      bone: bone ?? this.bone,
      bmi: bmi ?? this.bmi,
      bmr: bmr ?? this.bmr,
      metabolicAge: metabolicAge ?? this.metabolicAge,
      visceralFat: visceralFat ?? this.visceralFat,
      protein: protein ?? this.protein,
      bodyScore: bodyScore ?? this.bodyScore,
      bodyAge: bodyAge ?? this.bodyAge,
      idealWeight: idealWeight ?? this.idealWeight,
      obesityDegree: obesityDegree ?? this.obesityDegree,
      subcutaneousFat: subcutaneousFat ?? this.subcutaneousFat,
      skeletalMuscle: skeletalMuscle ?? this.skeletalMuscle,
      timestamp: timestamp ?? this.timestamp,
      rawData: rawData ?? this.rawData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'weight': weight,
      'bodyFat': bodyFat,
      'water': water,
      'muscle': muscle,
      'bone': bone,
      'bmi': bmi,
      'bmr': bmr,
      'metabolicAge': metabolicAge,
      'visceralFat': visceralFat,
      'protein': protein,
      'bodyScore': bodyScore,
      'bodyAge': bodyAge,
      'idealWeight': idealWeight,
      'obesityDegree': obesityDegree,
      'subcutaneousFat': subcutaneousFat,
      'skeletalMuscle': skeletalMuscle,
      'timestamp': timestamp?.toIso8601String(),
    };
  }

  factory BodyComposition.fromJson(Map<String, dynamic> json) {
    return BodyComposition(
      weight: json['weight']?.toDouble(),
      bodyFat: json['bodyFat']?.toDouble(),
      water: json['water']?.toDouble(),
      muscle: json['muscle']?.toDouble(),
      bone: json['bone']?.toDouble(),
      bmi: json['bmi']?.toDouble(),
      bmr: json['bmr']?.toInt(),
      metabolicAge: json['metabolicAge']?.toInt(),
      visceralFat: json['visceralFat']?.toInt(),
      protein: json['protein']?.toDouble(),
      bodyScore: json['bodyScore']?.toInt(),
      bodyAge: json['bodyAge']?.toInt(),
      idealWeight: json['idealWeight']?.toDouble(),
      obesityDegree: json['obesityDegree']?.toDouble(),
      subcutaneousFat: json['subcutaneousFat']?.toDouble(),
      skeletalMuscle: json['skeletalMuscle']?.toDouble(),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'])
          : null,
    );
  }
}

/// Enum for weight scale device types
enum WeightScaleType {
  /// FITSHOW scale (FS-0B5DDB)
  fitshow,

  /// Senssun scale (IF_B8B) - ONEMED Digital Bathroom Scale 825
  senssun,

  /// Generic BLE Body Composition Service (0x181B)
  genericBCS,

  /// Unknown device type
  unknown,
}

/// Parser utility for BLE weight scale devices
/// Supports:
/// - ONEMED Digital Bathroom Scale 825 (Model 825) with 8 Electrode + Dual-frequency Bio-Impedance
/// - FITSHOW scales (FS-0B5DDB)
/// - Senssun scales (IF_B8B)
class WeightScaleParser {
  // Buffer for fff3 float chunks. IF_B8B sends 9 segmental impedance values
  // split across 2 BLE notifications (4+5 or 5+4 floats). We accumulate them
  // and only return a result once all 9 are received.
  static final List<double> _floatBuffer = [];
  static final List<int> _floatBufferRaw = [];
  static DateTime? _lastChunkAt;

  static void resetFloatBuffer() {
    _floatBuffer.clear();
    _floatBufferRaw.clear();
    _lastChunkAt = null;
  }

  static const String bodyCompositionServiceUUID = '181b';
  static const String fitnessMachineServiceUUID = '1826';
  static const String customServiceUUID = 'fff0';

  static const String bodyCompositionMeasurementUUID = '2a9c';
  static const String bodyCompositionFeatureUUID = '2a9b';
  static const String weightMeasurementUUID = '2a9d';
  static const String weightScaleFeatureUUID = '2a9e';

  static const String fitshowDataUUID = 'fff1';
  static const String fitshowNotifyUUID = 'fff4';

  static const String senssunDataUUID = 'fff1';
  static const String senssunNotifyUUID = 'fff3';

  static WeightScaleType detectDeviceType(String deviceName) {
    final lowerName = deviceName.toLowerCase();

    if (lowerName.startsWith('fs-') || lowerName.contains('fitshow')) {
      return WeightScaleType.fitshow;
    }

    if (lowerName.startsWith('if_') || lowerName.contains('senssun')) {
      return WeightScaleType.senssun;
    }

    return WeightScaleType.unknown;
  }

  static BodyComposition? parse(
    List<int> value, {
    required String deviceName,
    WeightScaleType? deviceType,
  }) {
    if (value.isEmpty) return null;

    final type = deviceType ?? detectDeviceType(deviceName);

    _scaleLog('[WeightScaleParser] Parsing data for $deviceName (type: $type)');
    _scaleLog('[WeightScaleParser] Raw data: $value');
    _scaleLog(
      '[WeightScaleParser] Raw data hex: ${value.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}',
    );

    switch (type) {
      case WeightScaleType.fitshow:
        return _parseFitshowData(value);
      case WeightScaleType.senssun:
        return _parseSenssunData(value);
      case WeightScaleType.genericBCS:
        return _parseBodyCompositionService(value);
      case WeightScaleType.unknown:
        return _parseAutoDetect(value);
    }
  }

  static BodyComposition? _parseFitshowData(List<int> value) {
    if (value.length < 4) return null;

    try {
      final header = value[0];

      if (header == 0xCF || header == 0x10) {
        return _parseFitshowWeightPacket(value);
      }

      if (header == 0x0F || header == 0x12 || header == 0x15) {
        return _parseFitshowBodyCompositionPacket(value);
      }

      if (value.length >= 20) {
        return _parseFitshowExtendedPacket(value);
      }

      return null;
    } catch (e) {
      _scaleLog('[WeightScaleParser] Error parsing FITSHOW data: $e');
      return null;
    }
  }

  static BodyComposition? _parseFitshowWeightPacket(List<int> value) {
    if (value.length < 4) return null;

    final weightRaw = (value[1] & 0xFF) | ((value[2] & 0xFF) << 8);
    final weight = weightRaw / 100.0;

    if (weight < 1 || weight > 300) return null;

    return BodyComposition(
      weight: weight,
      timestamp: DateTime.now(),
      rawData: value,
    );
  }

  static BodyComposition? _parseFitshowBodyCompositionPacket(List<int> value) {
    if (value.length < 14) return null;

    final weight = ((value[1] & 0xFF) | ((value[2] & 0xFF) << 8)) / 100.0;
    final bodyFat = ((value[3] & 0xFF) | ((value[4] & 0xFF) << 8)) / 10.0;
    final water = ((value[5] & 0xFF) | ((value[6] & 0xFF) << 8)) / 10.0;
    final muscle = ((value[7] & 0xFF) | ((value[8] & 0xFF) << 8)) / 10.0;
    final bone = ((value[9] & 0xFF) | ((value[10] & 0xFF) << 8)) / 10.0;
    final bmi = ((value[11] & 0xFF) | ((value[12] & 0xFF) << 8)) / 10.0;
    final bmr = value.length > 14
        ? ((value[13] & 0xFF) | ((value[14] & 0xFF) << 8))
        : null;

    return BodyComposition(
      weight: weight > 0 && weight < 300 ? weight : null,
      bodyFat: bodyFat > 0 && bodyFat < 100 ? bodyFat : null,
      water: water > 0 && water < 100 ? water : null,
      muscle: muscle > 0 && muscle < 100 ? muscle : null,
      bone: bone > 0 && bone < 50 ? bone : null,
      bmi: bmi > 0 && bmi < 100 ? bmi : null,
      bmr: bmr != null && bmr > 0 && bmr < 10000 ? bmr : null,
      timestamp: DateTime.now(),
      rawData: value,
    );
  }

  static BodyComposition? _parseFitshowExtendedPacket(List<int> value) {
    if (value.length < 20) return null;

    try {
      final weight = ((value[1] & 0xFF) | ((value[2] & 0xFF) << 8)) / 100.0;
      final bodyFat = ((value[3] & 0xFF) | ((value[4] & 0xFF) << 8)) / 10.0;
      final water = ((value[5] & 0xFF) | ((value[6] & 0xFF) << 8)) / 10.0;
      final muscle = ((value[7] & 0xFF) | ((value[8] & 0xFF) << 8)) / 10.0;
      final bone = ((value[9] & 0xFF) | ((value[10] & 0xFF) << 8)) / 10.0;
      final bmi = ((value[11] & 0xFF) | ((value[12] & 0xFF) << 8)) / 10.0;
      final bmr = (value[13] & 0xFF) | ((value[14] & 0xFF) << 8);
      final metabolicAge = value[15] & 0xFF;
      final visceralFat = value[16] & 0xFF;
      final protein = ((value[17] & 0xFF) | ((value[18] & 0xFF) << 8)) / 10.0;

      return BodyComposition(
        weight: weight > 0 && weight < 300 ? weight : null,
        bodyFat: bodyFat > 0 && bodyFat < 100 ? bodyFat : null,
        water: water > 0 && water < 100 ? water : null,
        muscle: muscle > 0 && muscle < 100 ? muscle : null,
        bone: bone > 0 && bone < 50 ? bone : null,
        bmi: bmi > 0 && bmi < 100 ? bmi : null,
        bmr: bmr > 0 && bmr < 10000 ? bmr : null,
        metabolicAge: metabolicAge > 0 && metabolicAge < 150
            ? metabolicAge
            : null,
        visceralFat: visceralFat > 0 && visceralFat < 60 ? visceralFat : null,
        protein: protein > 0 && protein < 50 ? protein : null,
        timestamp: DateTime.now(),
        rawData: value,
      );
    } catch (e) {
      _scaleLog('[WeightScaleParser] Error parsing extended packet: $e');
      return null;
    }
  }

  // Type bytes for legacy 8-byte Senssun protocol (MySenssunSdk format).
  static const _legacyTypes = {0xA0, 0xAA, 0xB0, 0xB1, 0xB2, 0xB3, 0xC0, 0xD0};

  /// Parse Senssun scale data (IF_B8B) - ONEMED Digital Bathroom Scale 825
  static BodyComposition? _parseSenssunData(List<int> value) {
    if (value.length < 4) return null;

    try {
      final header = value[0];
      final header2 = value.length > 1 ? value[1] : 0;

      _scaleLog(
        '[WeightScaleParser] Senssun header: 0x${header.toRadixString(16)} 0x${header2.toRadixString(16)}',
      );

      if (header == 0x33 && header2 == 0xCC) {
        return _parseSenssunMainPacket(value);
      }

      // Legacy MySenssunSdk 8-byte protocol: [h1][h2][v1h][v1l][v2h][v2l][type][chk]
      // Type byte at index 6 identifies the metric pair in the packet.
      if (value.length == 8 && _legacyTypes.contains(value[6] & 0xFF)) {
        return _parseSenssunLegacyPacket(value);
      }

      // Final-packet path. Signature: bytes[4..5] == 0x03 0x03.
      // Strict-spec parsing (byte[0]=score, byte[1]=visceral, byte[2..3]=BMR)
      // failed in field tests — score byte position is not consistent.
      // Switch to defensive range-based scan: each metric searched within its
      // typical biologic range, signature bytes excluded, byte indices already
      // claimed by higher-priority metrics also excluded.
      if (value.length >= 8 && value[4] == 0x03 && value[5] == 0x03) {
        if (_floatBuffer.isNotEmpty) {
          _scaleLog(
            '[WeightScaleParser] Final packet: flushing partial buffer (${_floatBuffer.length} floats)',
          );
          resetFloatBuffer();
        }

        final bytes = value.map((b) => b & 0xFF).toList();
        _scaleLog('[WeightScaleParser] Final packet bytes: $bytes');

        // 1) Body Score — byte in 60..100 (typical adult fitness score).
        int? bodyScore;
        int? bodyScoreIdx;
        for (int i = 0; i < bytes.length; i++) {
          if (i == 4 || i == 5) continue;
          if (bytes[i] >= 60 && bytes[i] <= 100) {
            bodyScore = bytes[i];
            bodyScoreIdx = i;
            break;
          }
        }

        // 2) BMR — first 2-byte big-endian combo in 800..3000 kcal range.
        int? bmr;
        int? bmrIdx;
        for (int i = 0; i + 1 < bytes.length; i++) {
          if (i == 4 || i == 5 || i + 1 == 4 || i + 1 == 5) continue;
          final beVal = (bytes[i] << 8) | bytes[i + 1];
          final leVal = (bytes[i + 1] << 8) | bytes[i];
          if (beVal >= 800 && beVal <= 3000) {
            bmr = beVal;
            bmrIdx = i;
            break;
          }
          if (leVal >= 800 && leVal <= 3000) {
            bmr = leVal;
            bmrIdx = i;
            break;
          }
        }

        // 3) Visceral Fat — byte in 1..30, excluding bytes claimed by score/BMR.
        int? visceralFat;
        for (int i = 0; i < bytes.length; i++) {
          if (i == 4 || i == 5) continue;
          if (i == bodyScoreIdx) continue;
          if (bmrIdx != null && (i == bmrIdx || i == bmrIdx + 1)) continue;
          if (bytes[i] >= 1 && bytes[i] <= 30) {
            visceralFat = bytes[i];
            break;
          }
        }

        _scaleLog(
          '[WeightScaleParser] Final extracted (range scan): '
          'score=$bodyScore (idx=$bodyScoreIdx) '
          'visceralFat=$visceralFat '
          'bmr=$bmr (idx=$bmrIdx)',
        );

        if (bodyScore != null || visceralFat != null || bmr != null) {
          return BodyComposition(
            bodyScore: bodyScore,
            visceralFat: visceralFat,
            bmr: bmr,
            timestamp: DateTime.now(),
            rawData: value,
          );
        }
        return null;
      }

      if (_hasSenssunFloatPattern(value)) {
        return _parseSenssunBodyCompositionFloats(value);
      }

      if (header == 0xCF || header == 0xCE) {
        return _parseSenssunWeightPacket(value);
      }

      if (header == 0xCA || header == 0xCB) {
        return _parseSenssunBodyCompositionPacket(value);
      }

      if (value.length >= 13) {
        return _parseSenssunAlternativePacket(value);
      }

      return null;
    } catch (e) {
      _scaleLog('[WeightScaleParser] Error parsing Senssun data: $e');
      return null;
    }
  }

  /// Parses legacy MySenssunSdk 8-byte packets.
  /// Format: [h1][h2][val1_high][val1_low][val2_high][val2_low][type][checksum]
  /// Source: MySenssunSdk (github.com/zhangjing02/MySenssunSdk)
  static BodyComposition? _parseSenssunLegacyPacket(List<int> value) {
    if (value.length != 8) return null;

    final val1 = ((value[2] & 0xFF) << 8) | (value[3] & 0xFF);
    final val2 = ((value[4] & 0xFF) << 8) | (value[5] & 0xFF);
    final typeByte = value[6] & 0xFF;

    _scaleLog(
      '[WeightScaleParser] Legacy packet type=0x${typeByte.toRadixString(16)} val1=$val1 val2=$val2',
    );

    switch (typeByte) {
      case 0xA0: // unstable weight
      case 0xAA: // stable weight
        final w = val1 / 100.0;
        if (w < 1 || w > 300) return null;
        return BodyComposition(
          weight: w,
          timestamp: DateTime.now(),
          rawData: value,
        );

      case 0xB0: // body fat % + water %
        final fat = val1 / 10.0;
        final water = val2 / 10.0;
        return BodyComposition(
          bodyFat: fat > 0 && fat < 80 ? fat : null,
          water: water > 0 && water < 100 ? water : null,
          timestamp: DateTime.now(),
          rawData: value,
        );

      case 0xB1: // visceral fat level + (second field varies by firmware)
        final visceral = val1;
        return BodyComposition(
          visceralFat: visceral > 0 && visceral < 60 ? visceral : null,
          timestamp: DateTime.now(),
          rawData: value,
        );

      case 0xB2: // protein % + mineral %
        final protein = val1 / 10.0;
        return BodyComposition(
          protein: protein > 0 && protein < 50 ? protein : null,
          timestamp: DateTime.now(),
          rawData: value,
        );

      case 0xB3: // metabolic age + body score
        final score = val2;
        return BodyComposition(
          bodyScore: score > 0 && score <= 100 ? score : null,
          timestamp: DateTime.now(),
          rawData: value,
        );

      case 0xC0: // muscle % + bone mass (bone bytes are reversed)
        final muscle = val1 / 10.0;
        final boneReversed = ((value[5] & 0xFF) << 8) | (value[4] & 0xFF);
        final bone = boneReversed / 10.0;
        return BodyComposition(
          muscle: muscle > 0 && muscle < 100 ? muscle : null,
          bone: bone > 0 && bone < 30 ? bone : null,
          timestamp: DateTime.now(),
          rawData: value,
        );

      case 0xD0: // BMR (kcal) + BMI
        final bmr = val1;
        final bmi = val2 / 10.0;
        return BodyComposition(
          bmr: bmr > 0 && bmr < 5000 ? bmr : null,
          bmi: bmi > 0 && bmi < 100 ? bmi : null,
          timestamp: DateTime.now(),
          rawData: value,
        );

      default:
        return null;
    }
  }

  static BodyComposition? _parseSenssunMainPacket(List<int> value) {
    if (value.length < 10) return null;

    try {
      int weightRaw;

      if (value.length == 17) {
        weightRaw = ((value[8] & 0xFF) << 8) | (value[9] & 0xFF);
      } else if (value.length >= 12) {
        weightRaw = ((value[10] & 0xFF) << 8) | (value[11] & 0xFF);
      } else {
        return null;
      }

      final weight = weightRaw / 100.0;

      _scaleLog(
        '[WeightScaleParser] Senssun main packet (${value.length} bytes): weightRaw=$weightRaw weight=$weight kg',
      );

      if (weight < 1 || weight > 300) return null;

      return BodyComposition(
        weight: weight,
        timestamp: DateTime.now(),
        rawData: value,
      );
    } catch (e) {
      _scaleLog('[WeightScaleParser] Error parsing Senssun main packet: $e');
      return null;
    }
  }

  static bool _hasSenssunFloatPattern(List<int> value) {
    if (value.length < 8) return false;
    if (value[0] == 0 && value[1] == 0 && value[2] == 42) return true;
    int count = 0;
    for (int i = 2; i < value.length; i += 4) {
      final b = value[i] & 0xFF;
      if (b >= 0x41 && b <= 0x43 || b == 0x45) count++;
    }
    return count >= 2;
  }

  static BodyComposition? _parseSenssunBodyCompositionFloats(List<int> value) {
    if (value.length < 8) return null;
    try {
      final chunkFloats = _decodeFloatChunk(value);
      if (chunkFloats.isEmpty) return null;
      return _accumulateAndMaybeFlush(chunkFloats, value);
    } catch (e) {
      _scaleLog('[WeightScaleParser] Error parsing body comp floats: $e');
      return null;
    }
  }

  /// Decodes one BLE notify payload into a list of Senssun IEEE-754 floats.
  /// Byte reorder: Senssun stores floats as [c0,c1,c2,c3] but interprets them
  /// as [c2,c3,c0,c1] big-endian.
  static List<double> _decodeFloatChunk(List<int> value) {
    final result = <double>[];
    int start = (value[0] == 0 && value[1] == 0 && value[2] == 42) ? 4 : 0;
    int position = 0;
    for (int i = start; i + 4 <= value.length; i += 4) {
      final chunk = value.sublist(i, i + 4);
      final marker = chunk[2] & 0xFF;
      final bd = ByteData(4);
      bd.setUint8(0, chunk[2]);
      bd.setUint8(1, chunk[3]);
      bd.setUint8(2, chunk[0]);
      bd.setUint8(3, chunk[1]);
      final floatVal = bd.getFloat32(0, Endian.big);
      if (floatVal.isNaN || floatVal.isInfinite) {
        position++;
        continue;
      }
      result.add(floatVal);
      _scaleLog(
        '[WeightScaleParser] chunk pos=$position marker=0x${marker.toRadixString(16)} '
        'raw=${floatVal.toStringAsFixed(0)} ÷100=${(floatVal / 100).toStringAsFixed(1)}',
      );
      position++;
    }
    return result;
  }

  /// Accumulates float chunks until 9 values are collected (full measurement),
  /// then flushes and builds a BodyComposition. Returns null while incomplete.
  static BodyComposition? _accumulateAndMaybeFlush(
    List<double> floats,
    List<int> raw,
  ) {
    final now = DateTime.now();
    if (_lastChunkAt != null && now.difference(_lastChunkAt!).inSeconds > 2) {
      resetFloatBuffer();
    }
    _floatBuffer.addAll(floats);
    _floatBufferRaw.addAll(raw);
    _lastChunkAt = now;

    _scaleLog(
      '[WeightScaleParser] Float buffer: ${_floatBuffer.length} values (added ${floats.length})',
    );

    if (_floatBuffer.length >= 9) {
      final complete = List<double>.from(_floatBuffer);
      final rawCopy = List<int>.from(_floatBufferRaw);
      resetFloatBuffer();
      return _buildBodyCompFromFloats(complete, rawCopy);
    }
    return null;
  }

  /// Builds BodyComposition from a complete set of 9 fff3 floats.
  /// Mapping reverse-engineered from OneMed 825 (Senssun IF_B8B), calibrated
  /// against display ground truth (BMR=1740, Fat=25.0%, Water=55.0%,
  /// Muscle=69.9%, Bone=4.0%, Score=80, BMI=27.6):
  ///   floats[0] — reserved
  ///   floats[1] / 100     → BMI
  ///   floats[2] — reserved
  ///   floats[3] / 100     → Body Fat %
  ///   floats[4] / 39.6    → Muscle %
  ///   floats[5] / 60      → Skeletal Muscle %
  ///   floats[6] / 128     → Subcutaneous Fat (kg, NOT %)
  ///   floats[7] / 54.25   → Bone Mass %
  ///   floats[8] / 39.6    → Body Water %
  ///   protein% = muscle% / 4.7   (derived)
  static BodyComposition _buildBodyCompFromFloats(
    List<double> floats,
    List<int> rawData,
  ) {
    _scaleLog('[WeightScaleParser] Decoded floats (${floats.length}): $floats');

    if (floats.length < 9) {
      _scaleLog('[WeightScaleParser] Incomplete floats — emitting raw only');
      return BodyComposition(
        rawFloats: floats,
        timestamp: DateTime.now(),
        rawData: rawData,
      );
    }

    final bmi = floats[1] / 104.4;
    final bodyFat = floats[3] / 104.4;
    final muscle = floats[4] / 40.1;
    final skeletalMuscle = floats[5] / 61.1;
    final subcutaneousFatKg = floats[6] / 128.0;
    final bone = floats[7] / 53.3;
    final water = floats[8] / 42.8;
    final protein = muscle / 4.68;

    _scaleLog(
      '[WeightScaleParser] Mapped: BMI=${bmi.toStringAsFixed(2)} '
      'Fat=${bodyFat.toStringAsFixed(2)}% Muscle=${muscle.toStringAsFixed(2)}% '
      'SkMuscle=${skeletalMuscle.toStringAsFixed(2)}% '
      'SubFat=${subcutaneousFatKg.toStringAsFixed(2)}kg '
      'Bone=${bone.toStringAsFixed(2)}% Water=${water.toStringAsFixed(2)}% '
      'Protein=${protein.toStringAsFixed(2)}%',
    );

    return BodyComposition(
      bmi: bmi,
      bodyFat: bodyFat,
      muscle: muscle,
      skeletalMuscle: skeletalMuscle,
      subcutaneousFat: subcutaneousFatKg,
      bone: bone,
      water: water,
      protein: protein,
      rawFloats: floats,
      timestamp: DateTime.now(),
      rawData: rawData,
    );
  }

  static BodyComposition? _parseSenssunWeightPacket(List<int> value) {
    if (value.length < 5) return null;

    final weightRaw = (value[2] & 0xFF) | ((value[3] & 0xFF) << 8);
    final weight = weightRaw / 100.0;

    if (weight < 1 || weight > 300) return null;

    return BodyComposition(
      weight: weight,
      timestamp: DateTime.now(),
      rawData: value,
    );
  }

  static BodyComposition? _parseSenssunBodyCompositionPacket(List<int> value) {
    if (value.length < 20) return null;

    final weight = ((value[2] & 0xFF) | ((value[3] & 0xFF) << 8)) / 100.0;
    final bodyFat = ((value[4] & 0xFF) | ((value[5] & 0xFF) << 8)) / 10.0;
    final water = ((value[6] & 0xFF) | ((value[7] & 0xFF) << 8)) / 10.0;
    final muscle = ((value[8] & 0xFF) | ((value[9] & 0xFF) << 8)) / 10.0;
    final bone = ((value[10] & 0xFF) | ((value[11] & 0xFF) << 8)) / 10.0;
    final bmi = ((value[12] & 0xFF) | ((value[13] & 0xFF) << 8)) / 10.0;
    final bmr = (value[14] & 0xFF) | ((value[15] & 0xFF) << 8);
    final metabolicAge = value[16] & 0xFF;
    final visceralFat = value.length > 17 ? value[17] & 0xFF : null;

    return BodyComposition(
      weight: weight > 0 && weight < 300 ? weight : null,
      bodyFat: bodyFat > 0 && bodyFat < 100 ? bodyFat : null,
      water: water > 0 && water < 100 ? water : null,
      muscle: muscle > 0 && muscle < 100 ? muscle : null,
      bone: bone > 0 && bone < 50 ? bone : null,
      bmi: bmi > 0 && bmi < 100 ? bmi : null,
      bmr: bmr > 0 && bmr < 10000 ? bmr : null,
      metabolicAge: metabolicAge > 0 && metabolicAge < 150
          ? metabolicAge
          : null,
      visceralFat: visceralFat != null && visceralFat > 0 && visceralFat < 60
          ? visceralFat
          : null,
      timestamp: DateTime.now(),
      rawData: value,
    );
  }

  static BodyComposition? _parseSenssunAlternativePacket(List<int> value) {
    if (value.length < 13) return null;

    try {
      final weight = ((value[0] & 0xFF) | ((value[1] & 0xFF) << 8)) / 100.0;

      if (weight < 1 || weight > 300) {
        final weightAlt =
            ((value[1] & 0xFF) | ((value[2] & 0xFF) << 8)) / 100.0;
        if (weightAlt >= 1 && weightAlt <= 300) {
          return BodyComposition(
            weight: weightAlt,
            timestamp: DateTime.now(),
            rawData: value,
          );
        }
        return null;
      }

      return BodyComposition(
        weight: weight,
        timestamp: DateTime.now(),
        rawData: value,
      );
    } catch (e) {
      return null;
    }
  }

  /// Parse standard BLE Body Composition Service (0x181B)
  static BodyComposition? _parseBodyCompositionService(List<int> value) {
    if (value.length < 4) return null;

    try {
      final flags = (value[0] & 0xFF) | ((value[1] & 0xFF) << 8);
      int offset = 2;

      double? bodyFat;
      if ((flags & 0x0002) != 0 && offset + 2 <= value.length) {
        bodyFat =
            ((value[offset] & 0xFF) | ((value[offset + 1] & 0xFF) << 8)) / 10.0;
        offset += 2;
      }

      DateTime? timestamp;
      if ((flags & 0x0004) != 0 && offset + 7 <= value.length) {
        final year = (value[offset] & 0xFF) | ((value[offset + 1] & 0xFF) << 8);
        final month = value[offset + 2];
        final day = value[offset + 3];
        final hour = value[offset + 4];
        final minute = value[offset + 5];
        final second = value[offset + 6];
        timestamp = DateTime(year, month, day, hour, minute, second);
        offset += 7;
      }

      if ((flags & 0x0008) != 0 && offset + 1 <= value.length) {
        offset += 1;
      }

      int? bmr;
      if ((flags & 0x0010) != 0 && offset + 2 <= value.length) {
        bmr = (value[offset] & 0xFF) | ((value[offset + 1] & 0xFF) << 8);
        offset += 2;
      }

      double? muscle;
      if ((flags & 0x0020) != 0 && offset + 2 <= value.length) {
        muscle =
            ((value[offset] & 0xFF) | ((value[offset + 1] & 0xFF) << 8)) / 10.0;
        offset += 2;
      }

      if ((flags & 0x0040) != 0 && offset + 2 <= value.length) {
        offset += 2;
      }

      if ((flags & 0x0080) != 0 && offset + 2 <= value.length) {
        offset += 2;
      }

      if ((flags & 0x0100) != 0 && offset + 2 <= value.length) {
        offset += 2;
      }

      double? water;
      if ((flags & 0x0200) != 0 && offset + 2 <= value.length) {
        water =
            ((value[offset] & 0xFF) | ((value[offset + 1] & 0xFF) << 8)) / 10.0;
        offset += 2;
      }

      if ((flags & 0x0400) != 0 && offset + 2 <= value.length) {
        offset += 2;
      }

      double? weight;
      if ((flags & 0x0800) != 0 && offset + 2 <= value.length) {
        weight =
            ((value[offset] & 0xFF) | ((value[offset + 1] & 0xFF) << 8)) /
            200.0;
        offset += 2;
      }

      if ((flags & 0x1000) != 0 && offset + 2 <= value.length) {
        offset += 2;
      }

      return BodyComposition(
        weight: weight,
        bodyFat: bodyFat,
        water: water,
        muscle: muscle,
        bmr: bmr,
        timestamp: timestamp ?? DateTime.now(),
        rawData: value,
      );
    } catch (e) {
      _scaleLog('[WeightScaleParser] Error parsing BCS data: $e');
      return null;
    }
  }

  static BodyComposition? _parseAutoDetect(List<int> value) {
    if (value.isEmpty) return null;

    BodyComposition? result;

    result = _parseSenssunData(value);
    if (result != null && result.isValid) return result;

    result = _parseFitshowData(value);
    if (result != null && result.isValid) return result;

    result = _parseBodyCompositionService(value);
    if (result != null && result.isValid) return result;

    return _parseGenericWeight(value);
  }

  static BodyComposition? _parseGenericWeight(List<int> value) {
    if (value.length < 2) return null;

    for (int i = 0; i < value.length - 1; i++) {
      final rawValue = (value[i] & 0xFF) | ((value[i + 1] & 0xFF) << 8);

      final weight1 = rawValue / 100.0;
      if (weight1 >= 20 && weight1 <= 200) {
        return BodyComposition(
          weight: weight1,
          timestamp: DateTime.now(),
          rawData: value,
        );
      }

      final weight2 = rawValue / 10.0;
      if (weight2 >= 20 && weight2 <= 200) {
        return BodyComposition(
          weight: weight2,
          timestamp: DateTime.now(),
          rawData: value,
        );
      }
    }

    return null;
  }

  static double calculateBMI(double weightKg, double heightCm) {
    if (heightCm <= 0) return 0;
    final heightM = heightCm / 100.0;
    return weightKg / (heightM * heightM);
  }

  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  static String bytesToAscii(List<int> bytes) {
    return bytes
        .where((b) => b >= 32 && b <= 126)
        .map((b) => String.fromCharCode(b))
        .join();
  }
}

/// Standard bioelectrical impedance analysis formulas for estimating body
/// composition values that the IF_B8B firmware does not transmit over BLE.
///
/// References:
/// - Deurenberg P. (1991), Br J Nutr — body fat from BMI/age/sex
/// - Mifflin MD, St Jeor ST. (1990), Am J Clin Nutr — BMR (weight/height/age)
/// - Katch-McArdle (1990) — BMR from lean mass (more accurate when fat% known)
/// - Watson PE. (1980), Am J Clin Nutr — total body water
/// - Sun SS et al. (2003), Am J Clin Nutr — FFM/TBW with impedance
/// - Janssen I. et al. (2000) — skeletal muscle from impedance
///
/// Accuracy without impedance: ±5% BMR, ±10% water/muscle, ±15% bone.
class BIAFormulas {
  static double bodyFatPercentDeurenberg({
    required double bmi,
    required int age,
    required bool isMale,
  }) {
    final fat = (1.20 * bmi) + (0.23 * age) - (10.8 * (isMale ? 1 : 0)) - 5.4;
    return fat.clamp(3.0, 60.0);
  }

  /// Katch-McArdle BMR from lean (fat-free) mass — more accurate than
  /// Mifflin-St Jeor when body fat % is known (e.g. from fff3 estimate).
  static int bmrKatchMcArdle(double fatFreeMassKg) =>
      (fatFreeMassKg * 21.6 + 370).round();

  static int bmrMifflinStJeor({
    required double weight,
    required double height,
    required int age,
    required bool isMale,
  }) {
    final bmr =
        (10 * weight) + (6.25 * height) - (5 * age) + (isMale ? 5 : -161);
    return bmr.round();
  }

  static double bodyWaterPercentWatson({
    required double weight,
    required double height,
    required int age,
    required bool isMale,
  }) {
    final tbw = isMale
        ? 2.447 - (0.09156 * age) + (0.1074 * height) + (0.3362 * weight)
        : -2.097 + (0.1069 * height) + (0.2466 * weight);
    return (tbw / weight * 100).clamp(30.0, 75.0);
  }

  static double leanBodyMassKg(double weight, double bodyFatPercent) =>
      weight * (1 - bodyFatPercent / 100);

  static double musclePercent(double weight, double leanMass) =>
      (leanMass * 0.55 / weight * 100).clamp(20.0, 90.0);

  static double bonePercent(double weight, double leanMass) =>
      (leanMass * 0.04 / weight * 100).clamp(2.0, 8.0);

  static double skeletalMusclePercent(double weight, double leanMass) =>
      (leanMass * 0.49 / weight * 100).clamp(15.0, 60.0);

  static double proteinPercent(double waterPercent, double bonePercent) =>
      (100 - waterPercent - bonePercent - 65).clamp(10.0, 25.0);

  static int visceralFatLevel(double bmi) => (bmi - 22).clamp(1, 30).round();
}

/// Helper class for creating fff2 write commands for Senssun/ONEMED scales
class WeightScaleCommands {
  static const int _header = 0xA5;

  static const int genderMale = 0;
  static const int genderFemale = 1;

  static List<int> createFatTestCommand({
    required int gender,
    required int age,
    required int height,
    int userId = 1,
  }) {
    assert(gender == 0 || gender == 1, 'Gender must be 0 (male) or 1 (female)');
    assert(age >= 1 && age <= 99, 'Age must be between 1 and 99');
    assert(
      height >= 100 && height <= 220,
      'Height must be between 100 and 220 cm',
    );
    assert(userId >= 0 && userId <= 7, 'User ID must be between 0 and 7');

    final genderByte = (gender == genderFemale ? 128 : 0) + userId;

    final buffer = List<int>.filled(9, 0);
    buffer[0] = _header;
    buffer[1] = 0x10;
    buffer[2] = genderByte;
    buffer[3] = age;
    buffer[4] = height;
    buffer[7] = _calculateChecksum(buffer, 1, 6);

    _scaleLog(
      '[WeightScaleCommands] FatTest command: ${WeightScaleParser.bytesToHex(buffer)}',
    );
    return buffer;
  }

  static List<int> createSyncDateCommand({
    required int year,
    required int dayOfYear,
  }) {
    final buffer = List<int>.filled(9, 0);
    buffer[0] = _header;
    buffer[1] = 0x30;
    buffer[2] = year % 100;
    buffer[3] = (dayOfYear >> 8) & 0xFF;
    buffer[4] = dayOfYear & 0xFF;
    buffer[7] = _calculateChecksum(buffer, 1, 6);

    _scaleLog(
      '[WeightScaleCommands] SyncDate command: ${WeightScaleParser.bytesToHex(buffer)}',
    );
    return buffer;
  }

  static List<int> createSyncTimeCommand({
    required int hour,
    required int minute,
    required int second,
  }) {
    final buffer = List<int>.filled(9, 0);
    buffer[0] = _header;
    buffer[1] = 0x31;
    buffer[2] = hour;
    buffer[3] = minute;
    buffer[4] = second;
    buffer[7] = _calculateChecksum(buffer, 1, 6);

    _scaleLog(
      '[WeightScaleCommands] SyncTime command: ${WeightScaleParser.bytesToHex(buffer)}',
    );
    return buffer;
  }

  static int _calculateChecksum(List<int> buffer, int start, int end) {
    int sum = 0;
    for (int i = start; i <= end && i < buffer.length; i++) {
      sum += buffer[i];
    }
    return sum & 0xFF;
  }
}

/// Log paket timbangan hanya di build debug.
void _scaleLog(String message) {
  if (kDebugMode) debugPrint(message);
}
