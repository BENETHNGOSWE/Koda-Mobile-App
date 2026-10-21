import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/constants/app_constants.dart';
import '../../../core/config/dio_client.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';

/// KodaLens — live DSE quote board.
///
/// Data comes from the Django live feed (latest.json), the same source the
/// web app's Koda Lens uses. Quotes refresh automatically every 30 seconds.
class KodaLensScreen extends ConsumerStatefulWidget {
  const KodaLensScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<KodaLensScreen> createState() => _KodaLensScreenState();
}

class _KodaLensScreenState extends ConsumerState<KodaLensScreen> {
  static const Duration _refreshInterval = Duration(seconds: 30);

  List<Map<String, dynamic>> _quotes = [];
  String? _fetchedAt;
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      // Cache-buster so we never read a stale quote from the CDN/proxy.
      final url =
          '${AppConstants.kodaLensBase}latest.json?t=${DateTime.now().millisecondsSinceEpoch}';
      final response = await dio.get(url);
      final raw = response.data;
      if (!mounted) return;
      if (raw is Map) {
        final list = <Map<String, dynamic>>[];
        final rawQuotes = raw['quotes'];
        if (rawQuotes is List) {
          for (final q in rawQuotes) {
            if (q is Map<String, dynamic>) {
              list.add(q);
            } else if (q is Map) {
              list.add(q.cast<String, dynamic>());
            }
          }
        }
        setState(() {
          _quotes = list;
          _fetchedAt = raw['fetched_at']?.toString();
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'The live feed returned an unexpected response.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load live market data. Check your connection.';
      });
    }
  }

  double _num(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

  List<Map<String, dynamic>> get _visibleQuotes {
    var list = _quotes;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) =>
          (c['symbol']?.toString() ?? '').toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.explore, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            Text(
              'KODA LENS',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_fetchedAt != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                'Updated ${_formatTime(_fetchedAt!)}',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search symbol…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  String _formatTime(String fetchedAt) {
    try {
      final dt = DateTime.parse(fetchedAt).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return fetchedAt;
    }
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
              Icon(Icons.cloud_off, size: 48, color: context.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium,
              ),
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
    if (_quotes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No live quotes available right now. The DSE feed may be paused.',
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    final visible = _visibleQuotes;
    if (visible.isEmpty) {
      return Center(
        child: Text(
          'No symbol matches "$_query".',
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: visible.length,
        itemBuilder: (context, index) =>
            _buildQuoteCard(visible[index]),
      ),
    );
  }

  Widget _buildQuoteCard(Map<String, dynamic> quote) {
    final symbol = quote['symbol']?.toString() ?? 'N/A';
    final last = _num(quote['last_price']);
    final opening = _num(quote['opening_price']);
    final change = _num(quote['change']);
    final high = _num(quote['high']);
    final low = _num(quote['low']);
    final volume = _num(quote['volume']);

    final changePercent = opening > 0 ? (change / opening) * 100 : 0.0;
    final isUp = change > 0;
    final isDown = change < 0;
    final changeColor = isUp
        ? Colors.green
        : (isDown ? Colors.red : context.colorScheme.onSurface.withValues(alpha: 0.5));

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/stock/$symbol'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symbol,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'H ${Formatters.formatNumberWithCommas(high)} · L ${Formatters.formatNumberWithCommas(low)}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.formatCurrency(last),
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: changeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUp
                              ? Icons.arrow_upward
                              : (isDown ? Icons.arrow_downward : Icons.remove),
                          size: 14,
                          color: changeColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${Formatters.formatPercentage(changePercent)}',
                          style: TextStyle(
                            color: changeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'VOL',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.formatCompactNumber(volume),
                      style: context.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
