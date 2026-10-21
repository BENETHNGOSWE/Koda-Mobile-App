import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/config/constants/app_constants.dart';
import '../../core/utils/formatters.dart';

/// Shared portfolio bottom sheets (add purchase / sell).
///
/// Used by the Portfolio tab and by the Dashboard hero card's quick
/// actions, so the same forms appear in both places.
class PortfolioSheets {
  final Dio dio;
  final void Function(String message, {bool success}) snack;
  final void Function() onChanged;

  PortfolioSheets({
    required this.dio,
    required this.snack,
    required this.onChanged,
  });

  double _num(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

  Map<String, dynamic> _map(dynamic v) => v is Map<String, dynamic>
      ? v
      : (v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{});

  String _extractError(dynamic e) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        if (data['message'] is String) return data['message'] as String;
        if (data['errors'] is Map) {
          final first = (data['errors'] as Map).values.first;
          if (first is List && first.isNotEmpty) {
            return first.first.toString();
          }
        }
      }
    } catch (_) {}
    return 'Something went wrong';
  }

  /// symbol -> stock id map, from GET /stocks.
  Future<Map<String, int>> _fetchStockIds() async {
    final response = await dio.get(ApiEndpoints.stocksList);
    final raw = response.data;
    final map = <String, int>{};
    if (raw is Map && raw['data'] is Map) {
      final stocks = _map(raw['data'])['stocks'];
      if (stocks is List) {
        for (final s in stocks) {
          final m = s is Map ? s.cast<String, dynamic>() : null;
          if (m == null) continue;
          final symbol = m['symbol']?.toString() ?? '';
          final id = m['id'] is int ? m['id'] as int : int.tryParse('${m['id']}');
          if (symbol.isNotEmpty && id != null) map[symbol] = id;
        }
      }
    }
    return map;
  }

  Future<void> addPurchase(
    BuildContext context, {
    String? preselectedSymbol,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return FutureBuilder<Map<String, int>>(
          future: _fetchStockIds(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Could not load the stock list.')),
              );
            }
            return _AddPurchaseForm(
              stockIds: snap.data!,
              preselectedSymbol: preselectedSymbol,
              onSubmit: (stockId, shares, price, date, notes) async {
                try {
                  await dio.post(
                    ApiEndpoints.portfolio,
                    data: {
                      'stock_id': stockId,
                      'shares': shares,
                      'purchase_price': price,
                      'purchase_date': date,
                      if (notes.isNotEmpty) 'notes': notes,
                    },
                  );
                  snack('Purchase recorded', success: true);
                  onChanged();
                  return true;
                } catch (e) {
                  snack(_extractError(e), success: false);
                  return false;
                }
              },
            );
          },
        );
      },
    );
  }

  Future<void> sell(
    BuildContext context,
    Map<String, dynamic> transaction,
  ) async {
    final maxShares = _num(transaction['remaining_shares']);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: _SellForm(
            symbol: transaction['symbol']?.toString() ?? '',
            maxShares: maxShares,
            purchasePrice: _num(transaction['purchase_price']),
            onSubmit: (sharesToSell, sellPrice, sellDate) async {
              try {
                final id = transaction['id'] is int
                    ? transaction['id'] as int
                    : int.parse('${transaction['id']}');
                await dio.post(
                  ApiEndpoints.portfolioSell(id),
                  data: {
                    'shares_to_sell': sharesToSell,
                    'sell_price': sellPrice,
                    'sell_date': sellDate,
                  },
                );
                snack('Sale recorded', success: true);
                onChanged();
                return true;
              } catch (e) {
                snack(_extractError(e), success: false);
                return false;
              }
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────── Add-purchase bottom form ───────────────────────

class _AddPurchaseForm extends StatefulWidget {
  final Map<String, int> stockIds;
  final String? preselectedSymbol;
  final Future<bool> Function(
    int stockId,
    int shares,
    double price,
    String date,
    String notes,
  ) onSubmit;

  const _AddPurchaseForm({
    required this.stockIds,
    required this.onSubmit,
    this.preselectedSymbol,
  });

  @override
  State<_AddPurchaseForm> createState() => _AddPurchaseFormState();
}

class _AddPurchaseFormState extends State<_AddPurchaseForm> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedSymbol;
  final _sharesController = TextEditingController();
  final _priceController = TextEditingController();
  DateTime _date = DateTime.now();
  late final TextEditingController _dateController;
  final _notesController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedSymbol = widget.preselectedSymbol;
    _dateController =
        TextEditingController(text: DateFormat('yyyy-MM-dd').format(_date));
  }

  @override
  void dispose() {
    _sharesController.dispose();
    _priceController.dispose();
    _dateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(_date);
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final stockId = widget.stockIds[_selectedSymbol];
      if (stockId == null) throw Exception('Please choose a stock');
      final ok = await widget.onSubmit(
        stockId,
        int.parse(_sharesController.text.trim()),
        double.parse(_priceController.text.trim()),
        DateFormat('yyyy-MM-dd').format(_date),
        _notesController.text.trim(),
      );
      if (mounted && ok) Navigator.pop(context);
    } catch (_) {
      // Validation already surfaced; keep the sheet open.
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final symbols = widget.stockIds.keys.toList()..sort();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'New Purchase',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedSymbol,
                decoration: const InputDecoration(
                  labelText: 'Stock',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in symbols)
                    DropdownMenuItem(
                      value: s,
                      child: Text(s, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (s) => setState(() => _selectedSymbol = s),
                validator: (v) => v == null ? 'Choose a stock' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sharesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Shares',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 1) return 'Enter a valid share count';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Purchase price (TZS)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n < 0.01) return 'Enter a valid price';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dateController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Purchase date',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: _pickDate,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Purchase'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Sell form ───────────────────────────────

class _SellForm extends StatefulWidget {
  final String symbol;
  final double maxShares;
  final double purchasePrice;
  final Future<bool> Function(double shares, double price, String date)
      onSubmit;

  const _SellForm({
    required this.symbol,
    required this.maxShares,
    required this.purchasePrice,
    required this.onSubmit,
  });

  @override
  State<_SellForm> createState() => _SellFormState();
}

class _SellFormState extends State<_SellForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sharesController;
  final _priceController = TextEditingController();
  late final TextEditingController _dateController;
  DateTime _date = DateTime.now();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _sharesController = TextEditingController(
      text: widget.maxShares == widget.maxShares.roundToDouble()
          ? widget.maxShares.toStringAsFixed(0)
          : widget.maxShares.toString(),
    );
    _dateController =
        TextEditingController(text: DateFormat('yyyy-MM-dd').format(_date));
  }

  @override
  void dispose() {
    _sharesController.dispose();
    _priceController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(_date);
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final ok = await widget.onSubmit(
      double.parse(_sharesController.text.trim()),
      double.parse(_priceController.text.trim()),
      DateFormat('yyyy-MM-dd').format(_date),
    );
    if (mounted) {
      if (ok) {
        Navigator.pop(context);
      } else {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sell ${widget.symbol}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'You hold ${widget.maxShares.toStringAsFixed(widget.maxShares == widget.maxShares.roundToDouble() ? 0 : 2)} shares '
              'bought at ${Formatters.formatCurrency(widget.purchasePrice)}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _sharesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Shares to sell',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n < 1) return 'Enter a valid share count';
                if (n > widget.maxShares) {
                  return 'You only hold ${sharesText(widget.maxShares)} shares';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sell price (TZS)',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n < 0.01) return 'Enter a valid price';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Sell date',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _pickDate,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm Sale'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String sharesText(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
