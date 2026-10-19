import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_settings.dart';
import '../data/record_store.dart';
import 'printer_service.dart';
import 'receipt_content.dart';
import 'receipt_renderer.dart';

enum PrintJobStatus { queued, printing, done, failed }

class PrintJob {
  final String recordId;
  final String name;
  PrintJobStatus status;
  String? message;
  PrintJob(this.recordId, this.name) : status = PrintJobStatus.queued;
}

/// Antrean cetak di latar belakang: petugas tidak menunggu printer — lansia
/// berikutnya bisa langsung diukur. Gagal cetak tidak menghapus data.
class PrintQueue extends ChangeNotifier {
  PrintQueue._();
  static final PrintQueue instance = PrintQueue._();

  final List<PrintJob> _jobs = [];
  bool _running = false;

  List<PrintJob> get jobs => List.unmodifiable(_jobs);
  int get pending => _jobs
      .where(
        (j) =>
            j.status == PrintJobStatus.queued ||
            j.status == PrintJobStatus.printing,
      )
      .length;
  List<PrintJob> get failed =>
      _jobs.where((j) => j.status == PrintJobStatus.failed).toList();

  /// Dapat diganti di test.
  @visibleForTesting
  Future<PrintResult> Function(Uint8List png) printer =
      PrinterService.instance.printReceipt;

  void enqueue(String recordId, String name) {
    _jobs.removeWhere(
      (j) => j.recordId == recordId && j.status != PrintJobStatus.printing,
    );
    _jobs.add(PrintJob(recordId, name));
    notifyListeners();
    unawaited(_run());
  }

  void retryFailed() {
    for (final j in _jobs) {
      if (j.status == PrintJobStatus.failed) j.status = PrintJobStatus.queued;
    }
    notifyListeners();
    unawaited(_run());
  }

  void dismissFailed() {
    _jobs.removeWhere((j) => j.status == PrintJobStatus.failed);
    notifyListeners();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final job = _jobs.firstWhereOrNullCompat(
          (j) => j.status == PrintJobStatus.queued,
        );
        if (job == null) break;
        job.status = PrintJobStatus.printing;
        notifyListeners();
        final record = RecordStore.instance.byId(job.recordId);
        if (record == null) {
          _jobs.remove(job);
          continue;
        }
        PrintResult result;
        try {
          final settings = AppSettings.instance;
          final png = await ReceiptRenderer.renderPng(
            buildReceipt(record, locationName: settings.locationName),
            paper: settings.paper,
          );
          result = await printer(png);
        } catch (e) {
          result = PrintResult(false, 'Gagal mencetak: $e');
        }
        if (result.ok) {
          // Struk sudah keluar: tetap "berhasil" walau catatan jumlah cetak
          // gagal disimpan — mencoba ulang akan mencetak dobel. Selesai
          // ditandai setelah catatan tersimpan, jadi antrean kosong = tersimpan.
          try {
            await RecordStore.instance.modify(
              record.id,
              (latest) => latest.copyWith(
                printCount: latest.printCount + 1,
                lastPrintedAt: DateTime.now(),
              ),
            );
          } catch (e) {
            debugPrint('[PrintQueue] printCount not saved: $e');
          }
          job.status = PrintJobStatus.done;
          job.message = result.warning;
        } else {
          job.status = PrintJobStatus.failed;
          job.message = result.message;
        }
        notifyListeners();
      }
      // Simpan hanya 20 riwayat cetak terakhir yang berhasil.
      final done = _jobs.where((j) => j.status == PrintJobStatus.done).toList();
      if (done.length > 20) {
        for (final j in done.take(done.length - 20)) {
          _jobs.remove(j);
        }
      }
    } finally {
      _running = false;
    }
  }
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNullCompat(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
