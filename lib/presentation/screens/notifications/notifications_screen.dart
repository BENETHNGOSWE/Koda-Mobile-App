import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/config/theme/theme_provider.dart';
import '../../providers/app_providers.dart';

/// Activity feed. The backend has no push-notification store, so this shows
/// the user's real recorded activity (logins, stock views, simulations,
/// comparisons…) from GET /user/activities.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Items dismissed locally during this session.
  final Set<String> _dismissedIds = {};

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(isDarkModeProvider);
    final activityAsync = ref.watch(activityProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications'),
            if (activityAsync.value != null)
              Text(
                '${activityAsync.value!.length} recent activities',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.primary,
                ),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Theme toggle button
          IconButton(
            icon: Icon(
              isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            tooltip: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggleTheme();
            },
          ),
          // Pull fresh activity from the server
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(activityProvider),
          ),
        ],
      ),
      body: activityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildEmptyState(context),
        data: (activities) {
          final visible = activities
              .where((a) => !_dismissedIds.contains(a['id']?.toString()))
              .toList();
          if (visible.isEmpty) return _buildEmptyState(context);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(activityProvider),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final activity = visible[index];
                return _buildActivityItem(context, activity);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 80,
            color: context.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Notifications',
            style: context.textTheme.titleLarge?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your recent account activity will show up here.',
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(BuildContext context, Map<String, dynamic> activity) {
    final type = activity['type']?.toString() ?? 'activity';
    final id = activity['id']?.toString() ?? 'activity';

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        setState(() {
          _dismissedIds.add(id);
        });
      },
      child: Container(
        color: context.colorScheme.primary.withValues(alpha: 0.04),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: CircleAvatar(
            backgroundColor: _getActivityColor(type).withValues(alpha: 0.1),
            child: Icon(
              _getActivityIcon(type),
              color: _getActivityColor(type),
              size: 24,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  activity['title']?.toString() ?? 'Activity',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: context.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                activity['description']?.toString() ?? '',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                activity['time']?.toString() ?? '',
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'login':
        return Icons.login;
      case 'logout':
        return Icons.logout;
      case 'stock_view':
        return Icons.visibility;
      case 'analysis':
        return Icons.analytics;
      case 'comparison':
        return Icons.compare_arrows;
      case 'simulation':
        return Icons.play_arrow;
      case 'watchlist_add':
      case 'watchlist_remove':
        return Icons.bookmark;
      default:
        return Icons.notifications;
    }
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'login':
      case 'logout':
        return Colors.blue;
      case 'stock_view':
        return Colors.green;
      case 'analysis':
        return Colors.purple;
      case 'comparison':
        return Colors.teal;
      case 'simulation':
        return Colors.orange;
      case 'watchlist_add':
      case 'watchlist_remove':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }
}
