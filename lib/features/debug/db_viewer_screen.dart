import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _tableFilterCtrl = TextEditingController();
  String _tableFilter = '';
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

  @override
  void dispose() {
    _tableFilterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTables() async {
    setState(() {
      _loading = true;
      _error = null;
      _tables.clear();
    });

    try {
      final db = context.read<AppDatabase>().db;
      final names = <String>{
        ...AppDatabase.allTablesForTesting,
        AppDatabase.tableTelemetryEvents,
      }.toList()
        ..sort();

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

  List<_TableInfo> get _filteredTables {
    final q = _tableFilter.trim().toLowerCase();
    if (q.isEmpty) return _tables;
    return _tables.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredTables;
    final knownCounts =
        visible.where((t) => t.rowCount != null && t.rowCount! >= 0);
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
                              visible.length,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    controller: _tableFilterCtrl,
                    decoration: InputDecoration(
                      hintText: DebugDbStrings.filterTablesHint,
                      prefixIcon: const Icon(Icons.filter_list),
                      suffixIcon: _tableFilter.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _tableFilterCtrl.clear();
                                setState(() => _tableFilter = '');
                              },
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _tableFilter = v),
                  ),
                ),
                if (_loading && _tables.isEmpty)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (visible.isEmpty)
                  Expanded(
                    child: Center(child: Text(DebugDbStrings.noTablesMatch)),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final t = visible[i];
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
  static const double _colWidth = 140;

  final _searchCtrl = TextEditingController();
  List<String> _columns = const [];
  Set<String> _searchScope = {};
  Set<String> _visibleColumns = {};
  List<Map<String, Object?>> _rows = const [];
  int _totalRows = 0;
  int _filteredTotal = 0;
  int _offset = 0;
  int _pageSize = 20;
  String _query = '';
  String? _sortColumn;
  bool _sortAsc = true;
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

      if (_searchScope.isEmpty) {
        _searchScope = _defaultSearchColumns(columns).toSet();
      }
      if (_visibleColumns.isEmpty) {
        _visibleColumns = columns.toSet();
      } else {
        _visibleColumns = _visibleColumns.where(columns.contains).toSet();
        if (_visibleColumns.isEmpty) _visibleColumns = columns.toSet();
      }

      final total = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table'),
          ) ??
          0;

      final filter = _parseSearch(_query, columns, _searchScope);
      final where = filter?.whereClause;
      final whereArgs = filter?.whereArgs ?? const <Object?>[];

      var filteredTotal = total;
      if (where != null) {
        filteredTotal = Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM $table WHERE $where',
                whereArgs,
              ),
            ) ??
            0;
      }

      final safeSort = _sortColumn != null && columns.contains(_sortColumn!)
          ? _sortColumn
          : null;

      List<Map<String, Object?>> rows;
      if (where == null) {
        rows = await db.query(
          table,
          limit: _pageSize,
          offset: _offset,
          orderBy: safeSort != null
              ? '$safeSort ${_sortAsc ? 'ASC' : 'DESC'}'
              : null,
        );
      } else {
        rows = await db.query(
          table,
          where: where,
          whereArgs: whereArgs,
          limit: _pageSize,
          offset: _offset,
          orderBy: safeSort != null
              ? '$safeSort ${_sortAsc ? 'ASC' : 'DESC'}'
              : null,
        );
      }

      if (!mounted) return;
      setState(() {
        _columns = columns;
        _rows = rows;
        _totalRows = total;
        _filteredTotal = filteredTotal;
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

  List<String> _defaultSearchColumns(List<String> columns) {
    const preferred = [
      'id',
      'patient_id',
      'member_id',
      'household_id',
      'reference_id',
      'fhir_id',
      'name',
      'patient_name',
      'status',
      'sync_status',
      'phone',
      'phone_number',
      'national_id',
    ];
    final ordered = <String>[];
    for (final p in preferred) {
      if (columns.contains(p)) ordered.add(p);
    }
    for (final c in columns) {
      if (!ordered.contains(c)) ordered.add(c);
      if (ordered.length >= 10) break;
    }
    return ordered;
  }

  void _reload({int? offset}) {
    if (offset != null) _offset = offset;
    _loadPage();
  }

  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAsc = !_sortAsc;
      } else {
        _sortColumn = column;
        _sortAsc = true;
      }
    });
    _reload(offset: 0);
  }

  List<String> get _displayColumns =>
      _columns.where(_visibleColumns.contains).toList();

  int get _pageTotal =>
      _query.trim().isEmpty ? _totalRows : _filteredTotal;

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
            icon: const Icon(Icons.view_column_outlined),
            tooltip: DebugDbStrings.columns,
            onPressed: _loading ? null : _showColumnPicker,
          ),
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: DebugDbStrings.searchHintAdvanced,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.tune, size: 16),
                  label: Text(DebugDbStrings.searchScope(_searchScope.length)),
                  onPressed: _loading ? null : _showSearchScopePicker,
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _pageSize,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 20, child: Text('20')),
                    DropdownMenuItem(value: 50, child: Text('50')),
                    DropdownMenuItem(value: 100, child: Text('100')),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() => _pageSize = v);
                          _reload(offset: 0);
                        },
                ),
                const Spacer(),
                if (_sortColumn != null)
                  Text(
                    DebugDbStrings.sortedBy(_sortColumn!, _sortAsc),
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
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
            Expanded(
              child: Center(
                child: Text(
                  _query.trim().isEmpty
                      ? DebugDbStrings.emptyTable
                      : DebugDbStrings.noRowsMatch,
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _query.trim().isEmpty
                          ? DebugDbStrings.pageLabel(
                              _offset + 1,
                              _offset + _rows.length,
                              _pageTotal,
                            )
                          : DebugDbStrings.pageLabelFiltered(
                              _offset + 1,
                              _offset + _rows.length,
                              _filteredTotal,
                              _totalRows,
                            ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    DebugDbStrings.columnCount(_displayColumns.length),
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  IconButton(
                    onPressed: _offset <= 0
                        ? null
                        : () => _reload(
                              offset: (_offset - _pageSize)
                                  .clamp(0, _pageTotal),
                            ),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: DebugDbStrings.prevPage,
                  ),
                  IconButton(
                    onPressed: _offset + _rows.length >= _pageTotal
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
    final cols = _displayColumns;
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _colWidth * cols.length + 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    for (final c in cols)
                      SizedBox(
                        width: _colWidth,
                        child: InkWell(
                          onTap: () => _toggleSort(c),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              children: [
                                Expanded(
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
                                if (_sortColumn == c)
                                  Icon(
                                    _sortAsc
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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
                            for (final c in cols)
                              SizedBox(
                                width: _colWidth,
                                child: InkWell(
                                  onTap: () => _showCell(context, c, row[c]),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 10,
                                    ),
                                    child: _CellText(
                                      text: _cellText(row[c]),
                                      highlight: _query.trim(),
                                      isJson: _looksLikeJson(row[c]),
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

  String _cellText(Object? value) {
    if (value == null) return '';
    final pretty = _tryPrettyJson(value, compact: true);
    final s = (pretty ?? value.toString()).replaceAll('\n', ' ');
    if (s.length <= 48) return s;
    return '${s.substring(0, 45)}…';
  }

  Future<void> _showSearchScopePicker() async {
    final selected = Set<String>.from(_searchScope);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      DebugDbStrings.searchScopeTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DebugDbStrings.searchScopeHelp,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in _columns)
                          FilterChip(
                            label: Text(c, style: const TextStyle(fontSize: 11)),
                            selected: selected.contains(c),
                            onSelected: (on) {
                              setModalState(() {
                                if (on) {
                                  selected.add(c);
                                } else {
                                  selected.remove(c);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(DebugDbStrings.close),
                        ),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _searchScope = selected.isEmpty
                                  ? _defaultSearchColumns(_columns).toSet()
                                  : selected;
                            });
                            Navigator.pop(ctx);
                            _reload(offset: 0);
                          },
                          child: Text(DebugDbStrings.apply),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showColumnPicker() async {
    final visible = Set<String>.from(_visibleColumns);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      DebugDbStrings.visibleColumnsTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in _columns)
                          FilterChip(
                            label: Text(c, style: const TextStyle(fontSize: 11)),
                            selected: visible.contains(c),
                            onSelected: (on) {
                              setModalState(() {
                                if (on) {
                                  visible.add(c);
                                } else if (visible.length > 1) {
                                  visible.remove(c);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setModalState(() => visible.addAll(_columns));
                          },
                          child: Text(DebugDbStrings.selectAll),
                        ),
                        FilledButton(
                          onPressed: () {
                            setState(() => _visibleColumns = visible);
                            Navigator.pop(ctx);
                          },
                          child: Text(DebugDbStrings.apply),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCell(
    BuildContext context,
    String column,
    Object? value,
  ) async {
    final raw = value?.toString() ?? 'null';
    final pretty = _tryPrettyJson(value);
    final isJson = pretty != null;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _ValueDetailDialog(
        title: column,
        raw: raw,
        pretty: pretty,
        isJson: isJson,
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
                _RowFieldTile(keyName: e.key, value: e.value),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(DebugDbStrings.copyRow),
            onPressed: () {
              final buf = StringBuffer();
              for (final e in row.entries) {
                buf.writeln('${e.key}: ${e.value}');
              }
              Clipboard.setData(ClipboardData(text: buf.toString()));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(DebugDbStrings.copied)),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(DebugDbStrings.close),
          ),
        ],
      ),
    );
  }
}

class _CellText extends StatelessWidget {
  const _CellText({
    required this.text,
    required this.highlight,
    required this.isJson,
  });

  final String text;
  final String highlight;
  final bool isJson;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontFamily: 'monospace',
      color: isJson ? AppColors.aiPurple : null,
      fontWeight: isJson ? FontWeight.w600 : null,
    );

    final q = highlight.trim().toLowerCase();
    if (q.isEmpty || !text.toLowerCase().contains(q)) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: TextStyle(
          backgroundColor: Colors.amber.withValues(alpha: 0.45),
        ),
      ));
      start = idx + q.length;
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: style, children: spans),
    );
  }
}

class _RowFieldTile extends StatelessWidget {
  const _RowFieldTile({required this.keyName, required this.value});

  final String keyName;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final raw = value?.toString() ?? 'null';
    final pretty = _tryPrettyJson(value);
    final isJson = pretty != null;

    if (!isJson) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SelectableText.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$keyName\n',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              TextSpan(
                text: raw,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          keyName,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        subtitle: Text(
          DebugDbStrings.jsonField,
          style: TextStyle(fontSize: 10, color: AppColors.aiPurple),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              pretty,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 14),
              label: Text(DebugDbStrings.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pretty));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(DebugDbStrings.copied)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueDetailDialog extends StatefulWidget {
  const _ValueDetailDialog({
    required this.title,
    required this.raw,
    required this.pretty,
    required this.isJson,
  });

  final String title;
  final String raw;
  final String? pretty;
  final bool isJson;

  @override
  State<_ValueDetailDialog> createState() => _ValueDetailDialogState();
}

class _ValueDetailDialogState extends State<_ValueDetailDialog> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final display = widget.isJson && _tab == 1 ? widget.pretty! : widget.raw;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          if (widget.isJson)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.aiPurple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'JSON',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.aiPurple,
                ),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isJson)
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(DebugDbStrings.rawTab)),
                  ButtonSegment(value: 1, label: Text(DebugDbStrings.prettyTab)),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            if (widget.isJson) const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  display,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: Text(DebugDbStrings.copy),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: display));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(DebugDbStrings.copied)),
            );
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(DebugDbStrings.close),
        ),
      ],
    );
  }
}

