import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../security_prefs.dart';
import '../theme.dart';
import 'pin_lock.dart';

/// Lets the user choose a new PIN (enter it, then confirm it).
/// Used both the first time a PIN is set up and whenever the user wants
/// to change an existing PIN from Settings.
class PinSetupScreen extends StatefulWidget {
  /// Called once the new PIN has been saved successfully.
  final VoidCallback onDone;
  /// Optional: lets the user back out without setting a PIN
  /// (e.g. when reached from Settings rather than from a fresh install).
  final bool canCancel;

  const PinSetupScreen({super.key, required this.onDone, this.canCancel = false});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  static const int _pinLength = 6;
  String _first = '';
  String _input = '';
  String _error = '';
  bool _shaking = false;
  bool _confirmStep = false;

  String get _title => _confirmStep ? 'Confirm PIN' : 'Choose a PIN';

  void _press(String digit) {
    if (_input.length >= _pinLength) return;
    setState(() { _input += digit; _error = ''; });
    if (_input.length == _pinLength) {
      Future.delayed(const Duration(milliseconds: 120), _onComplete);
    }
  }

  void _backspace() {
    if (_input.isEmpty) return;
    setState(() { _input = _input.substring(0, _input.length - 1); _error = ''; });
  }

  Future<void> _onComplete() async {
    if (!_confirmStep) {
      setState(() {
        _first = _input;
        _input = '';
        _confirmStep = true;
      });
      return;
    }
    if (_input == _first) {
      await SecurityPrefs.setPin(_input);
      if (mounted) widget.onDone();
    } else {
      setState(() {
        _shaking = true;
        _error = "PINs didn't match. Start over.";
      });
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _input = '';
            _first = '';
            _confirmStep = false;
            _shaking = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: widget.canCancel
          ? AppBar(
              backgroundColor: AppTheme.surface,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      body: SafeArea(
        child: KeyboardListener(
          focusNode: FocusNode()..requestFocus(),
          onKeyEvent: (e) {
            if (e is KeyDownEvent) {
              final key = e.logicalKey.keyLabel;
              if (RegExp(r'^\d$').hasMatch(key)) { _press(key); }
              else if (e.logicalKey == LogicalKeyboardKey.backspace) { _backspace(); }
            }
          },
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, color: AppTheme.green, size: 32),
                const SizedBox(height: 12),
                Text(_title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                const SizedBox(height: 6),
                Text(
                  _confirmStep
                      ? 'Enter the same $_pinLength digits again'
                      : 'Pick $_pinLength digits to protect your wallet',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 28),
                PinDots(length: _pinLength, filledCount: _input.length, shaking: _shaking),
                const SizedBox(height: 40),
                PinKeypad(onDigit: _press, onBackspace: _backspace),
                const SizedBox(height: 18),
                SizedBox(
                  height: 18,
                  child: Text(_error,
                      style: const TextStyle(fontSize: 12, color: AppTheme.red)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
