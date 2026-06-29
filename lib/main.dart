import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'security_prefs.dart';
import 'widgets/pin_lock.dart';
import 'screens/entries_screen.dart';
import 'screens/recurring_screen.dart';
import 'screens/credit_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WalletApp());
}

class WalletApp extends StatelessWidget {
  const WalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wallet Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  bool? _hasPin;
  bool _unlocked = false;
  int _tab = 0;
  DateTime? _backgroundedAt;

  // Each counter is bumped when we navigate TO that tab, forcing the
  // screen to dispose and reinitialise (re-sync + reload from DB).
  int _entriesEpoch   = 0;
  int _recurringEpoch = 0;
  int _creditEpoch    = 0;

  static const Duration _lockTimeout = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPin();
  }

  Future<void> _checkPin() async {
    try {
      final hasPin = await SecurityPrefs.hasPin()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!mounted) return;
      setState(() {
        _hasPin = hasPin;
        _unlocked = !hasPin;
      });
    } catch (_) {
      // If SharedPreferences fails or times out, just open the app unlocked
      if (!mounted) return;
      setState(() {
        _hasPin = false;
        _unlocked = true;
      });
    }
  }

  Future<void> _refreshSecurityState() async {
    try {
      final hasPin = await SecurityPrefs.hasPin()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!mounted) return;
      setState(() {
        _hasPin = hasPin;
        if (!hasPin) _unlocked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasPin = false;
        _unlocked = true;
      });
    }
  }

  void _onTabSelected(int i) {
    setState(() {
      if (i == 0 && _tab != 0) _entriesEpoch++;
      if (i == 1 && _tab != 1) _recurringEpoch++;
      if (i == 2 && _tab != 2) _creditEpoch++;
      _tab = i;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_backgroundedAt != null) {
        final elapsed = DateTime.now().difference(_backgroundedAt!);
        if (elapsed >= _lockTimeout && (_hasPin ?? false)) {
          setState(() => _unlocked = false);
        }
        _backgroundedAt = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPin == null) {
      return const Scaffold(
        backgroundColor: AppTheme.surface,
        body: Center(child: CircularProgressIndicator(color: AppTheme.green)),
      );
    }
    if (!_unlocked) {
      return PinLockScreen(onUnlocked: () => setState(() => _unlocked = true));
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.account_balance_wallet_outlined,
              color: AppTheme.green, size: 20),
          SizedBox(width: 8),
          Text('Wallet Tracker',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        ]),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsScreen(onSecurityChanged: _refreshSecurityState),
              ));
              _refreshSecurityState();
            },
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: 'Settings',
            color: AppTheme.textSecondary,
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          EntriesScreen(key: ValueKey(_entriesEpoch)),
          RecurringScreen(key: ValueKey(_recurringEpoch)),
          CreditScreen(key: ValueKey(_creditEpoch)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black12,
        selectedIndex: _tab,
        onDestinationSelected: _onTabSelected,
        indicatorColor: AppTheme.greenLight,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet, color: AppTheme.green),
            label: 'Tracker',
          ),
          NavigationDestination(
            icon: Icon(Icons.repeat_outlined),
            selectedIcon: Icon(Icons.repeat, color: AppTheme.green),
            label: 'Recurring',
          ),
          NavigationDestination(
            icon: Icon(Icons.credit_card_outlined),
            selectedIcon: Icon(Icons.credit_card, color: AppTheme.green),
            label: 'Credit',
          ),
        ],
      ),
    );
  }
}