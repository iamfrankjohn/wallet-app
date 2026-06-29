import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../theme.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _schedules = [];
  bool _loading = true;
  bool _formOpen = false;
  final Map<String, bool> _groupExpanded = {};

  final _nameCtrl  = TextEditingController();
  final _amtCtrl   = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _type      = 'bill';
  int _payDay1      = 15;
  int? _payDay2;
  String _startDate = DateTime.now().toIso8601String().substring(0, 10);
  String? _endDate;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _nameCtrl.dispose(); _amtCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  // Syncs all active schedules, shows a snackbar with the result, then
  // refreshes the list. Called automatically every time the tab is opened.
  Future<void> _load() async {
    final newCount = await _db.syncAllRecurring();
    final rows = await _db.getRecurring();
    if (!mounted) return;
    setState(() { _schedules = rows; _loading = false; });
    // Show feedback after the first frame so the list is already visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final msg = newCount > 0
          ? 'Sync complete — $newCount new ${newCount == 1 ? 'entry' : 'entries'} added'
          : 'Sync complete — already up to date';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(msg),
        ]),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        backgroundColor: AppTheme.textPrimary,
      ));
    });
  }

  Future<void> _addSchedule() async {
    final name = _nameCtrl.text.trim();
    final amt  = double.tryParse(_amtCtrl.text);
    if (name.isEmpty)                              { _toast('Enter a name'); return; }
    if (amt == null || !amt.isFinite || amt <= 0)  { _toast('Enter a valid amount'); return; }
    await _db.addRecurring({
      'name': name, 'type': _type, 'amount': amt,
      'pay_day': _payDay1, 'pay_day2': _payDay2,
      'start_date': _startDate, 'end_date': _endDate,
      'notes': _notesCtrl.text.trim(), 'active': 1,
    });
    _nameCtrl.clear(); _amtCtrl.clear(); _notesCtrl.clear();
    setState(() { _formOpen = false; _payDay2 = null; _endDate = null; });
    _toast('Schedule added ✓');
    await _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete schedule?'),
        content: const Text('Pending entries for this schedule will also be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _db.deleteRecurring(id);
    _toast('Schedule deleted.');
    await _load();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      backgroundColor: AppTheme.textPrimary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.green));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildAddForm(),
            const SizedBox(height: 14),
            if (_schedules.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(children: [
                    Icon(Icons.repeat, size: 28, color: AppTheme.textMuted.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    const Text('No recurring schedules yet',
                        style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  ]),
                ),
              )
            else
              ..._buildGroupedSchedules(),
          ]),
        ),
      ),
    );
  }

  Widget _buildAddForm() {
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
            const Icon(Icons.add, size: 15, color: AppTheme.green),
            const SizedBox(width: 6),
            const Text('New Schedule',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(_formOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: AppTheme.textMuted, size: 18),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _formOpen ? Column(children: [
            const SizedBox(height: 14),
            const Align(alignment: Alignment.centerLeft,
                child: Text('Type', style: TextStyle(fontSize: 12,
                    color: AppTheme.textSecondary, fontWeight: FontWeight.w500))),
            const SizedBox(height: 5),
            toggleRow(
              values: ['income', 'bill'],
              labels: ['Income', 'Bill'],
              icons: [Icons.payments_outlined, Icons.receipt_outlined],
              selected: _type,
              onSelect: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 12),
            TextField(controller: _nameCtrl,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(hintText: 'Name / Description')),
            const SizedBox(height: 10),
            TextField(controller: _amtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(hintText: 'Amount (₱)')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _dayPicker('Pay Day 1', _payDay1, (v) => setState(() => _payDay1 = v))),
              const SizedBox(width: 8),
              Expanded(child: _dayPicker2()),
            ]),
            const SizedBox(height: 10),
            _dateTile('Start Date', _startDate, (d) => setState(() => _startDate = d)),
            const SizedBox(height: 6),
            _dateTile('End Date (optional)', _endDate, (d) => setState(() => _endDate = d), clearable: true),
            const SizedBox(height: 10),
            TextField(controller: _notesCtrl,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(hintText: 'Notes (optional)')),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _addSchedule,
                  child: const Text('Add Schedule')),
            ),
          ]) : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  Widget _dayPicker(String label, int value, ValueChanged<int> onChanged) {
    return DropdownButtonFormField<int>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: List.generate(31, (i) => DropdownMenuItem(
          value: i + 1, child: Text(ordinal(i + 1)))),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }

  Widget _dayPicker2() {
    return DropdownButtonFormField<int?>(
      value: _payDay2,
      decoration: const InputDecoration(labelText: 'Pay Day 2 (opt.)'),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('None')),
        ...List.generate(31, (i) => DropdownMenuItem<int?>(
            value: i + 1, child: Text(ordinal(i + 1)))),
      ],
      onChanged: (v) => setState(() => _payDay2 = v),
    );
  }

  Widget _dateTile(String label, String? value, ValueChanged<String> onPicked,
      {bool clearable = false}) {
    return GestureDetector(
      onTap: () async {
        final initial = value != null
            ? DateTime.tryParse(value) ?? DateTime.now()
            : DateTime.now();
        final picked = await showDatePicker(
          context: context, initialDate: initial,
          firstDate: DateTime(2020), lastDate: DateTime(2035),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.light(primary: AppTheme.green)),
            child: child!,
          ),
        );
        if (picked != null) onPicked(picked.toIso8601String().substring(0, 10));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAF8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x26000000), width: 0.5),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(
            value != null ? '$label: ${formatDate(value)}' : label,
            style: TextStyle(fontSize: 14,
                color: value != null ? AppTheme.textPrimary : AppTheme.textMuted),
          )),
          if (clearable && value != null)
            GestureDetector(
              onTap: () => setState(() => _endDate = null),
              child: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
            ),
        ]),
      ),
    );
  }

  static String _firstWord(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    final spaceIdx = trimmed.indexOf(' ');
    return spaceIdx == -1 ? trimmed : trimmed.substring(0, spaceIdx);
  }

  List<Widget> _buildGroupedSchedules() {
    // Group schedules by first word of their name.
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final s in _schedules) {
      final key = _firstWord(s['name'] as String);
      groups.putIfAbsent(key, () => []).add(s);
    }

    final widgets = <Widget>[];
    for (final entry in groups.entries) {
      final key = entry.key;
      final items = entry.value;

      if (items.length == 1) {
        widgets.add(_buildScheduleCard(items.first));
      } else {
        final isExpanded = _groupExpanded[key] ?? false;
        final groupTotal = items.fold(0.0, (s, e) => s + (e['amount'] as num).toDouble());
        final unpaidTotal = items.fold(0.0, (s, e) => s + ((e['unpaid_total'] as num?) ?? 0).toDouble());
        final unpaidCount = items.fold(0, (s, e) => s + ((e['unpaid_count'] as num?) ?? 0).toInt());
        final isIncome = items.first['type'] == 'income';
        final sign = isIncome ? '+' : '−';
        final color = isIncome ? AppTheme.greenDark : AppTheme.red;

        // Group header card
        widgets.add(Container(
          margin: EdgeInsets.only(bottom: isExpanded ? 0 : 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: isExpanded ? Radius.zero : const Radius.circular(14),
              bottomRight: isExpanded ? Radius.zero : const Radius.circular(14),
            ),
            border: Border.all(color: AppTheme.border, width: 0.5),
          ),
          child: GestureDetector(
            onTap: () => setState(() => _groupExpanded[key] = !isExpanded),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(isIncome ? Icons.payments_outlined : Icons.repeat,
                    size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(key,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text('${items.length} entries · Total: $sign${formatAmount(groupTotal)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: unpaidTotal > 0 ? AppTheme.pendingLight : AppTheme.greenLight,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    unpaidTotal > 0
                        ? '$unpaidCount unpaid · $sign${formatAmount(unpaidTotal)} remaining'
                        : 'All paid',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: unpaidTotal > 0 ? AppTheme.pending : AppTheme.greenDark,
                    ),
                  ),
                ),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  isExpanded ? 'Hide details' : 'Show details',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 4),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 16, color: AppTheme.textMuted,
                ),
              ]),
            ]),
          ),
        ));

        // Group items (collapsible)
        if (isExpanded) {
          for (int i = 0; i < items.length; i++) {
            final isLast = i == items.length - 1;
            widgets.add(Container(
              margin: EdgeInsets.only(bottom: isLast ? 10 : 0),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.only(
                  bottomLeft: isLast ? const Radius.circular(14) : Radius.zero,
                  bottomRight: isLast ? const Radius.circular(14) : Radius.zero,
                ),
                border: Border(
                  left: const BorderSide(color: AppTheme.border, width: 0.5),
                  right: const BorderSide(color: AppTheme.border, width: 0.5),
                  bottom: const BorderSide(color: AppTheme.border, width: 0.5),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: color.withValues(alpha: 0.4), width: 3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 0, 0, 0),
                  child: _buildScheduleCard(items[i], grouped: true),
                ),
              ),
            ));
          }
        }
      }
    }
    return widgets;
  }

  Widget _buildScheduleCard(Map<String, dynamic> s, {bool grouped = false}) {
    final active      = (s['active'] as int) == 1;
    final isIncome    = s['type'] == 'income';
    final color       = !active ? AppTheme.textMuted : (isIncome ? AppTheme.greenDark : AppTheme.red);
    final unpaidTotal = (s['unpaid_total'] as num? ?? 0).toDouble();
    final unpaidCount = (s['unpaid_count'] as num? ?? 0).toInt();
    final hasPayDay2  = s['pay_day2'] != null;
    final sign        = isIncome ? '+' : '−';
    final freqStr     = hasPayDay2
        ? '${ordinal(s['pay_day'] as int)} & ${ordinal(s['pay_day2'] as int)} of each month'
        : '${ordinal(s['pay_day'] as int)} of each month';

    return Container(
      margin: grouped ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: grouped ? null : BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(isIncome ? Icons.payments_outlined : Icons.repeat,
              size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['name'] as String,
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14,
                  color: active ? AppTheme.textPrimary : AppTheme.textMuted)),
          Text(freqStr, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          if (s['end_date'] != null)
            Text('Until ${formatDate(s['end_date'] as String)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))
          else
            const Text('Ongoing',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: unpaidTotal > 0 ? AppTheme.pendingLight : AppTheme.greenLight,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              unpaidTotal > 0
                  ? '$unpaidCount unpaid · $sign${formatAmount(unpaidTotal)} remaining'
                  : 'All paid',
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: unpaidTotal > 0 ? AppTheme.pending : AppTheme.greenDark,
              ),
            ),
          ),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$sign${formatAmount((s['amount'] as num).toDouble())}',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: color)),
          const SizedBox(height: 8),
          Row(children: [
            GestureDetector(
              onTap: () async {
                await _db.toggleRecurring(s['id'] as int, !active);
                _toast(active ? 'Schedule paused.' : 'Schedule resumed.');
                await _load();
              },
              child: Icon(
                active ? Icons.pause_circle_outline : Icons.play_circle_outline,
                size: 20, color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _delete(s['id'] as int),
              child: const Icon(Icons.delete_outline, size: 20, color: AppTheme.red),
            ),
          ]),
        ]),
      ]),
    );
  }
}