import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kodastock/core/utils/extensions.dart';
import 'package:kodastock/core/utils/formatters.dart';
import 'package:kodastock/domain/entities/stock_entity.dart';

class StockCard extends StatelessWidget {
  final StockEntity stock;
  final VoidCallback? onTap;

  const StockCard({                                                                                                                                                                                                                                                                                                                                           
    Key? key,
    required this.stock,
    this.onTap,
  }) : super(key: key);                                                                                                                                                                                                                                                                                                                                                

  @override
  Widget build(BuildContext context) {
    final isZero = stock.changePercent == 0;
    final isPositive = stock.changePercent >= 0;
    final changeColor = isZero
        ? context.colorScheme.onSurface.withValues(alpha: 0.6)
        : (isPositive ? Colors.green : Colors.red);

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: changeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top content section with padding
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Header with symbol and watchlist icon
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: context.colorScheme.primary.withValues(alpha: 0.1),
                      radius: 20,
                      child: Text(
                        stock.symbol.substring(0, 2).toUpperCase(),
                        style: context.textTheme.labelLarge?.copyWith(
                          color: context.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stock.symbol,
                            style: context.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            stock.name,
                            style: context.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.star_border,
                      size: 20,
                      color: context.colorScheme.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Progress bar placeholder
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Current price section with change percentage
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CURRENT PRICE',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: changeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!isZero) ...[
                              Icon(
                                isPositive
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 15,
                                color: changeColor,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '${isPositive ? '+' : ''}${stock.changePercent.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: changeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Price and Volume row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${stock.currentPrice.toStringAsFixed(0)} TZS',
                      style: context.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.rocket_outlined,
                          size: 14,
                          color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Vol: ${Formatters.formatVolume(stock.volume)}',
                          style: context.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Additional info row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          stock.lastUpdated != null
                              ? 'Updated ${DateFormat('MMM d, HH:mm').format(stock.lastUpdated!)}'
                              : '—',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

            // View Details button - full width, no extra padding
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('View Details'),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, size: 16),
                    ],
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