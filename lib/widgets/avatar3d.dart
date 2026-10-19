// Avatar 3D lansia yang memperagakan langkah pengukuran.
//
// Renderer kecil tanpa paket tambahan. Badan, lengan, dan kaki adalah satu
// permukaan menerus (sapuan penampang elips sepanjang kurva Catmull-Rom),
// jadi tidak ada sambungan bola-tabung seperti manekin. Kepala, tangan, dan
// sepatu dari elipsoid berorientasi. Tiap titik sudut diterangi (lampu utama
// hangat, lampu isi sejuk, langit/lantai, cahaya tepi, kilap), segitiga
// diurutkan dari belakang ke depan lalu digambar sekali lewat
// Canvas.drawVertices. Wajah (mata berkedip, alis, kacamata, senyum) digambar
// 2D dari titik 3D yang diproyeksikan supaya tetap tajam. Mesh hanya dibangun
// ulang saat pose berubah; goyangan idle hanya memutar kamera.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/motion.dart';
import '../app/theme.dart';
import '../models/device_models.dart';
import '../models/health_record.dart';
import '../models/measurements.dart';

/// Pose avatar mengikuti jalur kritis.
enum AvatarPhase { standing, seated, gripping, finished }

/// Keadaan titik ukur di tubuh avatar.
enum AvatarSpot { ready, active, gate, done }

// ─── Vektor ──────────────────────────────────────────────────────────────────

@immutable
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  V3 operator -() => V3(-x, -y, -z);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 get unit {
    final l = length;
    return l == 0 ? this : V3(x / l, y / l, z / l);
  }

  static V3 lerp(V3 a, V3 b, double t) =>
      V3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);
}

const _up = V3(0, 1, 0);

