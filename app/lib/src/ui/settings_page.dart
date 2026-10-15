// Settings: theme, sound, where the music comes from, data saver, library
// import / export, the problem log, about.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../links.dart';
import '../log.dart';
import '../settings.dart';
import '../sources/jiosaavn.dart';
import '../util.dart';
import 'glass.dart';
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

  Future<void> _saveLog(AppState app) async {
    await attempt(app, () async {
      final stamp = nowStamp().replaceAll(':', '').replaceAll('-', '');
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save the problem log',
        fileName: 'paattu-log-$stamp.txt',
        bytes: Uint8List.fromList(utf8.encode(await problemLog.text())),
        mimeType: 'text/plain',
      );
      if (saved != null) app.toast('Saved the problem log');
    }, failure: "Couldn't save it");
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
              GlassGroup(children: [
                ListTile(
                  leading: Icon(Icons.equalizer, color: sound.on ? theme.colorScheme.primary : null),
                  title: const Text('Equaliser, tone and speed'),
                  subtitle: Text(sound.summary),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openSound(context),
                ),
              ]),
              const SectionHeader('Now Playing'),
              GlassGroup(children: [
                SwitchListTile(
                  title: const Text('Video in the background'),
                  subtitle: const Text("A blurred, silent bit of the song's video, kept in time with it "
                      '(about 1 MB a minute)'),
                  value: settings.videoBackground,
                  onChanged: (on) => settings.videoBackground = on,
                ),
              ]),
              const SectionHeader('Music from'),
              GlassGroup(children: [
                for (final source in [...searchSites, 'all'])
                  ListTile(
                    leading: Icon(
                      settings.musicFrom == source ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: settings.musicFrom == source ? theme.colorScheme.primary : null,
                    ),
                    title: Text(source == 'all' ? 'Every site' : siteName(source)),
                    subtitle: Text(switch (source) {
                      'youtube' => 'Nearly everything, Opus around 130–160 kbps',
                      'jiosaavn' => 'Film albums from the labels, mostly 320 kbps AAC',
                      'soundcloud' => 'Covers, remixes and independent artists',
                      _ => 'All three at once, each song once',
                    }),
                    onTap: () => settings.musicFrom = source,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text("A song that won't play is looked for on the other sites.",
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
              ]),
              const SectionHeader('Library'),
              GlassGroup(children: [
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
              ]),
              const SectionHeader('Problem log'),
              GlassGroup(children: [
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Save the problem log'),
                  subtitle: const Text('What Paattu tried and what went wrong: attach it to a bug report'),
                  onTap: () => _saveLog(app),
                ),
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy it'),
                  onTap: () => attempt(app, () async {
                    await Clipboard.setData(ClipboardData(text: await problemLog.text()));
                    app.toast('Copied the problem log');
                  }, failure: "Couldn't copy it"),
                ),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Read it'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _LogPage())),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Clear it'),
                  onTap: () async {
                    final ok = await confirm(context,
                        title: 'Clear the problem log?', body: 'It starts again empty.', action: 'Clear');
                    if (ok) await attempt(app, problemLog.clear, failure: "Couldn't clear it");
                  },
                ),
              ]),
              const SectionHeader('About'),
              GlassGroup(children: [
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
              ]),
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 108,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.background,
            borderRadius: BorderRadius.circular(18),
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

/// The problem log to read, newest at the bottom.
class _LogPage extends StatelessWidget {
  const _LogPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Problem log')),
      body: FutureBuilder<String>(
        future: problemLog.text(),
        builder: (context, snapshot) {
          final text = snapshot.data;
          if (text == null) return const Center(child: CircularProgressIndicator());
          if (text.trim().isEmpty) return const Center(child: Text('Nothing logged yet'));
          return SingleChildScrollView(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: SelectableText(text,
                style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.4)),
          );
        },
      ),
    );
  }
}
