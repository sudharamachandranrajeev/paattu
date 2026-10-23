// A newer Paattu, found and installed from inside the app: the releases this
// project already publishes on GitHub — the same ones the README sends people
// to — so there's nothing extra to publish. Tag a version and the Release
// workflow builds the APK, the Windows installer and the Linux AppImage, with
// a SHA256SUMS.txt beside them.
//
// What is downloaded is checked against that SHA-256 before it is installed:
// installing a program is the one thing here worth being careful about, so a
// release that can't be checked isn't installed at all.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'log.dart';
import 'sources/http.dart' show browserAgent, httpClient;
import 'util.dart';

/// Where the app looks, and where it sends the person when it can't install.
const releaseApiUrl = 'https://api.github.com/repos/sudharamachandranrajeev/paattu/releases/latest';
const releasePageUrl = 'https://github.com/sudharamachandranrajeev/paattu/releases';

/// The file the releases publish their checksums in.
const checksumsName = 'SHA256SUMS.txt';

/// Android's installer is handed over through this (MainActivity.kt).
const updateChannel = MethodChannel('dev.paattu.paattu/update');

/// One file of a release.
class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, {this.size = 0, this.digest = ''});

  final String name;
  final Uri url;
  final int size;

  /// GitHub's own checksum for it ("sha256:07412d…"), when it gave one.
  final String digest;

  /// The checksum without its "sha256:" in front, or empty.
  String get sha256 => digest.startsWith('sha256:') ? digest.substring(7) : '';
}

/// A published release, as far as this device cares.
class Release {
  const Release({required this.version, required this.assets, this.notes = '', this.page = ''});

  factory Release.fromJson(Json json) => Release(
        version: asString(json['tag_name']).replaceFirst(RegExp(r'^[vV]'), ''),
        notes: asString(json['body']),
        page: asString(json['html_url']),
        assets: {
          for (final raw in asList(json['assets']).map(asJson))
            asString(raw['name']): ReleaseAsset(
              asString(raw['name']),
              Uri.parse(asString(raw['browser_download_url'])),
              size: toInt(raw['size']) ?? 0,
              digest: asString(raw['digest']),
            ),
        },
      );

  final String version;
  final String notes;
  final String page;
  final Map<String, ReleaseAsset> assets;

  /// The file to install on this device, if the release has one for it.
  ReleaseAsset? installerFor(String os) {
    final suffix = installerSuffix(os);
    if (suffix == null) return null;
    for (final asset in assets.values) {
      if (asset.name.endsWith(suffix)) return asset;
    }
    return null;
  }

  /// The checksums file, when the release published one.
  ReleaseAsset? get checksums => assets[checksumsName];

  /// Kept in settings.json between runs, so the app can say what it found
  /// without asking GitHub again.
  Json toJson() => <String, dynamic>{
        'version': version,
        'notes': notes,
        'page': page,
        'assets': {
          for (final a in assets.values)
            a.name: <String, dynamic>{'url': a.url.toString(), 'size': a.size, 'digest': a.digest},
        },
      };

  factory Release.fromJsonKept(Json json) => Release(
        version: asString(json['version']),
        notes: asString(json['notes']),
        page: asString(json['page']),
        assets: {
          for (final entry in asJson(json['assets']).entries)
            entry.key: ReleaseAsset(
              entry.key,
              Uri.parse(asString(asJson(entry.value)['url'])),
              size: toInt(asJson(entry.value)['size']) ?? 0,
              digest: asString(asJson(entry.value)['digest']),
            ),
        },
      );
}

/// What the installer for [os] is called: 'android', 'windows' or 'linux'.
/// Null for one Paattu can't install for (a phone's other OS, the web).
String? installerSuffix(String os) => switch (os) {
      'android' => '-android.apk',
      'windows' => '-windows-x64-setup.exe',
      'linux' => '.AppImage',
      _ => null,
    };

/// The numbers of a version, "v0.7.10" → [0, 7, 10]. A part that isn't a
/// number counts as 0, and anything after a '-' (a pre-release) is dropped.
List<int> versionParts(String version) {
  final plain = version.trim().replaceFirst(RegExp(r'^[vV]'), '').split('-').first;
  return [for (final part in plain.split('.')) int.tryParse(part.trim()) ?? 0];
}