class _SearchFilter {
  const _SearchFilter({required this.whereClause, required this.whereArgs});
  final String whereClause;
  final List<Object?> whereArgs;
}

_SearchFilter? _parseSearch(
  String raw,
  List<String> columns,
  Set<String> scope,
) {
  final q = raw.trim();
  if (q.isEmpty) return null;

  final exact = RegExp(r'^([\w]+)\s*=\s*(.+)$').firstMatch(q);
  if (exact != null) {
    final col = exact.group(1)!;
    if (columns.contains(col)) {
      return _SearchFilter(
        whereClause: '$col = ?',
        whereArgs: [exact.group(2)!.trim()],
      );
    }
  }

  final columnLike = RegExp(r'^([\w]+)\s*[:~]\s*(.+)$').firstMatch(q);
  if (columnLike != null) {
    final col = columnLike.group(1)!;
    if (columns.contains(col)) {
      return _SearchFilter(
        whereClause: 'CAST($col AS TEXT) LIKE ?',
        whereArgs: ['%${columnLike.group(2)!.trim()}%'],
      );
    }
  }

  final cols = scope.where(columns.contains).toList();
  if (cols.isEmpty) return null;

  final like = '%$q%';
  return _SearchFilter(
    whereClause: cols.map((c) => 'CAST($c AS TEXT) LIKE ?').join(' OR '),
    whereArgs: List<Object?>.filled(cols.length, like),
  );
}

bool _looksLikeJson(Object? value) {
  if (value == null) return false;
  final s = value is String ? value : value.toString();
  final t = s.trim();
  return (t.startsWith('{') && t.endsWith('}')) ||
      (t.startsWith('[') && t.endsWith(']'));
}

String? _tryPrettyJson(Object? value, {bool compact = false}) {
  if (value == null) return null;
  final s = value is String ? value : value.toString();
  if (!_looksLikeJson(s)) return null;
  try {
    final decoded = jsonDecode(s.trim());
    if (compact) {
      return const JsonEncoder().convert(decoded);
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } catch (_) {
    return null;
  }
}