double _smooth(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

int _mix(int a, int b, double t) {
  int ch(int s) {
    final ca = (a >> s) & 0xFF, cb = (b >> s) & 0xFF;
    return (ca + (cb - ca) * t).round() & 0xFF;
  }

  return (0xFF << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

int _shade(int c, double k) {
  int ch(int s) => (((c >> s) & 0xFF) * k).round().clamp(0, 255);
  return (0xFF << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

// ─── Kerangka & pose ─────────────────────────────────────────────────────────

/// Sendi. L = sisi kiri avatar (x positif), R = sisi kanan (x negatif);
/// avatar menghadap +z (ke arah penonton).
enum J {
  pelvis,
  chest,
  neck,
  head,
  lShoulder,
  lElbow,
  lWrist,
  lHand,
  rShoulder,
  rElbow,
  rWrist,
  rHand,
  lHip,
  lKnee,
  lAnkle,
  rHip,
  rKnee,
  rAnkle,
}

typedef Skeleton = Map<J, V3>;

/// Berdiri di timbangan; punggung sedikit membungkuk, kepala agak maju.
const _standing = <J, V3>{
  J.pelvis: V3(0, 0.92, 0),
  J.chest: V3(0, 1.2, 0.018),
  J.neck: V3(0, 1.355, 0.05),
  J.head: V3(0, 1.495, 0.075),
  J.lShoulder: V3(0.182, 1.272, 0.012),
  J.lElbow: V3(0.207, 1.04, -0.012),
  J.lWrist: V3(0.214, 0.832, 0.028),
  J.lHand: V3(0.215, 0.776, 0.045),
  // Kanan sedikit maju: oksimeter terjepit di jari.
  J.rShoulder: V3(-0.182, 1.272, 0.012),
  J.rElbow: V3(-0.212, 1.05, 0.03),
  J.rWrist: V3(-0.215, 0.86, 0.11),
  J.rHand: V3(-0.21, 0.81, 0.15),
  J.lHip: V3(0.094, 0.885, 0),
  J.lKnee: V3(0.098, 0.52, 0.022),
  J.lAnkle: V3(0.098, 0.158, 0),
  J.rHip: V3(-0.094, 0.885, 0),
  J.rKnee: V3(-0.098, 0.52, 0.022),
  J.rAnkle: V3(-0.098, 0.158, 0),
};

/// Duduk tenang di kursi, kedua tangan di paha (tensi & oksimeter).
const _seated = <J, V3>{
  J.pelvis: V3(0, 0.585, -0.07),
  J.chest: V3(0, 0.862, -0.058),
  J.neck: V3(0, 1.018, -0.026),
  J.head: V3(0, 1.158, 0.0),
  J.lShoulder: V3(0.182, 0.935, -0.068),
  J.lElbow: V3(0.232, 0.712, -0.04),
  J.lWrist: V3(0.192, 0.672, 0.19),
  J.lHand: V3(0.18, 0.668, 0.255),
  J.rShoulder: V3(-0.182, 0.935, -0.068),
  J.rElbow: V3(-0.232, 0.712, -0.04),
  J.rWrist: V3(-0.192, 0.672, 0.19),
  J.rHand: V3(-0.18, 0.668, 0.255),
  J.lHip: V3(0.098, 0.565, -0.03),
  J.lKnee: V3(0.108, 0.56, 0.335),
  J.lAnkle: V3(0.108, 0.098, 0.37),
  J.rHip: V3(-0.098, 0.565, -0.03),
  J.rKnee: V3(-0.108, 0.56, 0.335),
  J.rAnkle: V3(-0.108, 0.098, 0.37),
};

/// Duduk, satu tangan maju meremas alat genggam.
Skeleton _gripping(GripSide side) {
  final s = Map<J, V3>.of(_seated);
  if (side == GripSide.left) {
    s[J.lElbow] = const V3(0.236, 0.735, 0.09);
    s[J.lWrist] = const V3(0.205, 0.83, 0.3);
    s[J.lHand] = const V3(0.195, 0.845, 0.362);
  } else {
    s[J.rElbow] = const V3(-0.236, 0.735, 0.09);
    s[J.rWrist] = const V3(-0.205, 0.83, 0.3);
    s[J.rHand] = const V3(-0.195, 0.845, 0.362);
  }
  return s;
}

Skeleton _skeletonFor(AvatarPhase p, GripSide side) => switch (p) {
  AvatarPhase.standing => _standing,
  AvatarPhase.seated || AvatarPhase.finished => _seated,
  AvatarPhase.gripping => _gripping(side),
};

Skeleton _lerpSkeleton(Skeleton a, Skeleton b, double t) => {
  for (final j in J.values) j: V3.lerp(a[j]!, b[j]!, t),
};

/// Bingkai kamera per pose: pusat tinggi, tinggi & lebar yang harus muat.
typedef _Frame = ({double centerY, double height, double width});

_Frame _frameFor(AvatarPhase p) => switch (p) {
  AvatarPhase.standing => (centerY: 0.83, height: 1.74, width: 0.74),
  _ => (centerY: 0.655, height: 1.38, width: 0.9),
};

_Frame _lerpFrame(_Frame a, _Frame b, double t) => (
  centerY: a.centerY + (b.centerY - a.centerY) * t,
  height: a.height + (b.height - a.height) * t,
  width: a.width + (b.width - a.width) * t,
);

// ─── Template bentuk ─────────────────────────────────────────────────────────

class _Sphere {
  final Float64List p; // titik bola satuan
  final Uint16List i;
  const _Sphere(this.p, this.i);
  int get count => p.length ~/ 3;
}

_Sphere _sphereTemplate(int lat, int lon) {
  final p = <double>[], idx = <int>[];
  for (var a = 0; a <= lat; a++) {
    final th = math.pi * a / lat;
    for (var b = 0; b <= lon; b++) {
      final ph = 2 * math.pi * b / lon;
      p.addAll([
        math.sin(th) * math.sin(ph),
        math.cos(th),
        math.sin(th) * math.cos(ph),
      ]);
    }
  }
  for (var a = 0; a < lat; a++) {
    for (var b = 0; b < lon; b++) {
      final k = a * (lon + 1) + b;
      idx.addAll([k, k + 1, k + lon + 1, k + 1, k + lon + 2, k + lon + 1]);
    }
  }
  return _Sphere(Float64List.fromList(p), Uint16List.fromList(idx));
}

final _sphereMid = _sphereTemplate(10, 16);
final _sphereLo = _sphereTemplate(7, 11);

// ─── Penyusun mesh ───────────────────────────────────────────────────────────

/// Satu cincin hasil sapuan (untuk menaruh kancing, manset, dll.).
class _Ring {
  final V3 c, u, w;
  final double rx, rz, param;
  const _Ring(this.c, this.u, this.w, this.rx, this.rz, this.param);

  /// Titik di permukaan pada sudut [a] (π/2 = depan), sedikit keluar [out].
  V3 at(double a, [double out = 0]) =>
      c + u * (math.cos(a) * (rx + out)) + w * (math.sin(a) * (rz + out));
}

class _Mesh {
  final List<double> p = [];
  final List<double> n = [];
  final List<int> c = []; // warna dasar ARGB per titik
  final List<double> g = []; // kilap 0..1 per titik
  final List<double> b = []; // geser urutan gambar (negatif = ke belakang)
  final List<int> l = []; // lapisan: 0 badan & properti, 1 kepala

  /// Lapisan gambar untuk titik berikutnya (kepala digambar paling akhir).
  int layer = 0;

  /// Geser kedalaman untuk bagian yang tersembunyi di dalam bagian lain
  /// (pangkal lengan/kaki, leher) supaya tidak "tembus" saat diurutkan.
  double bias = 0;
  final List<int> i = [];

  int get vertexCount => p.length ~/ 3;

  void _v(V3 q, V3 nn, int argb, double gloss) {
    p
      ..add(q.x)
      ..add(q.y)
      ..add(q.z);
    n
      ..add(nn.x)
      ..add(nn.y)
      ..add(nn.z);
    c.add(argb);
    g.add(gloss);
    b.add(bias);
    l.add(layer);
  }

  /// Elipsoid dengan sumbu [ax], [ay], [az] (saling tegak lurus, panjang =
  /// jari-jari). [colorAt] menerima koordinat bola satuan.
  void ellipsoid(
    V3 at,
    V3 ax,
    V3 ay,
    V3 az,
    Color color, {
    _Sphere? t,
    double gloss = 0.05,
    int Function(double x, double y, double z)? colorAt,
    bool Function(double x, double y, double z)? keep,
  }) {
    final s = t ?? _sphereMid;
    final base = vertexCount;
    final argb = color.toARGB32();
    final kx = ax * (1 / ax.dot(ax)),
        ky = ay * (1 / ay.dot(ay)),
        kz = az * (1 / az.dot(az));
    for (var k = 0; k < s.count; k++) {
      final x = s.p[k * 3], y = s.p[k * 3 + 1], z = s.p[k * 3 + 2];
      _v(
        at + ax * x + ay * y + az * z,
        (kx * x + ky * y + kz * z).unit,
        colorAt == null ? argb : colorAt(x, y, z),
        gloss,
      );
    }
    for (var q = 0; q < s.i.length; q += 3) {
      final a = s.i[q], b = s.i[q + 1], d = s.i[q + 2];
      if (keep != null) {
        final cx = (s.p[a * 3] + s.p[b * 3] + s.p[d * 3]) / 3;
        final cy = (s.p[a * 3 + 1] + s.p[b * 3 + 1] + s.p[d * 3 + 1]) / 3;
        final cz = (s.p[a * 3 + 2] + s.p[b * 3 + 2] + s.p[d * 3 + 2]) / 3;
        if (!keep(cx, cy, cz)) continue;
      }
      i
        ..add(base + a)
        ..add(base + b)
        ..add(base + d);
    }
  }

  /// Elipsoid sejajar sumbu dunia.
  void ball(
    V3 at,
    V3 r,
    Color color, {
    _Sphere? t,
    double gloss = 0.05,
    int Function(double x, double y, double z)? colorAt,
    bool Function(double x, double y, double z)? keep,
  }) => ellipsoid(
    at,
    V3(r.x, 0, 0),
    V3(0, r.y, 0),
    V3(0, 0, r.z),
    color,
    t: t,
    gloss: gloss,
    colorAt: colorAt,
    keep: keep,
  );

  /// Sapuan penampang elips (rx ke samping, rz ke depan) sepanjang kurva
  /// Catmull-Rom melalui [ctrl]. [colorAt] menerima parameter kontrol u
  /// (0..ctrl.length-1) dan sudut a (π/2 = depan). [side] memaku arah
  /// "samping" (badan); tanpa itu bingkai dibawa sejajar sepanjang kurva.
  List<_Ring> sweep(
    List<V3> ctrl,
    List<(double, double)> sec, {
    required int Function(double u, double a) colorAt,
    V3? side,
    int seg = 16,
    int sub = 5,
    double gloss = 0.05,
    bool capStart = true,
    bool capEnd = true,
    double Function(double u)? biasAt,
    V3 Function(V3 p, double u, double a)? warp,
  }) {
    final nc = ctrl.length;
    final bias0 = bias;
    V3 cp(int k) {
      if (k < 0) return ctrl[0] * 2 - ctrl[1];
      if (k >= nc) return ctrl[nc - 1] * 2 - ctrl[nc - 2];
      return ctrl[k];
    }

    // Titik kurva + penampang.
    final pts = <V3>[];
    final secs = <(double, double)>[];
    final us = <double>[];
    for (var s = 0; s < nc - 1; s++) {
      final p0 = cp(s - 1), p1 = cp(s), p2 = cp(s + 1), p3 = cp(s + 2);
      for (var k = 0; k < sub; k++) {
        final t = k / sub, t2 = t * t, t3 = t2 * t;
        pts.add(
          (p1 * 2 +
                  (p2 - p0) * t +
                  (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                  (-p0 + p1 * 3 - p2 * 3 + p3) * t3) *
              0.5,
        );
        final e = t * t * (3 - 2 * t);
        secs.add((
          sec[s].$1 + (sec[s + 1].$1 - sec[s].$1) * e,
          sec[s].$2 + (sec[s + 1].$2 - sec[s].$2) * e,
        ));
        us.add(s + t);
      }
    }
    pts.add(ctrl[nc - 1]);
    secs.add(sec[nc - 1]);
    us.add((nc - 1).toDouble());
    final rn = pts.length;

    // Bingkai tiap cincin.
    final rings = <_Ring>[];
    V3? prevU;
    for (var r = 0; r < rn; r++) {
      final tan = (pts[math.min(r + 1, rn - 1)] - pts[math.max(r - 1, 0)]).unit;
      V3 u;
      if (side != null) {
        u = (side - tan * side.dot(tan)).unit;
      } else if (prevU == null) {
        final h = tan.y.abs() > 0.9 ? const V3(1, 0, 0) : _up;
        u = tan.cross(h).unit;
      } else {
        u = (prevU - tan * prevU.dot(tan)).unit;
      }
      prevU = u;
      final w = u.cross(tan);
      rings.add(_Ring(pts[r], u, w, secs[r].$1, secs[r].$2, us[r]));
    }

    // Titik permukaan.
    final grid = <V3>[];
    for (final ring in rings) {
      for (var k = 0; k <= seg; k++) {
        final a = 2 * math.pi * k / seg;
        final q = ring.at(a);
        grid.add(warp == null ? q : warp(q, ring.param, a));
      }
    }
    final base = vertexCount;
    for (var r = 0; r < rn; r++) {
      final ring = rings[r];
      for (var k = 0; k <= seg; k++) {
        final idx = r * (seg + 1) + k;
        final q = grid[idx];
        final kp = r * (seg + 1) + (k + 1) % seg;
        final km = r * (seg + 1) + (k - 1 + seg) % seg;
        final rp = math.min(r + 1, rn - 1) * (seg + 1) + k;
        final rm = math.max(r - 1, 0) * (seg + 1) + k;
        var nn = (grid[kp] - grid[km]).cross(grid[rp] - grid[rm]).unit;
        final radial = q - ring.c;
        if (nn.dot(radial) < 0) nn = -nn;
        if (nn.length < 0.5) nn = radial.unit;
        final a = 2 * math.pi * k / seg;
        bias = biasAt?.call(ring.param) ?? bias0;
        _v(q, nn, colorAt(ring.param, a), gloss);
      }
    }
    for (var r = 0; r < rn - 1; r++) {
      for (var k = 0; k < seg; k++) {
        final a = base + r * (seg + 1) + k;
        final b = a + seg + 1;
        i.addAll([a, a + 1, b, a + 1, b + 1, b]);
      }
    }

    // Tutup ujung dengan setengah elipsoid.
    void cap(_Ring ring, V3 dir, int color) {
      final tan = dir.unit;
      final r = math.min(ring.rx, ring.rz);
      ellipsoid(
        ring.c,
        ring.u * ring.rx,
        tan * r,
        ring.w * ring.rz,
        Color(color),
        t: _sphereLo,
        gloss: gloss,
      );
    }

    if (capStart) {
      bias = biasAt?.call(0) ?? bias0;
      cap(rings.first, pts[0] - pts[1], colorAt(0, math.pi / 2));
    }
    if (capEnd) {
      bias = biasAt?.call(nc - 1.0) ?? bias0;
      cap(
        rings.last,
        pts[rn - 1] - pts[rn - 2],
        colorAt(nc - 1.0, math.pi / 2),
      );
    }
    bias = bias0;
    return rings;
  }

  /// Salinan ringkas (typed array) untuk digambar tiap frame.
  _Geo freeze() => _Geo(
    Float64List.fromList(p),
    Float64List.fromList(n),
    Int32List.fromList(c),
    Float64List.fromList(g),
    Float64List.fromList(b),
    Int8List.fromList(l),
    Int32List.fromList(i),
  );

  /// Permukaan bebas f(θ, φ) di sekitar [center] (θ 0..π dari atas, φ 0..2π
  /// mulai dari belakang). Normal dihitung numerik dari bentuk akhirnya.
  void surface(
    V3 center,
    int lat,
    int lon,
    V3 Function(double th, double ph) f,
    int Function(double th, double ph) colorAt, {
    double gloss = 0.05,
  }) {
    const e = 1e-3;
    final base = vertexCount;
    for (var a = 0; a <= lat; a++) {
      final th = math.pi * a / lat;
      for (var k = 0; k <= lon; k++) {
        final ph = 2 * math.pi * k / lon;
        final q = f(th, ph);
        final dTh =
            f(math.min(th + e, math.pi), ph) - f(math.max(th - e, 0), ph);
        final dPh = f(th, ph + e) - f(th, ph - e);
        var nn = dTh.cross(dPh).unit;
        if (nn.length < 0.5 || a == 0 || a == lat) nn = q.unit;
        if (nn.dot(q) < 0) nn = -nn;
        _v(center + q, nn, colorAt(th, ph), gloss);
      }
    }
    for (var a = 0; a < lat; a++) {
      for (var k = 0; k < lon; k++) {
        final q = base + a * (lon + 1) + k;
        i.addAll([q, q + 1, q + lon + 1, q + 1, q + lon + 2, q + lon + 1]);
      }
    }
  }

  void box(V3 at, V3 half, Color color, {double gloss = 0.1}) {
    const faces = [
      V3(1, 0, 0),
      V3(-1, 0, 0),
      V3(0, 1, 0),
      V3(0, -1, 0),
      V3(0, 0, 1),
      V3(0, 0, -1),
    ];
    final argb = color.toARGB32();
    for (final nn in faces) {
      final u = nn.x.abs() > 0.5 ? _up : const V3(1, 0, 0);
      final v = nn.cross(u);
      final b = vertexCount;
      for (final (su, sv) in const [
        (-1.0, -1.0),
        (1.0, -1.0),
        (1.0, 1.0),
        (-1.0, 1.0),
      ]) {
        final q = nn + u * su + v * sv;
        _v(
          V3(at.x + q.x * half.x, at.y + q.y * half.y, at.z + q.z * half.z),
          nn,
          argb,
          gloss,
        );
      }
      i.addAll([b, b + 2, b + 1, b, b + 3, b + 2]);
    }
  }
}

/// Geometri beku: posisi, normal, warna, kilap, geser kedalaman, lapisan.
class _Geo {
  final Float64List p, n;
  final Int32List c;
  final Float64List g, b;
  final Int8List l;
  final Int32List i;
  const _Geo(this.p, this.n, this.c, this.g, this.b, this.l, this.i);
  int get vertexCount => p.length ~/ 3;
}

// ─── Warna ───────────────────────────────────────────────────────────────────

class _Palette {
  static const skin = Color(0xFFE8B893);
  static const skinShadow = Color(0xFFC98F6C);
  static const hair = Color(0xFFE6E3E1);
  static const hairShade = Color(0xFFBDB8B4);
  static const shirt = Color(0xFFF7F2EA);
  static const button = Color(0xFFF4EBDD);
  static const shoes = Color(0xFF4A3E38);
  static const sole = Color(0xFF2B2624);
  static const wood = Color(0xFFC9A57C);
  static const woodDark = Color(0xFFA9845B);
  static const cushion = Color(0xFFA7BFD0);
  static const scale = Color(0xFFF3F5F9);
  static const scaleTop = Color(0xFFE3E7EF);
  static const scaleDisplay = Color(0xFF2B3141);
  static const cuff = Color(0xFF2F4E86);
  static const device = Color(0xFFFFFFFF);
  static const grip = Color(0xFF39B887);

  /// Kardigan.
  static Color top(Gender? g) => switch (g) {
    Gender.female => const Color(0xFFD7899A),
    Gender.male => const Color(0xFF6E92C8),
    null => const Color(0xFF6DB3A9),
  };

  static Color pants(Gender? g) => switch (g) {
    Gender.female => const Color(0xFF5E6380),
    _ => const Color(0xFF51586B),
  };
}

// ─── Adegan ──────────────────────────────────────────────────────────────────

const _headRadii = V3(0.122, 0.138, 0.13);

/// Bentuk kepala dari arah bola satuan: rahang sedikit meruncing, dagu
/// sedikit maju, belakang kepala agak pipih; [hair] = tebal rambut (relatif).
V3 _headShape(double x0, double y0, double z0, V3 r, double hair) {
  var x = x0, z = z0;
  if (y0 < 0) {
    final k = y0 * y0;
    x *= 1 - 0.2 * k;
    if (z > 0) z += 0.07 * k * z;
  }
  if (z < 0) z *= 0.95;
  final sc = 1 + hair;
  return V3(x * r.x * sc, y0 * r.y * sc, z * r.z * sc);
}

/// Data wajah untuk lapisan 2D.
class _Face {
  final V3 center;
  final V3 radii;
  final Gender? gender;
  const _Face(this.center, this.radii, this.gender);

  /// Titik di permukaan wajah pada (fx, fy) dari pusat kepala.
  V3 at(double fx, double fy, [double out = 0]) {
    final nx = fx / radii.x, ny = fy / radii.y;
    final nz = math.sqrt(math.max(0.0, 1 - nx * nx - ny * ny));
    return center + _headShape(nx, ny, nz, radii, 0) + normalAt(fx, fy) * out;
  }

  /// Normal permukaan (dunia) di titik wajah.
  V3 normalAt(double fx, double fy) {
    final nx = fx / radii.x, ny = fy / radii.y;
    final nz = math.sqrt(math.max(0.0, 1 - nx * nx - ny * ny));
    final p = V3(nx * radii.x, ny * radii.y, nz * radii.z);
    return V3(
      p.x / (radii.x * radii.x),
      p.y / (radii.y * radii.y),
      p.z / (radii.z * radii.z),
    ).unit;
  }
}

/// Titik jangkar (dunia) untuk sorotan alat.
class _Anchors {
  final Map<DeviceType, V3> spots;
  final _Face face;
  final List<V3> vLeft, vRight; // tepi kerah V (bawah → atas)
  final List<V3> floorSpots; // pusat bayangan kontak
  const _Anchors(
    this.spots,
    this.face,
    this.vLeft,
    this.vRight,
    this.floorSpots,
  );
}

/// Tangan: telapak + jari rapat + ibu jari, menghadap [palmN].
void _hand(
  _Mesh m,
  V3 wrist,
  V3 center,
  V3 palmN,
  bool left, {
  bool fist = false,
}) {
  final dir = (center - wrist).unit;
  final n = (palmN - dir * palmN.dot(dir)).unit;
  final side = n.cross(dir) * (left ? 1 : -1); // ke arah ibu jari
  const skin = _Palette.skin;
  // Telapak + jari rapat sebagai satu bentuk sarung tangan; kepalan saat meremas.
  m.ellipsoid(
    center + dir * (fist ? 0.006 : 0.014) + n * (fist ? 0.01 : 0.0),
    dir * (fist ? 0.046 : 0.058),
    side * 0.037,
    n * (fist ? 0.034 : 0.024),
    skin,
    gloss: 0.1,
  );
  // Ibu jari.
  final tAx = (dir * 0.8 + n * 0.4).unit;
  m.ellipsoid(
    center + side * 0.032 + n * 0.008 - dir * 0.004,
    tAx * 0.03,
    side * 0.014,
    tAx.cross(side).unit * 0.014,
    skin,
    t: _sphereLo,
    gloss: 0.1,
  );
}

(_Geo, _Anchors) _buildScene(
  Skeleton s,
  AvatarPhase phase,
  Gender? gender,
  GripSide gripSide,
  Set<DeviceType> devicesOn,
) {
  final m = _Mesh();
  final top = _Palette.top(gender);
  final topArgb = top.toARGB32();
  final cuffArgb = _shade(topArgb, 0.86);
  final pantsArgb = _Palette.pants(gender).toARGB32();
  final skinArgb = _Palette.skin.toARGB32();
  // Seberapa "duduk" pose saat ini (0 berdiri … 1 duduk). Selama transisi
  // kursi/timbangan berganti di tengah gerakan, bukan di awal.
  final sit = _smooth(0, 1, (0.92 - s[J.pelvis]!.y) / 0.335);
  final seated = sit > 0.5;
  final female = gender == Gender.female;

  // ── Properti: timbangan atau kursi ──
  if (!seated) {
    m.box(
      const V3(0, 0.03, 0.03),
      const V3(0.25, 0.03, 0.2),
      _Palette.scale,
      gloss: 0.45,
    );
    m.box(
      const V3(0, 0.0605, 0.03),
      const V3(0.235, 0.0015, 0.185),
      _Palette.scaleTop,
      gloss: 0.6,
    );
    m.box(
      const V3(0, 0.063, 0.19),
      const V3(0.06, 0.003, 0.022),
      _Palette.scaleDisplay,
      gloss: 0.7,
    );
  } else {
    m.box(
      const V3(0, 0.43, 0.02),
      const V3(0.25, 0.028, 0.245),
      _Palette.wood,
      gloss: 0.15,
    );
    m.ball(
      const V3(0, 0.478, 0.03),
      const V3(0.225, 0.021, 0.215),
      _Palette.cushion,
      gloss: 0.04,
      keep: (x, y, z) => y > -0.2, // bagian bawah tertutup dudukan
    );
    for (final (x, z) in [
      (0.215, 0.235),
      (-0.215, 0.235),
      (0.215, -0.195),
      (-0.215, -0.195),
    ]) {
      m.sweep(
        [V3(x, 0, z), V3(x, 0.41, z)],
        const [(0.02, 0.02), (0.024, 0.024)],
        colorAt: (_, _) => _Palette.woodDark.toARGB32(),
        seg: 8,
        sub: 1,
        gloss: 0.15,
      );
    }
    for (final x in [0.215, -0.215]) {
      m.sweep(
        [V3(x, 0.44, -0.205), V3(x, 1.04, -0.235)],
        const [(0.022, 0.022), (0.022, 0.022)],
        colorAt: (_, _) => _Palette.woodDark.toARGB32(),
        seg: 8,
        sub: 1,
        gloss: 0.15,
      );
    }
    m.box(
      const V3(0, 0.86, -0.222),
      const V3(0.2, 0.15, 0.016),
      _Palette.wood,
      gloss: 0.15,
    );
    m.box(
      const V3(0, 1.035, -0.234),
      const V3(0.235, 0.025, 0.022),
      _Palette.woodDark,
      gloss: 0.15,
    );
  }

  // ── Kepala: satu permukaan (kulit → rambut uban bervolume) ──
  m.layer = 1;
  final head = s[J.head]!;
  const hr = _headRadii;
  // Garis rambut: depan tinggi, samping di atas telinga, belakang rendah.
  double hairline(double z) => female ? -0.06 + 0.64 * z : 0.06 + 0.66 * z;
  final thick = female ? 0.085 : 0.04;
  final hairArgb = _Palette.hair.toARGB32();
  final hairShade = _Palette.hairShade.toARGB32();
  (double, double, double) dir(double th, double ph) => (
    -math.sin(th) * math.sin(ph),
    math.cos(th),
    -math.sin(th) * math.cos(ph),
  );
  double hairAt(double x, double y, double z) {
    var h = _smooth(-0.07, 0.07, y - hairline(z));
    // Perempuan: rambut sedikit menggembung di atas & belakang.
    if (female) h *= 1 + 0.35 * _smooth(0.2, 0.9, y - 0.4 * z);
    return h;
  }

  m.surface(
    head,
    20,
    36,
    (th, ph) {
      final (x, y, z) = dir(th, ph);
      return _headShape(x, y, z, hr, thick * hairAt(x, y, z));
    },
    (th, ph) {
      final (x, y, z) = dir(th, ph);
      final h = _smooth(-0.07, 0.07, y - hairline(z));
      // Guratan sisiran ke belakang.
      final comb = 0.5 + 0.5 * math.sin(x * 24 + y * 5);
      final hair = _mix(hairArgb, hairShade, 0.35 * comb);
      return _mix(skinArgb, hair, h);
    },
    gloss: 0.08,
  );
  if (female) {
    // Konde.
    m.ball(
      head + const V3(0, 0.06, -0.15),
      const V3(0.064, 0.06, 0.056),
      _Palette.hair,
      gloss: 0.08,
      colorAt: (x, y, z) => _mix(
        hairArgb,
        hairShade,
        0.3 * (0.5 + 0.5 * math.sin(x * 9 + y * 7)),
      ),
    );
  }
  // Telinga & hidung.
  for (final sx in [1.0, -1.0]) {
    m.ellipsoid(
      head + V3(0.117 * sx, -0.012, -0.012),
      V3(0.016 * sx, 0, 0),
      const V3(0, 0.034, 0),
      const V3(0, 0, 0.023),
      _Palette.skin,
      t: _sphereLo,
      gloss: 0.1,
    );
  }
  final face = _Face(head, hr, gender);
  m.ball(
    face.at(0, -0.016, -0.009),
    const V3(0.016, 0.019, 0.016),
    _Palette.skin,
    t: _sphereLo,
    gloss: 0.15,
  );
  m.layer = 0;

  // ── Leher ──
  final neck = s[J.neck]!, chest = s[J.chest]!, pelvis = s[J.pelvis]!;
  m.bias = -0.03;
  m.sweep(
    [neck - const V3(0, 0.03, 0), head - const V3(0, 0.08, 0.025)],
    const [(0.05, 0.048), (0.047, 0.045)],
    colorAt: (_, _) => _Palette.skinShadow.toARGB32(),
    seg: 12,
    sub: 2,
    capStart: false,
    capEnd: false,
  );
  m.bias = 0;

  if (seated) {
    // Panggul (celana) di bawah kardigan, mengisi celah di antara paha.
    m.bias = -0.08;
    m.ball(
      pelvis + const V3(0, -0.01, 0.03),
      const V3(0.165, 0.095, 0.15),
      Color(pantsArgb),
      t: _sphereLo,
    );
    m.bias = 0;
  }

  // ── Badan (celana → kardigan → kerah V) ──
  final spine = (chest - pelvis).unit;
  final torsoCtrl = [
    pelvis - spine * 0.075,
    pelvis,
    V3.lerp(pelvis, chest, 0.45) + const V3(0, 0, 0.012),
    chest,
    V3.lerp(chest, neck, 0.55),
    neck - (neck - chest).unit * 0.005,
  ];
  final torso = m.sweep(
    torsoCtrl,
    const [
      (0.178, 0.13),
      (0.172, 0.126),
      (0.156, 0.128),
      (0.172, 0.122),
      (0.184, 0.108),
      (0.058, 0.054),
    ],
    side: const V3(1, 0, 0),
    seg: 40,
    sub: 6,
    // Bawah terbuka: kardigan menutup pangkal kaki (tidak terlihat dari atas).
    capStart: false,
    capEnd: false,
    colorAt: (u, _) => u < 0.34 ? cuffArgb : topArgb,
    // Duduk: kardigan menutupi pangkal paha (digambar di atasnya) dan
    // ujung depannya terangkat, menempel di atas pangkuan.
    biasAt: seated ? (u) => 0.1 * _smooth(1.8, 1.55, u) : null,
    warp: seated
        ? (q, u, a) {
            // Bagian depan yang lebih rendah dari pangkuan dinaikkan ke
            // pangkuan (tanpa melipat permukaan); samping & belakang tetap.
            final lap = s[J.lHip]!.y + 0.082;
            final front = _smooth(0.05, 0.6, math.sin(a)) * sit;
            return V3(q.x, q.y + math.max(0.0, lap - q.y) * front, q.z);
          }
        : null,
  );
  // Kerah V (digambar 2D di atas badan supaya tepinya tajam).
  final vLeft = <V3>[], vRight = <V3>[];
  for (final r in torso) {
    if (r.param < 3.3) continue;
    final v = ((r.param - 3.3) / 1.7).clamp(0.0, 1.0);
    final width = 0.06 + 0.86 * v;
    vLeft.add(r.at(math.pi / 2 + width, 0.002));
    vRight.add(r.at(math.pi / 2 - width, 0.002));
  }
  // Kancing kardigan di garis depan.
  for (final r in torso) {
    for (final uu in const [1.95, 2.45, 2.95]) {
      if ((r.param - uu).abs() < 0.01) {
        m.ball(
          r.at(math.pi / 2, 0.006),
          const V3(0.011, 0.011, 0.006),
          _Palette.button,
          t: _sphereLo,
          gloss: 0.4,
        );
      }
    }
  }

  // ── Lengan (kardigan sampai pergelangan) ──
  for (final (sh, el, wr, ha, left) in [
    (J.lShoulder, J.lElbow, J.lWrist, J.lHand, true),
    (J.rShoulder, J.rElbow, J.rWrist, J.rHand, false),
  ]) {
    final shoulder = s[sh]!, elbow = s[el]!, wrist = s[wr]!;
    final inner = shoulder + V3(left ? -0.052 : 0.052, -0.03, 0);
    m.sweep(
      [inner, shoulder, elbow, wrist],
      const [(0.056, 0.056), (0.06, 0.06), (0.048, 0.048), (0.042, 0.042)],
      colorAt: (u, _) => u > 2.8 ? cuffArgb : topArgb,
      seg: 16,
      sub: 5,
      capStart: false,
      biasAt: (u) => u < 1 ? -0.05 * (1 - u) : 0,
    );
    final gripping =
        phase == AvatarPhase.gripping && (gripSide == GripSide.left) == left;
    final palmN = switch (phase) {
      AvatarPhase.standing => V3(left ? -1 : 1, 0, 0.15),
      _ when gripping => V3(left ? -0.6 : 0.6, -0.8, 0),
      _ => const V3(0, -1, 0),
    };
    final handC = s[ha]!;
    final hDir = (handC - wrist).unit;
    _hand(m, wrist - hDir * 0.012, handC, palmN, left, fist: gripping);
  }

  // ── Kaki & sepatu ──
  for (final (hp, kn, an, left) in [
    (J.lHip, J.lKnee, J.lAnkle, true),
    (J.rHip, J.rKnee, J.rAnkle, false),
  ]) {
    final hip = s[hp]!, knee = s[kn]!, ankle = s[an]!;
    m.sweep(
      [hip + V3(left ? -0.03 : 0.03, 0.07, 0), hip, knee, ankle],
      const [(0.09, 0.09), (0.088, 0.088), (0.066, 0.066), (0.052, 0.052)],
      colorAt: (_, _) => pantsArgb,
      seg: 16,
      sub: 5,
      capStart: false,
      biasAt: (u) => -0.09 * ((1.75 - u) / 1.75).clamp(0.0, 1.0),
    );
    m.ball(
      ankle + const V3(0, -0.05, 0.048),
      const V3(0.05, 0.044, 0.104),
      _Palette.shoes,
      gloss: 0.35,
    );
    m.ball(
      ankle + const V3(0, -0.087, 0.05),
      const V3(0.054, 0.011, 0.11),
      _Palette.sole,
      t: _sphereLo,
      gloss: 0.1,
    );
  }

  // ── Alat yang sedang terpasang ──
  final lSh = s[J.lShoulder]!, lEl = s[J.lElbow]!;
  final lUpper = V3.lerp(lSh, lEl, 0.5);
  if (devicesOn.contains(DeviceType.tensimeter)) {
    m.sweep(
      [V3.lerp(lSh, lEl, 0.24), V3.lerp(lSh, lEl, 0.72)],
      const [(0.074, 0.074), (0.072, 0.072)],
      colorAt: (_, _) => _Palette.cuff.toARGB32(),
      seg: 18,
      sub: 3,
      gloss: 0.12,
      capStart: false,
      capEnd: false,
    );
  }
  final rHand = s[J.rHand]!, rWrist = s[J.rWrist]!;
  final rDir = (rHand - rWrist).unit;
  final rTip = rHand + rDir * 0.07;
  if (devicesOn.contains(DeviceType.pulseOximeter)) {
    final side = rDir.cross(_up).unit;
    final upN = side.cross(rDir).unit;
    m.ellipsoid(
      rTip,
      rDir * 0.034,
      side * 0.028,
      upN * 0.026,
      _Palette.device,
      t: _sphereLo,
      gloss: 0.5,
    );
    m.ellipsoid(
      rTip + upN * 0.022,
      rDir * 0.018,
      side * 0.016,
      upN * 0.006,
      _Palette.scaleDisplay,
      t: _sphereLo,
      gloss: 0.6,
    );
  }
  final gripHand = s[gripSide == GripSide.left ? J.lHand : J.rHand]!;
  final gripAt = gripHand + const V3(0, 0.01, 0.04);
  if (devicesOn.contains(DeviceType.gripStrength)) {
    m.ball(gripAt, const V3(0.05, 0.05, 0.05), _Palette.grip, gloss: 0.45);
  }

  final lA = s[J.lAnkle]!, rA = s[J.rAnkle]!;
  final feet = V3.lerp(lA, rA, 0.5) + const V3(0, -0.09, 0.06);
  return (
    m.freeze(),
    _Anchors(
      {
        DeviceType.weightScale: feet,
        DeviceType.thermometer: face.at(0, 0.085, 0.01),
        DeviceType.pulseOximeter: rTip,
        DeviceType.tensimeter: lUpper,
        DeviceType.gripStrength: gripAt,
      },
      face,
      vLeft,
      vRight,
      seated
          ? [
              V3(lA.x, 0, lA.z + 0.05),
              V3(rA.x, 0, rA.z + 0.05),
              const V3(0, 0, 0.02),
            ]
          : [const V3(0, 0, 0.03)],
    ),
  );
}

// ─── Widget ──────────────────────────────────────────────────────────────────

class ElderAvatar3D extends StatefulWidget {
  final AvatarPhase phase;
  final Gender? gender;
  final GripSide gripSide;

  /// Titik ukur yang disorot beserta keadaannya.
  final Map<DeviceType, AvatarSpot> spots;

  /// Alat yang digambar terpasang di tubuh.
  final Set<DeviceType> devicesOn;

  const ElderAvatar3D({
    super.key,
    required this.phase,
    this.gender,
    this.gripSide = GripSide.left,
    this.spots = const {},
    this.devicesOn = const {},
  });

  @override
  State<ElderAvatar3D> createState() => _ElderAvatar3DState();
}

class _ElderAvatar3DState extends State<ElderAvatar3D>
    with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );
  late final AnimationController _pose = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );
  late Skeleton _from = _skeletonFor(widget.phase, widget.gripSide);
  late Skeleton _to = _from;
  late _Frame _frameFrom = _frameFor(widget.phase);
  late _Frame _frameTo = _frameFrom;
  double _drag = 0;

  // Mesh disimpan; dibangun ulang hanya bila pose/alat berubah.
  Object? _meshKey;
  (_Geo, _Anchors)? _scene;

  @override
  void initState() {
    super.initState();
    if (Motion.enabled) _idle.repeat();
  }

  @override
  void didUpdateWidget(covariant ElderAvatar3D old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase || old.gripSide != widget.gripSide) {
      final t = Curves.easeInOutCubic.transform(_pose.value);
      _from = _lerpSkeleton(_from, _to, t);
      _frameFrom = _lerpFrame(_frameFrom, _frameTo, t);
      _to = _skeletonFor(widget.phase, widget.gripSide);
      _frameTo = _frameFor(widget.phase);
      if (Motion.enabled) {
        _pose.forward(from: 0);
      } else {
        _pose.value = 1;
      }
    }
  }

  (_Geo, _Anchors) _sceneFor(double t) {
    final key = Object.hash(
      t,
      _from,
      _to,
      widget.phase,
      widget.gender,
      widget.gripSide,
      Object.hashAllUnordered(widget.devicesOn),
    );
    if (key != _meshKey || _scene == null) {
      _meshKey = key;
      _scene = _buildScene(
        _lerpSkeleton(_from, _to, t),
        widget.phase,
        widget.gender,
        widget.gripSide,
        widget.devicesOn,
      );
    }
    return _scene!;
  }

  @override
  void dispose() {
    _idle.dispose();
    _pose.dispose();
    super.dispose();
  }

  /// Kedip singkat dua kali per siklus 10 detik (0 = terbuka, 1 = tertutup).
  static double _blink(double t) {
    double one(double at) {
      final d = (t - at).abs() * 10; // detik
      return d > 0.14 ? 0 : 1 - d / 0.14;
    }

    return math.max(one(0.31), math.max(one(0.335), one(0.78)));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Avatar lansia: ${switch (widget.phase) {
            AvatarPhase.standing => 'berdiri di timbangan',
            AvatarPhase.seated => 'duduk untuk tensi',
            AvatarPhase.gripping => 'meremas alat genggam',
            AvatarPhase.finished => 'selesai',
          }}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) =>
            setState(() => _drag += d.delta.dx * 0.012),
        onDoubleTap: () => setState(() => _drag = 0),
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_idle, _pose]),
            builder: (context, _) {
              final t = _idle.value;
              final poseT = Curves.easeInOutCubic.transform(_pose.value);
              // Sudut putar dibulatkan: badan hanya digambar ulang bila
              // putarannya benar-benar berubah (hemat CPU di iMin).
              var yaw =
                  -0.42 +
                  (Motion.enabled ? 0.3 * math.sin(2 * math.pi * t) : 0) +
                  _drag;
              yaw = (yaw / 0.005).roundToDouble() * 0.005;
              final pulse = Motion.enabled
                  ? 0.5 + 0.5 * math.sin(2 * math.pi * t * 6)
                  : 0.6;
              final (geo, anchors) = _sceneFor(poseT);
              final frame = _lerpFrame(_frameFrom, _frameTo, poseT);
              return Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _AvatarPainter(
                        geo: geo,
                        anchors: anchors,
                        yaw: yaw,
                        blink: Motion.enabled ? _blink(t) : 0,
                        frame: frame,
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _SpotsPainter(
                      anchors: anchors,
                      spots: widget.spots,
                      yaw: yaw,
                      pulse: pulse,
                      frame: frame,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Pelukis ─────────────────────────────────────────────────────────────────

/// Kamera bersama untuk pelukis badan & titik ukur.
mixin _Camera {
  static const pitch = 0.15;
  static const camDist = 4.2;

  double get yaw;
  _Frame get frame;

  late double _cy, _sy, _cp, _sp, _focal, _ox, _oy;

  void _setup(Size size) {
    _cy = math.cos(yaw);
    _sy = math.sin(yaw);
    _cp = math.cos(pitch);
    _sp = math.sin(pitch);
    final k = math.min(
      size.height * 0.9 / frame.height,
      size.width * 0.92 / frame.width,
    );
    _focal = k * camDist;
    _ox = size.width / 2;
    _oy = size.height * 0.5;
  }

  /// Dunia → kamera.
  V3 _view(V3 p) {
    final yy = p.y - frame.centerY;
    final x1 = p.x * _cy + p.z * _sy;
    final z1 = -p.x * _sy + p.z * _cy;
    return V3(x1, yy * _cp - z1 * _sp, yy * _sp + z1 * _cp);
  }

  V3 _rot(double x, double y, double z) {
    final x1 = x * _cy + z * _sy;
    final z1 = -x * _sy + z * _cy;
    return V3(x1, y * _cp - z1 * _sp, y * _sp + z1 * _cp);
  }

  double _scaleAt(V3 v) => _focal / (camDist - v.z);

  Offset _project(V3 v) {
    final k = _scaleAt(v);
    return Offset(_ox + v.x * k, _oy - v.y * k);
  }

  Offset _at(V3 world) => _project(_view(world));
}

class _AvatarPainter extends CustomPainter with _Camera {
  final _Geo geo;
  final _Anchors anchors;
  @override
  final double yaw;
  final double blink;
  @override
  final _Frame frame;

  _AvatarPainter({
    required this.geo,
    required this.anchors,
    required this.yaw,
    required this.blink,
    required this.frame,
  });

  static const _camDist = _Camera.camDist;

  // Lampu dalam ruang kamera.
  static final _key = const V3(-0.45, 0.7, 0.55).unit;
  static final _fill = const V3(0.75, 0.1, 0.45).unit;
  static final _half = (_key + const V3(0, 0, 1)).unit;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _setup(size);

    // Panggung lembut di belakang avatar.
    final stageC = Offset(_ox, _oy);
    final stageR = math.min(size.width, size.height) * 0.5;
    canvas.drawCircle(
      stageC,
      stageR,
      Paint()
        ..shader = ui.Gradient.radial(stageC, stageR, [
          AppColors.primarySoft,
          AppColors.primarySoft.withValues(alpha: 0),
        ]),
    );

    // Bayangan lantai: lebar & lembut, lalu bayangan kontak yang lebih pekat.
    void floorShadow(V3 at, double r, int alpha) {
      final v = _view(at);
      final c = _project(v);
      final s = _scaleAt(v);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(1, 0.3);
      canvas.drawCircle(
        Offset.zero,
        r * s,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, r * s, [
            Color.fromARGB(alpha, 0x24, 0x29, 0x35),
            const Color(0x00242935),
          ]),
      );
      canvas.restore();
    }

    floorShadow(
      V3(0, 0, anchors.floorSpots.length > 1 ? 0.08 : 0.03),
      0.46,
      0x2A,
    );
    for (final f in anchors.floorSpots) {
      floorShadow(f, anchors.floorSpots.length > 1 ? 0.11 : 0.3, 0x30);
    }

    _paintMesh(canvas);
    _paintFace(canvas);
  }

  void _paintMesh(Canvas canvas) {
    final mesh = geo;
    final n = mesh.vertexCount;
    final sx = Float64List(n), sy = Float64List(n), vz = Float64List(n);
    final vx = Float64List(n), vy = Float64List(n);
    final nx = Float64List(n), ny = Float64List(n), nz = Float64List(n);
    final col = Int32List(n);
    final kx = _key.x, ky = _key.y, kz = _key.z;
    final fx0 = _fill.x, fy0 = _fill.y, fz0 = _fill.z;
    final hx = _half.x, hy = _half.y, hz = _half.z;
    final cy = _cy, sny = _sy, cp = _cp, sp = _sp, cY = frame.centerY;
    final focal = _focal, ox = _ox, oy = _oy;
    final pp = mesh.p, pn = mesh.n, pc = mesh.c, pg = mesh.g;
    for (var k = 0; k < n; k++) {
      final i3 = k * 3;
      // Posisi dunia → kamera.
      final x = pp[i3], yy = pp[i3 + 1] - cY, z = pp[i3 + 2];
      final x1 = x * cy + z * sny;
      final z1 = -x * sny + z * cy;
      final y2 = yy * cp - z1 * sp;
      final z2 = yy * sp + z1 * cp;
      vx[k] = x1;
      vy[k] = y2;
      vz[k] = z2;
      final s = focal / (_camDist - z2);
      sx[k] = ox + x1 * s;
      sy[k] = oy - y2 * s;
      // Normal → kamera.
      final a = pn[i3], b = pn[i3 + 1], c = pn[i3 + 2];
      final qx = a * cy + c * sny;
      final qz1 = -a * sny + c * cy;
      final qy = b * cp - qz1 * sp;
      final qz = b * sp + qz1 * cp;
      nx[k] = qx;
      ny[k] = qy;
      nz[k] = qz;

      // Lambert setengah-bungkus (lebih lembut untuk kulit & kain).
      final dk = math.max(0.0, (qx * kx + qy * ky + qz * kz + 0.2) / 1.2);
      final df = math.max(0.0, qx * fx0 + qy * fy0 + qz * fz0);
      final hemi = 0.5 + 0.5 * qy; // 1 = menghadap langit
      final rimBase = 1 - math.max(0.0, qz);
      final rim = rimBase * rimBase * rimBase * 0.1;
      var spec = 0.0;
      final gloss = pg[k];
      if (gloss > 0) {
        final nh = qx * hx + qy * hy + qz * hz;
        if (nh > 0.8) {
          final s2 = nh * nh, s4 = s2 * s2, s8 = s4 * s4, s16 = s8 * s8;
          spec = s16 * s8 * gloss * 0.4;
        }
      }
      final base = pc[k];
      // Cahaya per kanal: hangat dari lampu utama, sejuk dari lampu isi & langit.
      final lr = 0.48 + 0.08 * hemi + 0.5 * dk + 0.1 * df;
      final lg = 0.48 + 0.09 * hemi + 0.48 * dk + 0.11 * df;
      final lb = 0.5 + 0.11 * hemi + 0.44 * dk + 0.13 * df;
      final add = 255 * spec;
      final r = (((base >> 16) & 0xFF) * lr + 0xDD * rim + add).round();
      final g = (((base >> 8) & 0xFF) * lg + 0xE6 * rim + add).round();
      final bl = ((base & 0xFF) * lb + 0xFF * rim + add).round();
      col[k] =
          (0xFF << 24) |
          ((r > 255 ? 255 : r) << 16) |
          ((g > 255 ? 255 : g) << 8) |
          (bl > 255 ? 255 : bl);
    }

    // Segitiga yang menghadap kamera, urut jauh → dekat.
    final tri = mesh.i;
    final tc = tri.length ~/ 3;
    final keep = <int>[];
    final keepHead = <int>[];
    final depth = Float64List(tc);
    for (var t = 0; t < tc; t++) {
      final a = tri[t * 3], b = tri[t * 3 + 1], c = tri[t * 3 + 2];
      // Normal bidang segitiga (arahnya disamakan dengan normal titik, jadi
      // tidak bergantung urutan sudut), lalu cek menghadap kamera.
      final e1x = vx[b] - vx[a], e1y = vy[b] - vy[a], e1z = vz[b] - vz[a];
      final e2x = vx[c] - vx[a], e2y = vy[c] - vy[a], e2z = vz[c] - vz[a];
      var fx = e1y * e2z - e1z * e2y;
      var fy = e1z * e2x - e1x * e2z;
      var fz = e1x * e2y - e1y * e2x;
      if (fx * (nx[a] + nx[b] + nx[c]) +
              fy * (ny[a] + ny[b] + ny[c]) +
              fz * (nz[a] + nz[b] + nz[c]) <
          0) {
        fx = -fx;
        fy = -fy;
        fz = -fz;
      }
      final cz = (vz[a] + vz[b] + vz[c]) / 3;
      final cx = (vx[a] + vx[b] + vx[c]) / 3;
      final cy = (vy[a] + vy[b] + vy[c]) / 3;
      if (fx * -cx + fy * -cy + fz * (_camDist - cz) <= 0) continue;
      depth[t] = cz + (mesh.b[a] + mesh.b[b] + mesh.b[c]) / 3;
      (mesh.l[a] == 1 ? keepHead : keep).add(t);
    }

    void draw(List<int> list) {
      list.sort((p, q) => depth[p].compareTo(depth[q]));
      final pos = Float32List(list.length * 6);
      final colors = Int32List(list.length * 3);
      var o = 0, oc = 0;
      for (final t in list) {
        for (var e = 0; e < 3; e++) {
          final k = tri[t * 3 + e];
          pos[o++] = sx[k];
          pos[o++] = sy[k];
          colors[oc++] = col[k];
        }
      }
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        pos,
        colors: colors,
      );
      canvas.drawVertices(vertices, BlendMode.dst, Paint());
      vertices.dispose();
    }

    draw(keep);
    _paintCollar(canvas);
    draw(keepHead);
  }

  /// Kerah V: kemeja krem di dalam, tepi kardigan sedikit lebih gelap.
  void _paintCollar(Canvas canvas) {
    final l = anchors.vLeft, r = anchors.vRight;
    if (l.length < 2) return;
    final ol = l.map(_at).toList(), orr = r.map(_at).toList();
    final path = Path()..moveTo(ol.first.dx, ol.first.dy);
    for (final q in ol.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    for (final q in orr.reversed) {
      path.lineTo(q.dx, q.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = _Palette.shirt);
    final s = _scaleAt(_view(l.first));
    final edge = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, 0.012 * s)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final side in [ol, orr]) {
      final p = Path()..moveTo(side.first.dx, side.first.dy);
      for (final q in side.skip(1)) {
        p.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(p, edge);
    }
  }

  /// Wajah 2D dari titik 3D: alis, mata (berkedip), kacamata, pipi, senyum,
  /// garis senyum, kumis (laki-laki).
  void _paintFace(Canvas canvas) {
    final f = anchors.face;
    final s = _scaleAt(_view(f.center));
    bool visible(double fx, double fy) {
      final nn = f.normalAt(fx, fy);
      return _rot(nn.x, nn.y, nn.z).z > 0.12;
    }

    Path curve(List<V3> pts) {
      final path = Path();
      final o = pts.map(_at).toList();
      path.moveTo(o.first.dx, o.first.dy);
      if (o.length == 3) {
        // Kurva melalui titik tengah.
        final c = o[1] * 2 - (o[0] + o[2]) / 2;
        path.quadraticBezierTo(c.dx, c.dy, o[2].dx, o[2].dy);
      } else {
        for (final p in o.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
      }
      return path;
    }

    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.0, w * s);

    // Pipi merona.
    for (final sx in [1.0, -1.0]) {
      if (!visible(0.072 * sx, -0.034)) continue;
      final c = _at(f.at(0.072 * sx, -0.034));
      final r = 0.03 * s;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [
            const Color(0x48EE7C86),
            const Color(0x00EE7C86),
          ]),
      );
    }

    final lid = blink.clamp(0.0, 1.0);
    for (final sx in [1.0, -1.0]) {
      const ex = 0.046, ey = 0.014;
      if (!visible(ex * sx, ey)) continue;
      // Alis putih keabuan, tebal.
      canvas.drawPath(
        curve([
          f.at(0.022 * sx, 0.05),
          f.at(0.047 * sx, 0.062),
          f.at(0.074 * sx, 0.05),
        ]),
        stroke(const Color(0xFFBDB6AE), 0.011),
      );
      final e = _at(f.at(ex * sx, ey));
      final ew = 0.017 * s, eh = 0.021 * s * (1 - lid);
      if (lid < 0.85) {
        canvas.drawOval(
          Rect.fromCenter(center: e, width: ew, height: eh),
          Paint()..color = const Color(0xFF3A2E2A),
        );
        canvas.drawCircle(
          e + Offset(-0.003 * s, -0.004 * s * (1 - lid)),
          math.max(0.8, 0.0035 * s),
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
      }
      // Kelopak atas (sedikit turun, khas lansia) / mata terpejam.
      canvas.drawPath(
        curve([
          f.at((ex - 0.014) * sx, ey + 0.004 - 0.012 * lid),
          f.at(ex * sx, ey + 0.012 - 0.016 * lid),
          f.at((ex + 0.015) * sx, ey + 0.002 - 0.012 * lid),
        ]),
        stroke(const Color(0xCC5B4339), 0.0045),
      );
      // Kerut halus di sudut mata.
      canvas.drawPath(
        curve([f.at(0.072 * sx, 0.016), f.at(0.083 * sx, 0.006)]),
        stroke(const Color(0x40805A48), 0.003),
      );
    }

    // Kacamata (bingkai bulat di depan wajah, gagang ke telinga).
    final frameP = stroke(const Color(0xFF7A5E4C), 0.0048);
    Offset? innerL, innerR;
    for (final sx in [1.0, -1.0]) {
      const ex = 0.046, ey = 0.012;
      if (!visible(ex * sx, ey)) continue;
      final c = f.at(ex * sx, ey, 0.014);
      final pts = <V3>[
        for (var k = 0; k <= 24; k++)
          c +
              V3(
                math.cos(2 * math.pi * k / 24) * 0.031,
                math.sin(2 * math.pi * k / 24) * 0.026,
                0,
              ),
      ];
      final ring = curve(pts)..close();
      canvas.drawPath(
        ring,
        Paint()..color = Colors.white.withValues(alpha: 0.14),
      );
      canvas.drawPath(ring, frameP);
      // Kilau lensa.
      canvas.drawPath(
        curve([
          c + const V3(-0.018, 0.012, 0),
          c + const V3(-0.008, 0.019, 0),
          c + const V3(0.004, 0.02, 0),
        ]),
        stroke(Colors.white.withValues(alpha: 0.7), 0.003),
      );
      final inner = _at(c + V3(-0.031 * sx, 0.004, 0));
      if (sx > 0) {
        innerL = inner;
      } else {
        innerR = inner;
      }
      // Gagang hanya di sisi yang menghadap kamera.
      if (visible(0.11 * sx, 0.0)) {
        canvas.drawPath(
          curve([c + V3(0.031 * sx, 0.004, 0), f.at(0.118 * sx, 0.012, 0.004)]),
          frameP,
        );
      }
    }
    if (innerL != null && innerR != null) {
      final mid = _at(f.at(0, 0.024, 0.02));
      canvas.drawPath(
        Path()
          ..moveTo(innerL.dx, innerL.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, innerR.dx, innerR.dy),
        frameP,
      );
    }

    if (f.gender == Gender.male && visible(0, -0.04)) {
      // Kumis putih: lebar & pendek, sedikit terangkat di ujung.
      const pts = [
        (-0.035, -0.049),
        (-0.021, -0.039),
        (-0.007, -0.0365),
        (0.0, -0.0385),
        (0.007, -0.0365),
        (0.021, -0.039),
        (0.035, -0.049),
        (0.03, -0.0525),
        (0.016, -0.049),
        (0.004, -0.0475),
        (0.0, -0.0485),
        (-0.004, -0.0475),
        (-0.016, -0.049),
        (-0.03, -0.0525),
      ];
      final o = [for (final (x, y) in pts) _at(f.at(x, y, 0.003))];
      final path = Path()..moveTo(o.first.dx, o.first.dy);
      for (final q in o.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFFDCD7D1));
      canvas.drawPath(path, stroke(const Color(0x66A0968D), 0.002));
    }

    if (visible(0, -0.07)) {
      // Senyum.
      canvas.drawPath(
        curve([f.at(0.026, -0.066), f.at(0, -0.079), f.at(-0.026, -0.066)]),
        stroke(const Color(0xFF9C5650), 0.0065),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter old) =>
      old.geo != geo ||
      old.yaw != yaw ||
      old.blink != blink ||
      old.frame != frame ||
      old.anchors != anchors;
}

/// Titik ukur yang berdenyut (digambar terpisah supaya badan tidak perlu
/// digambar ulang tiap frame).
class _SpotsPainter extends CustomPainter with _Camera {
  final _Anchors anchors;
  final Map<DeviceType, AvatarSpot> spots;
  @override
  final double yaw;
  final double pulse;
  @override
  final _Frame frame;

  _SpotsPainter({
    required this.anchors,
    required this.spots,
    required this.yaw,
    required this.pulse,
    required this.frame,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || spots.isEmpty) return;
    _setup(size);
    _paintSpots(canvas);
    // Kotak kecil (kartu panduan di layar genggam): tanpa label supaya rapi.
    if (size.height >= 220 && size.width >= 200) _paintLabels(canvas, size);
  }

  static Color _colorOf(AvatarSpot s) => switch (s) {
    AvatarSpot.active => AppColors.primary,
    AvatarSpot.ready => AppColors.blueDenim,
    AvatarSpot.gate => AppColors.orangeAction,
    AvatarSpot.done => AppColors.darkGreen,
  };

  /// Label nama alat di samping titik ukur, dengan garis penunjuk. Label di
  /// sisi kiri/kanan tubuh, disusun dari atas ke bawah supaya tidak bertumpuk.
  void _paintLabels(Canvas canvas, Size size) {
    final fontSize = (size.height * 0.036).clamp(11.0, 15.0);
    final items = <(Offset, DeviceType, AvatarSpot)>[
      for (final e in spots.entries)
        if (anchors.spots[e.key] case final p?) (_at(p), e.key, e.value),
    ];
    for (final left in [true, false]) {
      final side = [
        for (final it in items)
          if ((it.$1.dx < _ox) == left) it,
      ]..sort((a, b) => a.$1.dy.compareTo(b.$1.dy));
      var minY = 4.0;
      for (final (c, type, state) in side) {
        final color = _colorOf(state);
        final done = state == AvatarSpot.done;
        final tp = TextPainter(
          text: TextSpan(
            style: TextStyle(
              fontFamily: AppText.family,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: done ? AppColors.darkGreen : Colors.white,
            ),
            children: [
              // Lexend tidak punya glyph ✓ → pakai ikon Material.
              if (done)
                TextSpan(
                  text:
                      '${String.fromCharCode(Icons.check_rounded.codePoint)} ',
                  style: TextStyle(fontFamily: Icons.check_rounded.fontFamily),
                ),
              TextSpan(text: type.shortLabel),
            ],
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final w = tp.width + fontSize * 1.1;
        final h = tp.height + fontSize * 0.5;
        final x = left
            ? math.max(4.0, c.dx - size.width * 0.18 - w)
            : math.min(size.width - 4 - w, c.dx + size.width * 0.18);
        final y = math.max(minY, c.dy - h / 2).clamp(4.0, size.height - h - 4);
        minY = y + h + 6;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(h / 2),
        );
        final anchor = Offset(left ? x + w : x, y + h / 2);
        canvas.drawLine(
          c,
          anchor,
          Paint()
            ..color = color.withValues(alpha: 0.6)
            ..strokeWidth = 1.5,
        );
        canvas.drawRRect(
          rect.shift(const Offset(0, 1.5)),
          Paint()..color = Colors.black.withValues(alpha: 0.08),
        );
        canvas.drawRRect(
          rect,
          Paint()..color = done ? AppColors.greenSoft : color,
        );
        if (done) {
          canvas.drawRRect(
            rect,
            Paint()
              ..color = AppColors.darkGreen.withValues(alpha: 0.5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
        tp.paint(
          canvas,
          Offset(x + (w - tp.width) / 2, y + (h - tp.height) / 2),
        );
      }
    }
  }

  void _paintSpots(Canvas canvas) {
    for (final e in spots.entries) {
      final p = anchors.spots[e.key];
      if (p == null) continue;
      final v = _view(p);
      final c = _project(v);
      final s = _scaleAt(v);
      final color = switch (e.value) {
        AvatarSpot.active => AppColors.primary,
        AvatarSpot.ready => AppColors.blueDenim,
        AvatarSpot.gate => AppColors.orange,
        AvatarSpot.done => AppColors.darkGreen,
      };
      final r = 0.05 * s;
      if (e.value == AvatarSpot.done) {
        canvas.drawCircle(c, r * 0.5, Paint()..color = Colors.white);
        canvas.drawCircle(c, r * 0.42, Paint()..color = color);
        final tick = Path()
          ..moveTo(c.dx - r * 0.2, c.dy)
          ..lineTo(c.dx - r * 0.04, c.dy + r * 0.16)
          ..lineTo(c.dx + r * 0.22, c.dy - r * 0.16);
        canvas.drawPath(
          tick,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.4, r * 0.1)
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }
      final strong = e.value != AvatarSpot.ready;
      final glowR = r * (1.2 + (strong ? 0.6 : 0.3) * pulse);
      canvas.drawCircle(
        c,
        glowR,
        Paint()
          ..shader = ui.Gradient.radial(c, glowR, [
            color.withValues(alpha: strong ? 0.45 : 0.25),
            color.withValues(alpha: 0),
          ]),
      );
      canvas.drawCircle(
        c,
        r * 0.5,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        c,
        r * 0.5,
        Paint()
          ..color = color.withValues(alpha: strong ? 0.95 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, r * 0.12),
      );
      canvas.drawCircle(c, r * 0.2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotsPainter old) =>
      old.yaw != yaw ||
      old.frame != frame ||
      old.anchors != anchors ||
      !mapEquals(old.spots, spots) ||
      (spots.isNotEmpty && old.pulse != pulse);
}
