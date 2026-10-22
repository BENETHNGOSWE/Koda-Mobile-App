import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/config/dio_client.dart';
import '../../../core/config/constants/app_constants.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/app_providers.dart';

class StockDetailScreen extends ConsumerStatefulWidget {
  final String symbol;

  const StockDetailScreen({
    super.key,
    required this.symbol,
  });

  @override
  ConsumerState<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends ConsumerState<StockDetailScreen> {
  Map<String, dynamic>? stockData;
  List<Map<String, dynamic>> priceData = [];
  Map<String, dynamic>? simulationData;
  String? _stockError;

  bool _isLoadingStock = true;
  bool _isLoadingPrices = true;
  bool _isLoadingSimulation = false;

  String _selectedPeriod = '1M';
  int _selectedDays = 30;
  bool _inWatchlist = false;

  final TextEditingController _capitalController = TextEditingController(text: '100000');
  final TextEditingController _dateController = TextEditingController();
  String _selectedStrategy = 'Balanced';

  /// The API serialises decimal columns as strings ("2910.00"), so every
  /// value that gets compared or formatted must go through this.
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

  @override
  void initState() {
    super.initState();
    _inWatchlist =
        ref.read(manageWatchlistProvider).isInWatchlist(widget.symbol);
    _fetchStockDetails();
    _fetchPriceData();
    _setDefaultDate();
  }

  @override
  void dispose() {
    _capitalController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _setDefaultDate() {
    final now = DateTime.now();
    _dateController.text = '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
  }

  Future<void> _fetchStockDetails() async {
    setState(() => _isLoadingStock = true);
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('${AppConstants.baseUrl}/stocks/${widget.symbol}');

      debugPrint('Stock response: ${response.data}');

      if (mounted) {
        setState(() {
          // API returns data under response.data['data']['stock']
          final raw = response.data;
          stockData = raw is Map
              ? (raw['data'] is Map ? raw['data']['stock'] : raw['stock'])
              : null;
          if (stockData is! Map) {
            _stockError = 'Stock data not found for ${widget.symbol}.';
          }
          _isLoadingStock = false;
        });
        debugPrint('Stock data loaded: $stockData');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingStock = false;
          _stockError = _extractError(e);
        });
      }
      debugPrint('Error fetching stock details: $e');
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
    return 'Something went wrong. Please try again.';
  }

  Future<void> _fetchPriceData() async {
    setState(() => _isLoadingPrices = true);
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        '${AppConstants.baseUrl}/stocks/${widget.symbol}/prices',
        queryParameters: {'days': _selectedDays},
      );

