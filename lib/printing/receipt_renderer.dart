import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app/theme.dart';
import '../data/app_settings.dart';
import 'receipt_content.dart';

/// Menggambar struk sebagai gambar hitam-putih selebar area cetak printer
/// (384 titik untuk 58 mm, 576 titik untuk 80 mm). Gambar yang sama dipakai
/// untuk pratinjau di layar dan untuk dicetak, jadi yang dilihat = yang tercetak.
class ReceiptRenderer {
  ReceiptRenderer._();

  static const _black = Color(0xFF000000);
  static const _white = Color(0xFFFFFFFF);
  static ui.Image? _logo;

  static Future<ui.Image?> _loadLogo() async {
    if (_logo != null) return _logo;
    try {
      final data = await rootBundle.load('assets/images/receipt_logo.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      _logo = (await codec.getNextFrame()).image;
    } catch (_) {
      _logo = null;
    }
    return _logo;
  }

  static Future<Uint8List> renderPng(
    ReceiptContent c, {
    required PaperWidth paper,
  }) async {
    final width = paper.dots.toDouble();
    // Hemat kertas: huruf tidak diperbesar di 80 mm — lebar ekstra dipakai
    // untuk dua kolom hasil, bukan huruf yang lebih tinggi.
    const pad = 6.0;
    final inner = width - pad * 2;
    final twoCol = paper == PaperWidth.mm80;
    const colGap = 18.0;
    final colW = (inner - colGap) / 2;

    TextStyle style(double size, {FontWeight weight = FontWeight.w500}) =>
        TextStyle(
          fontFamily: AppText.family,
          fontSize: size,
          fontWeight: weight,
          color: _black,
          height: 1.2,
        );

    final body = style(21);
    final bodyBold = style(21, weight: FontWeight.w700);
    final small = style(16);
    final heading = style(17, weight: FontWeight.w700);
    final title = style(20, weight: FontWeight.w700);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    var y = pad;

    TextPainter layout(
      String text,
      TextStyle s, {
      double? maxWidth,
      TextAlign align = TextAlign.left,
    }) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: s),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth ?? inner);
      return tp;
    }

    void centered(String text, TextStyle s, {double gapAfter = 2}) {
      final tp = layout(text, s, align: TextAlign.center);
      tp.paint(canvas, Offset(pad + (inner - tp.width) / 2, y));
      y += tp.height + gapAfter;
    }

    void divider({bool dashed = true, double gap = 6}) {
      y += gap / 2;
      final paint = Paint()
        ..color = _black
        ..strokeWidth = 2;
      if (dashed) {
        var x = pad;
        while (x < width - pad) {
          canvas.drawLine(
            Offset(x, y),
            Offset((x + 8).clamp(0, width - pad), y),
            paint,
          );
          x += 14;
        }
      } else {
        canvas.drawLine(Offset(pad, y), Offset(width - pad, y), paint);
      }
      y += gap / 2 + 2;
    }

    /// Label kiri, nilai kanan dalam satu kolom selebar [w] mulai [x].
    /// Mengembalikan tinggi yang dipakai. Tidak muat → nilai turun ke bawah.
    double cell(
      double x,
      double w,
      String label,
      String value, {
      TextStyle? labelStyle,
      TextStyle? valueStyle,
      bool flagged = false,
    }) {
      final ls = labelStyle ?? body;
      final vs = valueStyle ?? bodyBold;
      final shown = flagged ? '$value *' : value;
      final lp = layout(label, ls, maxWidth: w * 0.6);
      final vp = layout(shown, vs, maxWidth: w, align: TextAlign.right);
      if (lp.width + vp.width + 10 <= w && vp.height <= lp.height * 1.5) {
        lp.paint(canvas, Offset(x, y));
        vp.paint(
          canvas,
          Offset(x + w - vp.width, y + (lp.height - vp.height) / 2),
        );
        return (lp.height > vp.height ? lp.height : vp.height) + 2;
      }
      lp.paint(canvas, Offset(x, y));
      final vp2 = layout(shown, vs, maxWidth: w, align: TextAlign.right);
      vp2.paint(canvas, Offset(x + w - vp2.width, y + lp.height));
      return lp.height + vp2.height + 2;
    }

    bool fitsHalf(ReceiptLine l) {
      final shown = l.flagged ? '${l.value} *' : l.value;
      final lw = layout(l.label, body, maxWidth: double.infinity).width;
      final vw = layout(shown, bodyBold, maxWidth: double.infinity).width;
      return lw + vw + 10 <= colW;
    }

    // ── Kepala ──
    final logo = await _loadLogo();
    if (logo != null) {
      final w = inner * (twoCol ? 0.36 : 0.46);
      final h = w * logo.height / logo.width;
      final dst = Rect.fromLTWH(pad + (inner - w) / 2, y, w, h);
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
      y += h + 4;
    } else {
      centered('CaritaHub', title);
    }
    centered(c.title.toUpperCase(), heading, gapAfter: 0);
    if (c.locationName != null) centered(c.locationName!, small, gapAfter: 0);
    divider(dashed: false);

    // ── Identitas: nama besar, sisanya diringkas ke satu baris ──
    String? idValue(String label) =>
        c.identity.where((l) => l.label == label).firstOrNull?.value;
    final name = idValue('Nama');
    if (name != null) {
      final tp = layout(name, style(23, weight: FontWeight.w700));
      tp.paint(canvas, Offset(pad, y));
      y += tp.height + 1;
    }
    final who = [
      ?idValue('Jenis kelamin'),
      if (idValue('Umur') case final u?) u.replaceAll(' tahun', ' th'),
    ].join(' · ');
    y += cell(
      pad,
      inner,
      who,
      idValue('Tanggal') ?? '',
      labelStyle: body,
      valueStyle: body,
    );
    for (final l in c.identity) {
      const merged = {'Nama', 'Jenis kelamin', 'Umur', 'Tanggal', 'No.'};
      if (merged.contains(l.label)) continue;
      y += cell(pad, inner, l.label, l.value, valueStyle: body);
    }

    // ── Hasil ──
    if (c.sections.isEmpty) {
      divider();
      centered('Belum ada hasil pengukuran', body);
    }
    for (final s in c.sections) {
      divider();
      final tp = layout(s.title.toUpperCase(), heading);
      tp.paint(canvas, Offset(pad, y));
      y += tp.height + 2;
      // 80 mm: baris pendek berpasangan dua kolom; yang panjang selebar penuh.
      ReceiptLine? pending;
      void flush() {
        if (pending == null) return;
        y += cell(
          pad,
          colW,
          pending!.label,
          pending!.value,
          flagged: pending!.flagged,
        );
        pending = null;
      }

      for (final l in s.lines) {
        if (twoCol && fitsHalf(l)) {
          if (pending == null) {
            pending = l;
            continue;
          }
          final left = pending!;
          pending = null;
          final h1 = cell(
            pad,
            colW,
            left.label,
            left.value,
            flagged: left.flagged,
          );
          final h2 = cell(
            pad + colW + colGap,
            colW,
            l.label,
            l.value,
            flagged: l.flagged,
          );
          y += h1 > h2 ? h1 : h2;
        } else {
          flush();
          y += cell(pad, inner, l.label, l.value, flagged: l.flagged);
        }
      }
      flush();
    }

    // ── Kaki ──
    divider(dashed: false);
    final note = layout(
      '${c.hasFlagged ? '* Di luar rentang normal. ' : ''}'
      'Bukan diagnosis — konsultasikan dengan tenaga kesehatan.',
      small,
    );
    note.paint(canvas, Offset(pad, y));
    y += note.height + 2;
    centered(
      [
        'No. ${c.recordId}',
        if (c.printNumber > 1) 'cetak ke-${c.printNumber}',
        'CaritaHub Health Station Lite',
      ].join(' · '),
      small,
      gapAfter: 0,
    );
    y += 4;
    centered(
      'Powering people who care',
      style(17, weight: FontWeight.w700),
      gapAfter: 0,
    );
    y += pad;

    final content = recorder.endRecording();

    // Latar putih di bawah semua isi.
    final height = y.ceil();
    final r2 = ui.PictureRecorder();
    final c2 = Canvas(r2);
    c2.drawRect(
      Rect.fromLTWH(0, 0, width, height.toDouble()),
      Paint()..color = _white,
    );
    c2.drawPicture(content);
    final image = await r2.endRecording().toImage(width.toInt(), height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}