/// Whether [candidate] is newer than [current], part by part, so 0.10.0 beats
/// 0.9.9 the way a person reads it.
bool isNewerVersion(String candidate, String current) {
  final a = versionParts(candidate), b = versionParts(current);
  for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Where the updater has got to.
enum UpdateState { idle, checking, upToDate, available, downloading, ready, installing, failed }

class UpdateManager extends ChangeNotifier {
  UpdateManager({required this.currentVersion, required this.dir, this.os = ''});

  /// What this build says it is.
  final String currentVersion;

  /// Where downloads go.
  final Directory dir;

  /// The OS to pick an installer for (empty for the one it's running on).
  final String os;

  String get platform => os.isEmpty ? Platform.operatingSystem : os;

  UpdateState state = UpdateState.idle;

  /// The newer release found, when there is one.
  Release? available;

  /// What went wrong, in plain words.
  String problem = '';

  /// How much of the download has arrived, 0 to 1.
  double progress = 0;

  /// The checked file, once it's downloaded.
  File? downloaded;

  /// The newest release on GitHub, or null when it couldn't be read (no
  /// internet, or a repository that isn't public — GitHub answers 404 then).
  Future<Release?> latest() async {
    final response = await httpClient
        .get(Uri.parse(releaseApiUrl),
            headers: {'User-Agent': browserAgent, 'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      problemLog.warn('update: GitHub said ${response.statusCode} about the releases');
      return null;
    }
    final release = Release.fromJson(asJson(jsonDecode(utf8.decode(response.bodyBytes))));
    return release.version.isEmpty ? null : release;
  }

  /// Look for a newer version. [quiet] keeps an "up to date" or a failure to
  /// itself, for the check at start-up.
  Future<void> check({bool quiet = false}) async {
    state = UpdateState.checking;
    problem = '';
    notifyListeners();
    Release? release;
    try {
      release = await latest();
    } catch (error) {
      problem = errorText(error);
    }
    if (release == null) {
      state = UpdateState.failed;
      problem = problem.isEmpty ? "couldn't reach the releases" : problem;
      if (!quiet) problemLog.warn('update: $problem');
      notifyListeners();
      return;
    }
    if (!isNewerVersion(release.version, currentVersion)) {
      available = null;
      state = UpdateState.upToDate;
      notifyListeners();
      return;
    }
    if (release.installerFor(platform) == null) {
      state = UpdateState.failed;
      problem = 'the new version has no file for this device';
      notifyListeners();
      return;
    }
    available = release;
    state = UpdateState.available;
    problemLog.info('update: ${release.version} is out (this is $currentVersion)');
    notifyListeners();
  }

  /// Download the new version, check it, and install it.
  Future<bool> downloadAndInstall() async {
    final release = available;
    final asset = release?.installerFor(platform);
    if (release == null || asset == null) {
      state = UpdateState.failed;
      problem = 'nothing to install';
      notifyListeners();
      return false;
    }
    state = UpdateState.downloading;
    progress = 0;
    problem = '';
    notifyListeners();
    try {
      await dir.create(recursive: true);
      final target = File('${dir.path}${Platform.pathSeparator}${asset.name}');
      await _download(asset, target);
      await _verify(asset, release, target);
      downloaded = target;
      state = UpdateState.installing;
      notifyListeners();
      await install(target);
      return true;
    } catch (error) {
      state = UpdateState.failed;
      problem = errorText(error);
      problemLog.error('update: ${asset.name}', error);
      notifyListeners();
      return false;
    }
  }

  Future<void> _download(ReleaseAsset asset, File target) async {
    final request = await httpClient
        .send(http.Request('GET', asset.url)..headers['User-Agent'] = browserAgent)
        .timeout(const Duration(seconds: 30));
    if (request.statusCode != 200) {
      unawaited(request.stream.listen(null).cancel());
      throw SourceException('the download said ${request.statusCode}');
    }
    // The server may not say how big it is; the release's own size then.
    final said = request.contentLength ?? 0;
    final total = said > 0 ? said : asset.size;
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    var got = 0;
    try {
      await for (final bytes in request.stream.timeout(const Duration(seconds: 60))) {
        sink.add(bytes);
        got += bytes.length;
        if (total > 0) {
          final now = got / total;
          // Only tell the screen when it has actually moved.
          if ((now - progress) > 0.01 || got >= total) {
            progress = now.clamp(0.0, 1.0);
            notifyListeners();
          }
        }
      }
      await sink.close();
      await part.rename(target.path);
    } catch (error) {
      await sink.close().catchError((Object _) {});
      await part.delete().then((_) {}, onError: (Object _) {});
      rethrow;
    }
    if (got == 0) throw SourceException('the download sent nothing');
    problemLog.info('update: downloaded ${asset.name} (${got ~/ 1024} KB)');
  }

  /// Check the file against the SHA-256 the release publishes, so a broken or
  /// meddled-with download isn't installed. No checksum anywhere means no
  /// install: the person can get it from the releases page instead.
  Future<void> _verify(ReleaseAsset asset, Release release, File file) async {
    final expected = (await _publishedChecksums(release))[asset.name] ?? asset.sha256;
    if (expected.isEmpty) {
      await file.delete().then((_) {}, onError: (Object _) {});
      throw SourceException('the release published no checksum, so Paattu won\'t install it');
    }
    // The file is hashed as it is read, so a big APK isn't held in memory.
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual.toLowerCase() != expected.toLowerCase()) {
      await file.delete().then((_) {}, onError: (Object _) {});
      throw SourceException('the download didn\'t match its checksum');
    }
    problemLog.info('update: ${asset.name} checked ($actual)');
  }

  /// SHA256SUMS.txt as a map of file name to checksum.
  Future<Map<String, String>> _publishedChecksums(Release release) async {
    final sums = release.checksums;
    if (sums == null) return const {};
    try {
      final response = await httpClient
          .get(sums.url, headers: {'User-Agent': browserAgent})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return const {};
      return parseChecksums(utf8.decode(response.bodyBytes));
    } catch (error) {
      // The asset's own digest may still be there to check against.
      problemLog.warn('update: reading $checksumsName: ${errorText(error)}');
      return const {};
    }
  }

  /// Install [file] the way this device can. What it does differs a lot:
  /// a phone hands the APK to its installer, Windows runs the setup, and a
  /// Linux AppImage is replaced where it stands.
  Future<void> install(File file) async {
    switch (platform) {
      case 'android':
        await updateChannel.invokeMethod<bool>('installApk', {'path': file.path});
      case 'windows':
        // The installer closes the running app (CloseApplications) and offers
        // to start the new one when it's done.
        await Process.start(file.path, ['/CURRENTUSER', '/NORESTART'], mode: ProcessStartMode.detached);
        problemLog.info('update: the installer is running; Paattu is closing');
        exit(0);
      case 'linux':
        await _installLinux(file);
      default:
        throw SourceException("Paattu can't install its own update on $platform");
    }
  }

  /// An AppImage running replaces itself (a rename leaves the running one
  /// alone until it's opened again); anything else is left in Downloads with
  /// the person told where.
  Future<void> _installLinux(File file) async {
    final running = Platform.environment['APPIMAGE'];
    if (running == null || running.isEmpty) {
      final home = Platform.environment['HOME'] ?? '';
      final downloads = Directory('$home${Platform.pathSeparator}Downloads');
      final where = await downloads.exists() ? downloads : Directory(home);
      final target = File('${where.path}${Platform.pathSeparator}${file.uri.pathSegments.last}');
      await file.copy(target.path);
      await Process.run('chmod', ['+x', target.path]);
      state = UpdateState.ready;
      problem = 'Saved to ${target.path} — open it to use the new version';
      notifyListeners();
      return;
    }
    await Process.run('chmod', ['+x', file.path]);
    await file.rename(running);
    state = UpdateState.ready;
    problem = 'Open Paattu again to use the new version';
    notifyListeners();
  }
}

/// A SHA256SUMS.txt as a map: "07412d…  Paattu-0.7.1-android.apk" per line,
/// with either one or two spaces before the name and an optional "*" marker.
Map<String, String> parseChecksums(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+\*?'));
    if (parts.length < 2) continue;
    final sum = parts.first;
    final name = parts.last;
    if (sum.length != 64 || name.isEmpty) continue;
    out[name] = sum.toLowerCase();
  }
  return out;
}
