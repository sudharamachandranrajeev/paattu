// The frame around the pages: navigation (a floating glass bar on phones, a
// rail on wide screens, both with a big + for making things), one navigator
// per tab, and the mini player.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'glass.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'mix_editor.dart';
import 'now_playing.dart';
import 'playlist_page.dart';
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

  /// The + button: a mix, a playlist, something from YouTube, a search.
  Future<void> _create() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (id, icon, title, detail) in const [
              ('mix', Icons.shuffle, 'New mix', 'Shuffle songs from the playlists and profiles you pick'),
              ('playlist', Icons.playlist_add, 'New playlist', 'Your own list of songs'),
              ('youtube', Icons.add_link, 'Add from YouTube', 'A profile (@handle) or a playlist link'),
              ('search', Icons.search, 'Search songs', 'JioSaavn and YouTube'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(title),
                subtitle: Text(detail),
                onTap: () => Navigator.pop(sheet, id),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'mix':
        await editMix(context, null);
      case 'playlist':
        final id = await newPlaylist(context);
        if (id == null || !mounted) return;
        _select(2);
        fire(_navigators[2].currentState!.push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlistId: id))));
      case 'youtube':
        await showAddFromYouTube(context);
      case 'search':
        _select(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final pages = [
      HomePage(onSearch: () => _select(1), onSettings: wide ? null : () => _select(3)),
      SearchPage(focus: _searchFocus),
      const LibraryPage(),
      const SettingsPage(),
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
                  _Rail(selected: _tab, onSelect: _select, onCreate: _create),
                  Expanded(child: body),
                ],
              )
            : body,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            if (!wide) _NavBar(selected: _tab, onSelect: _select, onCreate: _create),
          ],
        ),
      ),
    );
  }
}

const _destinations = [
  (Icons.home_outlined, Icons.home_rounded, 'Home'),
  (Icons.search, Icons.search, 'Search'),
  (Icons.library_music_outlined, Icons.library_music, 'Library'),
  (Icons.settings_outlined, Icons.settings, 'Settings'),
];

/// Phones: a glass bar floating at the bottom, the + in the middle.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.selected, required this.onSelect, required this.onCreate});
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (var i = 0; i < _destinations.length; i++)
        _NavItem(destination: _destinations[i], selected: i == selected, onTap: () => onSelect(i)),
    ];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Glass(
        blur: true,
        radius: 30,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [...items.take(2), _CreateButton(onPressed: onCreate), ...items.skip(2)],
          ),
        ),
      ),
    );
  }
}

/// Wide screens: the same, standing up at the left.
class _Rail extends StatelessWidget {
  const _Rail({required this.selected, required this.onSelect, required this.onCreate});
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => SafeArea(
        right: false,
        minimum: const EdgeInsets.fromLTRB(12, 12, 0, 12),
        child: Glass(
          radius: 30,
          child: SizedBox(
            width: 76,
            // Shrunk to fit a phone on its side.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Image.asset('assets/icon.png', width: 40, height: 40),
                  const SizedBox(height: 20),
                  _CreateButton(onPressed: onCreate),
                  const SizedBox(height: 20),
                  for (var i = 0; i < _destinations.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _NavItem(destination: _destinations[i], selected: i == selected, onTap: () => onSelect(i)),
                    ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      );
}

/// A tab: its icon in a rounded square, outlined in the highlight when open.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.onTap});
  final (IconData, IconData, String) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, selectedIcon, label) = destination;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 30,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: selected ? scheme.secondary.withValues(alpha: 0.12) : Colors.transparent,
              border: Border.all(color: selected ? scheme.secondary : Colors.transparent, width: 1.6),
            ),
            child: Icon(selected ? selectedIcon : icon, color: selected ? scheme.onSurface : scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// The big glowing +.
class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'New mix, playlist…',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: 'Make a mix or playlist, or add from YouTube',
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: tileColours(scheme, 0),
              ),
              boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: 1)],
            ),
            child: const Icon(Icons.add, size: 30, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
