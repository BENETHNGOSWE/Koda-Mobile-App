import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/constants/app_constants.dart';
import '../../../core/config/dio_client.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import 'portfolio_sheets.dart';

/// Portfolio — tracks the logged-in user's purchases and sales against
/// live prices. Backend: GET/POST/PUT/DELETE /portfolio, POST /portfolio/{id}/sell.
class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  List<Map<String, dynamic>> _transactions = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // all | active | sold

  double _num(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

  Map<String, dynamic> _map(dynamic v) => v is Map<String, dynamic>
      ? v
      : (v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{});

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(ApiEndpoints.portfolio);
      final raw = response.data;
      if (!mounted) return;
      if (raw is Map && raw['data'] is Map) {
        final data = _map(raw['data']);
        final txList = <Map<String, dynamic>>[];
        final rawTx = data['transactions'];
        if (rawTx is List) {
          for (final t in rawTx) {
            if (t is Map<String, dynamic>) {
              txList.add(t);
            } else if (t is Map) {
              txList.add(t.cast<String, dynamic>());
            }
          }
        }
        setState(() {
          _transactions = txList;
          _summary = data['summary'] is Map ? _map(data['summary']) : null;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _extractError(e);
      });
    }
  }

  String _extractError(dynamic e) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        if (data['message'] is String) return data['message'] as String;
        if (data['errors'] is Map) {
          final first = (data['errors'] as Map).values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
        }
      }
    } catch (_) {}
    return 'Something went wrong';
  }

  void _snack(String message, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  List<Map<String, dynamic>> get _visibleTransactions {
    if (_filter == 'all') return _transactions;
    return _transactions
        .where((t) => (t['status']?.toString() ?? 'active') == _filter)
        .toList();
  }

  String _sharesText(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  PortfolioSheets _sheets() => PortfolioSheets(
        dio: ref.read(dioProvider),
        snack: _snack,
        onChanged: _load,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Portfolio',
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: Material(
        elevation: 4,
        color: context.colorScheme.primary,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => _sheets().addPurchase(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: context.colorScheme.onPrimary),
                const SizedBox(width: 8),
                Text(
                  'Add Purchase',
                  style: TextStyle(
                    color: context.colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: context.colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center, style: context.textTheme.bodyMedium),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 56,
                  color: context.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(
                'No holdings yet',
                style: context.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Record your first DSE purchase to start tracking performance.',
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _sheets().addPurchase(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Purchase'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_summary != null) _buildSummaryCard(_summary!),
        _buildFilterChips(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _visibleTransactions.length,
              itemBuilder: (context, index) =>
                  _buildTransactionTile(_visibleTransactions[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> s) {
    final totalValue = _num(s['total_value']);
    final totalInvested = _num(s['total_invested']);
    final gainLoss = _num(s['total_gain_loss']);
    final unrealized = _num(s['unrealized_gain']);
    final realized = _num(s['realized_gain']);
    final perfPercent = _num(s['performance_percent']);
    final stockCount = s['stock_count'] is int
        ? s['stock_count'] as int
        : _num(s['stock_count']).toInt();
    final isPositive = gainLoss >= 0;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOTAL PORTFOLIO VALUE',
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    Formatters.formatCurrency(totalValue),
                    style: context.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isPositive ? Colors.green : Colors.red)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    Formatters.formatPercentage(perfPercent),
                    style: TextStyle(
                      color: isPositive ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _summaryStat(
                      'Invested', Formatters.formatCurrency(totalInvested)),
                ),
                Expanded(
                  child: _summaryStat(
                    'Unrealized',
                    Formatters.formatCurrency(unrealized),
                    color: unrealized >= 0 ? Colors.green : Colors.red,
                  ),
                ),
                Expanded(
                  child: _summaryStat(
                      'Realized', Formatters.formatCurrency(realized)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Active stocks: $stockCount',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.labelSmall?.copyWith(
            color: context.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: ['all', 'active', 'sold'].map((f) {
          final selected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f.toUpperCase()),
              selected: selected,
              onSelected: (_) => setState(() => _filter = f),
              labelStyle: TextStyle(
                color: selected
                    ? context.colorScheme.onPrimary
                    : context.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> t) {
    final symbol = t['symbol']?.toString() ?? 'N/A';
    final name = t['name']?.toString() ?? '';
    final isActive = (t['status']?.toString() ?? 'active') == 'active';
    final shares = _num(isActive ? t['remaining_shares'] : t['shares']);
    final purchasePrice = _num(t['purchase_price']);
    final purchaseDate = t['purchase_date']?.toString() ?? '';
    final currentPrice = _num(t['current_price']);
    final gainLoss = _num(isActive ? t['gain_loss'] : t['realized_gain']);
    final gainPercent =
        _num(isActive ? t['gain_loss_percent'] : _realizedPercent(t));
    final notes = t['notes']?.toString() ?? '';
    final isPositive = gainLoss >= 0;

    final detail = isActive
        ? '${_sharesText(shares)} sh @ ${Formatters.formatCurrency(purchasePrice)}'
        : 'SOLD ${_sharesText(shares)} sh';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          symbol,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isActive ? Colors.green : Colors.grey)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isActive ? 'ACTIVE' : 'SOLD',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: isActive ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (name.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(
                        color:
                            context.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    purchaseDate.isEmpty ? detail : '$detail · $purchaseDate',
                    style: context.textTheme.bodySmall,
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '“$notes”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color:
                            context.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Formatters.formatCurrency(isActive
                      ? _num(t['current_value'])
                      : _num(t['invested'])),
                  style: context.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.formatPercentage(gainPercent),
                  style: TextStyle(
                    color: isPositive ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Now ${Formatters.formatCurrency(currentPrice)}',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (action) {
                if (action == 'sell' && isActive) {
                  _sheets().sell(context, t);
                } else if (action == 'delete') {
                  _confirmDelete(context, t);
                }
              },
              itemBuilder: (context) => [
                if (isActive)
                  const PopupMenuItem(
                    value: 'sell',
                    child: Row(
                      children: [
                        Icon(Icons.sell, size: 18),
                        SizedBox(width: 8),
                        Text('Sell shares'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Delete record'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _realizedPercent(Map<String, dynamic> t) {
    final invested = _num(t['invested']);
    final realized = _num(t['realized_gain']);
    return invested > 0 ? (realized / invested) * 100 : 0;
  }

  // ────────────────────────────── Delete ───────────────────────────────

  Future<void> _confirmDelete(BuildContext context, Map<String, dynamic> t) async {
    final symbol = t['symbol']?.toString() ?? 'this record';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text(
            'This permanently removes the $symbol record from your portfolio.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final dio = ref.read(dioProvider);
      final id = t['id'] is int ? t['id'] as int : int.parse('${t['id']}');
      await dio.delete('${ApiEndpoints.portfolio}/$id');
      _snack('Record deleted');
      await _load();
    } catch (e) {
      _snack(_extractError(e), success: false);
    }
  }
}
