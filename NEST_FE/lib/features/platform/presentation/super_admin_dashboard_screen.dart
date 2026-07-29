import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nest_fe/core/auth/session_controller.dart';
import 'package:nest_fe/core/providers/core_providers.dart';
import 'package:nest_fe/core/widgets/async_value_view.dart';
import 'package:nest_fe/features/artist_application/presentation/artist_applications_screen.dart';
import 'package:nest_fe/features/platform/data/platform_api.dart';
import 'package:nest_fe/features/platform/presentation/console_layout.dart';

final platformApiProvider = Provider((ref) => PlatformApi(ref.watch(dioClientProvider)));
final platformOverviewProvider =
    FutureProvider.autoDispose((ref) => ref.watch(platformApiProvider).overview());

/// The Super Admin's ERP home - deliberately a different screen from the academy DashboardScreen
/// everyone else sees. A Super Admin has no academy membership, so the usual "your courses / your
/// role" tiles are meaningless for them; what they need is the cross-tenant view of the platform.
class SuperAdminDashboardScreen extends ConsumerWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final overviewAsync = ref.watch(platformOverviewProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(platformOverviewProvider.future),
      child: AsyncValueView<PlatformOverview>(
        value: overviewAsync,
        onRetry: () => ref.invalidate(platformOverviewProvider),
        data: (context, data) {
          final colorScheme = Theme.of(context).colorScheme;
          return ConsolePage(
            children: [
              Text('Platform overview', style: Theme.of(context).textTheme.bodyMedium),
              Text(user?.fullName ?? 'Super Admin', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 24),

              const ConsoleSectionTitle('Live now'),
              ConsoleStatGrid(stats: [
                ConsoleStat('Active last hour', '${data.activity.activeLastHour}', Icons.bolt_outlined),
                ConsoleStat('Active today', '${data.activity.activeToday}', Icons.today_outlined),
                ConsoleStat('Active this week', '${data.activity.activeThisWeek}', Icons.date_range_outlined),
                ConsoleStat('Active this month', '${data.activity.activeThisMonth}', Icons.calendar_month_outlined),
                ConsoleStat('Total users', '${data.users.total}', Icons.people_outline),
                ConsoleStat(
                  'Installs seen',
                  '${data.activity.installsSeen}',
                  Icons.install_mobile_outlined,
                  // Honest labelling: the backend cannot read Play Store / App Store download
                  // counts, so this is distinct devices that launched the app, not downloads.
                  footnote: 'devices, not store downloads',
                ),
              ]),
              const SizedBox(height: 28),

              const ConsoleSectionTitle('Academies'),
              ConsoleStatGrid(stats: [
                ConsoleStat('Total', '${data.academies.total}', Icons.account_balance_outlined),
                ConsoleStat('Active', '${data.academies.active}', Icons.check_circle_outline),
                ConsoleStat('Suspended', '${data.academies.suspended}', Icons.pause_circle_outline,
                    tone: data.academies.suspended > 0 ? colorScheme.error : null),
                ConsoleStat('New this month', '${data.academies.newThisMonth}', Icons.trending_up),
                ConsoleStat('New users / week', '${data.users.newThisWeek}', Icons.person_add_alt_outlined),
                ConsoleStat('New users / month', '${data.users.newThisMonth}', Icons.group_add_outlined),
              ]),
              const SizedBox(height: 28),

              // Side by side on a desktop window - the trend and the role split are read together,
              // and stacking them wastes half the screen. Falls back to stacked when narrow.
              _TrendAndRoles(
                trend: data.signupTrend,
                byRole: data.users.byRole,
              ),
              const SizedBox(height: 28),

              const ConsoleSectionTitle('Social'),
              ConsoleStatGrid(stats: [
                ConsoleStat('Total posts', '${data.social.totalPosts}', Icons.dynamic_feed_outlined),
                ConsoleStat('Posts this week', '${data.social.postsThisWeek}', Icons.post_add_outlined),
                ConsoleStat('Total events', '${data.social.totalEvents}', Icons.celebration_outlined),
                ConsoleStat('Upcoming events', '${data.social.upcomingEvents}', Icons.event_available_outlined),
              ]),
              const SizedBox(height: 24),

              // Artist applications lost its own nav tab to Billing, so it needs a route from
              // here - a queue nobody can reach is a queue that never gets worked.
              const ConsoleSectionTitle('Review queue'),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(Icons.palette_outlined,
                      color: data.social.pendingArtistApplications > 0 ? colorScheme.tertiary : null),
                  title: const Text('Artist applications'),
                  subtitle: Text(data.social.pendingArtistApplications == 0
                      ? 'Nothing waiting for review'
                      : '${data.social.pendingArtistApplications} waiting for review'),
                  trailing: data.social.pendingArtistApplications == 0
                      ? const Icon(Icons.chevron_right)
                      : Badge(label: Text('${data.social.pendingArtistApplications}')),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ArtistApplicationsScreen()),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Signup trend and role split, side by side on a desktop window. They're read together ("we grew
/// - who are the new people?"), and stacking them on a wide screen wastes half the viewport. Falls
/// back to stacked below the compact breakpoint.
class _TrendAndRoles extends StatelessWidget {
  const _TrendAndRoles({required this.trend, required this.byRole});

  final List<DailyCount> trend;
  final Map<String, int> byRole;

  @override
  Widget build(BuildContext context) {
    final chart = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConsoleSectionTitle('Signups - last 30 days'),
        _SignupTrendChart(trend: trend),
      ],
    );
    final roles = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConsoleSectionTitle('Users by role'),
        _RoleBreakdown(byRole: byRole),
      ],
    );

    if (ConsoleBreakpoints.isCompact(context)) {
      return Column(children: [chart, const SizedBox(height: 24), roles]);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: chart),
          const SizedBox(width: 20),
          Expanded(flex: 2, child: roles),
        ],
      ),
    );
  }
}

