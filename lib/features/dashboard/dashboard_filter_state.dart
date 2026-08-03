import 'package:flutter/foundation.dart';

import '../../core/widgets/patient_filter_panel.dart';

/// User-selected Dashboard filter state (village chip, need-category chips,
/// search query).
///
/// Provided above the router (see `main.dart`) rather than owned by
/// `DashboardScreen` itself. The visit-flow route is deliberately a
/// root-level `GoRoute` (see `router.dart`), so navigating into it and back
/// via `context.go(...)` destroys and recreates `DashboardScreen` — any
/// filter state kept as local `State` fields was silently reset on every
/// round trip. Living here, above that boundary, it survives.
class DashboardFilterState extends ChangeNotifier {
  String? _selectedVillageChipName;
  Set<NeedFilter> _selectedNeeds = const {};
  String _searchQuery = '';

  String? get selectedVillageChipName => _selectedVillageChipName;
  Set<NeedFilter> get selectedNeeds => _selectedNeeds;
  String get searchQuery => _searchQuery;

  void setVillage(String? name) {
    _selectedVillageChipName = name;
    notifyListeners();
  }

  void setNeeds(Set<NeedFilter> needs) {
    _selectedNeeds = needs;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clear() {
    _selectedVillageChipName = null;
    _selectedNeeds = const {};
    _searchQuery = '';
    notifyListeners();
  }
}
