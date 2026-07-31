import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_strings.dart';
import '../../core/db/app_database.dart';
import '../../core/theme/app_theme.dart';

/// Debug-only offline DB browser (SQLCipher via the live [AppDatabase] handle).
///
/// Kept deliberately lightweight: progressive table counts, small pages, and
/// a ListView of row cards (not DataTable) so large tables don't freeze the UI.
class DebugDbViewerScreen extends StatefulWidget {
  const DebugDbViewerScreen({super.key});

  @override
  State<DebugDbViewerScreen> createState() => _DebugDbViewerScreenState();
}

class _DebugDbViewerScreenState extends State<DebugDbViewerScreen> {
  final List<_TableInfo> _tables = [];
  bool _loading = true;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    assert(kDebugMode, 'DebugDbViewerScreen is debug-only');
    _loadTables();
  }

  Future<void> _loadTables() async {
    setState(() {
      _loading = true;
      _error = null;
      _tables.clear();
    });

    try {
      final db = context.read<AppDatabase>().db;
      final names = List<String>.from(AppDatabase.allTablesForTesting)
        ..sort();

      // Seed list immediately so the screen isn't blank while COUNTs run.
      if (!mounted) return;
      setState(() {
        _tables.addAll(names.map((n) => _TableInfo(name: n, rowCount: null)));
        _loading = false;
      });

      for (final name in names) {
        if (!mounted) return;
        int? count;
        try {
          count = Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM $name'),
              ) ??
              0;
        } catch (e) {
          debugPrint('[DebugDb] COUNT $name failed: $e');
          count = -1;
        }
        if (!mounted) return;
        final i = _tables.indexWhere((t) => t.name == name);
        if (i >= 0) {
          setState(() {
            _tables[i] = _TableInfo(name: name, rowCount: count);
          });
        }
        // Yield so the UI can paint between table counts.
        await Future<void>.delayed(Duration.zero);
      }

      if (!mounted) return;
      setState(() {
        _tables.sort((a, b) {
          final ac = a.rowCount ?? -1;
          final bc = b.rowCount ?? -1;
          final byCount = bc.compareTo(ac);
          if (byCount != 0) return byCount;
          return a.name.compareTo(b.name);
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final knownCounts =
        _tables.where((t) => t.rowCount != null && t.rowCount! >= 0);
    final totalRows =
        knownCounts.fold<int>(0, (sum, t) => sum + (t.rowCount ?? 0));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DebugDbStrings.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            Text(
              DebugDbStrings.subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: DebugDbStrings.refresh,
            onPressed: _loading ? null : _loadTables,
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  DebugDbStrings.loadError(_error!),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: AppColors.aiSurfaceStart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      _loading
                          ? DebugDbStrings.summary(_tables.length, 0)
                          : DebugDbStrings.summary(
                              _tables.length,
                              totalRows,
                            ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ),
                if (_loading && _tables.isEmpty)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: _tables.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = _tables[i];
                        final countLabel = t.rowCount == null
                            ? '…'
                            : t.rowCount! < 0
                                ? '!'
                                : t.rowCount! > 999
                                    ? '999+'
                                    : '${t.rowCount}';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: (t.rowCount ?? 0) > 0
                                ? AppColors.aiPurple
                                : AppColors.navy.withValues(alpha: 0.25),
                            foregroundColor: Colors.white,
                            child: Text(
                              countLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            t.name,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            t.rowCount == null
                                ? DebugDbStrings.counting
                                : t.rowCount! < 0
                                    ? DebugDbStrings.countFailed
                                    : DebugDbStrings.rowCount(t.rowCount!),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _DebugTableDetailScreen(
                                  tableName: t.name,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TableInfo {
  const _TableInfo({required this.name, required this.rowCount});
  final String name;
  final int? rowCount;
}

class _DebugTableDetailScreen extends StatefulWidget {
  const _DebugTableDetailScreen({required this.tableName});

  final String tableName;

  @override
  State<_DebugTableDetailScreen> createState() =>
      _DebugTableDetailScreenState();
}

class _DebugTableDetailScreenState extends State<_DebugTableDetailScreen> {
  static const int _pageSize = 20;
  static const double _colWidth = 140;

  final _searchCtrl = TextEditingController();
  List<String> _columns = const [];
  List<Map<String, Object?>> _rows = const [];
  int _totalRows = 0;
  int _offset = 0;
  String _query = '';
  bool _loading = true;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadPage();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = context.read<AppDatabase>().db;
      final table = widget.tableName;

      final pragma = await db.rawQuery('PRAGMA table_info($table)');
      final columns = pragma
          .map((r) => (r['name'] as String?) ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final total = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table'),
          ) ??
          0;

      final searchCols = _searchColumns(columns);

      List<Map<String, Object?>> rows;
      final q = _query.trim();
      if (q.isEmpty) {
        rows = await db.query(
          table,
          limit: _pageSize,
          offset: _offset,
        );
      } else if (searchCols.isEmpty) {
        rows = const [];
      } else {
        // Limit search columns to avoid full-table CAST OR scans that freeze.
        final like = '%$q%';
        final where =
            searchCols.map((c) => 'CAST($c AS TEXT) LIKE ?').join(' OR ');
        rows = await db.query(
          table,
          where: where,
          whereArgs: List<Object?>.filled(searchCols.length, like),
          limit: _pageSize,
          offset: _offset,
        );
      }

      if (!mounted) return;
      setState(() {
        _columns = columns;
        _rows = rows;
        _totalRows = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<String> _searchColumns(List<String> columns) {
    const preferred = [
      'id',
      'patient_id',
      'member_id',
      'household_id',
      'name',
      'patient_name',
      'status',
      'sync_status',
      'phone',
      'phone_number',
    ];
    final ordered = <String>[];
    for (final p in preferred) {
      if (columns.contains(p)) ordered.add(p);
    }
    for (final c in columns) {
      if (!ordered.contains(c)) ordered.add(c);
      if (ordered.length >= 6) break;
    }
    return ordered;
  }

  String _cellText(Object? value) {
    if (value == null) return '';
    final s = value.toString().replaceAll('\n', ' ');
    if (s.length <= 48) return s;
    return '${s.substring(0, 45)}…';
  }

  void _reload({int? offset}) {
    if (offset != null) _offset = offset;
    _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.tableName,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: DebugDbStrings.refresh,
            onPressed: _loading ? null : () => _reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: DebugDbStrings.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                          _reload(offset: 0);
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                setState(() => _query = v);
                _reload(offset: 0);
              },
            ),
          ),
          if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    DebugDbStrings.loadError(_error!),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_rows.isEmpty)
            Expanded(child: Center(child: Text(DebugDbStrings.emptyTable)))
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DebugDbStrings.pageLabel(
                        _offset + 1,
                        _offset + _rows.length,
                        _totalRows,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    DebugDbStrings.columnCount(_columns.length),
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  IconButton(
                    onPressed: _offset <= 0
                        ? null
                        : () => _reload(
                              offset: (_offset - _pageSize)
                                  .clamp(0, _totalRows),
                            ),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: DebugDbStrings.prevPage,
                  ),
                  IconButton(
                    onPressed: _offset + _rows.length >= _totalRows
                        ? null
                        : () => _reload(offset: _offset + _pageSize),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: DebugDbStrings.nextPage,
                  ),
                ],
              ),
            ),
            Expanded(child: _buildTable()),
          ],
        ],
      ),
    );
  }

  Widget _buildTable() {
    // Spreadsheet-style grid: sticky-feel header + scroll both axes.
    // Truncated cells keep layout cheap; tap a cell for the full value.
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _colWidth * _columns.length + 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                color: AppColors.navy.withValues(alpha: 0.92),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 48,
                      child: Center(
                        child: Text(
                          '#',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    for (final c in _columns)
                      SizedBox(
                        width: _colWidth,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            c,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Rows
              Expanded(
                child: ListView.builder(
                  itemCount: _rows.length,
                  itemExtent: 40,
                  itemBuilder: (context, i) {
                    final row = _rows[i];
                    final bg = i.isEven
                        ? Colors.white
                        : AppColors.navy.withValues(alpha: 0.04);
                    return Material(
                      color: bg,
                      child: InkWell(
                        onTap: () => _showFullRow(context, row),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 48,
                              child: Center(
                                child: Text(
                                  '${_offset + i + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.navy,
                                  ),
                                ),
                              ),
                            ),
                            for (final c in _columns)
                              SizedBox(
                                width: _colWidth,
                                child: InkWell(
                                  onTap: () => _showCell(
                                    context,
                                    c,
                                    row[c],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 10,
                                    ),
                                    child: Text(
                                      _cellText(row[c]),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCell(
    BuildContext context,
    String column,
    Object? value,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(column, style: const TextStyle(fontFamily: 'monospace')),
        content: SingleChildScrollView(
          child: SelectableText(
            value?.toString() ?? 'null',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(DebugDbStrings.close),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullRow(
    BuildContext context,
    Map<String, Object?> row,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.tableName,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in row.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${e.key}\n',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        TextSpan(
                          text: e.value?.toString() ?? 'null',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(DebugDbStrings.close),
          ),
        ],
      ),
    );
  }
}

