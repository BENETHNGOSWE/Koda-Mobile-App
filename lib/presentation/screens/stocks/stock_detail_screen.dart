import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/config/dio_client.dart';
import '../../../core/config/constants/app_constants.dart';
import 'package:fl_chart/fl_chart.dart';

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

  String _selectedPeriod = '1 Month';
  int _selectedDays = 30;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.symbol),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
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
                  const SizedBox(height: 24),

                  // Period Selector
                  _buildPeriodSelector(),
                  const SizedBox(height: 16),

                  // Price Chart
                  _buildPriceChart(),
                  const SizedBox(height: 32),

                  // Trading Simulator
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

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: context.colorScheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stockData!['name'] ?? widget.symbol,
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  currentPrice == null
                      ? 'No price data'
                      : 'TZS ${currentPrice.toStringAsFixed(2)}',
                  style: context.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (change != null) ...[
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isPositive
                              ? const Color(AppColors.successColor)
                              : const Color(AppColors.errorColor))
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${isPositive ? '+' : ''}${change.toStringAsFixed(2)} (${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%)',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: isPositive
                            ? const Color(AppColors.successColor)
                            : const Color(AppColors.errorColor),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Period:',
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPeriodButton('7 Days', 7),
            _buildPeriodButton('1 Month', 30),
            _buildPeriodButton('3 Months', 90),
            _buildPeriodButton('6 Months', 180),
            _buildPeriodButton('1 Year', 365),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Current View: $_selectedPeriod',
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodButton(String label, int days) {
    final isSelected = _selectedPeriod == label;
    return ElevatedButton(
      onPressed: () => _changePeriod(label, days),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? context.colorScheme.primary
            : context.colorScheme.surface,
        foregroundColor: isSelected
            ? Colors.white
            : context.colorScheme.onSurface,
        elevation: isSelected ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? context.colorScheme.primary
                : context.colorScheme.primary.withValues(alpha: 0.4),
            width: isSelected ? 0 : 1.5,
          ),
        ),
      ),
      child: Text(label),
    );
  }

  Widget _buildPriceChart() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: context.colorScheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Price Movement',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _isLoadingPrices
                ? const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : priceData.isEmpty
                    ? const SizedBox(
                        height: 200,
                        child: Center(child: Text('No data available')),
                      )
                    : _parsedCloses().isEmpty
                        ? const SizedBox(
                            height: 200,
                            child: Center(child: Text('No data available')),
                          )
                        : SizedBox(
                        height: 300,
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: true,
                              horizontalInterval: 10,
                              verticalInterval: 1,
                              getDrawingHorizontalLine: (value) {
                                return FlLine(
                                  color: context.colorScheme.onSurface.withValues(alpha: 0.1),
                                  strokeWidth: 1,
                                );
                              },
                              getDrawingVerticalLine: (value) {
                                return FlLine(
                                  color: context.colorScheme.onSurface.withValues(alpha: 0.1),
                                  strokeWidth: 1,
                                );
                              },
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 30,
                                  interval: (priceData.length / 6).ceilToDouble(),
                                  getTitlesWidget: (value, meta) {
                                    if (value.toInt() >= 0 && value.toInt() < priceData.length) {
                                      final date = priceData[value.toInt()]['date']?.toString() ?? '';
                                      final parts = date.split('-');
                                      if (parts.length == 3) {
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            '${parts[1]}/${parts[2]}',
                                            style: context.textTheme.bodySmall,
                                          ),
                                        );
                                      }
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: 20,
                                  reservedSize: 42,
                                  getTitlesWidget: (value, meta) {
                                    return Text(
                                      value.toInt().toString(),
                                      style: context.textTheme.bodySmall,
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(
                              show: true,
                              border: Border.all(
                                color: context.colorScheme.onSurface.withValues(alpha: 0.1),
                              ),
                            ),
                            minX: 0,
                            maxX: (priceData.length - 1).toDouble(),
                            minY: _getMinPrice() - 10,
                            maxY: _getMaxPrice() + 10,
                            lineBarsData: [
                              LineChartBarData(
                                spots: priceData
                                        .asMap()
                                        .entries
                                        .where((entry) => _num(entry.value['close']) != null)
                                        .map((entry) {
                                  return FlSpot(
                                    entry.key.toDouble(),
                                    _num(entry.value['close'])!.toDouble(),
                                  );
                                }).toList(),
                                isCurved: true,
                                color: const Color(AppColors.primaryColor),
                                barWidth: 3,
                                isStrokeCapRound: true,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: const Color(AppColors.primaryColor).withValues(alpha: 0.1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
          ],
        ),
      ),
    );
  }

  /// Close prices that could actually be parsed; rows with a missing or
  /// malformed close are skipped instead of crashing the chart.
  List<double> _parsedCloses() {
    return priceData
        .map((p) => _num(p['close']))
        .whereType<double>()
        .toList();
  }

  double _getMinPrice() {
    final closes = _parsedCloses();
    if (closes.isEmpty) return 0;
    return closes.reduce((a, b) => a < b ? a : b);
  }

  double _getMaxPrice() {
    final closes = _parsedCloses();
    if (closes.isEmpty) return 100;
    return closes.reduce((a, b) => a > b ? a : b);
  }

  Widget _buildTradingSimulator() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.gps_fixed, color: Color(AppColors.errorColor)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Professional Trading Simulator',
                    style: context.textTheme.titleLarge?.copyWith(
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
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: context.colorScheme.primary.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                ),
                child: _isLoadingSimulation
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Run Simulation'),
              ),
            ),
          ],
        ),
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
          decoration: const InputDecoration(
            hintText: '100000',
          ),
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
          decoration: const InputDecoration(
            hintText: 'mm/dd/yyyy',
            suffixIcon: Icon(Icons.calendar_today),
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
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
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
        // Investment Summary Cards - 2x2 Grid
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'INVESTMENT',
                    'TZS ${_formatNumber(investment['actual_investment'])}',
                    '${investment['shares']} shares',
                    const Color(AppColors.primaryColor),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'CURRENT VALUE',
                    'TZS ${_formatNumber(currentStatus['current_value'])}',
                    profitLossPercent == null
                        ? 'N/A'
                        : '${profitLossPercent >= 0 ? '+' : ''}${profitLossPercent.toStringAsFixed(2)}%',
                    profitLossPercent == null || profitLossPercent >= 0
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
                  child: _buildSummaryCard(
                    'RECOMMENDED ACTION',
                    _str(primaryRec['action']),
                    _str(primaryRec['holding_period']),
                    const Color(0xFF9C27B0),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'MARKET SENTIMENT',
                    _str(marketSentiment['sentiment']),
                    'Score: ${_fmt(marketSentiment['sentiment_score'])}%',
                    const Color(0xFFFFA726),
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

  Widget _buildSummaryCard(String title, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.6),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionsTabs() {
    if (simulationData is! Map) return const SizedBox();

    final predictions = _map(simulationData!['predictions']);

    return DefaultTabController(
      length: 4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            isScrollable: true,
            labelColor: context.colorScheme.primary,
            unselectedLabelColor: context.colorScheme.onSurface.withValues(alpha: 0.6),
            indicatorColor: context.colorScheme.primary,
            tabs: const [
              Tab(text: 'Predictions'),
              Tab(text: 'Technical'),
              Tab(text: 'Signals'),
              Tab(text: 'Best Strategy'),
            ],
          ),
          const SizedBox(height: 16),
          // Use intrinsic height for tab content instead of fixed height
          Builder(
            builder: (context) {
              final tabController = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: tabController,
                builder: (context, child) {
                  final index = tabController.index;
                  switch (index) {
                    case 0:
                      return _buildPredictionsTab(predictions);
                    case 1:
                      return _buildTechnicalTab();
                    case 2:
                      return _buildSignalsTab();
                    case 3:
                      return _buildBestStrategyTab();
                    default:
                      return _buildPredictionsTab(predictions);
                  }
                },
              );
            },
          ),
        ],
      ),
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
          decoration: BoxDecoration(
            color: confidenceColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: confidenceColor.withValues(alpha: 0.3),
            ),
          ),
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
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: confidenceColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    confidenceScore == null ? 'N/A' : '${confidenceScore.toStringAsFixed(0)}%',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(AppColors.warningColor).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _str(prediction['recommendation'], ''),
              style: context.textTheme.bodySmall?.copyWith(
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

          // Moving Averages
          Card(
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: context.colorScheme.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Momentum
          Card(
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: context.colorScheme.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Momentum Indicators',
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTechnicalRow('RSI', '${_fmt(momentum['rsi'])} (${_str(momentum['rsi_signal'], 'n/a')})'),
                  _buildTechnicalRow('MACD', '${_fmt(momentum['macd'])} (${_str(momentum['macd_signal'], 'n/a')})'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Support & Resistance
          Card(
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: context.colorScheme.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  _buildTechnicalRow('Pivot', _fmt(supportResistance['pivot']), Colors.blue),
                  _buildTechnicalRow('Support 1', _fmt(supportResistance['support_1']), Colors.green),
                  _buildTechnicalRow('Support 2', _fmt(supportResistance['support_2']), Colors.green),
                  _buildTechnicalRow('Support 3', _fmt(supportResistance['support_3']), Colors.green),
                ],
              ),
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
          Card(
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: context.colorScheme.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Overall Signal:',
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getSignalColor(overall).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _getSignalColor(overall)),
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
            ...signalsList.map((signal) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: context.colorScheme.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: ListTile(
              leading: Icon(
                signal['type'] == 'bullish' ? Icons.trending_up : Icons.trending_down,
                color: signal['type'] == 'bullish'
                    ? const Color(AppColors.successColor)
                    : const Color(AppColors.errorColor),
              ),
              title: Text(
                _str(signal['indicator']),
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(_str(signal['message'], '')),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStrengthColor(signal['strength']?.toString() ?? 'weak').withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _str(signal['strength'], 'weak'),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: _getStrengthColor(signal['strength']?.toString() ?? 'weak'),
                  ),
                ),
              ),
            ),
          )),
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
          Card(
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: context.colorScheme.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(AppColors.primaryColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _str(primaryRec['action']),
                      style: context.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStrategyRow('Holding Period', _str(primaryRec['holding_period'])),
                  _buildStrategyRow('Expected Return', expectedReturn == null ? 'N/A' : '${expectedReturn.toStringAsFixed(2)}%'),
                  _buildStrategyRow('Confidence', confidence == null ? 'N/A' : '${confidence.toStringAsFixed(0)}%'),
                ],
              ),
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
            ...keyFactors.map((factor) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: context.colorScheme.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Color(AppColors.successColor)),
              title: Text(factor.toString()),
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
            ...riskWarnings.map((warning) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: context.colorScheme.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: ListTile(
                leading: const Icon(Icons.warning, color: Color(AppColors.warningColor)),
                title: Text(warning.toString()),
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
