import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_colors.dart';

/// The installed app's version, as stores and support desks write it:
/// "1.4.2 (27)". The first part is `version:` in pubspec.yaml before the "+"
/// (what Play shows people); the number in brackets is the build number
/// after it (Play's versionCode, one higher on every upload). Both are set by
/// tool/release.sh, never by hand.
class AppVersion {
  const AppVersion(this.name, this.build);

  final String name;
  final String build;

  /// "1.4.2 (27)", "1.4.2 (27) · debug" on a developer build, or just the
  /// name when there is no build number.
  String get label {
    final base = build.isEmpty ? name : '$name ($build)';
    return kReleaseMode ? base : '$base · debug';
  }

  static Future<AppVersion>? _loaded;

  /// Read once per run; the version can't change while the app is open.
  static Future<AppVersion> load() => _loaded ??= PackageInfo.fromPlatform().then(
    (info) => AppVersion(info.version, info.buildNumber),
  );
}

/// "Version 1.4.2 (27)" in small muted type, for the foot of a menu.
class AppVersionText extends StatelessWidget {
  const AppVersionText({super.key, this.prefix = 'Version '});

  final String prefix;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppVersion>(
      future: AppVersion.load(),
      builder: (context, snapshot) => Text(
        snapshot.hasData ? '$prefix${snapshot.data!.label}' : '',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
      ),
    );
  }
}