/// Horizontal bars rather than a pie: role counts are wildly uneven (thousands of students to a
/// handful of admins), and a pie chart of that is unreadable while a bar list stays exact.
class _RoleBreakdown extends StatelessWidget {
  const _RoleBreakdown({required this.byRole});
  final Map<String, int> byRole;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = byRole.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();

    final max = entries.first.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('By role', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            ...entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          e.key.replaceAll('_', ' '),
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: max == 0 ? 0 : e.value / max,
                            minHeight: 8,
                            backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${e.value}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _SignupTrendChart extends StatelessWidget {
  const _SignupTrendChart({required this.trend});
  final List<DailyCount> trend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (trend.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No signup data yet.'))),
      );
    }

    final maxCount = trend.map((d) => d.count).reduce((a, b) => a > b ? a : b);
    // A flat all-zero series would collapse the axis to a single line, so keep a minimum ceiling.
    final maxY = (maxCount < 4 ? 4 : maxCount * 1.25).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 16, 12),
        child: SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: colorScheme.onSurface.withValues(alpha: 0.08),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) return const SizedBox.shrink();
                      return Text('${value.toInt()}', style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    // Only every 7th day, otherwise 30 labels overlap into an unreadable smear.
                    interval: 7,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= trend.length) return const SizedBox.shrink();
                      final day = trend[index].day;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${day.day}/${day.month}', style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < trend.length; i++) FlSpot(i.toDouble(), trend[i].count.toDouble()),
                  ],
                  isCurved: true,
                  curveSmoothness: 0.25,
                  color: colorScheme.primary,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: colorScheme.primary.withValues(alpha: 0.15),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((spot) {
                    final day = trend[spot.x.toInt()].day;
                    return LineTooltipItem(
                      '${day.day}/${day.month}\n${spot.y.toInt()} signups',
                      TextStyle(color: colorScheme.onInverseSurface, fontWeight: FontWeight.w600),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