      if (mounted) {
        setState(() {
          priceData = (response.data['data']['prices'] as List<dynamic>)
              .map((p) => p as Map<String, dynamic>)
              .toList();
          _isLoadingPrices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPrices = false);
      }
      debugPrint('Error fetching price data: $e');
    }
  }

  Future<void> _runSimulation() async {
    if (stockData == null || stockData!['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock data not loaded yet')),
      );
      return;
    }

    // Validate capital input
    if (_capitalController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter investment capital')),
      );
      return;
    }

    final capital = int.tryParse(_capitalController.text);
    if (capital == null || capital <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid investment amount')),
      );
      return;
    }

    setState(() => _isLoadingSimulation = true);
    try {
      final dio = ref.read(dioProvider);

      final requestData = {
        'stock_id': stockData!['id'],
        'capital': capital,
        'strategy': _selectedStrategy.toLowerCase(),
      };

      // Only add buy_date if it's provided
      if (_dateController.text.isNotEmpty) {
        requestData['buy_date'] = _formatDateForApi(_dateController.text);
      }

      debugPrint('Sending simulation request: $requestData');

      final response = await dio.post(
        '${AppConstants.baseUrl}/simulate-investment',
        data: requestData,
      );

      debugPrint('Simulation response: ${response.data}');

      if (mounted) {
        setState(() {
          simulationData = response.data['data'];
          _isLoadingSimulation = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Simulation completed successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSimulation = false);
      }
      debugPrint('Error running simulation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  String _formatDateForApi(String displayDate) {
    // Convert MM/DD/YYYY to YYYY-MM-DD
    final parts = displayDate.split('/');
    if (parts.length == 3) {
      return '${parts[2]}-${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}';
    }
    return displayDate;
  }

  void _changePeriod(String period, int days) {
    setState(() {
      _selectedPeriod = period;
      _selectedDays = days;
    });
    _fetchPriceData();
  }

  Future<void> _toggleWatchlist() async {
    final watchlist = ref.read(manageWatchlistProvider);
    final ok = _inWatchlist
        ? await watchlist.removeFromWatchlist(widget.symbol)
        : await watchlist.addToWatchlist(widget.symbol);
    if (!ok || !mounted) return;
    setState(() => _inWatchlist = !_inWatchlist);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_inWatchlist
            ? '$widget.symbol added to watchlist'
            : '$widget.symbol removed from watchlist'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Percent move over the currently selected period (first vs last close).
  double? _periodReturn() {
    final closes = _parsedCloses();
    if (closes.length < 2) return null;
    final first = closes.first;
    if (first <= 0) return null;
    return (closes.last - first) / first * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundDecoration: context.ambientTopGlow,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _inWatchlist ? Icons.star : Icons.star_border,
              color: _inWatchlist ? Colors.amber : null,
            ),
            tooltip: 'Watchlist',
            onPressed: _toggleWatchlist,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoadingStock
          ? const Center(child: CircularProgressIndicator())
          : _stockError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: context.colorScheme.error),
                        const SizedBox(height: 16),
                        Text(
                          _stockError!,
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _stockError = null);
                            _fetchStockDetails();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stock Header
                  _buildStockHeader(),
                  const SizedBox(height: 16),

                  // 1. Chart container
                  _buildPriceChart(),
                  const SizedBox(height: 12),

                  // 2. Timeline (period) container
                  _buildPeriodPills(),
                  const SizedBox(height: 24),

                  // 3. Trading Simulator
                  _buildTradingSimulator(),
                  const SizedBox(height: 32),

                  // Simulation Results
                  if (simulationData != null) ...[
                    _buildSimulationResults(),
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStockHeader() {
    if (stockData is! Map) return const SizedBox();

    final changePercent = _num(stockData!['change_percent']) ?? 0.0;
    final isPositive = changePercent >= 0;
    final currentPrice = _num(stockData!['current_price']);
    final change = _num(stockData!['change']);
    final changeColor = isPositive
        ? const Color(AppColors.successColor)
        : const Color(AppColors.errorColor);
    final name = (stockData!['name'] ?? '').toString();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.white,
          child: Text(
            widget.symbol.length >= 2
                ? widget.symbol.substring(0, 2).toUpperCase()
                : widget.symbol,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.symbol,
                style: context.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (name.isNotEmpty)
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall?.copyWith(
                    color:
                        context.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              currentPrice == null
                  ? '—'
                  : 'TZS ${NumberFormat('#,##0.00').format(currentPrice)}',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (change != null) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: changeColor,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${isPositive ? '+' : ''}${change.toStringAsFixed(2)} '
                    '(${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: changeColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Compact period pills (1D 1W 1M 3M 6M 1Y) + the period's return,
  /// rendered inside the chart card below the chart.
  Widget _buildPeriodPills() {
    final periods = <String, int>{
      '1D': 1,
      '1W': 7,
      '1M': 30,
      '3M': 90,
      '6M': 180,
      '1Y': 365,
    };
    final periodReturn = _periodReturn();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: context.cardDecoration(radius: 20),
      child: Row(
        children: [
          for (final entry in periods.entries)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: GestureDetector(
                onTap: () => _changePeriod(entry.key, entry.value),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _selectedPeriod == entry.key
                        ? context.colorScheme.onSurface.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _selectedPeriod == entry.key
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _selectedPeriod == entry.key
                          ? context.colorScheme.onSurface
                          : context.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          if (periodReturn != null) ...[
            Icon(
              Icons.candlestick_chart,
              size: 15,
              color: periodReturn >= 0
                  ? const Color(AppColors.successColor)
                  : const Color(AppColors.errorColor),
            ),
            const SizedBox(width: 4),
            Text(
              '${periodReturn >= 0 ? '+' : ''}${periodReturn.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: periodReturn >= 0
                    ? const Color(AppColors.successColor)
                    : const Color(AppColors.errorColor),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceChart() {
    const chartHeight = 320.0;
    const bottomAxis = 26.0;
    const rightAxis = 46.0;
    const lineColor = Color(0xFF22C55E);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: context.cardDecoration(radius: 20),
      child: Column(
        children: [
          _isLoadingPrices
              ? const SizedBox(
                  height: 280,
                  child: Center(child: CircularProgressIndicator()),
                )
              : priceData.isEmpty || _parsedCloses().isEmpty
                  ? SizedBox(
                      height: 280,
                      child: Center(
                        child: Text(
                          'No price data for this period',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final closes = _parsedCloses();
                        final min = closes.reduce((a, b) => a < b ? a : b);
                        final max = closes.reduce((a, b) => a > b ? a : b);
                        final range = (max - min) == 0
                            ? (max * 0.02) + 1
                            : max - min;
                        final minY = min - range * 0.06;
                        final maxY = max + range * 0.06;
                        final last = closes.last;
                        final plotH = chartHeight - bottomAxis;
                        final rel = (last - minY) / (maxY - minY);
                        final pointY = (1 - rel) * plotH;
                        final pillTop =
                            (pointY - 11).clamp(0.0, plotH - 22).toDouble();

                        return SizedBox(
                          height: chartHeight,
                          child: Stack(
                            children: [
                              LineChart(
                                LineChartData(
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: false,
                                    drawHorizontalLine: true,
                                    horizontalInterval: (maxY - minY) / 4,
                                    getDrawingHorizontalLine: (value) {
                                      return FlLine(
                                        color: context.colorScheme.onSurface
                                            .withValues(alpha: 0.07),
                                        strokeWidth: 1,
                                      );
                                    },
                                  ),
                                  titlesData: FlTitlesData(
                                    show: true,
                                    leftTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false),
                                    ),
                                    topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false),
                                    ),
                                    rightTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: rightAxis,
                                        interval: (maxY - minY) / 4,
                                        getTitlesWidget: (value, meta) {
                                          return Text(
                                            NumberFormat('#,##0')
                                                .format(value),
                                            style: context.textTheme
                                                .bodySmall
                                                ?.copyWith(fontSize: 9),
                                          );
                                        },
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: bottomAxis,
                                        interval: (priceData.length / 6)
                                            .ceilToDouble()
                                            .clamp(1.0, 24.0),
                                        getTitlesWidget: (value, meta) {
                                          final i = value.toInt();
                                          if (i < 0 || i >= priceData.length) {
                                            return const Text('');
                                          }
                                          final date = priceData[i]['date']
                                                  ?.toString() ??
                                              '';
                                          final parts = date.split('-');
                                          if (parts.length == 3) {
                                            try {
                                              final dt = DateTime(
                                                  int.parse(parts[0]),
                                                  int.parse(parts[1]),
                                                  int.parse(parts[2]));
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 6),
                                                child: Text(
                                                  _selectedDays >= 90
                                                      ? DateFormat('MMM')
                                                          .format(dt)
                                                      : DateFormat('d MMM')
                                                          .format(dt),
                                                  style: context.textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                          fontSize: 9),
                                                ),
                                              );
                                            } catch (_) {
                                              return const Text('');
                                            }
                                          }
                                          return const Text('');
                                        },
                                      ),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  minX: 0,
                                  maxX: (priceData.length - 1).toDouble(),
                                  minY: minY,
                                  maxY: maxY,
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: priceData
                                              .asMap()
                                              .entries
                                              .where((entry) {
                                                final v =
                                                    _num(entry.value['close']);
                                                return v != null && v > 0;
                                              })
                                              .map((entry) {
                                        return FlSpot(
                                          entry.key.toDouble(),
                                          _num(entry.value['close'])!
                                              .toDouble(),
                                        );
                                      }).toList(),
                                      isCurved: true,
                                      color: lineColor,
                                      barWidth: 2.5,
                                      isStrokeCapRound: true,
                                      dotData: const FlDotData(show: false),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: lineColor
                                            .withValues(alpha: 0.10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Vertical guide at the last close
                              Positioned(
                                right: rightAxis + 0.5,
                                top: pointY,
                                height:
                                    (plotH - pointY).clamp(0.0, plotH).toDouble(),
                                width: 1,
                                child: Container(
                                  color: lineColor.withValues(alpha: 0.45),
                                ),
                              ),
                              // Last-price pill on the right edge
                              Positioned(
                                right: rightAxis + 6,
                                top: pillTop,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: lineColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    NumberFormat('#,##0').format(last),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }

  /// Close prices that could actually be parsed; rows with a missing or
  /// malformed close are skipped instead of crashing the chart.
  List<double> _parsedCloses() {
    final out = <double>[];
    for (final p in priceData) {
      final v = _num(p['close']);
      // Skip missing or zero/negative closes — junk rows that would
      // spike the chart down to 0.
      if (v != null && v > 0) out.add(v);
    }
    return out;
  }

  InputDecoration _fieldDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: context.colorScheme.surfaceContainerHighest,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: context.colorScheme.onSurface.withValues(alpha: 0.32),
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: context.colorScheme.onSurface.withValues(alpha: 0.32),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: const Color(0xFF2563EB),
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildTradingSimulator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(AppColors.errorColor).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.smart_toy,
                  size: 18,
                  color: Color(AppColors.errorColor),
                ),
              ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Professional Trading Simulator',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                // Use column layout for small screens, row for larger screens
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCapitalField(),
                      const SizedBox(height: 16),
                      _buildDateField(),
                      const SizedBox(height: 16),
                      _buildStrategyField(),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: _buildCapitalField()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildDateField()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildStrategyField()),
                  ],
                );
              },
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoadingSimulation ? null : _runSimulation,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoadingSimulation
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Run Simulation',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapitalField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Investment Capital (TZS)',
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _capitalController,
          keyboardType: TextInputType.number,
          style: context.textTheme.bodyMedium,
          decoration: _fieldDecoration().copyWith(hintText: '100000'),
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Buy Date (Optional)',
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _dateController,
          style: context.textTheme.bodyMedium,
          decoration: _fieldDecoration().copyWith(
            hintText: 'mm/dd/yyyy',
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          readOnly: true,
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (date != null) {
              _dateController.text = '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
            }
          },
        ),
      ],
    );
  }

  Widget _buildStrategyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Strategy',
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedStrategy,
          isExpanded: true,
          items: ['Balanced', 'Aggressive', 'Conservative']
              .map((strategy) => DropdownMenuItem(
                    value: strategy,
                    child: Text(strategy),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedStrategy = value);
            }
          },
          decoration: _fieldDecoration(),
        ),
      ],
    );
  }

  Widget _buildSimulationResults() {
    if (simulationData is! Map) return const SizedBox();

    final investment = _map(simulationData!['investment']);
    final currentStatus = _map(simulationData!['current_status']);
    final marketSentiment = _map(simulationData!['market_sentiment']);
    final bestStrategy = _map(simulationData!['best_strategy']);
    final primaryRec = _map(bestStrategy['primary_recommendation']);
    final profitLossPercent = _num(currentStatus['profit_loss_percent']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Investment Summary — flat 2x2 tiles
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildSummaryTile(
                    'Investment',
                    'TZS ${_formatNumber(investment['actual_investment'])}',
                    '${investment['shares']} shares',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryTile(
                    'Current value',
                    'TZS ${_formatNumber(currentStatus['current_value'])}',
                    profitLossPercent == null
                        ? '—'
                        : '${profitLossPercent >= 0 ? '+' : ''}${profitLossPercent.toStringAsFixed(2)}%',
                    profitLossPercent == null
                        ? null
                        : profitLossPercent >= 0
                            ? const Color(AppColors.successColor)
                            : const Color(AppColors.errorColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryTile(
                    'Recommended action',
                    _str(primaryRec['action']),
                    _str(primaryRec['holding_period']),
                    _actionColor(_str(primaryRec['action'])),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryTile(
                    'Market sentiment',
                    _str(marketSentiment['sentiment']),
                    'Score: ${_fmt(marketSentiment['sentiment_score'])}%',
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Predictions Tabs
        _buildPredictionsTabs(),
      ],
    );
  }

  Widget _buildSummaryTile(
    String title,
    String value,
    String subtitle, [
    Color? valueColor,
  ]) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: context.colorScheme.onSurface
                  .withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor ?? context.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurface
                  .withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Color? _actionColor(String action) {
    final a = action.toLowerCase();
    if (a.contains('buy')) return const Color(AppColors.successColor);
    if (a.contains('sell')) return const Color(AppColors.errorColor);
    return null;
  }

  Widget _buildPredictionsTabs() {
    if (simulationData is! Map) return const SizedBox();

    final predictions = _map(simulationData!['predictions']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPredictionsTab(predictions),
        const SizedBox(height: 28),
        _buildTechnicalTab(),
        const SizedBox(height: 28),
        _buildSignalsTab(),
        const SizedBox(height: 28),
        _buildBestStrategyTab(),
      ],
    );
  }

  Widget _buildPredictionsTab(Map<String, dynamic> predictions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Text(
            'Price Predictions & Scenarios',
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildPredictionCard('2d', _map(predictions['2d'])),
              _buildPredictionCard('1w', _map(predictions['1w'])),
              _buildPredictionCard('2w', _map(predictions['2w'])),
              _buildPredictionCard('1m', _map(predictions['1m'])),
              _buildPredictionCard('3m', _map(predictions['3m'])),
              _buildPredictionCard('6m', _map(predictions['6m'])),
            ],
          ),
        ],
    );
  }

  Widget _buildPredictionCard(String key, Map<String, dynamic> prediction) {
    final scenariosRaw = prediction['scenarios'];
    if (scenariosRaw is! Map) return const SizedBox.shrink();
    final scenarios = scenariosRaw.cast<String, dynamic>();
    final confidence = _map(prediction['confidence']);
    final confidenceScore = _num(confidence['score']);
    final expectedProfit = _num(scenarios['expected'] is Map ? (scenarios['expected'] as Map)['profit'] : null);
    final expected = _map(scenarios['expected']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final confidenceColor = _getConfidenceColor(confidenceScore);
        return Container(
          width: constraints.maxWidth < 600
              ? constraints.maxWidth
              : (constraints.maxWidth - 12) / 2,
          padding: const EdgeInsets.all(16),
          decoration: context.cardDecoration(radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _str(prediction['period'], key),
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  confidenceScore == null
                      ? 'N/A'
                      : '${confidenceScore.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: confidenceColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_str(prediction['days'], '0')} days',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const Divider(height: 24),
          _buildScenarioRow('Best Case:', _scenarioValue(scenarios, 'best', 'price'), _scenarioValue(scenarios, 'best', 'return_percent'), true),
          const SizedBox(height: 8),
          _buildScenarioRow('Expected:', expected['price'], expected['return_percent'], null),
          const SizedBox(height: 8),
          _buildScenarioRow('Worst Case:', _scenarioValue(scenarios, 'worst', 'price'), _scenarioValue(scenarios, 'worst', 'return_percent'), false),
          const Divider(height: 24),
          Text(
            'Your Return:',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'TZS ${_formatNumber(expected['profit'])}',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: expectedProfit == null || expectedProfit >= 0
                  ? const Color(AppColors.successColor)
                  : const Color(AppColors.errorColor),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(AppColors.warningColor).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _str(prediction['recommendation'], ''),
              style: context.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(AppColors.warningColor),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Risk/Reward: ${_str(prediction['risk_reward_ratio'])}:1',
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
            ],
          ),
        );
      },
    );
  }

  dynamic _scenarioValue(Map<String, dynamic> scenarios, String which, String field) {
    final item = scenarios[which];
    return item is Map ? item[field] : null;
  }

  Widget _buildScenarioRow(String label, dynamic price, dynamic percent, bool? isPositive) {
    Color color = context.colorScheme.onSurface;
    if (isPositive != null) {
      color = isPositive ? const Color(AppColors.successColor) : const Color(AppColors.errorColor);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: context.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${price.toStringAsFixed(2)}',
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            Text(
              '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%',
              style: context.textTheme.bodySmall?.copyWith(
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getConfidenceColor(double? score) {
    if (score == null) return const Color(0xFFFFA726);
    if (score >= 75) return const Color(0xFF4CAF50);
    if (score >= 65) return const Color(0xFF8BC34A);
    if (score >= 50) return const Color(0xFFFFA726);
    return const Color(0xFFFF5722);
  }

  Widget _buildTechnicalTab() {
    if (simulationData is! Map) return const SizedBox();

    final technical = _map(simulationData!['technical_analysis']);
    final movingAverages = _map(technical['moving_averages']);
    final momentum = _map(technical['momentum']);
    final supportResistance = _map(technical['support_resistance']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Text(
            'Technical Analysis',
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Indicators
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: context.cardDecoration(radius: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Moving Averages',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTechnicalRow('SMA 20', _fmt(movingAverages['sma_20'])),
                _buildTechnicalRow('SMA 50', _fmt(movingAverages['sma_50'])),
                _buildTechnicalRow('EMA 12', _fmt(movingAverages['ema_12'])),
                _buildTechnicalRow('EMA 26', _fmt(movingAverages['ema_26'])),
                _sectionDivider(),
                Text(
                  'Momentum Indicators',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTechnicalRow('RSI', '${_fmt(momentum['rsi'])} (${_str(momentum['rsi_signal'], 'n/a')})'),
                _buildTechnicalRow('MACD', '${_fmt(momentum['macd'])} (${_str(momentum['macd_signal'], 'n/a')})'),
                _sectionDivider(),
                Text(
                  'Support & Resistance',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTechnicalRow('Resistance 3', _fmt(supportResistance['resistance_3']), Colors.red),
                _buildTechnicalRow('Resistance 2', _fmt(supportResistance['resistance_2']), Colors.red),
                _buildTechnicalRow('Resistance 1', _fmt(supportResistance['resistance_1']), Colors.red),
                _buildTechnicalRow('Pivot', _fmt(supportResistance['pivot'])),
                _buildTechnicalRow('Support 1', _fmt(supportResistance['support_1']), Colors.green),
                _buildTechnicalRow('Support 2', _fmt(supportResistance['support_2']), Colors.green),
                _buildTechnicalRow('Support 3', _fmt(supportResistance['support_3']), Colors.green),
              ],
            ),
          ),
        ],
    );
  }

  Widget _buildTechnicalRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodyMedium),
          Text(
            value,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      height: 1,
      color: context.colorScheme.onSurface.withValues(alpha: 0.08),
    );
  }

  Widget _buildSignalsTab() {
    if (simulationData is! Map) return const SizedBox();

    final signals = _map(simulationData!['trading_signals']);
    final rawList = signals['signals'];
    final signalsList = rawList is List ? rawList.whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
    final summary = _map(signals['summary']);
    final overall = summary['overall']?.toString() ?? 'neutral';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Text(
            'Trading Signals',
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Overall Signal
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: context.cardDecoration(radius: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overall Signal',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getSignalColor(overall).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    overall.toUpperCase(),
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _getSignalColor(overall),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Signal List
          if (signalsList.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'No trading signals for this stock yet.',
                style: context.textTheme.bodyMedium,
              ),
            )
          else
            ...signalsList.map((signal) {
              final isBullish = signal['type'] == 'bullish';
              final message = _str(signal['message'], '');
              final strength = _str(signal['strength'], 'weak');
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: context.cardDecoration(radius: 14),
                child: Row(
                  children: [
                    Icon(
                      isBullish ? Icons.trending_up : Icons.trending_down,
                      size: 20,
                      color: isBullish
                          ? const Color(AppColors.successColor)
                          : const Color(AppColors.errorColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _str(signal['indicator']),
                            style: context.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (message.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                message,
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: context.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strength,
                      style: context.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _getStrengthColor(strength),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
    );
  }

  Widget _buildBestStrategyTab() {
    if (simulationData is! Map) return const SizedBox();

    final strategy = _map(simulationData!['best_strategy']);
    final primaryRec = _map(strategy['primary_recommendation']);
    final keyFactors = strategy['key_factors'] is List
        ? strategy['key_factors'] as List
        : <dynamic>[];
    final riskWarnings = strategy['risk_warnings'] is List
        ? strategy['risk_warnings'] as List
        : <dynamic>[];
    final expectedReturn = _num(primaryRec['expected_return']);
    final confidence = _num(primaryRec['confidence']);
    final actionText = _str(primaryRec['action']);
    final actionColor = _actionColor(actionText) ??
        const Color(AppColors.primaryColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Text(
            'Recommended Strategy',
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Primary Recommendation
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: context.cardDecoration(radius: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    actionText,
                    style: context.textTheme.titleMedium?.copyWith(
                      color: actionColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildStrategyRow('Holding Period', _str(primaryRec['holding_period'])),
                _buildStrategyRow('Expected Return', expectedReturn == null ? '—' : '${expectedReturn.toStringAsFixed(2)}%'),
                _buildStrategyRow('Confidence', confidence == null ? '—' : '${confidence.toStringAsFixed(0)}%'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Key Factors
          Text(
            'Key Factors',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (keyFactors.isEmpty)
            Text('No key factors available.', style: context.textTheme.bodyMedium)
          else
            ...keyFactors.map((factor) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.colorScheme.onSurface
                    .withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 18, color: Color(AppColors.successColor)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(factor.toString())),
                ],
              ),
            )),
          const SizedBox(height: 16),

          // Risk Warnings
          if (riskWarnings.isNotEmpty) ...[
            Text(
              'Risk Warnings',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...riskWarnings.map((warning) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.colorScheme.onSurface
                    .withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning,
                      size: 18, color: Color(AppColors.warningColor)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(warning.toString())),
                ],
              ),
            )),
          ],
        ],
    );
  }

  Widget _buildStrategyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          Text(
            value,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSignalColor(String signal) {
    switch (signal.toLowerCase()) {
      case 'bullish':
        return const Color(AppColors.successColor);
      case 'bearish':
        return const Color(AppColors.errorColor);
      default:
        return const Color(AppColors.warningColor);
    }
  }

  Color _getStrengthColor(String strength) {
    switch (strength.toLowerCase()) {
      case 'strong':
        return const Color(AppColors.errorColor);
      case 'moderate':
        return const Color(AppColors.warningColor);
      default:
        return const Color(AppColors.successColor);
    }
  }

  String _formatNumber(dynamic number) {
    if (number == null) return '0';
    final double parsedNum = (number is int || number is double)
        ? number.toDouble()
        : double.tryParse(number.toString()) ?? 0;
    return parsedNum.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
