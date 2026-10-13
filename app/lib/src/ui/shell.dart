// The frame around the pages: navigation (a bar on phones, a rail on wide
// screens), one navigator per tab, and the mini player.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'now_playing.dart';
import 'search_page.dart';
import 'settings_page.dart';

class PaattuApp extends StatefulWidget {
  const PaattuApp({super.key, required this.state});
  final AppState state;

  @override
  State<PaattuApp> createState() => _PaattuAppState();
}

class _PaattuAppState extends State<PaattuApp> {
  StreamSubscription<String>? _messages;

  @override
  void initState() {
    super.initState();
    _messages = widget.state.player.messages.stream.listen(widget.state.toast);
  }

  @override
  void dispose() {
    _messages?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Paattu(
        state: widget.state,
        child: ListenableBuilder(
          listenable: widget.state.settings,
          builder: (context, _) => MaterialApp(
            title: 'Paattu',
            debugShowCheckedModeBanner: false,
            theme: widget.state.settings.theme.data,
            scaffoldMessengerKey: widget.state.messenger,
            navigatorKey: widget.state.navigator,
            home: const Shell(),
          ),
        ),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  final _navigators = List.generate(4, (_) => GlobalKey<NavigatorState>());
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _select(int tab) {
    if (tab == _tab) {
      // Tapping the open tab goes back to its first page.
      _navigators[tab].currentState?.popUntil((route) => route.isFirst);
    }
    setState(() => _tab = tab);
    if (tab == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
    }
  }

  Widget _tabNavigator(int i, Widget page) => Navigator(
        key: _navigators[i],
        onGenerateRoute: (settings) => MaterialPageRoute<void>(builder: (_) => page, settings: settings),
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final pages = [
      HomePage(onSearch: () => _select(1), onSettings: wide ? null : () => _select(3)),
      SearchPage(focus: _searchFocus),
      const LibraryPage(),
      const SettingsPage(),
    ];
    const destinations = [
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.search, Icons.saved_search, 'Search'),
      (Icons.library_music_outlined, Icons.library_music, 'Library'),
      (Icons.settings_outlined, Icons.settings, 'Settings'),
    ];
    final body = IndexedStack(
      index: _tab,
      children: [for (var i = 0; i < pages.length; i++) _tabNavigator(i, pages[i])],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final navigator = _navigators[_tab].currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        } else if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        body: wide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Image.asset('assets/icon.png', width: 40, height: 40),
                    ),
                    destinations: [
                      for (final (icon, selected, label) in destinations)
                        NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              )
            : body,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            if (!wide)
              NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: _select,
                height: 64,
                destinations: [
                  for (final (icon, selected, label) in destinations)
                    NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
