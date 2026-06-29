import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../theme.dart';

class EntriesScreen extends StatefulWidget {
  const EntriesScreen({super.key});
  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends State<EntriesScreen> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _entries = [];
  // Full generated period list like the website (6 months back/forward)
  List<Map<String, String>> _periodList = []; // [{value:'YYYY-MM-DD', label:'Jun 5–19'}]
  int _periodIndex = 0;
  bool _loading = true;
  String _filter = 'all'; // all / income / bill
  bool _formExpanded = false;
  bool _historyExpanded = false;
  final Map<String, bool> _groupExpanded = {};

  // Form
  String _selectedType   = 'income';
  String _selectedStatus = 'pending';
  final _amtCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  String _selectedDate = DateTime.now().toIso8601String().substring(0, 10);

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  // ── Period helpers ──────────────────────────────────────────────────────
  static String _pad2(int n) => n.toString().padLeft(2, '0');
  static String _cutoff(int y, int m, int d) => '$y-${_pad2(m)}-${_pad2(d)}';

  static String _periodRangeLabel(String value) {
    final parts = value.split('-').map(int.parse).toList();
    final m = parts[1]; final d = parts[2];
    if (d == 5) { return '${_months[m-1]} 5–19'; }
    int nm = m + 1;
    if (nm > 12) { nm = 1; }
    return '${_months[m-1]} 20–${_months[nm-1]} 4';
  }

  List<Map<String, String>> _buildPeriodList() {
    final now = DateTime.now();
    final List<String> list = [];
    for (int offset = -6; offset <= 6; offset++) {
      final d = DateTime(now.year, now.month + offset, 1);
      list.add(_cutoff(d.year, d.month, 5));
      list.add(_cutoff(d.year, d.month, 20));
    }
    list.sort();
    return list.map((v) => {'value': v, 'label': _periodRangeLabel(v)}).toList();
  }

