import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/utils/extensions.dart';
import '../../../core/config/dio_client.dart';
import '../../../core/config/constants/app_constants.dart';
import '../../providers/app_providers.dart';

class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen>
    with SingleTickerProviderStateMixin {
  String? stock1;
  String? stock2;
  String? stock3;
  int period = 30; // Default to 30 days
  late TabController _tabController;
  bool _showResults = false;
  bool _isComparing = false;
  bool _loadingPrices = false;
  dynamic _comparisonData;

  /// Normalised price series per symbol (indexed to 100 at the start),
  /// fetched after the compare call for the price-movement chart.
  final Map<String, List<double>> _priceSeries = {};

  static const List<Color> _seriesColors = [
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFF8E24AA),
  ];

  final Map<String, int> periods = {
    '1 Week': 7,
    '1 Month': 30,
    '3 Months': 90,
    '6 Months': 180,
    '1 Year': 365,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Safe accessors — the API serialises decimals as strings, so every
  // value that is compared or formatted must be coerced first.
  // ─────────────────────────────────────────────────────────────────────
  double? _num(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _fmt(dynamic value, {int decimals = 2, String suffix = ''}) {
    final n = _num(value);
    if (n == null) return 'N/A';
    return n.toStringAsFixed(decimals) + suffix;
  }

  String _str(dynamic value, [String fallback = 'N/A']) {
    if (value == null) return fallback;
    return value.toString();
  }

  Map<String, dynamic> _map(dynamic value) {
    return value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};
  }

  /// Health rating label derived from the 0-100 health score.
  String _healthRating(dynamic score) {
    final n = _num(score);
    if (n == null) return 'No data';
    if (n >= 75) return 'Excellent';
    if (n >= 50) return 'Good';
    if (n >= 30) return 'Fair';
    return 'Poor';
  }

  /// The selected symbols in display order (2 or 3).
  List<String> get _selectedSymbols => [
        stock1!,
        stock2!,
        if (stock3 != null) stock3!,
      ];

  /// Per-stock entries from the compare response, in selection order.
  List<Map<String, dynamic>> get _stockEntries {
    if (_comparisonData is! Map) return const [];
    final data = _comparisonData as Map<String, dynamic>;
    final stocks = data['stocks'];
    if (stocks is! List) return const [];
    final bySymbol = <String, Map<String, dynamic>>{};
    for (final raw in stocks.whereType<Map<String, dynamic>>()) {
      final s = raw['stock'];
      if (s is Map && s['symbol'] is String) {
        bySymbol[s['symbol'] as String] = raw;
      }
    }
    return _selectedSymbols
        .map((symbol) => bySymbol[symbol] ?? const <String, dynamic>{})
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Compare Stocks'),
            Text(
              'Comprehensive technical and fundamental analysis side by side',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // Header section (selection and compare button)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSelectionSection(context),
                  const SizedBox(height: 24),
                  _buildCompareButton(context),
                ],
              ),
            ),
          ),
          // Results section
          if (_showResults && stock1 != null && stock2 != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildComparisonResults(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionSection(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Stocks to Compare',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildStockDropdown(
              context,
              'Stock 1',
              stock1,
              (value) {
                setState(() => stock1 = value);
              },
              excludeStocks: [stock2, stock3],
            ),
            const SizedBox(height: 16),
            _buildStockDropdown(
              context,
              'Stock 2',
              stock2,
              (value) {
                setState(() => stock2 = value);
              },
              excludeStocks: [stock1, stock3],
            ),
            const SizedBox(height: 16),
            _buildStockDropdown(
              context,
              'Stock 3 (Optional)',
              stock3,
              (value) {
                setState(() => stock3 = value);
              },
              excludeStocks: [stock1, stock2],
            ),
            const SizedBox(height: 16),
            _buildPeriodDropdown(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStockDropdown(
    BuildContext context,
    String label,
    String? value,
    Function(String?) onChanged, {
    List<String?>? excludeStocks,
  }) {
    final stocksAsync = ref.watch(stocksListProvider(null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        stocksAsync.when(
          data: (stocks) {
            // Filter out already selected stocks from other dropdowns
            final filteredStocks = stocks.where((stock) {
              return excludeStocks == null || !excludeStocks.contains(stock.symbol);
            }).toList();

            // Ensure the current value is valid for this dropdown
            final validValue = (value != null && filteredStocks.any((s) => s.symbol == value)) ? value : null;

            return DropdownButtonFormField<String>(
              key: ValueKey('$label-${excludeStocks?.join(',') ?? ''}'),
              initialValue: validValue,
              decoration: InputDecoration(
                hintText: 'Select a stock',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: filteredStocks.map((stock) {
                return DropdownMenuItem(
                  value: stock.symbol,
                  child: Text('${stock.symbol} - ${stock.name}'),
                );
              }).toList(),
              onChanged: onChanged,
            );
          },
          loading: () => DropdownButtonFormField<String>(
            decoration: InputDecoration(
              hintText: 'Loading stocks...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: const [],
            onChanged: null,
          ),
          error: (error, _) => DropdownButtonFormField<String>(
            decoration: InputDecoration(
              hintText: 'Error loading stocks',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: const [],
            onChanged: null,
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodDropdown(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Period',
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: period,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          items: periods.entries.map((entry) {
            return DropdownMenuItem(
              value: entry.value,
              child: Text(entry.key),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => period = value!);
          },
        ),
      ],
    );
  }

  Widget _buildCompareButton(BuildContext context) {
    final isEnabled = stock1 != null && stock2 != null && !_isComparing;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isEnabled ? _handleCompareStocks : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _isComparing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.compare_arrows),
                  const SizedBox(width: 8),
                  const Text('Compare Stocks'),
                ],
              ),
      ),
    );
  }

  Future<void> _handleCompareStocks() async {
    setState(() {
      _isComparing = true;
      _showResults = false;
      _priceSeries.clear();
    });

    try {
      final dio = ref.read(dioProvider);
      final symbols = _selectedSymbols;

      final response = await dio.post(
        ApiEndpoints.compare,
        data: {
          'symbols': symbols,
          'period': period,
        },
      );

      if (mounted) {
        setState(() {
          _comparisonData = response.data is Map ? response.data['data'] : null;
          _showResults = true;
          _isComparing = false;
        });
      }

      // Fetch the price series for the movement chart (in parallel).
      if (mounted) {
        await _loadPriceSeries(symbols, dio);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isComparing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to compare stocks: ${_extractError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _extractError(dynamic e) {
    try {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      final message = e.message;
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {}
    return 'Something went wrong';
  }

  Future<void> _loadPriceSeries(
    List<String> symbols,
    dynamic dio,
  ) async {
    setState(() => _loadingPrices = true);
    try {
      await Future.wait(symbols.map((symbol) async {
        try {
          final response = await dio.get(
            ApiEndpoints.stockPrices(symbol),
            queryParameters: {'days': period},
          );
          final raw = response.data;
          final prices =
              raw is Map && raw['data'] is Map ? raw['data']['prices'] : null;
          if (prices is List) {
            final closes = <double>[];
            for (final p in prices) {
              if (p is Map) {
                final close = _num(p['close']);
                if (close != null) closes.add(close);
              }
            }
            if (closes.length >= 2 && closes.first > 0) {
              final base = closes.first;
              _priceSeries[symbol] =
                  closes.map((c) => (c / base) * 100).toList();
            }
          }
        } catch (_) {
          // A missing series for one stock must not break the others.
        }
      }));
    } finally {
      if (mounted) {
        setState(() => _loadingPrices = false);
      }
    }
  }

  Widget _buildComparisonResults(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Badges section
        _buildResultBadges(context),
        const SizedBox(height: 16),
        // Fixed tab bar
        _buildTabBar(context),
        const SizedBox(height: 16),
        // Tab content - using AnimatedBuilder to avoid nested scrolling
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, child) {
            switch (_tabController.index) {
              case 0:
                return _buildOverviewTab(context);
              case 1:
                return _buildTechnicalAnalysisTab(context);
              case 2:
                return _buildFundamentalAnalysisTab(context);
              case 3:
                return _buildPredictionsTab(context);
              case 4:
                return _buildSignalsFlagsTab(context);
              default:
                return _buildOverviewTab(context);
            }
          },
        ),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: context.cardDecoration(radius: 14),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        dividerColor: Colors.transparent,
        labelColor: context.colorScheme.onSurface,
        unselectedLabelColor:
            context.colorScheme.onSurface.withValues(alpha: 0.5),
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        indicator: BoxDecoration(
          color: context.colorScheme.onSurface.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Technical'),
          Tab(text: 'Fundamental'),
          Tab(text: 'Predictions'),
          Tab(text: 'Signals'),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStockCards(context),
        const SizedBox(height: 24),
        _buildKeyMetricsTable(context),
        const SizedBox(height: 20),
        _buildMarketCautionCard(context),
        const SizedBox(height: 20),
        _buildDetailedAnalysisSection(context),
      ],
    );
  }

  Widget _buildTechnicalAnalysisTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPriceMovementChart(context),
        const SizedBox(height: 24),
        _buildTechnicalMetricsTable(context),
        const SizedBox(height: 20),
        _buildMarketCautionCard(context),
      ],
    );
  }

  Widget _buildFundamentalAnalysisTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFundamentalMetricsTable(context),
        const SizedBox(height: 20),
        _buildMarketCautionCard(context),
      ],
    );
  }

  Widget _buildPredictionsTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPredictionCards(context),
        const SizedBox(height: 20),
        _buildMarketCautionCard(context),
        const SizedBox(height: 20),
        _buildDetailedAnalysisSection(context),
      ],
    );
  }

  Widget _buildSignalsFlagsTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._selectedSymbols.asMap().entries.map((entry) {
          final symbol = entry.value;
          final entryData =
              entry.key < _stockEntries.length ? _stockEntries[entry.key] : const <String, dynamic>{};
          return Column(
            children: [
              if (entry.key > 0) const SizedBox(height: 24),
              _buildSignalsForStock(context, symbol, entryData),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildResultBadges(BuildContext context) {
    if (_comparisonData is! Map) return const SizedBox.shrink();
    final data = _comparisonData as Map<String, dynamic>;

    // The backend returns its picks under 'rankings'.
    final rankings = data['rankings'];
    if (rankings is! Map) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            // First row
            Row(
              children: [
                if (rankings['best_overall'] != null)
                  Expanded(
                    child: _buildBadge(
                      context,
                      'BEST OVERALL',
                      _str((rankings['best_overall'] as Map)['symbol']),
                      Colors.amber,
                      Icons.emoji_events,
                    ),
                  ),
                const SizedBox(width: 12),
                if (rankings['best_value'] != null)
                  Expanded(
                    child: _buildBadge(
                      context,
                      'BEST VALUE',
                      _str((rankings['best_value'] as Map)['symbol']),
                      Colors.blue,
                      Icons.diamond,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Second row
            Row(
              children: [
                if (rankings['best_growth'] != null)
                  Expanded(
                    child: _buildBadge(
                      context,
                      'BEST GROWTH',
                      _str((rankings['best_growth'] as Map)['symbol']),
                      Colors.purple,
                      Icons.rocket_launch,
                    ),
                  ),
                const SizedBox(width: 12),
                if (rankings['safest_pick'] != null)
                  Expanded(
                    child: _buildBadge(
                      context,
                      'SAFEST PICK',
                      _str((rankings['safest_pick'] as Map)['symbol']),
                      Colors.green,
                      Icons.shield,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStockCards(BuildContext context) {
    final entries = _stockEntries;
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      children: entries.map<Widget>((stockData) {
        return _buildStockCard(context, stockData);
      }).toList(),
    );
  }

  Widget _buildStockCard(BuildContext context, Map<String, dynamic> stockData) {
    final stock = _map(stockData['stock']);
    final symbol = _str(stock['symbol']);
    final name = _str(stock['name']);
    final recommendation = _map(stockData['recommendation']);
    final action = _str(recommendation['action'], 'N/A');
    final score = _num(recommendation['score']);
    final breakdown = _map(recommendation['breakdown']);
    final technicalScore = _num(breakdown['technical_score']);
    final fundamentalScore = _num(breakdown['fundamental_score']);
    final summary = _str(recommendation['summary'], 'No data available');

    if (symbol.isEmpty) return const SizedBox.shrink();

    // Determine status color based on action
    Color statusColor;
    switch (action.toLowerCase()) {
      case 'buy':
      case 'strong buy':
        statusColor = Colors.green;
        break;
      case 'hold':
      case 'caution':
        statusColor = Colors.orange;
        break;
      case 'sell':
      case 'avoid':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        symbol,
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        name,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.bookmark_border, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                action,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildScoreRow(
                context, 'Overall Score', score?.toStringAsFixed(1) ?? 'N/A'),
            const SizedBox(height: 8),
            _buildScoreRow(context, 'Technical', _fmt(technicalScore, decimals: 1)),
            const SizedBox(height: 8),
            _buildScoreRow(context, 'Fundamental', _fmt(fundamentalScore, decimals: 1)),
            const SizedBox(height: 16),
            Text(
              summary,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 11,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreRow(BuildContext context, String label, String score) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.textTheme.bodySmall),
        Text(
          score,
          style: context.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _columnValue(int index, String Function(Map<String, dynamic>) getter) {
    if (index >= _stockEntries.length) return '';
    return getter(_stockEntries[index]);
  }

  Widget _buildKeyMetricsTable(BuildContext context) {
    if (_stockEntries.isEmpty) return const SizedBox.shrink();

    String price(Map<String, dynamic> e) => _fmt(e['price'], suffix: ' TZS');
    String change(Map<String, dynamic> e) {
      final technical = _map(e['technical']);
      return _fmt(technical['change_percent'], suffix: '%');
    }
    Color changeColor(Map<String, dynamic> e) {
      final technical = _map(e['technical']);
      final v = _num(technical['change_percent']);
      return v == null ? Colors.grey : (v >= 0 ? Colors.green : Colors.red);
    }
    String health(Map<String, dynamic> e) {
      final fundamental = _map(e['fundamental']);
      final score = _num(fundamental['health_score']);
      if (score == null) return 'N/A';
      return '${score.toStringAsFixed(0)}%\n${_healthRating(score)}';
    }

    return Container(
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KEY METRICS',
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: context.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 20),
            _buildMetricTableRow(
              context,
              'Current Price',
              _columnValue(0, price),
              _columnValue(1, price),
              _columnValue(2, price),
            ),
            const Divider(),
            _buildMetricTableRow(
              context,
              '$period-Day Change',
              _columnValue(0, change),
              _columnValue(1, change),
              _columnValue(2, change),
              valueColors: [
                changeColor(_stockEntries[0]),
                _stockEntries.length > 1 ? changeColor(_stockEntries[1]) : null,
                _stockEntries.length > 2 ? changeColor(_stockEntries[2]) : null,
              ],
            ),
            const Divider(),
            _buildMetricTableRow(
              context,
              'Financial Health',
              _columnValue(0, health),
              _columnValue(1, health),
              _columnValue(2, health),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTableRow(BuildContext context, String label, String value1, String value2, String value3, {List<Color?>? valueColors}) {
    valueColors ??= [null, null, null];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value1,
              style: context.textTheme.bodyMedium?.copyWith(
                color: valueColors[0],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              value2,
              style: context.textTheme.bodyMedium?.copyWith(
                color: valueColors[1],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              value3,
              style: context.textTheme.bodyMedium?.copyWith(
                color: valueColors[2],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Real, computed highlights — no hard-coded figures.
  Widget _buildDetailedAnalysisSection(BuildContext context) {
    double? volOf(Map<String, dynamic> e) =>
        _num(_map(e['technical'])['volatility']);
    double? roeOf(Map<String, dynamic> e) {
      final metrics = _map(_map(e['fundamental'])['metrics']);
      return _num(_map(metrics['profitability'])['roe']);
    }
    double? changeOf(Map<String, dynamic> e) =>
        _num(_map(e['technical'])['change_percent']);
    String symbolOf(Map<String, dynamic> e) =>
        _str(_map(e['stock'])['symbol']);

    final withTechnical =
        _stockEntries.where((e) => volOf(e) != null).toList();
    final withRoeList = _stockEntries.where((e) => roeOf(e) != null).toList();
    final negativeMovers = _stockEntries
        .where((e) => changeOf(e) != null && changeOf(e)! < 0)
        .toList();

    final stable = withTechnical.isNotEmpty
        ? withTechnical.reduce((a, b) => (volOf(a)! <= volOf(b)!) ? a : b)
        : null;
    final bestRoe = withRoeList.isNotEmpty
        ? withRoeList.reduce((a, b) => (roeOf(a)! >= roeOf(b)!) ? a : b)
        : null;
    final weakestStock = negativeMovers.isNotEmpty
        ? negativeMovers.reduce((a, b) => (changeOf(a)! <= changeOf(b)!) ? a : b)
        : null;

    final items = <_AnalysisHighlight>[];
    if (stable != null) {
      items.add(_AnalysisHighlight(
        icon: Icons.shield,
        iconColor: Colors.green,
        title: 'Most Stable',
        description: '${symbolOf(stable)} has the lowest volatility at ${_fmt(volOf(stable), suffix: '%')}.',
      ));
    }
    if (bestRoe != null) {
      items.add(_AnalysisHighlight(
        icon: Icons.monetization_on,
        iconColor: Colors.amber,
        title: 'Profitability Leader',
        description: '${symbolOf(bestRoe)} leads the comparison with ${_fmt(roeOf(bestRoe), suffix: '%')} ROE.',
      ));
    }
    if (weakestStock != null) {
      items.add(_AnalysisHighlight(
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.orange,
        title: 'Weakest Mover',
        description:
            '${symbolOf(weakestStock)} is down ${_fmt(changeOf(weakestStock))}% over the selected period.',
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, color: context.colorScheme.onSurface),
                const SizedBox(width: 8),
                Text(
                  'Detailed Analysis',
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...items.asMap().entries.map((entry) {
              final item = entry.value;
              return Column(
                children: [
                  if (entry.key > 0) const SizedBox(height: 16),
                  _buildAnalysisItem(
                    context,
                    icon: item.icon,
                    iconColor: item.iconColor,
                    title: item.title,
                    description: item.description,
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisItem(BuildContext context, {required IconData icon, required Color iconColor, required String title, required String description}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Normalised (indexed to 100) price movement for the selected period.
  Widget _buildPriceMovementChart(BuildContext context) {
    final symbolsWithSeries =
        _selectedSymbols.where((s) => !_seriesIsEmpty(s)).toList();

    return Container(
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Price Movement Comparison',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Indexed to 100 at the start of the selected period',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            if (_loadingPrices)
              const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (symbolsWithSeries.isEmpty)
              Container(
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'No price data available for this period',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 260,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: context.colorScheme.onSurface.withValues(alpha: 0.1),
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 10,
                          reservedSize: 36,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: context.textTheme.bodySmall,
                          ),
                        ),
                      ),
                      bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(
                        color: context.colorScheme.onSurface.withValues(alpha: 0.1),
                      ),
                    ),
                    minY: _minIndex(symbolsWithSeries) - 2,
                    maxY: _maxIndex(symbolsWithSeries) + 2,
                    lineBarsData: [
                      for (int i = 0; i < symbolsWithSeries.length; i++)
                        LineChartBarData(
                          spots: List.generate(
                            _priceSeries[symbolsWithSeries[i]]!.length,
                            (x) => FlSpot(
                              x.toDouble(),
                              _priceSeries[symbolsWithSeries[i]]![x],
                            ),
                          ),
                          isCurved: true,
                          color: _seriesColors[i % _seriesColors.length],
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                children: [
                  for (int i = 0; i < symbolsWithSeries.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _seriesColors[i % _seriesColors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          symbolsWithSeries[i],
                          style: context.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _seriesIsEmpty(String symbol) {
    final series = _priceSeries[symbol];
    return series == null || series.isEmpty;
  }

  double _minIndex(List<String> symbols) {
    double min = double.infinity;
    for (final s in symbols) {
      for (final v in _priceSeries[s]!) {
        if (v < min) min = v;
      }
    }
    return min;
  }

  double _maxIndex(List<String> symbols) {
    double max = double.negativeInfinity;
    for (final s in symbols) {
      for (final v in _priceSeries[s]!) {
        if (v > max) max = v;
      }
    }
    return max;
  }

  Widget _buildTechnicalMetricsTable(BuildContext context) {
    if (_stockEntries.isEmpty) return const SizedBox.shrink();

    String volatility(Map<String, dynamic> e) {
      final v = _num(_map(e['technical'])['volatility']);
      if (v == null) return 'N/A';
      final level = v < 1 ? 'Low' : (v < 5 ? 'Medium' : 'High');
      return '${v.toStringAsFixed(2)}%\n$level';
    }

    String holdingPattern(Map<String, dynamic> e, String key) {
      final stats = _map(_map(e['technical'])['holding_stats']);
      final s = _map(stats[key]);
      final gain = _num(s['avg_gain']);
      final success = _num(s['success_rate']);
      if (gain == null && success == null) return 'N/A';
      return '${gain == null ? 'N/A' : gain.toStringAsFixed(2)}%\nSuccess: ${success == null ? 'N/A' : success.toStringAsFixed(1)}%';
    }

    return Container(
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TECHNICAL METRICS',
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: context.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 20),
            _buildTechnicalMetricRow(
              context,
              'Volatility',
              _columnValue(0, volatility),
              _columnValue(1, volatility),
              _columnValue(2, volatility),
            ),
            const Divider(),
            _buildTechnicalMetricRow(
              context,
              '1-Week Pattern',
              _columnValue(0, (e) => holdingPattern(e, '1w')),
              _columnValue(1, (e) => holdingPattern(e, '1w')),
              _columnValue(2, (e) => holdingPattern(e, '1w')),
            ),
            const Divider(),
            _buildTechnicalMetricRow(
              context,
              '1-Month Pattern',
              _columnValue(0, (e) => holdingPattern(e, '1m')),
              _columnValue(1, (e) => holdingPattern(e, '1m')),
              _columnValue(2, (e) => holdingPattern(e, '1m')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalMetricRow(BuildContext context, String label, String value1, String value2, String value3) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value1,
              style: context.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              value2,
              style: context.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              value3,
              style: context.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFundamentalMetricsTable(BuildContext context) {
    if (_stockEntries.isEmpty) return const SizedBox.shrink();

    dynamic metricValue(Map<String, dynamic> e, String path) {
      final metrics = _map(_map(e['fundamental'])['metrics']);
      final parts = path.split('.');
      dynamic node = metrics;
      for (final part in parts) {
        if (node is Map) {
          node = node[part];
        } else {
          return null;
        }
      }
      return node;
    }

    String pe(Map<String, dynamic> e) =>
        _fmt(metricValue(e, 'valuation.pe_ratio'));
    String pb(Map<String, dynamic> e) =>
        _fmt(metricValue(e, 'valuation.pb_ratio'));
    String roe(Map<String, dynamic> e) =>
        _fmt(metricValue(e, 'profitability.roe'), suffix: '%');
    String de(Map<String, dynamic> e) {
      final metrics = _map(_map(e['fundamental'])['metrics']);
      final meta = _map(metrics['_meta']);
      // Banks have no leverage group; showing '—' is honest.
      if (meta['industry_type'] == 'banking') return '— (bank)';
      return _fmt(metricValue(e, 'leverage.debt_to_equity'));
    }
    String dy(Map<String, dynamic> e) =>
        _fmt(metricValue(e, 'valuation.dividend_yield'), suffix: '%');
    String mos(Map<String, dynamic> e) {
      final valuation = _map(_map(e['fundamental'])['valuation']);
      return _fmt(valuation['margin_of_safety'], suffix: '%');
    }

    return Container(
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'FUNDAMENTAL METRICS',
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: context.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 20),
            _buildMetricTableRow(context, 'P/E Ratio', _columnValue(0, pe), _columnValue(1, pe), _columnValue(2, pe)),
            const Divider(),
            _buildMetricTableRow(context, 'P/B Ratio', _columnValue(0, pb), _columnValue(1, pb), _columnValue(2, pb)),
            const Divider(),
            _buildMetricTableRow(context, 'ROE', _columnValue(0, roe), _columnValue(1, roe), _columnValue(2, roe)),
            const Divider(),
            _buildMetricTableRow(context, 'Debt-to-Equity', _columnValue(0, de), _columnValue(1, de), _columnValue(2, de)),
            const Divider(),
            _buildMetricTableRow(context, 'Dividend Yield', _columnValue(0, dy), _columnValue(1, dy), _columnValue(2, dy)),
            const Divider(),
            _buildMetricTableRow(context, 'Margin of Safety', _columnValue(0, mos), _columnValue(1, mos), _columnValue(2, mos)),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionCards(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final children = _selectedSymbols.asMap().entries
            .map((entry) {
              final entryData = entry.key < _stockEntries.length
                  ? _stockEntries[entry.key]
                  : const <String, dynamic>{};
              final fundamental = _map(entryData['fundamental']);
              final prediction = _map(fundamental['prediction']);
              final stock = _map(entryData['stock']);
              return _buildPredictionCard(
                context,
                _str(stock['symbol'], 'Stock ${entry.key + 1}'),
                currentPrice: _fmt(entryData['price']),
                target: _fmt(prediction['predicted_price']),
                expectedChange: _fmt(prediction['expected_change_percent'], suffix: '%'),
                conservative: _fmt(prediction['conservative_price']),
                optimistic: _fmt(prediction['optimistic_price']),
                confidence: prediction['confidence']?.toString(),
                hasData: prediction.isNotEmpty,
              );
            })
            .toList();

        // Use column layout on small screens, row on larger screens
        if (constraints.maxWidth < 600 || children.length > 2) {
          return Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                children[i],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPredictionCard(
    BuildContext context,
    String stock, {
    String? currentPrice,
    String? target,
    String? expectedChange,
    String? conservative,
    String? optimistic,
    String? confidence,
    bool hasData = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stock,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            if (hasData) ...[
              Text(
                'Current Price',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              Text(
                currentPrice ?? 'N/A',
                style: context.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '3-Month Target',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              Text(
                target ?? 'N/A',
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Expected Change',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              Text(
                expectedChange ?? 'N/A',
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Conservative', style: context.textTheme.bodySmall),
                  Text(conservative ?? 'N/A', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Optimistic', style: context.textTheme.bodySmall),
                  Text(optimistic ?? 'N/A', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Confidence', style: context.textTheme.bodySmall),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      (confidence ?? 'unknown')
                          .split('')
                          .map((c) => c.toUpperCase())
                          .join()
                          .toLowerCase(),
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'No prediction data available for this stock',
                    style: TextStyle(color: context.colorScheme.onSurface.withValues(alpha: 0.55)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSignalsForStock(
      BuildContext context, String stockCode, Map<String, dynamic> stockEntry) {
    final fundamental = _map(stockEntry['fundamental']);
    final signals = _map(fundamental['signals']);
    final greenFlags = signals['green_flags'] is List
        ? signals['green_flags']
            .whereType<Map<String, dynamic>>()
            .toList()
        : <Map<String, dynamic>>[];
    final redFlags = signals['red_flags'] is List
        ? signals['red_flags']
            .whereType<Map<String, dynamic>>()
            .toList()
        : <Map<String, dynamic>>[];

    return Container(
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stockCode,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            if (greenFlags.isEmpty && redFlags.isEmpty) ...[
              Text(
                'No signal data available for this stock',
                style: TextStyle(color: context.colorScheme.onSurface.withValues(alpha: 0.55)),
              ),
            ] else ...[
              if (greenFlags.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Positive Signals (${greenFlags.length})',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...greenFlags.map((signal) => _buildSignalCard(context, signal, Colors.green)),
                const SizedBox(height: 20),
              ],
              if (redFlags.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.cancel, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Warning Signals (${redFlags.length})',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...redFlags.map((signal) => _buildSignalCard(context, signal, Colors.red)),
              ]
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSignalCard(BuildContext context, Map<String, dynamic> signal, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _str(signal['title']),
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _str(signal['description'], ''),
            style: context.textTheme.bodySmall?.copyWith(
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String label, String stock, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stock,
            style: context.textTheme.titleLarge?.copyWith(
              color: context.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Derived from the real scores — a warning when the comparison contains
  /// weak stocks, otherwise a positive note.
  Widget _buildMarketCautionCard(BuildContext context) {
    if (_stockEntries.isEmpty) return const SizedBox.shrink();

    final weak = _stockEntries.where((e) {
      final score = _num(_map(e['fundamental'])['health_score']);
      final action = _str(_map(_map(e['recommendation'])['action']), '');
      return (score != null && score < 40) ||
          action.toLowerCase() == 'avoid' ||
          action.toLowerCase() == 'caution';
    }).toList();

    final (title, body, color) = weak.isEmpty
        ? (
            'MARKET OUTLOOK',
            'All selected stocks show acceptable fundamental health for the selected period.',
            Colors.green,
          )
        : (
            'MARKET CAUTION',
            '${weak.length} of ${_stockEntries.length} selected stock${weak.length > 1 ? 's' : ''} show${weak.length > 1 ? '' : 's'} weak signals'
                ' (${weak.map((e) => _str(_map(e['stock'])['symbol'])).join(', ')}). '
                'Consider waiting for better opportunities.',
            Colors.amber,
          );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            color == Colors.amber ? Icons.warning_amber_rounded : Icons.check_circle,
            color: color[700] ?? color,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.textTheme.titleSmall?.copyWith(
                    color: color[900] ?? color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: color[900] ?? color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisHighlight {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  _AnalysisHighlight({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });
}
