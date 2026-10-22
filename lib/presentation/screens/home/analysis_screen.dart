import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/ambient_top_glow.dart';
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
              maxLines: 2,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, size: 20),
            tooltip: 'Price alerts',
            onPressed: () => context.push('/alerts'),
          ),
        ],
      ),
      body: AmbientTopGlow(
        child: SingleChildScrollView(
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
      )
      ),
    );
  }

  Widget _buildSelectionSection(BuildContext context) {
    final stocksAsync = ref.watch(stocksListProvider(null));

    return Container(
      width: double.infinity,
      decoration: context.cardDecoration(radius: 20),
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
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No financial data has been published for this stock '
                        'yet, so analysis is not available.',
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.onSurface
                              .withValues(alpha: 0.8),
                        ),
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
    final data = _analysisData as Map<String, dynamic>;
    final description = _periodDescription(data);
    final marketPrice = _num(data['market_price']);
    final priceDate = data['price_date']?.toString() ?? '';
    final isHistorical = data['is_historical'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today,
                  size: 20, color: context.colorScheme.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  description.isEmpty ? 'Reporting period' : description,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
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

    // Judge by the DIRECTION of the recommendation, not the exact wording:
    // anything with 'sell'/'avoid' → red, 'buy' → green,
    // 'hold'/'wait'/'caution'/'neutral' → orange.
    final actionLower = action.toLowerCase();
    Color actionColor;
    if (actionLower.contains('sell') || actionLower.contains('avoid')) {
      actionColor = Colors.red;
    } else if (actionLower.contains('buy')) {
      actionColor = Colors.green;
    } else if (actionLower.contains('hold') ||
        actionLower.contains('wait') ||
        actionLower.contains('caution') ||
        actionLower.contains('neutral')) {
      actionColor = Colors.orange;
    } else {
      actionColor = Colors.grey;
    }
    final hasDirection = actionColor != Colors.grey;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: actionColor
            .withValues(alpha: hasDirection ? 0.16 : 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INVESTMENT RECOMMENDATION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: context.colorScheme.onSurface
                  .withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            action.toUpperCase(),
            style: context.textTheme.displaySmall?.copyWith(
              color: hasDirection ? actionColor : context.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              summary,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurface
                    .withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: actionColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Score: ${score.toStringAsFixed(0)}/${maxScore.toStringAsFixed(0)}',
              style: context.textTheme.bodyMedium?.copyWith(
                color: actionColor,
                fontWeight: FontWeight.w700,
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

    final statusColor = valuationStatus.contains('under')
        ? Colors.green
        : valuationStatus.contains('over')
            ? Colors.red
            : Colors.grey;
    final mosNegative = marginOfSafety == null || marginOfSafety < 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: context.cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up,
                  size: 20, color: context.colorScheme.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Valuation',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  formatStatus(valuationStatus),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Margin of safety — full-width block with a thin gauge bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colorScheme.onSurface
                  .withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Margin of Safety',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                    Text(
                      _fmt(marginOfSafety, suffix: '%'),
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: mosNegative ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: marginOfSafety == null
                        ? 0
                        : (marginOfSafety.clamp(0.0, 100.0) / 100).toDouble(),
                    minHeight: 4,
                    backgroundColor: context.colorScheme.onSurface
                        .withValues(alpha: 0.08),
                    color: mosNegative ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                    context, 'Market Price', _fmt(marketPrice, suffix: ' TZS')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(context, 'Book Value / Share',
                    _fmt(bookValue, suffix: ' TZS')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(context, 'Graham Number',
                    _fmt(grahamNumber, suffix: ' TZS')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(context, 'Intrinsic Value',
                    _fmt(intrinsicValue, suffix: ' TZS')),
              ),
            ],
          ),
        ],
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

    final changePositive = (expectedChangePercent ?? 0) >= 0;
    final confLower = confidence.toLowerCase();
    final confidenceColor = confLower.contains('high')
        ? Colors.green
        : confLower.contains('medium') || confLower.contains('moderate')
            ? Colors.orange
            : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: context.cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up,
                  size: 20, color: context.colorScheme.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$timeframe Price Prediction',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildPredictionItem(
                    context, 'Conservative', _fmt(conservativePrice)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPredictionItem(context, 'Expected',
                    _fmt(predictedPrice),
                    isPrimary: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPredictionItem(
                    context, 'Optimistic', _fmt(optimisticPrice)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colorScheme.onSurface
                  .withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'Expected Change',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  expectedChangePercent == null
                      ? 'N/A'
                      : '${changePositive ? '+' : ''}${expectedChangePercent.toStringAsFixed(1)}%',
                  style: context.textTheme.headlineSmall?.copyWith(
                    color: changePositive ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (expectedChange != null)
                  Text(
                    '(${expectedChange >= 0 ? '+' : ''}${expectedChange.toStringAsFixed(2)} TZS)',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Prediction Confidence',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: confidenceColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  confidence.isEmpty
                      ? 'Unknown'
                      : confidence[0].toUpperCase() + confidence.substring(1),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: confidenceColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionItem(BuildContext context, String label, String value, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: context.colorScheme.onSurface
            .withValues(alpha: isPrimary ? 0.14 : 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: context.colorScheme.onSurface
                  .withValues(alpha: isPrimary ? 0.7 : 0.5),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
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
      return value is Map<String, dynamic> ? value : const <String, dynamic>{};
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

    // Related metrics grouped into their own containers.
    final groups = <(String, List<(String, String)>)>[
      (
        'PER-SHARE & VALUATION',
        [
          ('EPS', _fmt(perShare['eps'])),
          ('P/E', _fmt(valuation['pe_ratio'])),
          ('P/B', _fmt(valuation['pb_ratio'])),
          ('PEG', _fmt(valuation['peg_ratio'])),
          ('DY', _fmt(valuation['dividend_yield'], suffix: '%')),
        ],
      ),
      (
        'PROFITABILITY',
        [
          ('ROE', _fmt(profitability['roe'], suffix: '%')),
          ('ROA', _fmt(profitability['roa'], suffix: '%')),
          if (isBanking)
            ('NIM',
                _fmt(profitability['net_interest_margin'], suffix: '%'))
          else
            ('NPM',
                _fmt(profitability['net_profit_margin'], suffix: '%')),
          if (isBanking)
            ('NPL', _fmt(assetQuality['npl_ratio'], suffix: '%'))
          else
            ('GPM', _fmt(profitability['gross_profit_margin'], suffix: '%')),
        ],
      ),
      (
        isBanking ? 'CAPITAL & LIQUIDITY' : 'LIQUIDITY & LEVERAGE',
        [
          if (isBanking)
            ('CAR', _fmt(capitalAdequacy['car'], suffix: '%'))
          else
            ('D/E', _fmt(leverage['debt_to_equity'])),
          if (isBanking)
            ('LDR', _fmt(liquidity['loan_to_deposit'], suffix: '%'))
          else
            ('CR', _fmt(liquidity['current_ratio'])),
          if (!isBanking)
            ('ICR', _fmt(leverage['interest_coverage'])),
        ],
      ),
    ];

    final scoreColor = healthScore == null
        ? Colors.grey
        : healthScore >= 70
            ? Colors.green
            : healthScore >= 40
                ? Colors.orange
                : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key Financial Metrics',
          style: context.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (final (title, items) in groups) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: context.cardDecoration(radius: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: context.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < items.length; i += 2)
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: i + 2 < items.length ? 10 : 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                              context, items[i].$1, items[i].$2),
                        ),
                        if (i + 1 < items.length) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildMetricTile(context,
                                items[i + 1].$1, items[i + 1].$2),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Financial Health — full-width container with a gauge bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: context.cardDecoration(radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'FINANCIAL HEALTH',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: context.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    healthScore == null
                        ? 'N/A'
                        : '${healthScore.toStringAsFixed(0)}/100',
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scoreColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: healthScore == null
                      ? 0
                      : (healthScore.clamp(0.0, 100.0) / 100).toDouble(),
                  minHeight: 4,
                  backgroundColor: context.colorScheme.onSurface
                      .withValues(alpha: 0.08),
                  color: scoreColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile(BuildContext context, String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: context.colorScheme.onSurface
                  .withValues(alpha: 0.5),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 20, color: Colors.green),
              const SizedBox(width: 10),
              Text(
                'Positive Signals (${greenFlags.length})',
                style: context.textTheme.titleSmall?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...greenFlags.whereType<Map<String, dynamic>>().map(
            (flag) => _buildSignalItem(
              context,
              flag['title']?.toString() ?? '',
              flag['description']?.toString() ?? '',
              true,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 16),
            height: 1,
            color: context.colorScheme.onSurface
                .withValues(alpha: 0.08),
          ),
          Row(
            children: [
              Icon(Icons.warning, size: 20, color: Colors.red),
              const SizedBox(width: 10),
              Text(
                'Warning Signals (${redFlags.length})',
                style: context.textTheme.titleSmall?.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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

}
