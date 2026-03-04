import 'dart:io';

void main() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found.');
    exit(1);
  }

  final content = pubspecFile.readAsStringSync();
  final versionMatch = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+).*',
    multiLine: true,
  ).firstMatch(content);

  if (versionMatch == null) {
    stderr.writeln('Error: Could not find version in pubspec.yaml.');
    exit(1);
  }

  final majorVersion = int.parse(versionMatch.group(1)!);
  final currentYearLastTwoDigits = int.parse(
    DateTime.now().year.toString().substring(2),
  );

  if (majorVersion != currentYearLastTwoDigits) {
    stderr.writeln(
      'Error: Major version ($majorVersion) does not match the last two digits of the current year ($currentYearLastTwoDigits).',
    );
    exit(1);
  }

  stdout.writeln(
    'Success: Version $majorVersion.x.x matches year 20$currentYearLastTwoDigits.',
  );
}
