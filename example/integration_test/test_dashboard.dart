import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Domain models
// ─────────────────────────────────────────────────────────────────────────────

enum TestStatus { pending, running, passed, failed, skipped }

class TestCase {
  TestCase({required this.category, required this.name});

  final String category;
  final String name;
  TestStatus status = TestStatus.pending;
  String? errorMessage;
}

class TestSuite extends ChangeNotifier {
  final List<TestCase> _cases = [];
  List<TestCase> get cases => List.unmodifiable(_cases);

  int get total => _cases.length;
  int get passed => _cases.where((c) => c.status == TestStatus.passed).length;
  int get failed => _cases.where((c) => c.status == TestStatus.failed).length;
  int get skipped => _cases.where((c) => c.status == TestStatus.skipped).length;
  int get running => _cases.where((c) => c.status == TestStatus.running).length;
  int get pending => _cases.where((c) => c.status == TestStatus.pending).length;
  bool get isComplete => pending == 0 && running == 0;

  void register(String category, String name) {
    _cases.add(TestCase(category: category, name: name));
  }

  Future<void> run(
    String name,
    Future<void> Function() test, {
    bool skip = false,
    String? skipReason,
  }) async {
    final tc = _cases.firstWhere((c) => c.name == name);

    if (skip) {
      tc.status = TestStatus.skipped;
      tc.errorMessage = skipReason;
      notifyListeners();
      return;
    }

    tc.status = TestStatus.running;
    notifyListeners();

    try {
      await test();
      tc.status = TestStatus.passed;
    } catch (e) {
      tc.status = TestStatus.failed;
      tc.errorMessage = e.toString().split('\n').first;
    }

    notifyListeners();
  }

  List<String> get categories => _cases.map((c) => c.category).toSet().toList();

  List<TestCase> byCategory(String category) =>
      _cases.where((c) => c.category == category).toList();
}

// ─────────────────────────────────────────────────────────────────────────────
// Visual dashboard
// ─────────────────────────────────────────────────────────────────────────────

class TestDashboard extends StatelessWidget {
  const TestDashboard({super.key, required this.suite});
  final TestSuite suite;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF58A6FF),
          surface: Color(0xFF161B22),
        ),
      ),
      home: _DashboardScreen(suite: suite),
    );
  }
}

class _DashboardScreen extends StatefulWidget {
  const _DashboardScreen({required this.suite});
  final TestSuite suite;

  @override
  State<_DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<_DashboardScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.suite.addListener(_onSuiteChange);
  }

  @override
  void dispose() {
    widget.suite.removeListener(_onSuiteChange);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSuiteChange() {
    setState(() {});
    // Jump to bottom so the currently-running test is always visible.
    // Uses jumpTo (instant) so it works inside the test-widget pump loop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final suite = widget.suite;
    return Scaffold(
      body: Column(
        children: [
          _SummaryBar(suite: suite),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                for (final category in suite.categories) ...[
                  _CategoryHeader(
                    category: category,
                    cases: suite.byCategory(category),
                  ),
                  ...suite
                      .byCategory(category)
                      .map((tc) => _TestTile(testCase: tc)),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary bar ──────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.suite});
  final TestSuite suite;

  @override
  Widget build(BuildContext context) {
    final done = suite.isComplete;
    final allPassed = done && suite.failed == 0 && suite.skipped == 0;

    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF161B22),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'FMH Feature Tests',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE6EDF3),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (!done)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF58A6FF),
                    ),
                  )
                else
                  Icon(
                    allPassed ? Icons.check_circle : Icons.error,
                    size: 16,
                    color: allPassed
                        ? const Color(0xFF3FB950)
                        : const Color(0xFFF85149),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Chip(suite.passed, '✓ Passed', const Color(0xFF3FB950)),
                _Chip(suite.failed, '✗ Failed', const Color(0xFFF85149)),
                _Chip(suite.skipped, '⏭ Skipped', const Color(0xFFD29922)),
                _Chip(
                  suite.pending + suite.running,
                  '· Pending',
                  const Color(0xFF8B949E),
                ),
                Text(
                  '${suite.total} total',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8B949E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: suite.total == 0
                    ? 0
                    : (suite.passed + suite.failed + suite.skipped) /
                          suite.total,
                backgroundColor: const Color(0xFF21262D),
                valueColor: AlwaysStoppedAnimation<Color>(
                  suite.failed > 0
                      ? const Color(0xFFF85149)
                      : const Color(0xFF3FB950),
                ),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.count, this.label, this.color);
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Category header ───────────────────────────────────────────────────────────

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category, required this.cases});
  final String category;
  final List<TestCase> cases;

  @override
  Widget build(BuildContext context) {
    final passed = cases.where((c) => c.status == TestStatus.passed).length;
    final failed = cases.where((c) => c.status == TestStatus.failed).length;
    final total = cases.length;

    Color countColor = const Color(0xFF8B949E);
    if (failed > 0) {
      countColor = const Color(0xFFF85149);
    } else if (passed == total) {
      countColor = const Color(0xFF3FB950);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: const Color(0xFF21262D))),
          const SizedBox(width: 10),
          Text(
            category.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8B949E),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$passed/$total',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: countColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: const Color(0xFF21262D))),
        ],
      ),
    );
  }
}

// ── Test tile ─────────────────────────────────────────────────────────────────

class _TestTile extends StatelessWidget {
  const _TestTile({required this.testCase});
  final TestCase testCase;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _borderColor,
          width: testCase.status == TestStatus.running ? 1 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusIcon(status: testCase.status),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    testCase.name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: _textColor,
                    ),
                  ),
                  if (testCase.errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      testCase.errorMessage!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFFF85149),
                        fontFamily: 'monospace',
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _borderColor {
    switch (testCase.status) {
      case TestStatus.passed:
        return const Color(0xFF3FB950).withAlpha(60);
      case TestStatus.failed:
        return const Color(0xFFF85149).withAlpha(80);
      case TestStatus.running:
        return const Color(0xFF58A6FF);
      case TestStatus.skipped:
        return const Color(0xFFD29922).withAlpha(50);
      case TestStatus.pending:
        return const Color(0xFF21262D);
    }
  }

  Color get _textColor {
    switch (testCase.status) {
      case TestStatus.passed:
        return const Color(0xFFE6EDF3);
      case TestStatus.failed:
        return const Color(0xFFF85149);
      case TestStatus.running:
        return const Color(0xFF58A6FF);
      case TestStatus.skipped:
        return const Color(0xFF8B949E);
      case TestStatus.pending:
        return const Color(0xFF8B949E);
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final TestStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case TestStatus.passed:
        return const Icon(
          Icons.check_circle,
          size: 16,
          color: Color(0xFF3FB950),
        );
      case TestStatus.failed:
        return const Icon(Icons.cancel, size: 16, color: Color(0xFFF85149));
      case TestStatus.running:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF58A6FF),
          ),
        );
      case TestStatus.skipped:
        return const Icon(Icons.skip_next, size: 16, color: Color(0xFFD29922));
      case TestStatus.pending:
        return const Icon(
          Icons.radio_button_unchecked,
          size: 16,
          color: Color(0xFF30363D),
        );
    }
  }
}
