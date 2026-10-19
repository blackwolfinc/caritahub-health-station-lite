import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../app/sound.dart';
import '../app/theme.dart';

/// Susunan tombol keyboard layar.
enum KeypadLayout {
  /// Huruf untuk nama.
  letters,

  /// Angka bulat (NIK, umur).
  digits,

  /// Angka dengan koma (tinggi badan).
  decimal,
}

/// Sisipkan [text] di posisi kursor (atau ganti teks terpilih), lalu jalankan
/// formatter kolom supaya aturannya sama dengan mengetik biasa.
/// [capitalizeWords] meniru TextCapitalization.words untuk kolom nama.
bool typeInto(
  TextEditingController c,
  String text, {
  List<TextInputFormatter> formatters = const [],
  bool capitalizeWords = false,
}) {
  final old = c.value;
  final sel = old.selection.isValid
      ? old.selection
      : TextSelection.collapsed(offset: old.text.length);
  if (capitalizeWords) {
    final before = old.text.substring(0, sel.start);
    final startOfWord = before.isEmpty || before.endsWith(' ');
    text = startOfWord ? text.toUpperCase() : text.toLowerCase();
  }
  var next = TextEditingValue(
    text: old.text.replaceRange(sel.start, sel.end, text),
    selection: TextSelection.collapsed(offset: sel.start + text.length),
  );
  for (final f in formatters) {
    next = f.formatEditUpdate(old, next);
  }
  if (next.text == old.text) return false;
  c.value = next;
  return true;
}

/// Hapus satu karakter sebelum kursor, atau teks yang sedang dipilih.
bool backspaceIn(TextEditingController c) {
  final old = c.value;
  final sel = old.selection.isValid
      ? old.selection
      : TextSelection.collapsed(offset: old.text.length);
  if (sel.isCollapsed && sel.start == 0) return false;
  final start = sel.isCollapsed ? sel.start - 1 : sel.start;
  c.value = TextEditingValue(
    text: old.text.replaceRange(start, sel.end, ''),
    selection: TextSelection.collapsed(offset: start),
  );
  return true;
}

/// Keyboard besar di dalam layar untuk tablet: tidak menutupi form dan
/// tombolnya mudah ditekan. Bungkus [TextFieldTapRegion] supaya kolom yang
/// sedang diisi tidak kehilangan fokus saat tombol ditekan.
class OnScreenKeyboard extends StatelessWidget {
  final KeypadLayout layout;

  /// Nama kolom yang sedang diisi, mis. "Nama".
  final String fieldLabel;
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  /// Pindah ke kolom berikutnya; null bila sudah kolom terakhir.
  final VoidCallback? onNext;

  /// Mulai pengukuran; null bila belum bisa (nama kosong).
  final VoidCallback? onSubmit;

  /// Kembali ke keyboard sistem.
  final VoidCallback? onClose;

  /// Tinggi tombol; di tablet lanskap dibuat lebih tinggi supaya keyboard
  /// setinggi form di sebelahnya.
  final double keyHeight;

  /// Teks & ikon tombol utama (bawaan: mulai pengukuran).
  final String submitLabel;
  final IconData submitIcon;

