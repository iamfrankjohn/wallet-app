import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../security_prefs.dart';
import '../theme.dart';

/// Lock screen shown when the app has a PIN set and is currently locked.
/// If the user has enabled biometrics, it will try Face ID / fingerprint
/// automatically as soon as the screen appears, falling back to the PIN
/// pad if biometrics fails, is cancelled, or isn't available.
class PinLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const PinLockScreen({super.key, required this.onUnlocked});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  static const int _pinLength = 6;
  String _input = '';
  String _error = '';
  bool _shaking = false;
  bool _checking = false;
  bool _biometricTried = false;

  final _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTryBiometric());
  }

  Future<void> _maybeTryBiometric() async {
    if (_biometricTried) return;
    _biometricTried = true;
    final enabled = await SecurityPrefs.isBiometricEnabled();
    if (!enabled || !mounted) return;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      if (!canCheck || !supported) return;
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Unlock Wallet Tracker',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (didAuth && mounted) widget.onUnlocked();
    } catch (_) {
      // Ignore and let the user fall back to the PIN pad.
    }
  }

  void _press(String digit) {
    if (_checking || _input.length >= _pinLength) return;
    setState(() { _input += digit; _error = ''; });
    if (_input.length == _pinLength) {
      Future.delayed(const Duration(milliseconds: 120), _check);
    }
  }

  void _backspace() {
    if (_checking || _input.isEmpty) return;
    setState(() { _input = _input.substring(0, _input.length - 1); _error = ''; });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final ok = await SecurityPrefs.verifyPin(_input);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() { _shaking = true; _error = 'Incorrect PIN, try again.'; _checking = false; });
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) setState(() { _input = ''; _shaking = false; });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
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
                const Text('Enter PIN',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                const SizedBox(height: 28),
                PinDots(length: _pinLength, filledCount: _input.length, shaking: _shaking),
                const SizedBox(height: 40),
                PinKeypad(onDigit: _press, onBackspace: _backspace),
                const SizedBox(height: 14),
                SizedBox(
                  height: 18,
                  child: Text(_error,
                      style: const TextStyle(fontSize: 12, color: AppTheme.red)),
                ),
                TextButton.icon(
                  onPressed: _maybeTryBiometric,
                  icon: const Icon(Icons.fingerprint, size: 18, color: AppTheme.textSecondary),
                  label: const Text('Use biometrics',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Row of dots showing how many digits have been entered so far.
class PinDots extends StatelessWidget {
  final int length;
  final int filledCount;
  final bool shaking;
  const PinDots({super.key, required this.length, required this.filledCount, this.shaking = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      transform: shaking
          ? Matrix4.translationValues(8, 0, 0)
          : Matrix4.identity(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(length, (i) {
          final filled = i < filledCount;
          final isError = shaking && filled;
          return Container(
            width: 14, height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isError ? AppTheme.red
                  : filled ? AppTheme.green : Colors.transparent,
              border: Border.all(
                color: isError ? AppTheme.red : AppTheme.green,
                width: 1.5,
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Reusable numeric keypad shared by the lock screen and PIN setup screens.
class PinKeypad extends StatelessWidget {
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  const PinKeypad({super.key, required this.onDigit, required this.onBackspace});

  Widget _key(String label, {VoidCallback? onTap, bool isEmpty = false}) {
    if (isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72, height: 72,
        decoration: const BoxDecoration(
          color: AppTheme.green,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: label == '⌫'
            ? const Icon(Icons.backspace_outlined, color: Colors.white, size: 22)
            : Text(label, style: const TextStyle(
                color: Colors.white, fontSize: 26, fontWeight: FontWeight.w500)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          ...'123456789'.split('').map((d) => _key(d, onTap: () => onDigit(d))),
          const SizedBox.shrink(),
          _key('0', onTap: () => onDigit('0')),
          _key('⌫', onTap: onBackspace),
        ],
      ),
    );
  }
}
