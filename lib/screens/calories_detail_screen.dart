import 'dart:math';

import 'package:flutter/material.dart';

import '../models/food_entry.dart';
import '../widgets/app_card.dart';

/// Detail screen for viewing calorie data with Daily and Weekly tabs.
class CaloriesDetailScreen extends StatefulWidget {
  final DateTime initialDate;
  final int calorieBudget;
  final List<FoodEntry> entries;
  final Map<String, Map<String, dynamic>> exerciseData;
  final String weekStartDay;

  const CaloriesDetailScreen({
    super.key,
    required this.initialDate,
    required this.calorieBudget,
    required this.entries,
    required this.exerciseData,
    required this.weekStartDay,
  });

  @override
  State<CaloriesDetailScreen> createState() => _CaloriesDetailScreenState();
}

class _CaloriesDetailScreenState extends State<CaloriesDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Selected dates
  late DateTime _selectedDate;
  late DateTime _selectedWeekStart;

  // Data from widget
  late List<FoodEntry> _entries;
  late Map<String, Map<String, dynamic>> _exerciseCache;
  late String _weekStartDay;

  // Selected bar for tooltip
  int? _selectedBarIndex;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
    _selectedDate = widget.initialDate;
    _entries = widget.entries;
    _exerciseCache = widget.exerciseData;
    _weekStartDay = widget.weekStartDay;
    _selectedWeekStart = _getWeekStart(widget.initialDate);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime _getWeekStart(DateTime date) {
    final targetWeekday = _weekStartDay == 'sunday'
        ? DateTime.sunday
        : DateTime.monday;
    int daysToSubtract = (date.weekday - targetWeekday + 7) % 7;
    return DateTime(date.year, date.month, date.day - daysToSubtract);
  }

  String _dateToId(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<FoodEntry> _entriesForDay(DateTime day) {
    return _entries.where((e) => _isSameDay(e.dateTime, day)).toList();
  }

  int _caloriesForDay(DateTime day) {
    return _entriesForDay(day).fold(0, (sum, e) => sum + e.calories);
  }

  int _exerciseForDay(DateTime day) {
    final dateId = _dateToId(day);
    final data = _exerciseCache[dateId];
    return data?['activeCalories'] as int? ?? 0;
  }

  List<int> _weeklyCalories(DateTime weekStart) {
    return List.generate(7, (i) {
      final day = weekStart.add(Duration(days: i));
      return _caloriesForDay(day);
    });
  }

  void _previousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
      _selectedBarIndex = null;
    });
  }

  void _nextWeek() {
    final now = DateTime.now();
    final nextWeekStart = _selectedWeekStart.add(const Duration(days: 7));
    // Don't allow if next week is entirely in the future
    if (nextWeekStart.isAfter(now)) return;
    setState(() {
      _selectedWeekStart = nextWeekStart;
      _selectedBarIndex = null;
    });
  }

  bool _canGoToNextWeek() {
    final now = DateTime.now();
    final nextWeekStart = _selectedWeekStart.add(const Duration(days: 7));
    return !nextWeekStart.isAfter(now);
  }

  void _previousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
  }

  void _nextDay() {
    final now = DateTime.now();
    if (_isSameDay(_selectedDate, now)) return; // Already at today
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    });
  }

  bool _canGoToNextDay() {
    return !_isSameDay(_selectedDate, DateTime.now());
  }

  String _formatWeekDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDayDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calories'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Colors.white,
              tabs: const [
                Tab(text: 'Daily', height: 36),
                Tab(text: 'Weekly', height: 36),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDailyTab(), _buildWeeklyTab()],
      ),
    );
  }

  Widget _buildWeeklyTab() {
    final weekCalories = _weeklyCalories(_selectedWeekStart);
    final hasData = weekCalories.any((c) => c > 0);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      children: [
        // Week navigation
        _buildDateNavigation(
          'Week of ${_formatWeekDate(_selectedWeekStart)}',
          onPrevious: _previousWeek,
          onNext: _canGoToNextWeek() ? _nextWeek : null,
        ),
        const SizedBox(height: 16),
        // Main card with bars
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Bar chart
              _buildWeeklyBars(weekCalories),
              const SizedBox(height: 16),
              // No data message
              if (!hasData)
                Text(
                  'No data for week',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyBars(List<int> calories) {
    const barHeight = 120.0;
    const tooltipHeight = 28.0;
    final maxCalories = widget.calorieBudget.toDouble();
    final days = _weekStartDay == 'sunday'
        ? ['Su', 'M', 'Tu', 'W', 'Th', 'F', 'Sa']
        : ['M', 'Tu', 'W', 'Th', 'F', 'Sa', 'Su'];

    return SizedBox(
      height: barHeight + 24 + tooltipHeight + 4,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final dayCalories = calories[i];
          final fillRatio = (dayCalories / maxCalories).clamp(0.0, 1.0);
          final isOverBudget = dayCalories > widget.calorieBudget;
          final day = _selectedWeekStart.add(Duration(days: i));
          final isToday = _isSameDay(day, DateTime.now());
          final isSelected = _selectedBarIndex == i;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedBarIndex = isSelected ? null : i;
                  });
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Tooltip above bar
                    SizedBox(
                      height: tooltipHeight,
                      child: isSelected
                          ? OverflowBox(
                              maxWidth: 80,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '$dayCalories',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    // Bar
                    Container(
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          height: barHeight * fillRatio,
                          decoration: BoxDecoration(
                            color: isOverBudget ? Colors.red : Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Day label
                    Text(
                      days[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isToday
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isToday
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDailyTab() {
    final foodCalories = _caloriesForDay(_selectedDate);
    final exerciseCalories = _exerciseForDay(_selectedDate);
    final netCalories = foodCalories - exerciseCalories;
    final remaining = widget.calorieBudget - netCalories;
    final isUnder = remaining >= 0;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      children: [
        // Day navigation
        _buildDateNavigation(
          _formatDayDate(_selectedDate),
          onPrevious: _previousDay,
          onNext: _canGoToNextDay() ? _nextDay : null,
        ),
        const SizedBox(height: 16),
        // Main card
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Donut chart
              _buildDonutChart(netCalories, remaining, isUnder),
              const SizedBox(height: 24),
              // Stats list
              _buildStatRow('Food calories consumed', foodCalories),
              _buildStatRow('Exercise calories burned', exerciseCalories),
              const Divider(height: 24),
              _buildStatRow('Net calories', netCalories),
              const SizedBox(height: 16),
              _buildStatRow('Daily calorie budget', widget.calorieBudget),
              _buildStatRow('Net calories', netCalories),
              const Divider(height: 24),
              _buildStatRow(
                isUnder ? 'Calories under budget' : 'Calories over budget',
                remaining.abs(),
                valueColor: isUnder ? Colors.green : Colors.red,
                bold: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDonutChart(int netCalories, int remaining, bool isUnder) {
    final progress = (netCalories / widget.calorieBudget).clamp(0.0, 1.0);

    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Arc chart open at bottom
          CustomPaint(
            size: const Size(180, 180),
            painter: _ArcPainter(
              progress: progress,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              progressColor: isUnder ? Colors.green : Colors.red,
              strokeWidth: 16,
            ),
          ),
          // Center text
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                remaining.abs().toString().replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},'),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Text(
                isUnder ? 'under' : 'over',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    String label,
    int value, {
    Color? valueColor,
    bool bold = false,
  }) {
    final formattedValue = value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            formattedValue,
            style: TextStyle(
              color: valueColor,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateNavigation(
    String title, {
    required VoidCallback onPrevious,
    required VoidCallback? onNext,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrevious),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right,
            color: onNext == null
                ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
                : null,
          ),
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Custom painter for drawing an arc that's open at the bottom (horseshoe shape)
class _ArcPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  _ArcPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Arc spans 240 degrees (from 150° to 390°), leaving 120° open at bottom
    const startAngle = 150 * pi / 180; // Start at bottom-left
    const sweepAngle = 240 * pi / 180; // Sweep 240 degrees

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      backgroundPaint,
    );

    // Draw progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor;
  }
}
