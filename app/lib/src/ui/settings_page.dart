// Settings: theme, sound, search sites, data saver, library import / export,
// about.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../links.dart';
import '../settings.dart';
import '../sources/jiosaavn.dart';
import '../util.dart';
import 'sound_page.dart';
import 'widgets.dart';

/// The desktop Paattu's library on this machine (Linux only).
File? desktopLibrary() {
  if (!Platform.isLinux) return null;
  final home = Platform.environment['HOME'];
  final data = Platform.environment['XDG_DATA_HOME'];
  final base = data != null && data.isNotEmpty ? data : (home == null ? null : '$home/.local/share');
  if (base == null) return null;
  final file = File('$base/paattu/library.json');
  return file.existsSync() ? file : null;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _export(BuildContext context, AppState app) async {
    await attempt(app, () async {
      final bytes = Uint8List.fromList(utf8.encode(app.library.export()));
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Export the library',
        fileName: 'paattu-library.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (saved != null) app.toast('Exported the library');
    }, failure: "Couldn't export");
  }

  Future<void> _importBytes(BuildContext context, AppState app, Uint8List bytes, String from) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    final incoming = asJson(decoded);
    final playlists = asJson(incoming['playlists']).length;
    final users = asJson(incoming['users']).length;
    if (!context.mounted) return;
    final ok = await confirm(context,
        title: 'Replace the library?',
        body: '$from has ${plural(playlists, 'playlist')} and ${plural(users, 'profile')}. '
            "It replaces what's in the app now (export first to keep a copy).",
        action: 'Replace');
    if (!ok) return;
    app.library.replaceWith(decoded);
    app.toast('Imported the library');
  }

  Future<void> _import(BuildContext context, AppState app) async {
    await attempt(app, () async {
      final file = await FilePicker.pickFile(dialogTitle: 'Import a Paattu library', type: FileType.any);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      await _importBytes(context, app, bytes, file.name);
    }, failure: "Couldn't import");
  }

  @override
  Widget build(BuildContext context) => LibraryBuilder(builder: (context, app) {
        final settings = app.settings;
        final theme = Theme.of(context);
        final desktop = desktopLibrary();
        final sound = settings.sound;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SectionHeader('Theme'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in themes)
                      _ThemeSwatch(theme: t, selected: settings.theme.id == t.id, onTap: () => settings.themeId = t.id),
                  ],
                ),
              ),
              const SectionHeader('Sound'),
              ListTile(
                leading: Icon(Icons.equalizer, color: sound.on ? theme.colorScheme.primary : null),
                title: const Text('Equaliser, tone and speed'),
                subtitle: Text(sound.summary),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openSound(context),
              ),
              const SectionHeader('Search'),
              for (final site in searchSites)
                CheckboxListTile(
                  title: Text(siteName(site)),
                  subtitle: Text(switch (site) {
                    'jiosaavn' => 'Film albums from the labels, mostly 320 kbps AAC',
                    'youtube' => 'Nearly everything, Opus around 130–160 kbps',
                    _ => 'Covers, remixes and independent artists',
                  }),
                  value: settings.searchSites.contains(site),
                  onChanged: (on) {
                    final next = List.of(settings.searchSites);
                    if (on == true) {
                      next.add(site);
                    } else if (next.length > 1) {
                      next.remove(site);
                    }
                    settings.searchSites = [for (final s in searchSites) if (next.contains(s)) s];
                  },
                ),
              SwitchListTile(
                title: const Text('Save data'),
                subtitle: const Text('Stream JioSaavn songs at 128 kbps instead of 320'),
                value: settings.saveData,
                onChanged: (on) {
                  settings.saveData = on;
                  jiosaavnSaveData = on;
                },
              ),
              const SectionHeader('Library'),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Export the library'),
                subtitle: const Text('A library.json the desktop Paattu and other devices can import'),
                onTap: () => _export(context, app),
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Import a library'),
                subtitle: const Text("From the desktop Paattu (~/.local/share/paattu/library.json) or another device"),
                onTap: () => _import(context, app),
              ),
              if (desktop != null)
                ListTile(
                  leading: const Icon(Icons.computer),
                  title: const Text('Use the desktop Paattu library'),
                  subtitle: Text(desktop.path),
                  onTap: () => attempt(app, () async {
                    final bytes = await desktop.readAsBytes();
                    if (!context.mounted) return;
                    await _importBytes(context, app, bytes, 'The desktop library');
                  }, failure: "Couldn't import"),
                ),
              const SectionHeader('About'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Paattu $appVersion'),
                subtitle: Text('Malayalam & Tamil music from YouTube, JioSaavn and SoundCloud. MIT licence.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('Source code and releases'),
                subtitle: const Text(repoUrl),
                onTap: () => fire(launchUrl(Uri.parse(repoUrl), mode: LaunchMode.externalApplication)),
              ),
            ],
          ),
        );
      });
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme, required this.selected, required this.onTap});
  final PaattuTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: theme.description,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 108,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final c in [theme.accent, theme.highlight, theme.surface])
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: theme.muted.withValues(alpha: 0.4))),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(theme.name, style: TextStyle(color: theme.foreground, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
