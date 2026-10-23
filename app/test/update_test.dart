// The updater: comparing versions the way a person reads them, picking the
// right file for this device out of a release, reading the checksums the
// release publishes, and keeping the version in the source in step with
// pubspec.yaml (it once said 0.6.0 while the build was 0.7.1).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paattu/src/app_state.dart';
import 'package:paattu/src/update.dart';
import 'package:paattu/src/util.dart';

Json _release(String version, {List<Json> assets = const []}) => <String, dynamic>{
      'tag_name': 'v$version',
      'name': 'Paattu $version',
      'body': '- Something new\n- Something else',
      'html_url': 'https://github.com/sudharamachandranrajeev/paattu/releases/tag/v$version',
      'assets': assets,
    };

Json _asset(String name, {int size = 1000, String digest = ''}) => <String, dynamic>{
      'name': name,
      'browser_download_url':
          'https://github.com/sudharamachandranrajeev/paattu/releases/download/v0.8.0/$name',
      'size': size,
      if (digest.isNotEmpty) 'digest': digest,
    };

void main() {
  group('isNewerVersion', () {
    test('a bigger part wins', () {
      expect(isNewerVersion('0.7.2', '0.7.1'), isTrue);
      expect(isNewerVersion('0.8.0', '0.7.1'), isTrue);
      expect(isNewerVersion('1.0.0', '0.9.9'), isTrue);
    });

    test('ten beats nine, read as numbers not words', () {
      expect(isNewerVersion('0.10.0', '0.9.9'), isTrue);
      expect(isNewerVersion('0.9.9', '0.10.0'), isFalse);
    });

    test('the same version isn\'t newer', () {
      expect(isNewerVersion('0.7.1', '0.7.1'), isFalse);
      expect(isNewerVersion('v0.7.1', '0.7.1'), isFalse);
    });

    test('an older version isn\'t newer', () {
      expect(isNewerVersion('0.7.0', '0.7.1'), isFalse);
      expect(isNewerVersion('0.6.9', '0.7.0'), isFalse);
    });

    test('a leading v, a pre-release suffix and missing parts', () {
      expect(isNewerVersion('v0.8.0', '0.7.1'), isTrue);
      // The "-rc1" is dropped: it compares on the numbers.
      expect(isNewerVersion('0.8.0-rc1', '0.7.1'), isTrue);
      expect(isNewerVersion('0.8', '0.7.1'), isTrue);
      expect(isNewerVersion('0.7', '0.7.1'), isFalse);
      expect(isNewerVersion('1', '0.9.9'), isTrue);
    });

    test('something that isn\'t a number counts as 0', () {
      expect(isNewerVersion('0.x.1', '0.0.0'), isTrue);
      expect(isNewerVersion('', '0.7.1'), isFalse);
      expect(versionParts('v0.7.10-beta'), [0, 7, 10]);
    });
  });

  group('installerSuffix', () {
    test('the files the Release workflow builds', () {
      expect(installerSuffix('android'), '-android.apk');
      expect(installerSuffix('windows'), '-windows-x64-setup.exe');
      expect(installerSuffix('linux'), '.AppImage');
      expect(installerSuffix('macos'), isNull);
      expect(installerSuffix('fuchsia'), isNull);
    });
  });

  group('Release', () {
    test('read from GitHub\'s answer', () {
      final release = Release.fromJson(_release('0.8.0', assets: [
        _asset('Paattu-0.8.0-android.apk', size: 63232185),
        _asset('Paattu-0.8.0-windows-x64-setup.exe', size: 34709447),
        _asset('Paattu-0.8.0-linux-x86_64.AppImage', size: 110086648),
        _asset('Paattu-0.8.0-linux-x64.tar.gz', size: 24996376),
        _asset(checksumsName, size: 493),
      ]));
      expect(release.version, '0.8.0');
      expect(release.notes, contains('Something new'));
      expect(release.page, endsWith('/tag/v0.8.0'));
      expect(release.installerFor('android')?.name, 'Paattu-0.8.0-android.apk');
      expect(release.installerFor('android')?.size, 63232185);
      expect(release.installerFor('windows')?.name, 'Paattu-0.8.0-windows-x64-setup.exe');
      // The AppImage, not the tarball.
      expect(release.installerFor('linux')?.name, 'Paattu-0.8.0-linux-x86_64.AppImage');
      expect(release.installerFor('macos'), isNull);
      expect(release.checksums?.name, checksumsName);
    });

    test('a release with no file for this device', () {
      final release = Release.fromJson(_release('0.8.0', assets: [_asset('Paattu-0.8.0-android.apk')]));
      expect(release.installerFor('windows'), isNull);
      expect(release.checksums, isNull);
    });

    test('a release with no assets at all', () {
      final release = Release.fromJson(_release('0.8.0'));
      expect(release.version, '0.8.0');
      expect(release.assets, isEmpty);
      expect(release.installerFor('android'), isNull);
    });

    test('GitHub\'s own digest is usable as a checksum', () {
      final release = Release.fromJson(
          _release('0.8.0', assets: [_asset('Paattu-0.8.0-android.apk', digest: 'sha256:07412D12')]));
      expect(release.installerFor('android')?.sha256, '07412D12');
    });

    test('an asset with no digest has no checksum of its own', () {
      final release = Release.fromJson(_release('0.8.0', assets: [_asset('Paattu-0.8.0-android.apk')]));
      expect(release.installerFor('android')?.sha256, '');
    });

    test('kept in settings.json between runs', () {
      final release = Release.fromJson(_release('0.8.0', assets: [
        _asset('Paattu-0.8.0-android.apk', size: 63232185, digest: 'sha256:abc123'),
        _asset(checksumsName, size: 493),
      ]));
      // Through JSON, as settings.json writes and reads it.
      final back = Release.fromJsonKept(jsonDecode(jsonEncode(release.toJson())) as Map<String, dynamic>);
      expect(back.version, '0.8.0');
      expect(back.notes, release.notes);
      expect(back.page, release.page);
      expect(back.installerFor('android')?.name, 'Paattu-0.8.0-android.apk');
      expect(back.installerFor('android')?.size, 63232185);
      expect(back.installerFor('android')?.sha256, 'abc123');
      expect(back.checksums?.name, checksumsName);
    });

    test('an empty settings entry reads back as an empty release', () {
      final back = Release.fromJsonKept(<String, dynamic>{});
      expect(back.version, '');
      expect(back.assets, isEmpty);
      expect(back.installerFor('android'), isNull);
    });
  });

  group('parseChecksums', () {
    test('a SHA256SUMS.txt as the Release workflow writes it', () {
      const text = '''
07412d1275e3428aa28ce995a9ca23f481165235fbd625959bb4f0cafabcb18d  Paattu-0.7.1-android.apk
e0375d7da54d6023e8a14472a3bf4a98ec6693aab9100f17e3122f73460dc18b  Paattu-0.7.1-windows-x64-setup.exe
''';
      final sums = parseChecksums(text);
      expect(sums.length, 2);
      expect(sums['Paattu-0.7.1-android.apk'], startsWith('07412d12'));
      expect(sums['Paattu-0.7.1-windows-x64-setup.exe'], startsWith('e0375d7d'));
    });

    test('one space, two spaces, a binary marker, and upper case', () {
      // Real SHA-256s are 64 hex characters; parseChecksums insists on that.
      final one = 'a' * 64;
      final two = 'B' * 64;
      final three = '0123456789abcdef' * 4;
      final sums = parseChecksums('$one one.apk\n'
          '$two *two.apk\n'
          '   $three   three.apk   \n');
      expect(sums['one.apk'], one);
      expect(sums['two.apk'], two.toLowerCase());
      expect(sums['three.apk'], three);
    });

    test('a line that isn\'t a checksum is passed over', () {
      final sums = parseChecksums('not a sum at all\n'
          '${'x' * 63}  short.apk\n'
          '${'y' * 65}  long.apk\n'
          '${'z' * 64}  \n'
          '\n');
      expect(sums, isEmpty);
    });

    test('nothing to read', () {
      expect(parseChecksums(''), isEmpty);
    });
  });

  test('the version in the source is pubspec.yaml\'s', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec)?.group(1);
    expect(version, isNotNull, reason: 'pubspec.yaml should say what version it is');
    expect(sourceVersion, version,
        reason: 'app_state.dart\'s sourceVersion has gone stale; it is what the app says it is '
            'until package_info_plus answers, and what the updater compares against in a test');
  });

  test('the app starts out saying the source version', () {
    expect(appVersion, sourceVersion);
  });

  group('newestRelease', () {
    test('pre-releases count, drafts and untagged ones don\'t', () {
      final list = [
        {'tag_name': 'v0.8.1', 'prerelease': true, 'assets': []},
        {'tag_name': 'v0.9.0', 'draft': true, 'assets': []},
        {'tag_name': '', 'assets': []},
        {'tag_name': 'v0.8.0', 'prerelease': true, 'assets': []},
      ];
      expect(newestRelease(list)?.version, '0.8.1');
    });
    test('newest by version, not by list order', () {
      expect(newestRelease([{'tag_name': 'v0.7.1'}, {'tag_name': 'v0.10.0'}, {'tag_name': 'v0.9.2'}])?.version, '0.10.0');
    });
    test('nothing to read', () {
      expect(newestRelease([]), isNull);
      expect(newestRelease({'message': 'Not Found'}), isNull);
      expect(newestRelease(null), isNull);
    });
  });
}
