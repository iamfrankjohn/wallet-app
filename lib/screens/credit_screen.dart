import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helper: parse hex color string → Color
// ─────────────────────────────────────────────────────────────────────────────
Color _hexColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return AppTheme.green;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CreditScreen
// ─────────────────────────────────────────────────────────────────────────────
class CreditScreen extends StatefulWidget {
  const CreditScreen({super.key});

  @override
  State<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends State<CreditScreen> {
  final _db = DatabaseHelper();

  List<Map<String, dynamic>> _accounts = [];

  // key: account id → list of transactions (with installments list embedded)
  final Map<int, List<Map<String, dynamic>>> _txnCache = {};

  bool _loading = true;
  bool _formOpen = false;
  int? _expandedAccountId;

  // ── create-account form ──────────────────────────────────────────────────
  final _accNameCtrl  = TextEditingController();
  final _accLimitCtrl = TextEditingController();
  final _accNotesCtrl = TextEditingController();
  String _accColor = '#1D9E75';

  static const List<String> _colorOptions = [
    '#1D9E75', '#3B82F6', '#8B5CF6', '#F59E0B',
    '#A32D2D', '#EC4899', '#06B6D4', '#F97316',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _accNameCtrl.dispose();
    _accLimitCtrl.dispose();
    _accNotesCtrl.dispose();
    super.dispose();
  }

  // ── data loading ─────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.getCreditAccounts();
    final Map<int, List<Map<String, dynamic>>> cache = {};
    for (final acc in rows) {
      final accId = acc['id'] as int;
      final txns  = await _loadTxnsForAccount(accId);
      cache[accId] = txns;
    }
    if (mounted) {
      setState(() {
        _accounts  = rows;
        _txnCache.clear();
        _txnCache.addAll(cache);
        _loading   = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadTxnsForAccount(int accId) async {
    final rawTxns = await _db.getCreditTxns(accId);
    final List<Map<String, dynamic>> result = [];
    for (final t in rawTxns) {
      final numInst = (t['num_installments'] as int? ?? 0);
      List<Map<String, dynamic>> installments = [];
      if (numInst > 0) {
        installments = await _db.getCreditInstallments(t['id'] as int);
      }
      result.add({...t, 'installments': installments});
    }
    return result;
  }

  // ── account CRUD ─────────────────────────────────────────────────────────
  Future<void> _addAccount() async {
    final name = _accNameCtrl.text.trim();
    if (name.isEmpty) { _toast('Enter account name'); return; }
    final limit = double.tryParse(_accLimitCtrl.text) ?? 0.0;
    await _db.addCreditAccount({
      'name': name,
      'credit_limit': limit.isFinite ? limit : 0.0,
      'color': _accColor,
      'notes': _accNotesCtrl.text.trim(),
    });
    _accNameCtrl.clear(); _accLimitCtrl.clear(); _accNotesCtrl.clear();
    setState(() { _formOpen = false; });
    _toast('Account added ✓');
    await _load();
  }

  Future<void> _editAccount(Map<String, dynamic> acc) async {
    final nameCtrl  = TextEditingController(text: acc['name'] as String);
    final limitCtrl = TextEditingController(text: '${(acc['credit_limit'] as num?)?.toDouble() ?? 0}');
    final notesCtrl = TextEditingController(text: acc['notes'] as String? ?? '');
    String chosenColor = acc['color'] as String? ?? '#1D9E75';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx2).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Edit Account',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(hintText: 'Account Name')),
            const SizedBox(height: 10),
            TextField(controller: limitCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: 'Credit Limit (₱)')),
            const SizedBox(height: 10),
            TextField(controller: notesCtrl,
                decoration: const InputDecoration(hintText: 'Notes (optional)')),
            const SizedBox(height: 12),
            const Text('Color', style: TextStyle(fontSize: 12, color: AppTheme.textMuted,
                fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8,
              children: _colorOptions.map((c) {
                final sel = chosenColor == c;
                return GestureDetector(
                  onTap: () => setSt(() => chosenColor = c),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: _hexColor(c), shape: BoxShape.circle,
                      border: Border.all(
                          color: sel ? AppTheme.textPrimary : Colors.transparent,
                          width: 2.5),
                    ),
                    child: sel
                        ? const Icon(Icons.check, color: Colors.white, size: 13)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx2, true),
                child: const Text('Save Changes'),
              ),
            ),
          ]),
        );
      }),
    );

    if (saved != true) return;
    await _db.editCreditAccount(acc['id'] as int, {
      'name': nameCtrl.text.trim(),
      'credit_limit': double.tryParse(limitCtrl.text) ?? 0.0,
      'color': chosenColor,
      'notes': notesCtrl.text.trim(),
    });
    _toast('Account updated ✓');
    await _load();
  }

  Future<void> _deleteAccount(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This removes all transactions and bill entries for this card permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _db.deleteCreditAccount(id);
    _toast('Account deleted.');
    await _load();
  }

  // ── transaction CRUD ─────────────────────────────────────────────────────
  Future<void> _deleteTxn(int txnId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove transaction?'),
        content: const Text('Mirrored bill entries will also be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _db.deleteCreditTxn(txnId);
    _toast('Transaction removed.');
    await _load();
  }

  // ── Add Charge (single or installment) ───────────────────────────────────
  Future<void> _openChargeModal(int accId) async {
    final amtCtrl   = TextEditingController();
    final descCtrl  = TextEditingController();
    final instCtrl  = TextEditingController(text: '0');
    final intCtrl   = TextEditingController(text: '0');
    String txnDate  = DateTime.now().toIso8601String().substring(0, 10);

    // Per-installment rows: list of {amtCtrl, dateCtrl}
    List<Map<String, TextEditingController>> instRows = [];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) {
        void rebuildInstRows(int n) {
          while (instRows.length < n) {
            instRows.add({
              'amt':  TextEditingController(),
              'date': TextEditingController(
                  text: DateTime.now().toIso8601String().substring(0, 10)),
            });
          }
          if (instRows.length > n) instRows = instRows.sublist(0, n);
          setSt(() {});
        }

        final numInst = int.tryParse(instCtrl.text) ?? 0;

        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx2).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Add Charge',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),

              // Date
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx2,
                    initialDate: DateTime.parse(txnDate),
                    firstDate: DateTime(2020), lastDate: DateTime(2035),
                    builder: (c, child) => Theme(
                      data: Theme.of(c).copyWith(colorScheme:
                        const ColorScheme.light(primary: AppTheme.green)),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setSt(() => txnDate = picked.toIso8601String().substring(0, 10));
                  }
                },
                child: _datePickerRow(txnDate),
              ),
              const SizedBox(height: 10),

              TextField(controller: descCtrl,
                  decoration: const InputDecoration(hintText: 'Description')),
              const SizedBox(height: 10),

              // Installment count
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Installments', style: TextStyle(
                      fontSize: 11, color: AppTheme.textMuted,
                      fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: instCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 15),
                    decoration: const InputDecoration(hintText: '0 = single'),
                    onChanged: (v) {
                      final n = int.tryParse(v) ?? 0;
                      rebuildInstRows(n);
                    },
                  ),
                ])),
                if (numInst == 0) ...[ // single charge: show amount field
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Amount (₱)', style: TextStyle(
                        fontSize: 11, color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    TextField(controller: amtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(hintText: '0.00')),
                  ])),
                ],
              ]),

              // Installment rows
              if (numInst > 0) ...[ 
                const SizedBox(height: 10),
                // Total interest
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8ED),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD4A035), width: 0.5),
                  ),
                  child: Row(children: [
                    const Icon(Icons.percent, size: 14, color: Color(0xFFB8780B)),
                    const SizedBox(width: 6),
                    const Text('Total Interest (₱)',
                        style: TextStyle(fontSize: 12, color: Color(0xFFB8780B),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: intCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                            hintText: '0.00', isDense: true, border: InputBorder.none))),
                  ]),
                ),
                const SizedBox(height: 8),
                const Row(children: [
                  Expanded(child: Text('Amount (₱)', style: TextStyle(
                      fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
                  SizedBox(width: 8),
                  Expanded(child: Text('Due Date', style: TextStyle(
                      fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 4),
                ...List.generate(instRows.length, (i) {
                  final row = instRows[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(child: Text('${i+1}',
                            style: const TextStyle(fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textMuted))),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: TextField(controller: row['amt'],
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(hintText: '0.00',
                              isDense: true))),
                      const SizedBox(width: 6),
                      Expanded(child: GestureDetector(
                        onTap: () async {
                          final cur = DateTime.tryParse(row['date']!.text)
                              ?? DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx2, initialDate: cur,
                            firstDate: DateTime(2020), lastDate: DateTime(2035),
                            builder: (c, child) => Theme(
                              data: Theme.of(c).copyWith(colorScheme:
                                const ColorScheme.light(primary: AppTheme.green)),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setSt(() => row['date']!.text =
                                picked.toIso8601String().substring(0, 10));
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 11),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppTheme.border, width: 0.5),
                          ),
                          child: Text(formatDate(row['date']!.text),
                              style: const TextStyle(fontSize: 13)),
                        ),
                      )),
                    ]),
                  );
                }),
              ],

              const SizedBox(height: 14),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final desc = descCtrl.text.trim();
                    if (desc.isEmpty) { _toast('Enter description'); return; }

                    if (numInst == 0) {
                      final amt = double.tryParse(amtCtrl.text);
                      if (amt == null || amt <= 0) {
                        _toast('Enter valid amount'); return;
                      }
                      await _db.addCreditTxn({
                        'account_id': accId,
                        'txn_type': 'charge',
                        'amount': amt,
                        'txn_date': txnDate,
                        'description': desc,
                        'num_installments': 0,
                      });
                    } else {
                      // Validate installment rows
                      for (int i = 0; i < instRows.length; i++) {
                        final a = double.tryParse(instRows[i]['amt']!.text);
                        if (a == null || a <= 0) {
                          _toast('Fill amount for installment ${i + 1}'); return;
                        }
                      }
                      final totalInterest = double.tryParse(intCtrl.text) ?? 0.0;
                      final perInstInterest = totalInterest / numInst;
                      // Principal only (no interest) stored as txn.amount
                      double totalPrincipal = 0;
                      for (final r in instRows) {
                        totalPrincipal += (double.tryParse(r['amt']!.text) ?? 0);
                      }
                      totalPrincipal -= totalInterest;

                      final db = await _db.database;
                      final txnId = await db.insert('credit_txns', {
                        'account_id': accId,
                        'txn_type': 'charge',
                        'amount': totalPrincipal,
                        'txn_date': txnDate,
                        'description': desc,
                        'num_installments': numInst,
                      });
                      for (int i = 0; i < instRows.length; i++) {
                        final instAmt  = double.parse(instRows[i]['amt']!.text);
                        final instDate = instRows[i]['date']!.text;
                        final cutoff   = DatabaseHelper.cutoffForDate(instDate);
                        await db.insert('credit_installments', {
                          'txn_id': txnId,
                          'installment_no': i + 1,
                          'amount': instAmt,
                          'interest': perInstInterest,
                          'due_date': instDate,
                        });
                        await db.insert('entries', {
                          'type': 'bill',
                          'amount': instAmt,
                          'entry_date': instDate,
                          'cutoff_date': cutoff,
                          'description': '$desc (${i + 1}/$numInst)',
                          'status': 'pending',
                          'source_ref': 'credit:$txnId:${i + 1}',
                        });
                      }
                      await _db.recalcAccountBalance(db, null, accountId: accId);
                    }

                    if (ctx2.mounted) Navigator.pop(ctx2);
                    _toast('Charge posted ✓');
                    await _load();
                  },
                  child: const Text('Post Charge'),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // ── Add Payment ───────────────────────────────────────────────────────────
  Future<void> _openPaymentModal(int accId) async {
    final amtCtrl  = TextEditingController();
    final descCtrl = TextEditingController(text: 'Payment');
    String txnDate = DateTime.now().toIso8601String().substring(0, 10);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx2).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add Payment',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: ctx2,
                initialDate: DateTime.parse(txnDate),
                firstDate: DateTime(2020), lastDate: DateTime(2035),
                builder: (c, child) => Theme(
                  data: Theme.of(c).copyWith(colorScheme:
                      const ColorScheme.light(primary: AppTheme.green)),
                  child: child!,
                ),
              );
              if (picked != null) {
                setSt(() => txnDate = picked.toIso8601String().substring(0, 10));
              }
            },
            child: _datePickerRow(txnDate),
          ),
          const SizedBox(height: 10),
          TextField(controller: amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(hintText: 'Amount (₱)')),
          const SizedBox(height: 10),
          TextField(controller: descCtrl,
              decoration: const InputDecoration(hintText: 'Description')),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green),
              onPressed: () async {
                final amt = double.tryParse(amtCtrl.text);
                if (amt == null || amt <= 0) { _toast('Enter valid amount'); return; }
                await _db.addCreditTxn({
                  'account_id': accId,
                  'txn_type': 'payment',
                  'amount': amt,
                  'txn_date': txnDate,
                  'description': descCtrl.text.trim().isEmpty
                      ? 'Payment' : descCtrl.text.trim(),
                  'num_installments': 0,
                });
                if (ctx2.mounted) Navigator.pop(ctx2);
                _toast('Payment posted ✓');
                await _load();
              },
              child: const Text('Post Payment'),
            ),
          ),
        ]),
      )),
    );
  }

  // ── Adjustment (rebate / add / subtract) ─────────────────────────────────
  Future<void> _openAdjustmentModal(int accId,
      List<Map<String, dynamic>> txns) async {
    final amtCtrl  = TextEditingController();
    final descCtrl = TextEditingController();
    String txnDate = DateTime.now().toIso8601String().substring(0, 10);
    String adjDir  = 'subtract'; // 'add' or 'subtract'

    // Find next unpaid installment across all charge txns
    Map<String, dynamic>? nextInst;
    for (final t in txns) {
      if (t['txn_type'] != 'charge') continue;
      final insts = t['installments'] as List<Map<String, dynamic>>? ?? [];
      for (final inst in insts) {
        if (inst['paid_date'] != null) continue;
        if (nextInst == null ||
            (inst['due_date'] as String).compareTo(
                nextInst['due_date'] as String) < 0) {
          nextInst = {
            ...inst,
            'txn_id': t['id'],
          };
        }
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSt) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx2).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Adjustment',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(nextInst != null
              ? 'Apply +/− adjustment. Will also update Installment #${nextInst['installment_no']} '
                  'due ${formatDate(nextInst['due_date'] as String)}.'
              : 'Apply a + or − adjustment to your balance.',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 14),

          // Type selector
          Row(children: [
            for (final dir in ['subtract', 'add'])
              Expanded(child: Padding(
                padding: dir == 'subtract'
                    ? const EdgeInsets.only(right: 4)
                    : const EdgeInsets.only(left: 4),
                child: GestureDetector(
                  onTap: () => setSt(() => adjDir = dir),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: adjDir == dir
                          ? (dir == 'subtract'
                              ? AppTheme.green : const Color(0xFFB8780B))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: adjDir == dir
                            ? (dir == 'subtract'
                                ? AppTheme.green : const Color(0xFFB8780B))
                            : AppTheme.border,
                        width: 0.5,
                      ),
                    ),
                    child: Center(child: Text(
                      dir == 'subtract' ? '− Subtract' : '+ Add',
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: adjDir == dir ? Colors.white : AppTheme.textMuted,
                      ),
                    )),
                  ),
                ),
              )),
          ]),
          const SizedBox(height: 10),

          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: ctx2,
                initialDate: DateTime.parse(txnDate),
                firstDate: DateTime(2020), lastDate: DateTime(2035),
                builder: (c, child) => Theme(
                  data: Theme.of(c).copyWith(colorScheme:
                      const ColorScheme.light(primary: AppTheme.green)),
                  child: child!,
                ),
              );
              if (picked != null) {
                setSt(() => txnDate = picked.toIso8601String().substring(0, 10));
              }
            },
            child: _datePickerRow(txnDate),
          ),
          const SizedBox(height: 10),

          TextField(controller: amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(hintText: 'Amount (₱)')),
          const SizedBox(height: 10),
          TextField(controller: descCtrl,
              decoration: const InputDecoration(
                  hintText: 'Description (e.g. Cashback, Fee, Correction)')),
          const SizedBox(height: 14),

          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB8780B)),
              onPressed: () async {
                final amt = double.tryParse(amtCtrl.text);
                if (amt == null || amt <= 0) { _toast('Enter valid amount'); return; }
                final desc = descCtrl.text.trim();
                if (desc.isEmpty) { _toast('Enter description'); return; }

                // Determine txn_type: rebate = subtract (matches PHP 'rebate/payment'),
                // add = 'adjustment' add direction
                final txnType = adjDir == 'subtract' ? 'rebate' : 'adjustment';
                final adjDesc = nextInst != null
                    ? '$desc (Installment #${nextInst['installment_no']} '
                      '${adjDir == "add" ? "+" : "−"}₱${amt.toStringAsFixed(2)})'
                    : desc;

                // Log the adjustment transaction
                await _db.addCreditTxn({
                  'account_id': accId,
                  'txn_type': txnType,
                  'amount': amt,
                  'txn_date': txnDate,
                  'description': adjDesc,
                  'num_installments': 0,
                });

                // If there's a next installment, also update its stored amount
                if (nextInst != null) {
                  final db = await _db.database;
                  final instId  = nextInst['id'] as int;
                  final txnId   = nextInst['txn_id'] as int;
                  final instNo  = nextInst['installment_no'] as int;
                  final oldAmt  = (nextInst['amount'] as num).toDouble();
                  final oldAdj  = (nextInst['adjustment'] as num? ?? 0).toDouble();
                  final delta   = adjDir == 'add' ? amt : -amt;
                  final newAmt  = (oldAmt + delta).clamp(0.0, double.infinity);
                  final newAdj  = oldAdj + delta;

                  await db.update('credit_installments',
                      {'amount': newAmt, 'adjustment': newAdj},
                      where: 'id=?', whereArgs: [instId]);

                  // Update mirrored entries row
                  final srcRef = 'credit:$txnId:$instNo';
                  await db.update('entries', {'amount': newAmt},
                      where: 'source_ref=?', whereArgs: [srcRef]);
                }

                if (ctx2.mounted) Navigator.pop(ctx2);
                _toast('Adjustment applied ✓');
                await _load();
              },
              child: const Text('Apply Adjustment'),
            ),
          ),
        ])),
      )),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      backgroundColor: AppTheme.textPrimary,
    ));
  }

  Widget _datePickerRow(String dateStr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(children: [
        const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Text(formatDate(dateStr), style: const TextStyle(fontSize: 14)),
      ]),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.green));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(children: [
            _buildInfoBanner(),
            const SizedBox(height: 12),
            _buildAddAccountForm(),
            const SizedBox(height: 14),
            if (_accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(children: [
                  Icon(Icons.credit_card_off_outlined, size: 28,
                      color: AppTheme.textMuted.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  const Text('No credit accounts yet. Add one above.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                ]),
              )
            else
              ..._accounts.map(_buildAccountCard),
          ]),
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.2), width: 0.5),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 16, color: AppTheme.green),
        SizedBox(width: 8),
        Expanded(child: Text(
          'Track credit cards, GCash Credit, or loans. '
          'Charges & installments mirror to your bill tracker automatically.',
          style: TextStyle(fontSize: 12, color: AppTheme.greenDark),
        )),
      ]),
    );
  }

  // ── Add account collapsible form ──────────────────────────────────────────
  Widget _buildAddAccountForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _formOpen = !_formOpen),
          child: Row(children: [
            const Icon(Icons.add_card, size: 15, color: AppTheme.green),
            const SizedBox(width: 6),
            const Text('Create Account',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(_formOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: AppTheme.textMuted, size: 18),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _formOpen
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 14),
                  TextField(controller: _accNameCtrl,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                          hintText: 'Account name (e.g. BPI Platinum)')),
                  const SizedBox(height: 10),
                  TextField(controller: _accLimitCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                          hintText: 'Credit limit ₱ (optional)')),
                  const SizedBox(height: 10),
                  TextField(controller: _accNotesCtrl,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                          hintText: 'Notes e.g. Statement on 15th (optional)')),
                  const SizedBox(height: 12),
                  const Text('Theme Color',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8,
                    children: _colorOptions.map((c) {
                      final sel = _accColor == c;
                      return GestureDetector(
                        onTap: () => setState(() => _accColor = c),
                        child: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: _hexColor(c), shape: BoxShape.circle,
                            border: Border.all(
                              color: sel ? AppTheme.textPrimary : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: sel
                              ? const Icon(Icons.check, color: Colors.white, size: 13)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity,
                      child: ElevatedButton(
                          onPressed: _addAccount,
                          child: const Text('Create Account'))),
                  const SizedBox(height: 6),
                  SizedBox(width: double.infinity,
                      child: TextButton(
                          onPressed: () => setState(() => _formOpen = false),
                          child: const Text('Cancel',
                              style: TextStyle(color: AppTheme.textMuted)))),
                ])
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  // ── Account card ──────────────────────────────────────────────────────────
  Widget _buildAccountCard(Map<String, dynamic> acc) {
    final accId     = acc['id'] as int;
    final color     = _hexColor(acc['color'] as String? ?? '#1D9E75');
    final limit     = (acc['credit_limit'] as num).toDouble();
    final balance   = (acc['balance'] as num).toDouble();
    final available = limit > 0 ? (limit - balance) : null;
    final pct       = limit > 0 ? (balance / limit).clamp(0.0, 1.0) : 0.0;
    final isExpanded = _expandedAccountId == accId;
    final txns      = _txnCache[accId] ?? [];

    final mainTxns  = txns.where((t) => t['txn_type'] != 'adjustment').toList();
    final adjTxns   = txns.where((t) => t['txn_type'] == 'adjustment').toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(children: [
        // ── Card Header ──
        GestureDetector(
          onTap: () =>
              setState(() => _expandedAccountId = isExpanded ? null : accId),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(acc['name'] as String,
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w600, fontSize: 16))),
                // Edit
                GestureDetector(
                  onTap: () => _editAccount(acc),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(Icons.edit_outlined, color: Colors.white70, size: 17),
                  ),
                ),
                // Delete
                GestureDetector(
                  onTap: () => _deleteAccount(accId),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(Icons.delete_outline, color: Colors.white70, size: 17),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white70, size: 18),
              ]),
              if (acc['notes'] != null && (acc['notes'] as String).isNotEmpty) ...[ 
                const SizedBox(height: 4),
                Text(acc['notes'] as String,
                    style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                _cardStat('Balance', formatAmount(balance)),
                _cardStat('Available',
                    available != null ? formatAmount(available < 0 ? 0 : available) : '—'),
                _cardStat('Limit', limit > 0 ? formatAmount(limit) : 'No limit'),
              ]),
              if (limit > 0) ...[ 
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      pct > 0.8 ? Colors.red.shade300 : Colors.white,
                    ),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${(pct * 100).toStringAsFixed(0)}% used',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ]),
          ),
        ),

        // ── Expanded panel ──
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Action buttons row
              Row(children: [
                _actionBtn('Charge', Icons.arrow_upward,
                    AppTheme.red, () => _openChargeModal(accId)),
                const SizedBox(width: 8),
                _actionBtn('Payment', Icons.arrow_downward,
                    AppTheme.green, () => _openPaymentModal(accId)),
                const SizedBox(width: 8),
                _actionBtn('Adjust', Icons.tune,
                    const Color(0xFFB8780B),
                    () => _openAdjustmentModal(accId, txns)),
              ]),
              const SizedBox(height: 16),

              // Main transactions (charge / payment / rebate)
              if (mainTxns.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text('No transactions yet.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted))),
                )
              else
                ...mainTxns.map((t) => _buildTxnRow(t)),

              // Adjustments collapsible section
              if (adjTxns.isNotEmpty)
                _AdjustmentsSection(adjTxns: adjTxns, onDelete: _deleteTxn),
            ]),
          ),
      ]),
    );
  }

  Widget _cardStat(String label, String value) {
    return Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10,
          fontWeight: FontWeight.w500)),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 13,
          fontWeight: FontWeight.w500)),
    ]));
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
          ),
          child: Column(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: color,
                fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ── Transaction row ───────────────────────────────────────────────────────
  Widget _buildTxnRow(Map<String, dynamic> t) {
    return _TxnRow(txn: t, onDelete: _deleteTxn);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TxnRow widget (stateful so installments can expand)
// ─────────────────────────────────────────────────────────────────────────────
class _TxnRow extends StatefulWidget {
  final Map<String, dynamic> txn;
  final Future<void> Function(int) onDelete;

  const _TxnRow({required this.txn, required this.onDelete});

  @override
  State<_TxnRow> createState() => _TxnRowState();
}

class _TxnRowState extends State<_TxnRow> {
  bool _instExpanded = false;

  @override
  Widget build(BuildContext context) {
    final t        = widget.txn;
    final type     = t['txn_type'] as String;
    final amt      = (t['amount'] as num).toDouble();
    final numInst  = (t['num_installments'] as int? ?? 0);
    final insts    = (t['installments'] as List<Map<String, dynamic>>?) ?? [];
    final isPmt    = type == 'payment' || type == 'rebate';
    final isAdj    = type == 'adjustment';

    final Color txnColor = isPmt
        ? AppTheme.greenDark
        : isAdj ? const Color(0xFFB8780B) : AppTheme.red;

    final allPaid  = insts.isNotEmpty && insts.every((i) => i['paid_date'] != null);
    final singlePaid = insts.isEmpty && t['paid_date'] != null;
    final fullyPaid  = allPaid || singlePaid;

    final totalInterest = insts.fold<double>(
        0, (s, i) => s + ((i['interest'] as num? ?? 0).toDouble()));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // icon badge
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: txnColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPmt ? Icons.arrow_downward
                  : isAdj ? Icons.tune : Icons.arrow_upward,
              size: 13, color: txnColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(t['description'] as String,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
            const SizedBox(height: 1),
            Row(children: [
              Text(formatDate(t['txn_date'] as String),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(width: 6),
              _typeBadge(type),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${isPmt ? '+' : isAdj ? '±' : '−'}${formatAmount(amt)}',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                  color: txnColor),
            ),
            if (fullyPaid) ...[ 
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text('Fully Paid',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppTheme.greenDark)),
              ),
            ],
          ]),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => widget.onDelete(t['id'] as int),
            child: const Icon(Icons.delete_outline, size: 16,
                color: AppTheme.textMuted),
          ),
        ]),

        // Installments expand toggle
        if (numInst > 0 && insts.isNotEmpty) ...[ 
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _instExpanded = !_instExpanded),
            child: Row(children: [
              Icon(_instExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Text(
                '${insts.length} installments'
                '${totalInterest > 0 ? '  +${formatAmount(totalInterest)} interest' : ''}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted),
              ),
            ]),
          ),
          if (_instExpanded) ...[ 
            const SizedBox(height: 6),
            Container(height: 0.5, color: AppTheme.border),
            const SizedBox(height: 6),
            ...insts.map((inst) {
              final paid = inst['paid_date'] != null;
              final instAmt = (inst['amount'] as num).toDouble();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(paid ? Icons.check_circle_outline : Icons.circle_outlined,
                      size: 13,
                      color: paid ? AppTheme.greenDark : AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    '${inst['installment_no']} — ${formatDate(inst['due_date'] as String)}',
                    style: TextStyle(fontSize: 11,
                        color: paid ? AppTheme.textMuted : AppTheme.textPrimary),
                  ),
                  const Spacer(),
                  Text(formatAmount(instAmt),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                          color: paid ? AppTheme.textMuted : AppTheme.textPrimary,
                          decoration: paid ? TextDecoration.lineThrough : null)),
                  if (paid) ...[ 
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(formatDate(inst['paid_date'] as String),
                          style: const TextStyle(fontSize: 9,
                              color: AppTheme.greenDark, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
              );
            }),
          ],
        ],
      ]),
    );
  }

  Widget _typeBadge(String type) {
    Color bg; Color fg;
    switch (type) {
      case 'payment':
        bg = AppTheme.green.withValues(alpha: 0.1); fg = AppTheme.greenDark;
      case 'rebate':
        bg = AppTheme.green.withValues(alpha: 0.1); fg = AppTheme.greenDark;
      case 'adjustment':
        bg = const Color(0xFFB8780B).withValues(alpha: 0.1);
        fg = const Color(0xFFB8780B);
      default: // charge
        bg = AppTheme.red.withValues(alpha: 0.1); fg = AppTheme.red;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(type, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
          color: fg, letterSpacing: 0.3)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adjustments collapsible section
// ─────────────────────────────────────────────────────────────────────────────
class _AdjustmentsSection extends StatefulWidget {
  final List<Map<String, dynamic>> adjTxns;
  final Future<void> Function(int) onDelete;

  const _AdjustmentsSection({required this.adjTxns, required this.onDelete});

  @override
  State<_AdjustmentsSection> createState() => _AdjustmentsSectionState();
}

class _AdjustmentsSectionState extends State<_AdjustmentsSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD4A035), width: 0.5),
          ),
          child: Row(children: [
            const Icon(Icons.tune, size: 14, color: Color(0xFFB8780B)),
            const SizedBox(width: 6),
            Text('${widget.adjTxns.length} Adjustment${widget.adjTxns.length > 1 ? "s" : ""}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: Color(0xFFB8780B))),
            const Spacer(),
            Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 14, color: const Color(0xFFB8780B)),
          ]),
        ),
      ),
      if (_open) ...[ 
        const SizedBox(height: 6),
        ...widget.adjTxns.map((t) => _TxnRow(txn: t, onDelete: widget.onDelete)),
      ],
    ]);
  }
}