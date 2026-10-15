// One kind of result (songs, albums, artists or playlists) for one search,
// from every chosen site at once (or, when none of them has that kind, every
// site that does), growing a page at a time as it's scrolled.

import 'package:flutter/foundation.dart';

import 'sources/sources.dart';
import 'util.dart';

class SearchFeed extends ChangeNotifier {
  SearchFeed(this.query, this.kind, List<String> sites) : pagers = _pagers(query, kind, sites);

  static List<SitePager> _pagers(String query, String kind, List<String> sites) {
    final having = kindSites[kind] ?? const <String>[];
    final chosen = having.where(sites.contains).toList();
    return [for (final site in chosen.isEmpty ? having : chosen) SitePager(site, kind, query)];
  }

  final String query;
  final String kind;
  final List<SitePager> pagers;
  final items = <Json>[];
  final _seen = <String>{};
  bool loading = false;
  bool _disposed = false;

  bool get done => pagers.every((p) => p.done);

  /// The sites whose first page failed, and why.
  Map<String, String> get errors => {
        for (final p in pagers)
          if (p.error != null) p.site: p.error!,
      };

  /// Fetch the next page from each site that has more.
  Future<void> more() async {
    if (_disposed || loading || done) return;
    loading = true;
    _notify();
    final pages = await Future.wait([
      for (final p in pagers) p.done ? Future.value(const <Json>[]) : p.next(),
    ]);
    if (_disposed) return;
    items.addAll(interleave(pages, _seen));
    loading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