  int _nearestPeriodIndex() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    int idx = 0;
    for (int i = 0; i < _periodList.length; i++) {
      if (_periodList[i]['value']!.compareTo(today) <= 0) { idx = i; }
    }
    return idx;
  }

  // ── Load ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _periodList = _buildPeriodList();
    _periodIndex = _nearestPeriodIndex();
    _loadEntries();
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    await _db.syncAllRecurring();
    final entries = await _db.getEntries();
    setState(() { _entries = entries; _loading = false; });
  }

  // ── Current period data ─────────────────────────────────────────────────
  String get _currentCutoff => _periodList[_periodIndex]['value']!;
  String get _currentLabel  => _periodList[_periodIndex]['label']!;

  List<Map<String, dynamic>> get _currentEntries =>
      _entries.where((e) => e['cutoff_date'] == _currentCutoff).toList();

  double _sumEntries(List<Map<String, dynamic>> list, String type, String status) =>
      list.where((e) => e['type'] == type && e['status'] == status)
          .fold(0.0, (s, e) => s + (e['amount'] as num).toDouble());

  // Carry-in: sum of all periods before current that have a positive net
  double _computeCarryIn() {
    double carry = 0;
    for (int i = 0; i < _periodIndex; i++) {
      final cv = _periodList[i]['value']!;
      // find the index in the full sorted period list that matches
      final pe = _entries.where((e) => e['cutoff_date'] == cv).toList();
      final inc  = _sumEntries(pe, 'income', 'paid');
      final paid = _sumEntries(pe, 'bill', 'paid');
      final start = carry > 0 ? carry : 0;
      carry = start + inc - paid;
    }
    return carry > 0 ? carry : 0;
  }

  // ── Add entry ───────────────────────────────────────────────────────────
  Future<void> _addEntry() async {
    final amt = double.tryParse(_amtCtrl.text);
    if (amt == null || !amt.isFinite || amt <= 0) { _toast('Enter a valid amount.'); return; }
    if (_selectedDate.isEmpty)    { _toast('Pick a date.');           return; }
    if (_descCtrl.text.trim().isEmpty) { _toast('Add a short description.'); return; }

    final cutoff = DatabaseHelper.cutoffForDate(_selectedDate);
    await _db.addEntry({
      'type': _selectedType,
      'amount': amt,
      'entry_date': _selectedDate,
      'cutoff_date': cutoff,
      'description': _descCtrl.text.trim(),
      'status': _selectedStatus,
    });
    _amtCtrl.clear();
    _descCtrl.clear();
    _toast('${_selectedType == 'income' ? 'Income' : 'Bill'} entry saved ✓');
    await _loadEntries();
    final idx = _periodList.indexWhere((p) => p['value'] == cutoff);
    if (idx != -1) setState(() => _periodIndex = idx);
  }

  Future<void> _toggleStatus(Map<String, dynamic> entry) async {
    final newStatus = entry['status'] == 'paid' ? 'pending' : 'paid';
    if (entry['status'] == 'paid') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(entry['type'] == 'bill' ? 'Mark as pending?' : 'Mark as verifying?'),
          content: Text(entry['type'] == 'bill'
              ? 'This will add it back into your remaining balance.'
              : 'This will remove it from your balance until verified again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                entry['type'] == 'bill' ? 'Mark pending' : 'Mark verifying',
                style: const TextStyle(color: AppTheme.pending),
              ),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    final ok = await _db.toggleEntryStatus(entry['id'] as int, newStatus);
    if (!ok) { _toast('This cutoff is locked and cannot be modified.'); return; }
    await _loadEntries();
  }

  Future<void> _deleteEntry(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await _db.deleteEntry(id);
    if (!ok) { _toast('This cutoff is locked and cannot be modified.'); return; }
    _toast('Entry deleted.');
    await _loadEntries();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      backgroundColor: AppTheme.textPrimary,
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.green));

    final pe       = _currentEntries;
    final carryIn  = _computeCarryIn();
    final totalInc = _sumEntries(pe, 'income', 'paid');
    final billsPaid= _sumEntries(pe, 'bill',   'paid');
    final billsAll = pe.where((e) => e['type'] == 'bill').fold(0.0, (s, e) => s + (e['amount'] as num).toDouble());
    final unpaid   = _sumEntries(pe, 'bill', 'pending');
    final balance  = carryIn + totalInc - billsPaid;
    final pendingCt= pe.where((e) => e['type'] == 'bill' && e['status'] == 'pending').length;

    return RefreshIndicator(
      color: AppTheme.green,
      onRefresh: _loadEntries,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Center(
          child: ConstrainedBox(
            // Caps content width on tablets/desktop/web so cards, forms, and
            // text don't stretch edge-to-edge on very wide screens. Phones
            // are narrower than this anyway, so they're unaffected.
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Period nav ─────────────────────────────────────────────
                _buildPeriodNav(),
                const SizedBox(height: 12),

                // ── Hero card ──────────────────────────────────────────────
                _buildHero(balance, carryIn, totalInc, billsPaid),
                const SizedBox(height: 12),

                // ── Stats grid ──────────────────────────────────────────────
                _buildStats(totalInc, billsAll, pendingCt, unpaid),
                const SizedBox(height: 14),

                // ── Add entry form ───────────────────────────────────────────
                _buildAddForm(),
                const SizedBox(height: 14),

                // ── History ──────────────────────────────────────────────────
                _buildHistory(pe),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Period nav ────────────────────────────────────────────────────────────
  Widget _buildPeriodNav() {
    return Row(children: [
      _navBtn(Icons.chevron_left,
          _periodIndex > 0 ? () => setState(() => _periodIndex--) : null),
      Expanded(
        child: Center(
          child: Text(_currentLabel,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary)),
        ),
      ),
      _navBtn(Icons.chevron_right,
          _periodIndex < _periodList.length - 1 ? () => setState(() => _periodIndex++) : null),
    ]);
  }

  Widget _navBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Icon(icon,
            color: onTap != null ? AppTheme.textSecondary : AppTheme.textMuted, size: 18),
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────
  Widget _buildHero(double balance, double carryIn, double income, double billsPaid) {
    final isNeg = balance < 0;
    final heroColor = isNeg ? AppTheme.red : AppTheme.green;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: heroColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Remaining this cutoff',
            style: TextStyle(color: Colors.white70, fontSize: 11,
                letterSpacing: 0.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(
          '${isNeg ? '−' : ''}${formatAmount(balance.abs())}',
          style: const TextStyle(color: Colors.white, fontSize: 30,
              fontWeight: FontWeight.w500, letterSpacing: -1),
        ),
        const SizedBox(height: 4),
        Text(
          '${carryIn > 0 ? "${formatAmount(carryIn)} carried · " : ""}'
          '${formatAmount(income)} income · ${formatAmount(billsPaid)} bills paid',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ]),
    );
  }

  // ── Stats grid ────────────────────────────────────────────────────────────
  Widget _buildStats(double income, double bills, int pendingCt, double unpaid) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Fixed card height (mainAxisExtent) instead of childAspectRatio, so
      // card height no longer scales with how wide the window/screen is.
      // On narrow phones this matches the old ~86px result; on wide
      // windows/tablets the cards now stay a sensible height instead of
      // ballooning with empty space.
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 86,
      ),
      children: [
        _statCard('Income this cutoff', '+${formatAmount(income)}',
            valueColor: AppTheme.greenDark),
        _statCard('Upcoming payments', '$pendingCt',
            valueColor: AppTheme.textPrimary),
        _statCard('Bills total this cutoff', '−${formatAmount(bills)}',
            valueColor: AppTheme.red),
        _statCard('Bills not paid', '−${formatAmount(unpaid)}',
            valueColor: AppTheme.red),
      ],
    );
  }

  Widget _statCard(String label, String value, {Color valueColor = AppTheme.textPrimary}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: valueColor),
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  // ── Add form ──────────────────────────────────────────────────────────────
  Widget _buildAddForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Column(children: [
        // Header row
        GestureDetector(
          onTap: () => setState(() => _formExpanded = !_formExpanded),
          child: Row(children: [
            const Icon(Icons.add, size: 15, color: AppTheme.green),
            const SizedBox(width: 6),
            const Text('Add an entry',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(_formExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: AppTheme.textMuted, size: 18),
          ]),
        ),

        // Collapsible body
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _formExpanded ? Column(children: [
            const SizedBox(height: 14),
            // Type
            const Align(alignment: Alignment.centerLeft,
                child: Text('Type', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500))),
            const SizedBox(height: 5),
            toggleRow(
              values: ['income', 'bill'],
              labels: ['Income received', 'Bill paid'],
              icons: [Icons.payments_outlined, Icons.receipt_outlined],
              selected: _selectedType,
              onSelect: (v) => setState(() {
                _selectedType = v;
                _selectedStatus = 'pending';
              }),
            ),
            const SizedBox(height: 12),
            // Date
            const Align(alignment: Alignment.centerLeft,
                child: Text('Date', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500))),
            const SizedBox(height: 5),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.light(primary: AppTheme.green),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked.toIso8601String().substring(0, 10));
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAF8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x26000000), width: 0.5),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  Text(_selectedDate, style: const TextStyle(fontSize: 16)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            // Amount
            const Align(alignment: Alignment.centerLeft,
                child: Text('Amount (₱)', style: TextStyle(fontSize: 12,
                    color: AppTheme.textSecondary, fontWeight: FontWeight.w500))),
            const SizedBox(height: 5),
            TextField(
              controller: _amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(hintText: 'e.g. 25000'),
              onSubmitted: (_) => _addEntry(),
            ),
            const SizedBox(height: 12),
            // Description
            const Align(alignment: Alignment.centerLeft,
                child: Text('Description', style: TextStyle(fontSize: 12,
                    color: AppTheme.textSecondary, fontWeight: FontWeight.w500))),
            const SizedBox(height: 5),
            TextField(
              controller: _descCtrl,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(hintText: 'e.g. June income, Electric bill'),
              onSubmitted: (_) => _addEntry(),
            ),
            const SizedBox(height: 12),
            // Status
            const Align(alignment: Alignment.centerLeft,
                child: Text('Status', style: TextStyle(fontSize: 12,
                    color: AppTheme.textSecondary, fontWeight: FontWeight.w500))),
            const SizedBox(height: 5),
            toggleRow(
              values: ['paid', 'pending'],
              labels: [
                _selectedType == 'income' ? 'Verified' : 'Paid',
                _selectedType == 'income' ? 'Verifying' : 'Pending',
              ],
              icons: [Icons.check_circle_outline, Icons.access_time],
              selected: _selectedStatus,
              onSelect: (v) => setState(() => _selectedStatus = v),
            ),
            const SizedBox(height: 14),
            // Submit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addEntry,
                icon: const Icon(Icons.check, size: 15),
                label: const Text('Add entry'),
              ),
            ),
          ]) : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  // ── History ───────────────────────────────────────────────────────────────
  Widget _buildHistory(List<Map<String, dynamic>> pe) {
    return Column(children: [
      // Header
      GestureDetector(
        onTap: () => setState(() => _historyExpanded = !_historyExpanded),
        child: Row(children: [
          const Icon(Icons.list, size: 15, color: AppTheme.textPrimary),
          const SizedBox(width: 5),
          const Text('History',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const Spacer(),
          Icon(_historyExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: AppTheme.textMuted, size: 18),
        ]),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        child: _historyExpanded ? Column(children: [
          const SizedBox(height: 10),
          // Filter tabs
          Row(children: [
            _filterTab('All',    'all'),
            const SizedBox(width: 6),
            _filterTab('Income', 'income'),
            const SizedBox(width: 6),
            _filterTab('Bills',  'bill'),
          ]),
          const SizedBox(height: 10),
          // List
          Container(
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            child: _buildEntryList(pe),
          ),
        ]) : const SizedBox.shrink(),
      ),
    ]);
  }

  Widget _filterTab(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.textPrimary : AppTheme.card,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: active ? AppTheme.textPrimary : AppTheme.border,
            width: 0.5,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : AppTheme.textSecondary,
                fontWeight: active ? FontWeight.w500 : FontWeight.normal)),
      ),
    );
  }

  // Returns the first word of a description (used as the group key).
  static String _firstWord(String desc) {
    final trimmed = desc.trim();
    if (trimmed.isEmpty) return trimmed;
    final spaceIdx = trimmed.indexOf(' ');
    return spaceIdx == -1 ? trimmed : trimmed.substring(0, spaceIdx);
  }

  Widget _buildEntryList(List<Map<String, dynamic>> pe) {
    final filtered = pe.where((e) {
      if (_filter == 'all') return true;
      return e['type'] == _filter;
    }).toList()
      ..sort((a, b) {
        // pending first
        final ap = a['status'] == 'pending' ? 0 : 1;
        final bp = b['status'] == 'pending' ? 0 : 1;
        return ap - bp;
      });

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(Icons.inbox_outlined, size: 28, color: AppTheme.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          const Text('No entries for this cutoff',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        ]),
      );
    }

    // Group entries by their first word.
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final e in filtered) {
      final key = _firstWord(e['description'] as String);
      groups.putIfAbsent(key, () => []).add(e);
    }

    // Separate single-item groups (render flat) from multi-item groups.
    final widgets = <Widget>[];
    bool firstWidget = true;

    for (final entry in groups.entries) {
      final key = entry.key;
      final items = entry.value;

      if (items.length == 1) {
        // Single item — render directly, no group header.
        if (!firstWidget) {
          widgets.add(const Divider(height: 0, thickness: 0.5,
              color: Color(0x14000000)));
        }
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildEntryRow(items.first),
        ));
        firstWidget = false;
      } else {
        // Multi-item group — render collapsible group.
        final isExpanded = _groupExpanded[key] ?? false;
        final groupTotal = items.fold(0.0, (s, e) => s + (e['amount'] as num).toDouble());
        final pendingCount = items.where((e) => e['status'] == 'pending').length;
        final isIncome = items.first['type'] == 'income';
        final sign = isIncome ? '+' : '−';
        final amtColor = isIncome ? AppTheme.greenDark : AppTheme.red;

        if (!firstWidget) {
          widgets.add(const Divider(height: 0, thickness: 0.5,
              color: Color(0x14000000)));
        }
        firstWidget = false;

        // Group header
        widgets.add(GestureDetector(
          onTap: () => setState(() =>
              _groupExpanded[key] = !isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(key,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                  '${items.length} entries · Total: $sign${formatAmount(groupTotal)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                if (pendingCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      const Icon(Icons.access_time, size: 11, color: AppTheme.pending),
                      const SizedBox(width: 3),
                      Text(
                        '$pendingCount pending · $sign${formatAmount(
                            items.where((e) => e['status'] == 'pending')
                                .fold(0.0, (s, e) => s + (e['amount'] as num).toDouble())
                        )}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.pending,
                            fontWeight: FontWeight.w500),
                      ),
                    ]),
                  ),
              ])),
              Text(
                isExpanded ? 'Hide details' : 'Show details',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              const SizedBox(width: 4),
              Icon(
                isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 16, color: AppTheme.textMuted,
              ),
            ]),
          ),
        ));

        // Group items (collapsible)
        if (isExpanded) {
          for (int i = 0; i < items.length; i++) {
            widgets.add(Container(
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withValues(alpha: 0.02),
                border: Border(
                  top: const BorderSide(color: Color(0x14000000), width: 0.5),
                  left: BorderSide(color: amtColor.withValues(alpha: 0.35), width: 3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 13, right: 16),
                child: _buildEntryRow(items[i]),
              ),
            ));
          }
        }
      }
    }

    return Column(children: widgets);
  }

  Widget _buildEntryRow(Map<String, dynamic> e) {
    final isIncome = e['type'] == 'income';
    final isPaid   = e['status'] == 'paid';
    final locked   = DatabaseHelper.isPreviousCutoffOrOlder(e['cutoff_date'] as String);
    final sign     = isIncome ? '+' : '−';
    final amtColor = isIncome ? AppTheme.greenDark : AppTheme.red;
    final canDelete = !locked && !isPaid;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14000000), width: 0.5)),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Date
          Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 11, color: AppTheme.textMuted),
            const SizedBox(width: 3),
            Text(formatDate(e['entry_date'] as String),
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ]),
          const SizedBox(height: 3),
          // Description + badges
          Wrap(spacing: 5, runSpacing: 4, children: [
            Text(e['description'] as String,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
            typeBadge(e['type'] as String),
            statusBadge(
              status: e['status'] as String,
              type: e['type'] as String,
              locked: locked,
              onTap: locked ? null : () => _toggleStatus(e),
            ),
          ]),
        ])),
        const SizedBox(width: 8),
        // Amount + delete
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$sign${formatAmount((e['amount'] as num).toDouble())}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: amtColor)),
          if (canDelete) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _deleteEntry(e['id'] as int),
              child: const Icon(Icons.delete_outline, size: 16, color: AppTheme.textMuted),
            ),
          ],
        ]),
      ]),
    );
  }
}