  const OnScreenKeyboard({
    super.key,
    required this.layout,
    required this.fieldLabel,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    this.onNext,
    this.onSubmit,
    this.onClose,
    this.keyHeight = 60,
    this.submitLabel = 'Mulai',
    this.submitIcon = Icons.monitor_heart_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      child: Container(
        key: const Key('onscreen_keyboard'),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.keyboard_alt_outlined,
                  size: 22,
                  color: AppColors.primary,
                ),
                const Gap(8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'Mengisi: ',
                      style: AppText.w400(15, AppColors.grey4),
                      children: [
                        TextSpan(text: fieldLabel, style: AppText.w700(15)),
                      ],
                    ),
                  ),
                ),
                if (onClose != null)
                  TextButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.keyboard_hide_outlined, size: 20),
                    label: const Text('Keyboard sistem'),
                  ),
              ],
            ),
            const Gap(12),
            if (layout == KeypadLayout.letters)
              _letters()
            else
              Align(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _numbers(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(List<Widget> keys) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: keys),
  );

  Widget _char(String c, {int flex = 10}) => _Key(
    height: keyHeight,
    flex: flex,
    keyId: 'kb_$c',
    onTap: () => onKey(c),
    child: Text(c, style: AppText.w600(22)),
  );

  Widget _backspace({int flex = 10}) => _Key(
    height: keyHeight,
    flex: flex,
    keyId: 'kb_backspace',
    kind: _KeyKind.action,
    repeat: true,
    onTap: onBackspace,
    child: const Icon(Icons.backspace_outlined, size: 26),
  );

  Widget _next({int flex = 10}) => _Key(
    height: keyHeight,
    flex: flex,
    keyId: 'kb_next',
    kind: _KeyKind.action,
    onTap: onNext,
    // Layar genggam: tombol sempit, cukup ikon panah.
    child: LayoutBuilder(
      builder: (context, c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.maxWidth >= 100) ...[
            Flexible(
              child: Text(
                'Lanjut',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.w600(17, AppColors.primary),
              ),
            ),
            const Gap(4),
          ],
          const Icon(Icons.arrow_forward_rounded, size: 24),
        ],
      ),
    ),
  );

  Widget _submit({int flex = 10}) => _Key(
    height: keyHeight,
    flex: flex,
    keyId: 'kb_submit',
    kind: _KeyKind.primary,
    onTap: onSubmit,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(submitIcon, size: 22, color: Colors.white),
        const Gap(6),
        Flexible(
          child: Text(
            submitLabel,
            overflow: TextOverflow.ellipsis,
            style: AppText.w700(17, Colors.white),
          ),
        ),
      ],
    ),
  );

  Widget _clear() => _Key(
    height: keyHeight,
    keyId: 'kb_clear',
    kind: _KeyKind.action,
    onTap: onClear,
    child: Text('Hapus', style: AppText.w600(17, AppColors.primary)),
  );

  static const _spacer5 = Spacer(flex: 5);

  /// Tiap baris 100 satuan (huruf = 10) supaya tombol huruf selebar mungkin:
  /// di Falcon2 (keyboard ±550 dp) tiap huruf ±49 dp, minimal 44 dp.
  Widget _letters() => Column(
    children: [
      _row([for (final c in 'QWERTYUIOP'.split('')) _char(c)]),
      _row([
        _spacer5,
        for (final c in 'ASDFGHJKL'.split('')) _char(c),
        _spacer5,
      ]),
      _row([
        _spacer5,
        for (final c in 'ZXCVBNM'.split('')) _char(c),
        _char("'"),
        _backspace(flex: 15),
      ]),
      Row(
        children: [
          if (onNext != null) _next(flex: 20) else const Spacer(flex: 20),
          _char('-'),
          _Key(
            height: keyHeight,
            flex: 40,
            keyId: 'kb_space',
            onTap: () => onKey(' '),
            child: Text('spasi', style: AppText.w500(16, AppColors.grey4)),
          ),
          _char('.'),
          _submit(flex: 20),
        ],
      ),
    ],
  );

  Widget _numbers() {
    final decimal = layout == KeypadLayout.decimal;
    return Column(
      children: [
        for (final r in const ['123', '456', '789'])
          _row([for (final c in r.split('')) _char(c)]),
        _row([decimal ? _char(',') : _clear(), _char('0'), _backspace()]),
        // Tinggi: "Hapus" di baris bawah supaya 165 terhapus sekali ketuk.
        Row(
          children: [
            if (decimal) _clear(),
            if (onNext != null) _next(),
            _submit(),
          ],
        ),
      ],
    );
  }
}

enum _KeyKind { char, action, primary }

class _Key extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final int flex;
  final String keyId;
  final _KeyKind kind;
  final double height;

  /// Tahan untuk mengulang (backspace).
  final bool repeat;

  const _Key({
    required this.child,
    required this.onTap,
    required this.keyId,
    this.flex = 10,
    this.kind = _KeyKind.char,
    this.height = 60,
    this.repeat = false,
  });

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  Timer? _timer;

  void _startRepeat() {
    HapticFeedback.mediumImpact();
    _timer = Timer.periodic(
      const Duration(milliseconds: 70),
      (_) => widget.onTap?.call(),
    );
  }

  void _stopRepeat() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final (bg, fg) = switch (widget.kind) {
      _KeyKind.char => (AppColors.lightGrey, AppColors.charcoal),
      _KeyKind.action => (AppColors.primarySoft, AppColors.primary),
      _KeyKind.primary => (AppColors.primary, Colors.white),
    };
    Widget key = Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: Key(widget.keyId),
        borderRadius: BorderRadius.circular(12),
        canRequestFocus: false,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                Sound.play(Sfx.tap);
                widget.onTap!();
              }
            : null,
        child: SizedBox(
          height: widget.height,
          child: Center(
            child: IconTheme.merge(
              data: IconThemeData(color: fg),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    if (enabled && widget.repeat) {
      key = GestureDetector(
        onLongPressStart: (_) => _startRepeat(),
        onLongPressEnd: (_) => _stopRepeat(),
        onLongPressCancel: _stopRepeat,
        child: key,
      );
    }
    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Opacity(opacity: enabled ? 1 : 0.4, child: key),
      ),
    );
  }
}
