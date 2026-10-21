import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/config/dio_client.dart';
import '../../../core/config/constants/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../../domain/entities/stock_entity.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  StockEntity? selectedStock;
  Map<String, dynamic>? selectedPeriod;
  List<Map<String, dynamic>> availablePeriods = [];
  bool _isLoadingPeriods = false;
  bool _isAnalyzing = false;
  bool _noFinancialData = false;
  dynamic _analysisData;

  // ─────────────────────────────────────────────────────────────────────
  // Safe numeric access. The API serialises decimal columns as strings
  // (e.g. "277.43"), so calling toStringAsFixed() / comparing them as
  // numbers used to throw. These helpers normalise num/String/null.
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

  /// Human-readable description of the reporting period, including whether
  /// figures are annualised estimates.
  String _periodDescription(Map<String, dynamic> data) {
    final period = data['financial_period'];
    if (period is! Map) return '';

    final fiscalYear = period['fiscal_year']?.toString() ?? '';
    final periodCode = (period['period']?.toString() ?? '').toUpperCase();
    final isCumulative = period['is_cumulative'] == true;

    String label;
    if (periodCode == 'FY' || periodCode == 'ANNUAL' || periodCode.isEmpty) {
      label = 'Full Year $fiscalYear';
    } else {
      label = '$periodCode $fiscalYear';
    }

    final meta = data['analysis'] is Map
        ? (data['analysis'] as Map)['_meta']
        : null;
    final isQuarterly = meta is Map ? meta['is_quarterly'] == true : false;
    final factor = meta is Map ? _num(meta['annualization_factor']) : null;

    if (!isQuarterly || isCumulative) {
      return '$label — figures as reported';
    }
    if (factor != null && (factor - 1.0).abs() > 0.001) {
      return '$label — single quarter, income figures annualised ×${factor.toStringAsFixed(0)} (estimates)';
    }
    return '$label — single quarter';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock Investment Analysis'),
            Text(
              'Get actionable insights and predictions to make informed investment decisions',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSelectionSection(context),
            const SizedBox(height: 24),
            _buildAnalyzeButton(context),
            const SizedBox(height: 32),
            if (_analysisData != null) ...[
              _buildAnalysisResults(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionSection(BuildContext context) {
    final stocksAsync = ref.watch(stocksListProvider(null));

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: context.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Stock to Analyze',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            stocksAsync.when(
              data: (stocks) {
                return DropdownButtonFormField<StockEntity>(
                  initialValue: selectedStock,
                  decoration: InputDecoration(
                    labelText: 'Stock',
                    hintText: 'Choose a stock',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: stocks.map((stock) {
                    return DropdownMenuItem(
                      value: stock,
                      child: Text('${stock.symbol} - ${stock.name}'),
                    );
                  }).toList(),
                  onChanged: (stock) {
                    setState(() {
                      selectedStock = stock;
                      selectedPeriod = null;
                      availablePeriods = [];
                      _noFinancialData = false;
                      _analysisData = null;
                    });
                    if (stock != null && stock.id != null) {
                      _fetchAvailablePeriods(stock.id!);
                    }
                  },
                );
              },
              loading: () => DropdownButtonFormField<StockEntity>(
                decoration: InputDecoration(
                  labelText: 'Stock',
                  hintText: 'Loading stocks...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: const [],
                onChanged: null,
              ),
              error: (error, _) => DropdownButtonFormField<StockEntity>(
                decoration: InputDecoration(
                  labelText: 'Stock',
                  hintText: 'Error loading stocks',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: const [],
                onChanged: null,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoadingPeriods)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (availablePeriods.isNotEmpty)
              DropdownButtonFormField<Map<String, dynamic>>(
                initialValue: selectedPeriod,
                decoration: InputDecoration(
                  labelText: 'Period',
                  hintText: 'Select a period',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: availablePeriods.map((period) {
                  return DropdownMenuItem(
                    value: period,
                    child: Text(period['label']?.toString() ?? ''),
                  );
                }).toList(),
                onChanged: (period) {
                  setState(() => selectedPeriod = period);
                },
              )
            else if (_noFinancialData)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No financial data has been published for this stock '
                        'yet, so analysis is not available.',
                        style: TextStyle(color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchAvailablePeriods(int stockId) async {
    setState(() {
      _isLoadingPeriods = true;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        ApiEndpoints.periods(stockId),
      );

      if (mounted) {
        final raw = response.data;
        final periodsRaw =
            raw is Map ? (raw['data'] is Map ? raw['data']['periods'] : null) : null;
        final periods = (periodsRaw is List
                ? periodsRaw
                : <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();

        setState(() {
          availablePeriods = periods;
          selectedPeriod = periods.isNotEmpty ? periods.first : null;
          _noFinancialData = periods.isEmpty;
          _isLoadingPeriods = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPeriods = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load periods: ${_extractError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Pull a human-readable message out of a DioException / server error.
  String _extractError(dynamic e) {
    try {
      final message = e.message;
      if (message is String && message.isNotEmpty) {
        final data = e.response?.data;
        if (data is Map && data['message'] is String) {
          return data['message'] as String;
        }
        return message;
      }
    } catch (_) {}
    return 'Something went wrong';
  }

  Widget _buildAnalyzeButton(BuildContext context) {
    final isEnabled = selectedStock != null && selectedPeriod != null && !_isAnalyzing;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isEnabled ? _handleAnalyzeStock : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _isAnalyzing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.analytics),
                  const SizedBox(width: 8),
                  Text('Analyze'),
                ],
              ),
      ),
    );
  }

  Future<void> _handleAnalyzeStock() async {
    if (selectedStock == null || selectedPeriod == null || selectedStock!.id == null) {
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisData = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        ApiEndpoints.analysis(selectedStock!.id!),
        queryParameters: {
          'year': selectedPeriod!['year'],
          'period': selectedPeriod!['period'],
        },
      );

      if (mounted) {
        setState(() {
          _analysisData = response.data['data'];
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to analyze stock: ${_extractError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildAnalysisResults(BuildContext context) {
    if (_analysisData == null || _analysisData is! Map) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPeriodBanner(context),
        const SizedBox(height: 20),
        _buildRecommendationCard(context),
        const SizedBox(height: 20),
        _buildValuationCard(context),
        const SizedBox(height: 20),
        _buildPredictionCard(context),
        const SizedBox(height: 20),
        _buildFinancialMetrics(context),
        const SizedBox(height: 20),
        _buildAnalysisBreakdown(context),
      ],
    );
  }

  /// Shows exactly which reporting period the figures below belong to —
  /// and whether they were annualised. Every metric on this page is for
  /// this period, so it must be stated explicitly.
  Widget _buildPeriodBanner(BuildContext context) {
    final data = _analysisData as Map;
    final description = _periodDescription(data);
    final marketPrice = _num(data['market_price']);
    final priceDate = data['price_date']?.toString() ?? '';
    final isHistorical = data['is_historical'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today,
                  size: 20, color: context.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  description.isEmpty ? 'Reporting period' : description,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: context.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (marketPrice != null) ...[
            const SizedBox(height: 8),
            Text(
              'Market price used: TZS ${marketPrice.toStringAsFixed(2)}'
              '${priceDate.isNotEmpty ? ' (as of $priceDate'
                  '${isHistorical ? ', historical price' : ''})' : ''}',
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(BuildContext context) {
    final analysis = _analysisData is Map ? _analysisData['analysis'] : null;
    final recommendation = analysis is Map ? analysis['recommendation'] : null;
    if (recommendation is! Map) return const SizedBox.shrink();

    final action = recommendation['action']?.toString() ?? 'N/A';
    final score = _num(recommendation['score']) ?? 0;
    final maxScore = _num(recommendation['max_score']) ?? 100;
    final summary = recommendation['summary']?.toString() ?? '';

    // Determine color based on action
    Color gradientStart;
    Color gradientEnd;
    switch (action.toLowerCase()) {
      case 'strong buy':
        gradientStart = Colors.green[700]!;
        gradientEnd = Colors.green[400]!;
        break;
      case 'buy':
        gradientStart = Colors.green[600]!;
        gradientEnd = Colors.green[300]!;
        break;
      case 'hold':
        gradientStart = Colors.orange[600]!;
        gradientEnd = Colors.orange[300]!;
        break;
      case 'sell':
      case 'avoid':
        gradientStart = Colors.red[600]!;
        gradientEnd = Colors.red[300]!;
        break;
      default:
        gradientStart = Colors.grey[600]!;
        gradientEnd = Colors.grey[300]!;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientStart, gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: gradientStart.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INVESTMENT RECOMMENDATION',
            style: context.textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            action,
            style: context.textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: context.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Score: ${score.toStringAsFixed(0)}/${maxScore.toStringAsFixed(0)}',
              style: context.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValuationCard(BuildContext context) {
    final analysis = _analysisData is Map ? _analysisData['analysis'] : null;
    final valuation = analysis is Map ? analysis['valuation'] : null;
    if (valuation is! Map) return const SizedBox.shrink();

    // Null means "no data" — show N/A, never a fabricated zero.
    final marketPrice = _num(valuation['market_price']);
    final bookValue = _num(valuation['book_value_per_share']);
    final grahamNumber = _num(valuation['graham_number']);
    final intrinsicValue = _num(valuation['intrinsic_value']);
    final marginOfSafety = _num(valuation['margin_of_safety']);
    final valuationStatus =
        valuation['valuation_status']?.toString() ?? 'unknown';

    // Format valuation status
    String formatStatus(String status) {
      return status.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
    }

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.green.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: context.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Stock Valuation',
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Valuation Status',
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatStatus(valuationStatus),
                    style: context.textTheme.headlineSmall?.copyWith(
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildMetricRow(context, 'Market Price', _fmt(marketPrice, suffix: ' TZS')),
            Divider(),
            _buildMetricRow(context, 'Book Value Per Share', _fmt(bookValue, suffix: ' TZS')),
            Divider(),
            _buildMetricRow(context, 'Graham Number (Max. Safe Value)', _fmt(grahamNumber, suffix: ' TZS')),
            Divider(),
            _buildMetricRow(context, 'Intrinsic Value (True Value)', _fmt(intrinsicValue, suffix: ' TZS')),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Margin of safety for value investing',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    _fmt(marginOfSafety, suffix: '%'),
                    style: context.textTheme.titleMedium?.copyWith(
                      color: marginOfSafety == null || marginOfSafety < 0
                          ? Colors.red[700]
                          : Colors.green[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionCard(BuildContext context) {
    final analysis = _analysisData is Map ? _analysisData['analysis'] : null;
    final prediction = analysis is Map ? analysis['prediction'] : null;
    if (prediction is! Map) return const SizedBox.shrink();

    final predictedPrice = _num(prediction['predicted_price']);
    final conservativePrice = _num(prediction['conservative_price']);
    final optimisticPrice = _num(prediction['optimistic_price']);
    final expectedChangePercent = _num(prediction['expected_change_percent']);
    final expectedChange = _num(prediction['expected_change']);
    final confidence = prediction['confidence']?.toString() ?? 'unknown';
    final timeframe = prediction['timeframe']?.toString() ?? '3-month';

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: context.colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, color: context.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  '$timeframe Price Prediction',
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildPredictionItem(context, 'Conservative', _fmt(conservativePrice)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPredictionItem(context, 'Expected', _fmt(predictedPrice), isPrimary: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPredictionItem(context, 'Optimistic', _fmt(optimisticPrice)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (expectedChangePercent ?? 0) >= 0
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Expected Change',
                    style: context.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    expectedChangePercent == null
                        ? 'N/A'
                        : '${expectedChangePercent >= 0 ? '+' : ''}${expectedChangePercent.toStringAsFixed(1)}%',
                    style: context.textTheme.headlineMedium?.copyWith(
                      color: (expectedChangePercent ?? 0) >= 0
                          ? Colors.green[700]
                          : Colors.red[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (expectedChange != null)
                    Text(
                      '(${expectedChange >= 0 ? '+' : ''}${expectedChange.toStringAsFixed(2)} TZS)',
                      style: context.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Prediction Confidence',
                  style: context.textTheme.bodyMedium,
                ),
                Chip(
                  label: Text(
                    confidence.isEmpty
                        ? 'Unknown'
                        : confidence[0].toUpperCase() + confidence.substring(1),
                  ),
                  backgroundColor: Colors.green.withValues(alpha: 0.1),
                  side: BorderSide(
                    color: Colors.green.withValues(alpha: 0.2),
                    width: 1,
                  ),
                  labelStyle: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionItem(BuildContext context, String label, String value, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isPrimary
            ? context.colorScheme.primary.withValues(alpha: 0.1)
            : context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPrimary
              ? context.colorScheme.primary
              : Colors.grey.withValues(alpha: 0.5),
          width: isPrimary ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.textTheme.labelSmall,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isPrimary ? context.colorScheme.primary : null,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialMetrics(BuildContext context) {
    final analysis = _analysisData is Map ? _analysisData['analysis'] : null;
    final metrics = analysis is Map ? analysis['metrics'] : null;
    if (metrics is! Map) return const SizedBox.shrink();

    Map<String, dynamic> group(String key) {
      final value = metrics[key];
      return value is Map ? value : const <String, dynamic>{};
    }

    // The backend groups metrics differently per industry. There is NO
    // 'financial_health' group: manufacturing keeps D/E under 'leverage'
    // and current ratio under 'liquidity', while banks have no leverage
    // group at all (they report NPL, CAR and LDR instead).
    final perShare = group('per_share');
    final valuation = group('valuation');
    final profitability = group('profitability');
    final liquidity = group('liquidity');
    final leverage = group('leverage');
    final assetQuality = group('asset_quality');
    final capitalAdequacy = group('capital_adequacy');
    final meta = group('_meta');
    final isBanking = meta['industry_type'] == 'banking';

    final healthScore = analysis is Map ? _num(analysis['health_score']) : null;

    final metricItems = <Map<String, dynamic>>[
      {'label': 'EPS', 'value': _fmt(perShare['eps']), 'color': Colors.blue},
      {'label': 'P/E', 'value': _fmt(valuation['pe_ratio']), 'color': Colors.indigo},
      {'label': 'P/B', 'value': _fmt(valuation['pb_ratio']), 'color': Colors.green},
      {'label': 'PEG', 'value': _fmt(valuation['peg_ratio']), 'color': Colors.grey},
      {'label': 'DY', 'value': _fmt(valuation['dividend_yield'], suffix: '%'), 'color': Colors.teal},
      {'label': 'ROE', 'value': _fmt(profitability['roe'], suffix: '%'), 'color': Colors.blue},
      {'label': 'ROA', 'value': _fmt(profitability['roa'], suffix: '%'), 'color': Colors.green},
    ];

    if (isBanking) {
      metricItems.addAll([
        {'label': 'NIM', 'value': _fmt(profitability['net_interest_margin'], suffix: '%'), 'color': Colors.teal},
        {'label': 'NPL', 'value': _fmt(assetQuality['npl_ratio'], suffix: '%'), 'color': Colors.red},
        {'label': 'CAR', 'value': _fmt(capitalAdequacy['car'], suffix: '%'), 'color': Colors.purple},
        {'label': 'LDR', 'value': _fmt(liquidity['loan_to_deposit'], suffix: '%'), 'color': Colors.orange},
      ]);
    } else {
      metricItems.addAll([
        {'label': 'NPM', 'value': _fmt(profitability['net_profit_margin'], suffix: '%'), 'color': Colors.teal},
        {'label': 'GPM', 'value': _fmt(profitability['gross_profit_margin'], suffix: '%'), 'color': Colors.red},
        {'label': 'D/E', 'value': _fmt(leverage['debt_to_equity']), 'color': Colors.pink},
        {'label': 'CR', 'value': _fmt(liquidity['current_ratio']), 'color': Colors.red},
        {'label': 'ICR', 'value': _fmt(leverage['interest_coverage']), 'color': Colors.orange},
      ]);
    }

    metricItems.add({
      'label': 'Score',
      'value': healthScore == null ? 'N/A' : healthScore.toStringAsFixed(0),
      'color': Colors.purple,
    });

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.purple.withValues(alpha: 0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: context.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Key Financial Metrics',
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = constraints.maxWidth < 600 ? 2 : 3;
                if (constraints.maxWidth > 900) crossAxisCount = 4;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: metricItems.length,
                  itemBuilder: (context, index) {
                    final item = metricItems[index];
                    return _buildMetricChip(
                      context,
                      item['label'] as String,
                      item['value'] as String,
                      item['color'] as Color,
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(BuildContext context, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: context.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisBreakdown(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analysis Breakdown',
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildSignalsSection(context),
      ],
    );
  }

  Widget _buildSignalsSection(BuildContext context) {
    final analysis = _analysisData is Map ? _analysisData['analysis'] : null;
    final signals = analysis is Map ? analysis['signals'] : null;
    final greenFlags = signals is Map
        ? (signals['green_flags'] is List ? signals['green_flags'] : <dynamic>[])
        : <dynamic>[];
    final redFlags = signals is Map
        ? (signals['red_flags'] is List ? signals['red_flags'] : <dynamic>[])
        : <dynamic>[];

    return Column(
      children: [
        Card(
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          color: Colors.green.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Colors.green.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700]),
                    const SizedBox(width: 12),
                    Text(
                      'Positive Signals (${greenFlags.length})',
                      style: context.textTheme.titleMedium?.copyWith(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...greenFlags.whereType<Map<String, dynamic>>().map(
                  (flag) => _buildSignalItem(
                    context,
                    flag['title']?.toString() ?? '',
                    flag['description']?.toString() ?? '',
                    true,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          color: Colors.red.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Colors.red.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red[700]),
                    const SizedBox(width: 12),
                    Text(
                      'Warning Signals (${redFlags.length})',
                      style: context.textTheme.titleMedium?.copyWith(
                        color: Colors.red[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...redFlags.whereType<Map<String, dynamic>>().map(
                  (flag) => _buildSignalItem(
                    context,
                    flag['title']?.toString() ?? '',
                    flag['description']?.toString() ?? '',
                    false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignalItem(BuildContext context, String title, String description, bool isPositive) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
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
              color: context.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
