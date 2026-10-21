// lib/presentation/providers/app_providers.dart

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../core/config/dio_client.dart';
import '../../core/config/constants/app_constants.dart';
import '../../data/sources/remote/stock_api_service.dart';
import '../../data/sources/local/local_storage.dart';
import '../../data/repositories/stock_repository_impl.dart';
import '../../domain/repositories/stock_repository.dart';
import '../../domain/usecases/stock_usecases.dart';
import '../../domain/entities/stock_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../data/models/auth/user_model.dart';

// Local Storage Provider
final localStorageProvider = FutureProvider<LocalStorage>((ref) async {
  return await LocalStorageProvider.create();
});

// NOTE: dioProvider is already defined in dio_client.dart
// We re-export it here or just use it directly

// API Service Provider - Uses the dio from dioClientProvider
final apiServiceProvider = Provider<StockApiService>((ref) {
  final dio = ref.watch(dioProvider);  // This comes from dio_client.dart
  return StockApiService(dio);
});

// Repository Provider
final stockRepositoryProvider = Provider<StockRepository>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final localStorage = ref.watch(localStorageProvider).value!;
  return StockRepositoryImpl(apiService, localStorage);
});

// Use Cases Providers
final getDashboardProvider = Provider<GetDashboard>((ref) {
  return GetDashboard(ref.watch(stockRepositoryProvider));
});

final getAllStocksProvider = Provider<GetAllStocks>((ref) {
  return GetAllStocks(ref.watch(stockRepositoryProvider));
});

final getStockDetailsProvider = Provider<GetStockDetails>((ref) {
  return GetStockDetails(ref.watch(stockRepositoryProvider));
});

final compareStocksUseCaseProvider = Provider<CompareStocks>((ref) {
  return CompareStocks(ref.watch(stockRepositoryProvider));
});

final getStockAnalysisProvider = Provider<GetStockAnalysis>((ref) {
  return GetStockAnalysis(ref.watch(stockRepositoryProvider));
});

final manageWatchlistProvider = Provider<ManageWatchlist>((ref) {
  return ManageWatchlist(ref.watch(stockRepositoryProvider));
});

// User Provider - Fetches current user data
final userProvider = FutureProvider<UserEntity>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final response = await dio.get(ApiEndpoints.user);
    final userModel = UserModel.fromJson(response.data);
    return userModel.toEntity();
  } on DioException catch (e) {
    throw Exception('Failed to load user: ${e.message}');
  }
});

// ─────────────────────────────────────────────────────────────────────────
// Market stats (real data from the public /stocks/stats endpoint)
// ─────────────────────────────────────────────────────────────────────────
final marketStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final response = await dio.get(ApiEndpoints.stocksStats);
    final data = response.data;
    if (data is Map && data['data'] is Map) {
      return data['data'] as Map<String, dynamic>;
    }
  } catch (_) {
    // Fall through to an empty stats map; the dashboard degrades gracefully.
  }
  return {};
});

// ─────────────────────────────────────────────────────────────────────────
// User activity (real data from /user/activities — used by dashboard and
// the notifications screen)
// ─────────────────────────────────────────────────────────────────────────
final activityProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final response = await dio.get(ApiEndpoints.userActivities(20));
    final data = response.data;
    if (data is Map && data['activities'] is List) {
      return (data['activities'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
  } catch (_) {
    // Not logged in or endpoint unavailable — show an empty feed.
  }
  return [];
});

