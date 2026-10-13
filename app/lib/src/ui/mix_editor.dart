// Make or change a mix: its name and what it shuffles (languages, followed
// profiles, playlists).

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../library.dart';
import '../util.dart';

Future<void> editMix(BuildContext context, String? mixId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MixEditor(mixId: mixId), fullscreenDialog: true));

class MixEditor extends StatefulWidget {
  const MixEditor({super.key, this.mixId});
  final String? mixId;

  @override
  State<MixEditor> createState() => _MixEditorState();
}

class _MixEditorState extends State<MixEditor> {
  final _name = TextEditingController();
  final _picked = <String>{}; // "type:id"
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    final mix = widget.mixId == null ? null : Paattu.of(context).library.findMix(widget.mixId!);
    if (mix != null) {
      _name.text = asString(mix['title']);
      for (final s in asList(mix['sources']).map(asJson)) {
        _picked.add('${s['type']}:${s['id']}');
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final app = Paattu.of(context);
    final sources = [
      for (final key in _picked)
        <String, dynamic>{'type': key.substring(0, key.indexOf(':')), 'id': key.substring(key.indexOf(':') + 1)},
    ];
    try {
      if (widget.mixId == null) {
        app.library.createMix(_name.text, sources);
      } else {
        final mix = app.library.getMix(widget.mixId!);
        if (_name.text.trim() != asString(mix['title'])) app.library.renameMix(widget.mixId!, _name.text);
        app.library.setMixSources(widget.mixId!, sources);
      }
      app.library.changed();
      Navigator.pop(context);
    } on LibraryException catch (error) {
      app.toast(error.message);
    }
  }

  Widget _check(String type, String id, String title, {String? subtitle}) {
    final key = '$type:$id';
    return CheckboxListTile(
      value: _picked.contains(key),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle),
      onChanged: (on) => setState(() => on == true ? _picked.add(key) : _picked.remove(key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = Paattu.of(context).library;
    final languages = {'Malayalam', 'Tamil', ...library.languages()}.toList();
    final users = library.sortedUsers();
    final playlists = [
      ...library.ownPlaylists().where((p) => asList(p['tracks']).isNotEmpty),
      for (final lang in library.languages()) ...library.shelves()[lang] ?? const <Json>[],
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mixId == null ? 'New mix' : 'Edit mix'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              autofocus: widget.mixId == null,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Evening melodies'),
            ),
          ),
          const _Heading('Languages', 'Every saved playlist in the language'),
          for (final lang in languages) _check('language', lang, lang),
          if (users.isNotEmpty) ...[
            const _Heading('Profiles', "The profile's saved playlists"),
            for (final u in users) _check('user', asString(u['id']), asString(u['name'])),
          ],
          if (playlists.isNotEmpty) ...[
            const _Heading('Playlists', null),
            for (final p in playlists)
              _check('playlist', asString(p['id']), asString(p['title']),
                  subtitle: asString(p['ownerName']).isEmpty ? null : asString(p['ownerName'])),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.detail);
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          if (detail != null)
            Text(detail!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
