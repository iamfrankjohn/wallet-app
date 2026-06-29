import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../security_prefs.dart';
import '../theme.dart';
import '../widgets/pin_setup.dart';

class SettingsScreen extends StatefulWidget {
  /// Called after the lock state may have changed (PIN set/removed),
  /// so the parent can refresh whether the app should show as locked.
  final VoidCallback onSecurityChanged;
  const SettingsScreen({super.key, required this.onSecurityChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _localAuth = LocalAuthentication();

  bool _hasPin = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String _biometricLabel = 'Biometric unlock';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasPin = await SecurityPrefs.hasPin();
    final biometricEnabled = await SecurityPrefs.isBiometricEnabled();

    bool available = false;
    String label = 'Biometric unlock';
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      available = canCheck && supported;
      if (available) {
        final types = await _localAuth.getAvailableBiometrics();
        if (types.contains(BiometricType.face)) {
          label = 'Face ID';
        } else if (types.contains(BiometricType.fingerprint) ||
            types.contains(BiometricType.strong) ||
            types.contains(BiometricType.weak)) {
          label = 'Fingerprint';
        }
      }
    } catch (_) {
      available = false;
    }

    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _biometricEnabled = biometricEnabled && hasPin;
      _biometricAvailable = available;
      _biometricLabel = label;
      _loading = false;
    });
  }

  Future<void> _setOrChangePin() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PinSetupScreen(
        canCancel: true,
        onDone: () => Navigator.of(context).pop(),
      ),
    ));
    widget.onSecurityChanged();
    await _load();
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove PIN?'),
        content: const Text(
            'The app will open without asking for a PIN until you set a new one.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SecurityPrefs.clearPin();
    widget.onSecurityChanged();
    await _load();
  }

  Future<void> _toggleBiometric(bool value) async {
    if (!_hasPin) return;
    if (value) {
      // Require a fresh biometric check before turning it on, so the
      // user confirms their fingerprint/face actually works on this device.
      try {
        final didAuth = await _localAuth.authenticate(
          localizedReason: 'Confirm to enable biometric unlock',
          options: const AuthenticationOptions(stickyAuth: true),
        );
        if (!didAuth) return;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not verify biometrics on this device.')),
          );
        }
        return;
      }
    }
    await SecurityPrefs.setBiometricEnabled(value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.green))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionLabel('App Lock'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.lock_outline, color: AppTheme.green),
                        title: Text(_hasPin ? 'Change PIN' : 'Set a PIN'),
                        subtitle: Text(
                          _hasPin
                              ? 'A PIN is currently protecting the app'
                              : 'No PIN is set — anyone can open the app',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
                        onTap: _setOrChangePin,
                      ),
                      if (_hasPin) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.lock_open_outlined, color: AppTheme.red),
                          title: const Text('Remove PIN'),
                          subtitle: const Text(
                            'App will open with no password',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                          onTap: _removePin,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel('Biometric Unlock'),
                Card(
                  child: SwitchListTile(
                    activeColor: AppTheme.green,
                    secondary: const Icon(Icons.fingerprint, color: AppTheme.green),
                    title: Text('Enable $_biometricLabel'),
                    subtitle: Text(
                      !_hasPin
                          ? 'Set a PIN first to use this'
                          : !_biometricAvailable
                              ? 'Not available on this device'
                              : 'Use $_biometricLabel instead of typing your PIN',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    value: _biometricEnabled,
                    onChanged: (!_hasPin || !_biometricAvailable) ? null : _toggleBiometric,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Your PIN is stored securely on this device only. '
                    'Biometric unlock still relies on your PIN as a backup '
                    'in case fingerprint or face recognition fails.',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, height: 1.4),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary, letterSpacing: 0.3)),
      );
}
