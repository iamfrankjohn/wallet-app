import 'package:flutter/material.dart';

// ── Website-matched design tokens ──────────────────────────────────────────
// Background: #f5f5f0  Card: #ffffff  Border: rgba(0,0,0,.1)
// Green (brand): #1D9E75  Green dark: #0F6E56  Green light: #E3F4EE
// Red: #A32D2D  Red light: #FBEAEA
// Pending: #B8780B  Pending light: #FFF4E0
// Text primary: #1a1a1a  Text secondary: #666  Text muted: #888

class AppTheme {
  static const Color green       = Color(0xFF1D9E75);
  static const Color greenDark   = Color(0xFF0F6E56);
  static const Color greenLight  = Color(0xFFE3F4EE);
  static const Color red         = Color(0xFFA32D2D);
  static const Color redLight    = Color(0xFFFBEAEA);
  static const Color surface     = Color(0xFFF5F5F0);
  static const Color card        = Color(0xFFFFFFFF);
  static const Color border      = Color(0x1A000000); // rgba(0,0,0,.1)
  static const Color textPrimary    = Color(0xFF1A1A1A);
  static const Color textSecondary  = Color(0xFF666666);
  static const Color textMuted      = Color(0xFF888888);
  static const Color pending        = Color(0xFFB8780B);
  static const Color pendingLight   = Color(0xFFFFF4E0);

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: surface,
        fontFamily: '-apple-system',
        appBarTheme: const AppBarTheme(
          backgroundColor: card,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w500,
            color: textPrimary, letterSpacing: -0.2,
          ),
        ),
        cardTheme: CardThemeData(
          color: card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: border, width: 0.5),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFAFAF8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x26000000), width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x26000000), width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: green, width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: card,
          selectedItemColor: green,
          unselectedItemColor: textMuted,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      );
}

String formatAmount(double amount) {
  // Guard against NaN/Infinity: toStringAsFixed returns "NaN" / "Infinity"
  // for these, which has no '.' to split on and would crash parts[1] below.
  if (!amount.isFinite) amount = 0;
  final parts = amount.toStringAsFixed(2).split('.');
  final whole = parts[0];
  final dec = parts[1];
  final buf = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return '₱$buf.$dec';
}

String formatDate(String date) {
  try {
    final dt = DateTime.parse(date);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  } catch (_) {
    return date;
  }
}

String ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1: return '${n}st';
    case 2: return '${n}nd';
    case 3: return '${n}rd';
    default: return '${n}th';
  }
}

// ── Shared UI components ──────────────────────────────────────────────────

/// Pill badge: type (income/bill) or status (paid/pending)
Widget typeBadge(String type) {
  final isIncome = type == 'income';
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: isIncome ? AppTheme.greenLight : AppTheme.redLight,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      isIncome ? 'Income' : 'Bill',
      style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w600,
        color: isIncome ? AppTheme.greenDark : AppTheme.red,
      ),
    ),
  );
}

Widget statusBadge({
  required String status,
  required String type,
  bool locked = false,
  VoidCallback? onTap,
}) {
  final isPaid = status == 'paid';
  final isIncome = type == 'income';
  final label = isPaid
      ? (isIncome ? 'Verified' : 'Paid')
      : (isIncome ? 'Verifying' : 'Pending');
  final color = isPaid ? AppTheme.greenDark : AppTheme.pending;
  final bg    = isPaid ? AppTheme.greenLight : AppTheme.pendingLight;
  final icon  = isPaid ? Icons.check_circle_outline : Icons.access_time;

  Widget badge = Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (locked)
        Icon(Icons.lock_outline, size: 10, color: color)
      else
        Icon(icon, size: 10, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w600, color: color,
      )),
    ]),
  );

  if (onTap != null && !locked) {
    return GestureDetector(onTap: onTap, child: badge);
  }
  return badge;
}

/// Toggle row used in Add forms (type / status)
Widget toggleRow({
  required List<String> values,
  required List<String> labels,
  required List<IconData> icons,
  required String selected,
  required void Function(String) onSelect,
}) {
  return Row(
    children: List.generate(values.length, (i) {
      final val = values[i];
      final isSelected = selected == val;
      Color activeColor;
      if (val == 'income') { activeColor = AppTheme.green; }
      else if (val == 'bill') { activeColor = AppTheme.red; }
      else if (val == 'paid') { activeColor = AppTheme.greenDark; }
      else if (val == 'pending') { activeColor = AppTheme.pending; }
      else { activeColor = AppTheme.green; }

      final bg = isSelected
          ? (val == 'paid' ? AppTheme.greenDark
              : val == 'pending' ? AppTheme.pending
              : val == 'income' ? AppTheme.greenDark
              : AppTheme.red)
          : const Color(0xFFFAFAF8);

      return Expanded(
        child: GestureDetector(
          onTap: () => onSelect(val),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.only(right: i < values.length - 1 ? 8 : 0),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? activeColor : const Color(0x26000000),
                width: 0.5,
              ),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icons[i], size: 15,
                  color: isSelected ? Colors.white : AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(labels[i], style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                fontWeight: FontWeight.w500, fontSize: 13,
              )),
            ]),
          ),
        ),
      );
    }),
  );
}