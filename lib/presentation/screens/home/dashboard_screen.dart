import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/dio_client.dart';
import '../../../core/config/theme/theme_provider.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/stock_entity.dart';
import '../../providers/app_providers.dart';
import '../portfolio/portfolio_sheets.dart';

/// Home dashboard — compact, investment-first layout matching the design
/// template: gradient backdrop, dark gradient hero with circular quick
/// actions, compact up/down cards, single-row quick actions, tight market
/// summary and top-movers table.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);
    final userAsync = ref.watch(userProvider);
    final portfolioAsync = ref.watch(portfolioProvider);

    return Scaffold(
      floatingActionButton: Material(
        elevation: 4,
        color: const Color(0xFF10B981),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => context.push('/kodalens'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.explore, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text(
                  'KODA LENS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/white_logo.png',
              height: 22,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            Text(
              'KodaStock',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, size: 20),
            onPressed: () => context.push('/notifications'),
          ),
          IconButton(
            icon: Icon(
              ref.watch(isDarkModeProvider)
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 20,
            ),
            onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
          ),
          InkWell(
            onTap: () => context.push('/profile'),
            borderRadius: BorderRadius.circular(20),
            child: userAsync.when(
              data: (user) {
                final nameParts = user.name.split(' ');
                final initials = nameParts.length > 1
                    ? '${nameParts[0][0]}${nameParts[1][0]}'
                    : nameParts[0].substring(0, 2);
                return CircleAvatar(
                  radius: 15,
                  backgroundColor: context.colorScheme.primary,
                  child: Text(
                    initials.toUpperCase(),
                    style: context.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
              loading: () => CircleAvatar(
                radius: 15,
                backgroundColor: context.colorScheme.primary,
              ),
              error: (_, __) => CircleAvatar(
                radius: 15,
                backgroundColor: context.colorScheme.primary,
                child: const Icon(Icons.person, size: 14, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: dashboardAsync.when(
        data: (dashboard) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.3],
              colors: [
                const Color(0xFF10B981).withValues(alpha: 0.12),
                const Color(0xFF10B981).withValues(alpha: 0.0),
              ],
            ),
          ),
          child: _buildContent(context, ref, dashboard, userAsync,
              portfolioAsync),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: context.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Failed to load dashboard',
                style: context.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: context.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(dashboardProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    DashboardEntity dashboard,
    AsyncValue<dynamic> userAsync,
    AsyncValue<Map<String, dynamic>?> portfolioAsync,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardProvider);
        ref.invalidate(portfolioProvider);
        ref.invalidate(userProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGreeting(context, userAsync),
            const SizedBox(height: 12),
            _buildPortfolioHero(context, ref, portfolioAsync),
            const SizedBox(height: 12),
            _buildUpDownCards(context, dashboard),
            const SizedBox(height: 12),
            _buildQuickActions(context),
            const SizedBox(height: 12),
            _buildMarketSummary(context, dashboard),
            const SizedBox(height: 12),
            _buildMarketOverview(context, dashboard),
            const SizedBox(height: 84),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── Greeting ───────────────────────────

  /// DSE trades Monday–Friday, 09:30–14:00 EAT (UTC+3, no DST).
  bool _isDseMarketOpen() {
    final nowEAT = DateTime.now().toUtc().add(const Duration(hours: 3));
    if (nowEAT.weekday > 5) return false;
    final mins = nowEAT.hour * 60 + nowEAT.minute;
    return mins >= 9 * 60 + 30 && mins < 14 * 60;
  }

  Widget _buildGreeting(BuildContext context, AsyncValue<dynamic> userAsync) {
    final now = DateTime.now();
    final open = _isDseMarketOpen();

    return userAsync.when(
      data: (user) {
        final first = user.name.split(' ').first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, $first! 👋',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Here's what's happening with your investments today.",
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(now),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                _marketBadge(context, open),
              ],
            ),
          ],
        );
      },
      loading: () => const SizedBox(height: 64),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _marketBadge(BuildContext context, bool open) {
    final color = open ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            open ? 'Market Open' : 'Market Closed',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── Portfolio hero card ───────────────────────

  double _num(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

  Map<String, dynamic> _map(dynamic v) => v is Map<String, dynamic>
      ? v
      : (v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{});

  List<Map<String, dynamic>> _listOfMaps(dynamic v) {
    final list = <Map<String, dynamic>>[];
    if (v is List) {
      for (final item in v) {
        if (item is Map<String, dynamic>) {
          list.add(item);
        } else if (item is Map) {
          list.add(item.cast<String, dynamic>());
        }
      }
    }
    return list;
  }

  Widget _buildPortfolioHero(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<String, dynamic>?> portfolioAsync,
  ) {
    final sheets = PortfolioSheets(
      dio: ref.read(dioProvider),
      snack: (message, {bool success = true}) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      },
      onChanged: () => ref.invalidate(portfolioProvider),
    );

    return portfolioAsync.when(
      data: (data) {
        if (data == null) {
          return _heroCard(context, child: _heroEmpty(context, sheets));
        }
        final summary = _map(data['summary']);
        final transactions = _listOfMaps(data['transactions']);
        final active = transactions
            .where((t) => (t['status']?.toString() ?? 'active') == 'active')
            .toList();

        final totalValue = _num(summary['total_value']);
        final gainLoss = _num(summary['total_gain_loss']);
        final perfPercent = _num(summary['performance_percent']);
        final positive = gainLoss >= 0;
        final gainColor = positive ? Colors.green : Colors.red;

        return _heroCard(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Value • Performance',
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              _PortfolioValue(value: totalValue),
              const SizedBox(height: 0),
              Row(
                children: [
                  Icon(
                    positive ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                    color: gainColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${positive ? '+' : '-'}${Formatters.formatCurrency(gainLoss.abs())} '
                    '(${Formatters.formatPercentage(perfPercent)})',
                    style: TextStyle(
                      color: gainColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (active.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _holdingsActionsRow(context, sheets, active),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 16,
                        color: context.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No holdings yet — add your first purchase.',
                          style: context.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: context.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
      loading: () => _heroCard(
        context,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => _heroCard(
        context,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Portfolio is unavailable right now.',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: context.colorScheme.onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(portfolioProvider),
                child: const Text('Retry', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.colorScheme.surfaceContainerHighest,
            context.colorScheme.surface,
          ],
        ),
        border: Border.all(
          color: context.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: child,
    );
  }

  Widget _heroEmpty(BuildContext context, PortfolioSheets sheets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Portfolio',
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Track your DSE investments here.',
          style: context.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: context.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () => sheets.addPurchase(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add your first purchase',
              style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  /// One row of circular Add/Sell buttons — one pair per holding
  /// (first two active holdings), matching the template layout.
  Widget _holdingsActionsRow(
    BuildContext context,
    PortfolioSheets sheets,
    List<Map<String, dynamic>> active,
  ) {
    return Row(
      children: [
        for (final t in active.take(2))
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _circleAction(
                  context,
                  icon: Icons.add,
                  label: 'Add',
                  onTap: () => sheets.addPurchase(
                    context,
                    preselectedSymbol: t['symbol']?.toString(),
                  ),
                ),
                const SizedBox(width: 10),
                _circleAction(
                  context,
                  icon: Icons.sell,
                  label: 'Sell',
                  onTap: () => sheets.sell(context, t),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _circleAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colorScheme.onSurface.withValues(alpha: 0.07),
              border: Border.all(
                color: context.colorScheme.onSurface.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: context.colorScheme.onSurface.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: context.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: context.colorScheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── Stocks up / down ───────────────────────

  Widget _buildUpDownCards(BuildContext context, DashboardEntity dashboard) {
    return Row(
      children: [
        Expanded(
          child: _upDownCard(context, up: true, count: dashboard.totalGainers),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _upDownCard(context, up: false, count: dashboard.totalLosers),
        ),
      ],
    );
  }

  Widget _upDownCard(BuildContext context, {required bool up, required int count}) {
    final color = up ? Colors.green : Colors.red;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  up ? 'Stocks Up' : 'Stocks Down',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(up ? Icons.check : Icons.cancel,
                      size: 11, color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'today',
              style: context.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: context.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Quick actions ─────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        _quickTile(context, Icons.show_chart, 'All Stocks', Colors.blue,
            () => context.go('/stocks')),
        const SizedBox(width: 8),
        _quickTile(context, Icons.compare_arrows, 'Compare', Colors.purple,
            () => context.go('/compare')),
        const SizedBox(width: 8),
        _quickTile(context, Icons.insights, 'Analysis', Colors.green,
            () => context.go('/analysis')),
        const SizedBox(width: 8),
        _quickTile(context, Icons.explore, 'KodaLens', const Color(0xFF10B981),
            () => context.push('/kodalens')),
      ],
    );
  }

  Widget _quickTile(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: Material(
        color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Market summary ─────────────────────────

  Widget _buildMarketSummary(BuildContext context, DashboardEntity dashboard) {
    final summary = dashboard.marketSummary;
    final topGainer = dashboard.topGainer;
    final topLoser = dashboard.topLoser;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Market Summary',
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _summaryRow(context, 'Listed Stocks', '${dashboard.totalStocks}'),
          if (topGainer != null)
            _summaryRow(
              context,
              'Top Gainer',
              '${topGainer.symbol}  ${Formatters.formatPercentage(topGainer.changePercent)}',
              valueColor: Colors.green,
            ),
          if (topLoser != null)
            _summaryRow(
              context,
              'Top Loser',
              '${topLoser.symbol}  ${Formatters.formatPercentage(topLoser.changePercent)}',
              valueColor: Colors.red,
            ),
          if (summary != null)
            _summaryRow(context, 'Total Volume',
                Formatters.formatCompactNumber(summary.totalVolume)),
          if (summary != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _miniStat(context, summary.gainers, 'Gainers',
                      Colors.green),
                ),
                Expanded(
                  child: _miniStat(context, summary.unchanged, 'Unchanged',
                      Colors.grey),
                ),
                Expanded(
                  child: _miniStat(context, summary.losers, 'Losers',
                      Colors.red),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: context.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: context.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(
      BuildContext context, int count, String label, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: context.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: context.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── Market overview ─────────────────────────

  Widget _buildMarketOverview(BuildContext context, DashboardEntity dashboard) {
    final rows = dashboard.marketOverview;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Market Overview',
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => context.go('/stocks'),
                borderRadius: BorderRadius.circular(8),
                child: Text(
                  'View All →',
                  style: context.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: context.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Header
          Row(
            children: [
              Expanded(flex: 5, child: _colHeader('Symbol')),
              Expanded(flex: 4,
                  child: _colHeader('Price', align: TextAlign.right)),
              Expanded(flex: 4,
                  child: _colHeader('Change', align: TextAlign.center)),
              Expanded(flex: 3,
                  child: _colHeader('Vol.', align: TextAlign.right)),
            ],
          ),
          const SizedBox(height: 2),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No market data yet.',
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            ...rows.map((s) => _overviewRow(context, s)),
        ],
      ),
    );
  }

  Text _colHeader(String text, {TextAlign align = TextAlign.left}) {
    return Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _overviewRow(BuildContext context, StockEntity s) {
    final positive = s.changePercent >= 0;
    return InkWell(
      onTap: () => context.push('/stock/${s.symbol}'),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.symbol,
                    style: context.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.bodySmall?.copyWith(
                      fontSize: 9,
                      color: context.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  Formatters.formatCurrency(s.currentPrice),
                  style: context.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: (positive ? Colors.green : Colors.red)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    Formatters.formatPercentage(s.changePercent),
                    style: TextStyle(
                      color: positive ? Colors.green : Colors.red,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  Formatters.formatCompactNumber(s.volume),
                  style: context.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: context.colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Portfolio total value with a hide/show (privacy) toggle.
class _PortfolioValue extends StatefulWidget {
  final double value;

  const _PortfolioValue({required this.value});

  @override
  State<_PortfolioValue> createState() => _PortfolioValueState();
}

class _PortfolioValueState extends State<_PortfolioValue> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _hidden
                ? '•••••••'
                : Formatters.formatCurrency(widget.value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: Icon(
            _hidden ? Icons.visibility_off : Icons.visibility,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.5),
          ),
          onPressed: () => setState(() => _hidden = !_hidden),
          tooltip: _hidden ? 'Show value' : 'Hide value',
        ),
      ],
    );
  }
}
