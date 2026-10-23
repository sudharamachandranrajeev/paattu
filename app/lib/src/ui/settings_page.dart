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
import '../offline.dart';
import '../settings.dart';
import '../sources/jiosaavn.dart';
import '../update.dart';
import '../util.dart';
import 'glass.dart';
import 'offline_page.dart';
import 'sound_page.dart';
import 'widgets.dart';

/// The top of the "space allowed" slider, in MB (32 GB).
const _limitSliderMax = 32 * 1024.0;

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

  /// Where the kept songs go (not Android: it keeps an app's folder to itself).
  Future<void> _pickFolder(AppState app) async {
    await attempt(app, () async {
      final picked = await FilePicker.getDirectoryPath(dialogTitle: 'Where to keep songs');
      if (picked == null || picked.isEmpty) return;
      app.settings.offlineDir = picked;
      app.toast('Keeping songs in $picked');
    }, failure: "Couldn't use that folder");
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
              const SectionHeader('Playback'),
              GlassGroup(children: [
                ListTile(
                  leading: const Icon(Icons.compare_arrows),
                  title: const Text('Crossfade'),
                  subtitle: Text(settings.crossfade == 0
                      ? 'Off: each song starts as the last one ends'
                      : 'Each song fades into the next over ${plural(settings.crossfade, 'second')}'),
                ),
                Slider(
                  value: settings.crossfade.toDouble(),
                  max: 12,
                  divisions: 12,
                  label: settings.crossfade == 0 ? 'Off' : '${settings.crossfade} s',
                  onChanged: (v) => settings.crossfade = v.round(),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.radio),
                  title: const Text('Auto radio'),
                  subtitle: const Text('When the songs you picked run out, carry on with songs like them'),
                  value: settings.autoRadio,
                  onChanged: (on) => settings.autoRadio = on,
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Forget what I played'),
                  subtitle: const Text('The play history the daily, weekly and monthly playlists are made from'),
                  onTap: () async {
                    if (await confirm(context,
                        title: 'Forget the play history?',
                        body: 'The playlists made for you start again from your favourites.',
                        action: 'Forget')) {
                      app.history.clear();
                      app.toast('Forgot the play history');
                    }
                  },
                ),
              ]),
              const SectionHeader('Now Playing'),
              GlassGroup(children: [
                for (final style in NowPlayingStyle.values)
                  ListTile(
                    leading: Icon(
                      settings.nowPlayingStyle == style ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: settings.nowPlayingStyle == style ? theme.colorScheme.primary : null,
                    ),
                    title: Text(style == NowPlayingStyle.cover ? '${style.label} (the usual)' : style.label),
                    subtitle: Text(style.description),
                    trailing: Icon(switch (style) {
                      NowPlayingStyle.cover => Icons.crop_original,
                      NowPlayingStyle.video => Icons.movie_outlined,
                      NowPlayingStyle.full => Icons.panorama_outlined,
                      NowPlayingStyle.record => Icons.album_outlined,
                    }),
                    onTap: () => settings.nowPlayingStyle = style,
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.view_in_ar_outlined),
                  title: const Text('Cover in 3D'),
                  subtitle: Text("Lifts what's in the picture out of it, tilting as you "
                      '${Platform.isAndroid ? 'move the phone' : 'move the pointer over it'} '
                      '(the Cover and Video first looks)'),
                  value: settings.coverDepth,
                  onChanged: (on) => settings.coverDepth = on,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('Colours from the cover'),
                  subtitle: const Text("Now Playing and the bar at the bottom take their colours from the song's cover"),
                  value: settings.coverColors,
                  onChanged: (on) => settings.coverColors = on,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.movie_filter_outlined),
                  title: const Text('Video in the background'),
                  subtitle: const Text("A silent bit of the song's video, kept in time with it "
                      '(about 1 MB a minute)'),
                  value: settings.videoBackground,
                  onChanged: (on) => settings.videoBackground = on,
                ),
                ListTile(
                  enabled: settings.videoBackground,
                  leading: const Icon(Icons.blur_on),
                  title: const Text('Video blur'),
                  subtitle: Text(switch (settings.videoBlur) {
                    0 => 'None: the video is sharp',
                    < 25 => 'A little (${settings.videoBlur})',
                    < 60 => 'Soft (${settings.videoBlur})',
                    _ => 'Heavy (${settings.videoBlur})',
                  }),
                ),
                Slider(
                  value: settings.videoBlur.toDouble(),
                  max: 100,
                  divisions: 20,
                  label: '${settings.videoBlur}',
                  onChanged: settings.videoBackground ? (v) => settings.videoBlur = v.round() : null,
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
                  subtitle: const Text("Stream JioSaavn songs at 128 kbps instead of 320, and don't download the next songs ahead"),
                  value: settings.saveData,
                  onChanged: (on) {
                    settings.saveData = on;
                    jiosaavnSaveData = on;
                  },
                ),
              ]),
              const SectionHeader('On this device'),
              GlassGroup(children: [
                ListenableBuilder(
                  listenable: app.offline,
                  builder: (context, _) => ListTile(
                    leading: const Icon(Icons.download_for_offline_outlined),
                    title: const Text('Songs kept offline'),
                    subtitle: Text(app.offline.count == 0
                        ? 'Nothing kept yet'
                        : '${plural(app.offline.count, 'song')} · '
                            '${formatBytes(app.offline.totalBytes)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const OfflinePage())),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.save_alt),
                  title: const Text('Keep the songs you listen to'),
                  subtitle: const Text('A song you play properly is kept, so it plays with no internet '
                      'and no data next time'),
                  value: settings.offlineAutoSave,
                  onChanged: (on) => settings.offlineAutoSave = on,
                ),
                ListTile(
                  enabled: !Platform.isAndroid,
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Folder'),
                  subtitle: Text(Platform.isAndroid
                      ? "${app.offline.path}\nAndroid keeps an app's folder to itself"
                      : app.offline.path),
                  trailing: Platform.isAndroid ? null : const Icon(Icons.chevron_right),
                  onTap: Platform.isAndroid ? null : () => _pickFolder(app),
                ),
                if (settings.offlineDir.isNotEmpty && !Platform.isAndroid)
                  ListTile(
                    leading: const Icon(Icons.folder_off_outlined),
                    title: const Text("Use the app's own folder"),
                    onTap: () {
                      settings.offlineDir = '';
                      app.toast('Keeping songs in the app\'s own folder');
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.sd_storage_outlined),
                  title: const Text('Space allowed'),
                  subtitle: Text(settings.offlineLimitMb == 0
                      ? 'No limit: songs are kept until you take them off'
                      : '${formatBytes(settings.offlineLimitMb << 20)} · the songs played least recently go first'),
                ),
                Slider(
                  value: settings.offlineLimitMb.toDouble().clamp(0, _limitSliderMax),
                  max: _limitSliderMax,
                  divisions: _limitSliderMax ~/ 512,
                  label: settings.offlineLimitMb == 0
                      ? 'No limit'
                      : formatBytes(settings.offlineLimitMb << 20),
                  onChanged: (v) => settings.offlineLimitMb = (v.round() ~/ 512) * 512,
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
                  title: Text('Paattu $appVersion'),
                  subtitle: Text('Malayalam & Tamil music from YouTube, JioSaavn and SoundCloud. MIT licence.',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ),
                _UpdateTile(app: app),
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

/// Looking for a newer Paattu, and installing it when there is one.
class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final updates = app.updates;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final release = updates.available;
        final version = release?.version ?? '';
        final busy = updates.state == UpdateState.downloading ||
            updates.state == UpdateState.installing ||
            updates.state == UpdateState.checking;
        final asset = release?.installerFor(updates.platform);
        final (title, subtitle) = switch (updates.state) {
          UpdateState.checking => ('Looking for a newer version…', ''),
          UpdateState.upToDate => ('Paattu $appVersion is the newest', ''),
          UpdateState.available => (
              'Update to $version',
              [
                if (asset != null && asset.size > 0) formatBytes(asset.size),
                'From the releases on GitHub',
              ].join(' · ')
            ),
          UpdateState.downloading => ('Downloading $version…', '${(updates.progress * 100).round()}%'),
          UpdateState.installing => ('Installing $version…', ''),
          UpdateState.ready => ('$version is ready', updates.problem),
          UpdateState.failed => ('Check for updates', updates.problem),
          UpdateState.idle => ('Check for updates', 'From the releases on GitHub'),
        };
        final found = updates.state == UpdateState.available || updates.state == UpdateState.ready;
        return ListTile(
          leading: Icon(
            switch (updates.state) {
              UpdateState.available || UpdateState.ready => Icons.system_update,
              UpdateState.failed => Icons.error_outline,
              _ => Icons.update,
            },
            color: found ? scheme.primary : null,
          ),
          title: Text(title),
          subtitle: subtitle.isEmpty ? null : Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
          trailing: busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onTap: busy ? null : () => _tap(context),
        );
      },
    );
  }

  /// Ask GitHub, and offer what it finds.
  Future<void> _tap(BuildContext context) async {
    final updates = app.updates;
    if (updates.state == UpdateState.available && updates.available != null) {
      await _offer(context, updates.available!);
      return;
    }
    await updates.check();
    switch (updates.state) {
      case UpdateState.upToDate:
        app.toast('Paattu $appVersion is the newest');
      case UpdateState.available:
        if (context.mounted) await _offer(context, updates.available!);
      default:
        app.toast(updates.problem.isEmpty ? "Couldn't look for a newer version" : updates.problem);
    }
  }

  /// What's new, and whether to download and install it.
  Future<void> _offer(BuildContext context, Release release) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Paattu ${release.version}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: SelectableText(
              release.notes.trim().isEmpty ? 'A newer version of Paattu.' : release.notes.trim(),
              style: Theme.of(dialog).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Download and install')),
        ],
      ),
    );
    if (go != true) return;
    await app.updates.downloadAndInstall();
    if (!context.mounted) return;
    // Windows closes the app so the installer can replace it, and a phone hands
    // the APK to its own installer: neither comes back here. Linux says what
    // to do next.
    switch (app.updates.state) {
      case UpdateState.ready:
      case UpdateState.failed:
        final reason = app.updates.problem;
        app.toast(app.updates.state == UpdateState.ready
            ? reason
            : '${reason.isEmpty ? "Couldn't install it" : reason}. Get it from the releases page');
      default:
        break;
    }
  }
}
