/// x.y.z version. Build numbers and suffixes are ignored, unparsable parts
/// count as 0.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  factory AppVersion.parse(String value) {
    final parts = value.trim().split(RegExp(r'[+\-\s]')).first.split('.');
    int at(int i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0;
    return AppVersion(at(0), at(1), at(2));
  }

  static const zero = AppVersion(0, 0, 0);

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

enum UpdateRequirement { none, optional, force }

/// Update rules for the current platform, from Remote Config.
class UpdatePolicy {
  const UpdatePolicy({
    required this.minVersion,
    required this.latestVersion,
    required this.storeUrl,
    this.message = '',
  });

  static const none = UpdatePolicy(minVersion: AppVersion.zero, latestVersion: AppVersion.zero, storeUrl: '');

  /// Older versions must update before using the app.
  final AppVersion minVersion;

  /// Older versions are offered an update once per release.
  final AppVersion latestVersion;
  final String storeUrl;

  /// Dialog body; empty uses the built-in text.
  final String message;

  /// Never blocks or nags a user who has no store link to follow: a missing
  /// link is a configuration mistake and must not lock people out of the app.
  UpdateRequirement evaluate(AppVersion current) {
    if (storeUrl.isEmpty) return UpdateRequirement.none;
    if (current < minVersion) return UpdateRequirement.force;
    if (current < latestVersion) return UpdateRequirement.optional;
    return UpdateRequirement.none;
  }
}
