import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/dio_client.dart';
import '../../../core/utils/extensions.dart';


class PriceAlertsScreen extends ConsumerStatefulWidget {
  const PriceAlertsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends ConsumerState<PriceAlertsScreen> {
  List<dynamic> stocks = [];
  List<dynamic> alerts = [];
  bool isLoadingStocks = false;
  bool isLoadingAlerts = false;
  bool isCreating = false;

  String? successMsg;
  String? errorMsg;

  // Form controllers
  String? selectedStockId;
  final TextEditingController targetPriceController = TextEditingController();
  String condition = 'above';

  @override
  void initState() {
    super.initState();
    _loadStocks();
    _loadAlerts();
  }

  @override
  void dispose() {
    targetPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadStocks() async {
    setState(() => isLoadingStocks = true);
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/stocks');

      final data = response.data['data'] ?? response.data;
      setState(() {
        stocks = data['stocks'] ?? (data is List ? data : []);
      });
    } catch (e) {
      debugPrint('Failed to load stocks: $e');
    } finally {
      setState(() => isLoadingStocks = false);
    }
  }

  Future<void> _loadAlerts() async {
    setState(() => isLoadingAlerts = true);
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/alerts'); // ← Fixed

      final data = response.data['data'] ?? response.data;
      setState(() {
        alerts = data is List ? data : (data['alerts'] ?? []);
      });
    } catch (e) {
      debugPrint('Failed to load alerts: $e');
    } finally {
      setState(() => isLoadingAlerts = false);
    }
  }

  Future<void> _createAlert() async {
    if (selectedStockId == null || targetPriceController.text.isEmpty) {
      setState(() => errorMsg = 'Please fill all fields');
      return;
    }

    setState(() {
      isCreating = true;
      successMsg = null;
      errorMsg = null;
    });

    try {
      final dio = ref.read(dioProvider);
      final stockId = int.tryParse(selectedStockId!);
      final targetPrice = double.tryParse(targetPriceController.text);
      if (stockId == null || targetPrice == null) {
        setState(() => errorMsg = 'Please enter a valid target price');
        return;
      }

      final response = await dio.post(
        '/alerts',
        data: {
          'stock_id': stockId,
          'target_price': targetPrice,
          'condition': condition,
        },
      );

      setState(() {
        successMsg = response.data is Map
            ? (response.data['message']?.toString() ?? 'Alert created successfully!')
            : 'Alert created successfully!';
        selectedStockId = null;
        targetPriceController.clear();
        condition = 'above';
      });

      await _loadAlerts();
    } catch (e) {
      setState(() {
        errorMsg = 'Failed to create alert: ${_extractError(e)}';
      });
    } finally {
      setState(() => isCreating = false);
    }
  }

  String _extractError(dynamic e) {
    try {
      final data = e.response?.data;
      if (data is Map) {
        if (data['message'] is String) return data['message'] as String;
        final errors = data['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final first = errors.values.first;
          return first is List && first.isNotEmpty ? first.first.toString() : first.toString();
        }
      }
    } catch (_) {}
    return 'please try again';
  }

  Future<void> _cancelAlert(dynamic alertId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Alert'),
        content: const Text('Are you sure you want to cancel this alert?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/alerts/$alertId');
      setState(() => successMsg = 'Alert cancelled');
      await _loadAlerts();
    } catch (e) {
      setState(() => errorMsg = 'Failed to cancel alert: ${_extractError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Price Alert Manager')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success/Error Messages
            if (successMsg != null) _buildMessage(successMsg!, Colors.green),
            if (errorMsg != null) _buildMessage(errorMsg!, Colors.red),

            // Create Alert Form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Set New Price Alert',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stock Dropdown
                    DropdownButtonFormField<String>(
                      value: selectedStockId,
                      decoration: const InputDecoration(
                        labelText: 'Stock Asset',
                        border: OutlineInputBorder(),
                      ),
                      items: stocks.map((stock) {
                        return DropdownMenuItem<String>(
                          value: stock['id'].toString(),
                          child: Text('${stock['symbol']} - ${stock['name']}'),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => selectedStockId = value),
                    ),
                    const SizedBox(height: 16),

                    // Target Price
                    TextFormField(
                      controller: targetPriceController,
                      decoration: const InputDecoration(
                        labelText: 'Target Threshold Price (TZS)',
                        hintText: 'e.g. 2500',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Condition
                    DropdownButtonFormField<String>(
                      value: condition,
                      decoration: const InputDecoration(
                        labelText: 'Alert Condition Trigger',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'above',
                          child: Text('📈 When price goes ABOVE target'),
                        ),
                        DropdownMenuItem(
                          value: 'below',
                          child: Text('📉 When price goes BELOW target'),
                        ),
                      ],
                      onChanged: (value) => setState(() => condition = value!),
                    ),
                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isCreating ? null : _createAlert,
                        icon: isCreating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.notifications_active),
                        label: Text(
                          isCreating ? 'Creating Alert...' : 'Set Price Alert',
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Active Alerts Section
            const Text(
              'Current Active Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (isLoadingAlerts)
              const Center(child: CircularProgressIndicator())
            else if (alerts.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text(
                    'No active alerts configured yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: alerts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final alert = alerts[index];
                  final symbol = '${alert['stock']?['symbol'] ?? 'N/A'}';
                  final name = alert['stock']?['name']?.toString() ?? '';
                  final status = alert['status']?.toString() ?? 'active';
                  final isActive = status == 'active';
                  final isTriggered = status == 'triggered';
                  final statusColor = isTriggered
                      ? Colors.amber
                      : isActive
                          ? Colors.green
                          : Colors.grey;
                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        symbol,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (name.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        context.textTheme.bodySmall?.copyWith(
                                      color: context.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  'TZS ${alert['target_price']} • '
                                  '${alert['condition'] == 'below' ? 'Below target' : 'Above target'}',
                                  style: context.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            tooltip: 'Actions',
                            onSelected: (action) {
                              if (action == 'cancel') {
                                _cancelAlert(alert['id']);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'cancel',
                                child: Row(
                                  children: [
                                    Icon(Icons.cancel_outlined, size: 18),
                                    SizedBox(width: 8),
                                    Text('Cancel alert'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(String message, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(message, style: TextStyle(color: color)),
    );
  }
}