// Small numeric helpers for API values that arrive as String or num.
double _asDouble(dynamic value, {double fallback = 0.0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

StockEntity? _stockEntityFromApiMap(dynamic raw) {
  if (raw is! Map) return null;
  final symbol = raw['symbol'];
  if (symbol is! String || symbol.isEmpty) return null;
  return StockEntity(
    id: raw['id'] is int ? raw['id'] as int : int.tryParse('${raw['id']}'),
    symbol: symbol,
    name: raw['name'] is String ? raw['name'] as String : symbol,
    currentPrice: _asDouble(raw['current_price']),
    changePercent: _asDouble(raw['change_percent'] ?? raw['change_percentage']),
    change: _asDouble(raw['change']),
    volume: _asDouble(raw['volume']),
    sector: raw['sector'] is String ? raw['sector'] as String : null,
  );
}

// State Providers for Dashboard - real data from /stocks + /stocks/stats
final dashboardProvider = FutureProvider<DashboardEntity>((ref) async {
  final getAllStocks = ref.watch(getAllStocksProvider);
  final watchlist = ref.watch(watchlistProvider);
  final stats = await ref.watch(marketStatsProvider.future);

  // Fetch all stocks
  final result = await getAllStocks();

  return result.fold(
    (error) => throw Exception(error),
    (stocks) {
      final gainers = stocks.where((s) => s.isGainer).toList();
      final losers = stocks.where((s) => s.isLoser).toList();

      // Sort to find top gainer and loser
      gainers.sort((a, b) => b.changePercent.compareTo(a.changePercent));
      losers.sort((a, b) => a.changePercent.compareTo(b.changePercent));

      // Prefer the server's own picks; fall back to the computed ones.
      final topGainer = _stockEntityFromApiMap(stats['topGainer']) ??
          (gainers.isNotEmpty ? gainers.first : null);
      final topLoser = _stockEntityFromApiMap(stats['topLoser']) ??
          (losers.isNotEmpty ? losers.first : null);

      final totalVolume = stats['totalVolume'] != null
          ? _asDouble(stats['totalVolume'])
          : stocks.fold<double>(0.0, (sum, stock) => sum + stock.volume);

      // Top movers: the stocks with the biggest absolute change, so the
      // overview shows the market's actual day rather than the first five
      // rows alphabetically.
      final movers = List<StockEntity>.from(stocks)
        ..sort((a, b) => b.changePercent.abs().compareTo(a.changePercent.abs()));

      return DashboardEntity(
        totalStocks: stats['totalStocks'] != null
            ? _asInt(stats['totalStocks'])
            : stocks.length,
        watchlistCount: watchlist.length,
        totalGainers: stats['gainersCount'] != null
            ? _asInt(stats['gainersCount'])
            : gainers.length,
        totalLosers: stats['losersCount'] != null
            ? _asInt(stats['losersCount'])
            : losers.length,
        topGainer: topGainer,
        topLoser: topLoser,
        marketSummary: MarketSummaryEntity(
          totalVolume: totalVolume,
          gainers: stats['gainersCount'] != null
              ? _asInt(stats['gainersCount'])
              : gainers.length,
          losers: stats['losersCount'] != null
              ? _asInt(stats['losersCount'])
              : losers.length,
          unchanged: stats['unchangedCount'] != null
              ? _asInt(stats['unchangedCount'])
              : stocks.length - gainers.length - losers.length,
        ),
        marketOverview: movers.take(5).toList(),
        recentActivity: [], // Filled in by the dashboard via activityProvider
      );
    },
  );
});

// State Provider for Stocks List
final stocksListProvider = FutureProvider.family<List<StockEntity>, String?>((
  ref,
  sector,
) async {
  final getAllStocks = ref.watch(getAllStocksProvider);
  final result = await getAllStocks(sector: sector);
  return result.fold(
    (error) => throw Exception(error),
    (stocks) => stocks,
  );
});

// State Provider for Stock Analysis
final stockAnalysisProvider = FutureProvider.family<AnalysisEntity, Map<String, String>>((
  ref,
  params,
) async {
  final getAnalysis = ref.watch(getStockAnalysisProvider);
  final result = await getAnalysis(params['symbol']!, params['period']!);
  return result.fold(
    (error) => throw Exception(error),
    (analysis) => analysis,
  );
});

// State Provider for Comparison
final comparisonProvider = FutureProvider.family<ComparisonEntity, Map<String, dynamic>>((
  ref,
  params,
) async {
  final compareStocks = ref.watch(compareStocksUseCaseProvider);
  final result = await compareStocks(
    params['symbols'] as List<String>,
    params['period'] as String,
  );
  return result.fold(
    (error) => throw Exception(error),
    (comparison) => comparison,
  );
});

// Watchlist Provider
final watchlistProvider = StateNotifierProvider<WatchlistNotifier, List<String>>((ref) {
  final manageWatchlist = ref.watch(manageWatchlistProvider);
  return WatchlistNotifier(manageWatchlist);
});

class WatchlistNotifier extends StateNotifier<List<String>> {
  final ManageWatchlist _manageWatchlist;

  WatchlistNotifier(this._manageWatchlist) : super([]) {
    _loadWatchlist();
  }

  void _loadWatchlist() {
    state = _manageWatchlist.getWatchlist();
  }

  Future<void> addToWatchlist(String symbol) async {
    final success = await _manageWatchlist.addToWatchlist(symbol);
    if (success) {
      state = [...state, symbol];
    }
  }

  Future<void> removeFromWatchlist(String symbol) async {
    final success = await _manageWatchlist.removeFromWatchlist(symbol);
    if (success) {
      state = state.where((s) => s != symbol).toList();
    }
  }

  bool isInWatchlist(String symbol) {
    return state.contains(symbol);
  }
}

// Onboarding Provider
final onboardingProvider = FutureProvider<bool>((ref) async {
  final localStorage = await ref.watch(localStorageProvider.future);
  return localStorage.getOnboardingCompleted();
});

class OnboardingNotifier extends StateNotifier<bool> {
  final LocalStorage _localStorage;

  OnboardingNotifier(this._localStorage) : super(false) {
    _loadOnboardingStatus();
  }

  void _loadOnboardingStatus() {
    state = _localStorage.getOnboardingCompleted();
  }

  Future<void> completeOnboarding() async {
    await _localStorage.setOnboardingCompleted(true);
    state = true;
  }
}

final onboardingNotifierProvider = StateNotifierProvider<OnboardingNotifier, bool>((ref) {
  final localStorage = ref.watch(localStorageProvider).value!;
  return OnboardingNotifier(localStorage);
});