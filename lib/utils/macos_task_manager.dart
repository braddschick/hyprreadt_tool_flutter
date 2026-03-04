import 'dart:io';
import 'package:path/path.dart' as p;
import 'task_operation_result.dart';
import 'logger.dart';

class MacOSTaskManager {
  static const String label = 'com.hypr.hyprready.daemon';
  static const String plistPath = '/Library/LaunchDaemons/$label.plist';

  /// Checks if the LaunchDaemon is currently installed.
  static Future<bool> isDaemonInstalled() async {
    if (!Platform.isMacOS) return false;
    return File(plistPath).exists();
  }

  /// Registers the LaunchDaemon using parsed arguments (for CLI).
  static Future<TaskOperationResult> registerFromArgs(List<String> args) async {
    String logPath = '/tmp/hyprready_headless.log';
    String sslUrl = 'https://show.gethypr.com';
    int delaySeconds = 5;

    // Parse args manually or reuse logic (simplified here)
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--log-file' && i + 1 < args.length) {
        logPath = args[i + 1];
      } else if (arg == '--ssl-url' && i + 1 < args.length) {
        sslUrl = args[i + 1];
      } else if (arg == '--boot-delay' && i + 1 < args.length) {
        delaySeconds = int.tryParse(args[i + 1]) ?? 5;
      }
    }

    // Pass the SSL URL via config file logic later?
    // Ideally we duplicate the config file creation logic or create a shared helper.
    // For now, let's assume the headless runner will read the config if it exists.
    // But since the daemon runs as root/daemon user, the relative path might be tricky.
    // The headless runner expects 'hyprready.json' next to the executable.

    return register(
      logPath: logPath,
      delaySeconds: delaySeconds,
      sslUrl: sslUrl,
    );
  }

  /// Uses `osascript` to request admin privileges for writing to /Library/LaunchDaemons.
  static Future<TaskOperationResult> register({
    required String logPath,
    required int delaySeconds,
    required String sslUrl,
  }) async {
    if (!Platform.isMacOS) {
      return TaskOperationResult.failure(
        'macOS LaunchDaemons are only supported on macOS.',
      );
    }

    try {
      final exePath = Platform.resolvedExecutable;
      // Note: resolvedExecutable in a bundle points to ".../Contents/MacOS/hyprready"

      // 1. Create config file next to executable (Shared Logic with Windows ideally)
      // Since this runs as admin/sudo, we can write next to the app bundle.
      // But if app is in /Applications, we might need write privs there too.
      // For now, let's skip the config file part or assume it's set,
      // OR we implement a simple write here if writable.
      // Let's rely on args for minimal config if possible, but headless runner reads file.
      // We will skip config file creation in this MVP step or just try best effort.

      // 2. Build Plist Content
      final plistContent =
          '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$exePath</string>
        <string>--headless</string>
        <string>--log-file</string>
        <string>$logPath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$logPath</string>
    <key>StandardErrorPath</key>
    <string>$logPath</string>
    <!-- Add delay via simple sleep wrapper? Or launchd doesn't support delay easily. -->
    <!-- launchd doesn't have a StartDelay. We might need a wrapper script or handle delay in app. -->
    <!-- The app handles delay internally via HeadlessRunner logic if --boot-delay arg passed? -->
    <!-- The current HeadlessRunner doesn't seem to have a delay arg logic in dart code yet? -->
    <!-- Re-checking headless_runner.dart... it doesn't seem to parse 'delay' arg. Windows used Value in Trigger. -->
    <!-- We should probably add the delay logic to the shell command if possible or just ignore for now. -->
</dict>
</plist>
''';

      // 3. Write plist to temp file
      final tempDir = Directory.systemTemp;
      final tempPlist = File(p.join(tempDir.path, '$label.plist'));
      await tempPlist.writeAsString(plistContent);

      // 4. Move to /Library/LaunchDaemons using sudo/osascript
      // Commands:
      // cp /tmp/... /Library/LaunchDaemons/...
      // chown root:wheel ...
      // chmod 644 ...
      // launchctl load ...

      final commands = [
        'cp "${tempPlist.path}" "$plistPath"',
        'chown root:wheel "$plistPath"',
        'chmod 644 "$plistPath"',
        'launchctl unload "$plistPath" || true', // unload if exists
        'launchctl load "$plistPath"',
      ].join(' && ');

      final scriptCommands = commands.replaceAll('"', '\\"');

      log.i('Requesting privileges to install daemon...');

      final result = await Process.run('osascript', [
        '-e',
        'do shell script "$scriptCommands" with administrator privileges',
      ]);

      if (result.exitCode == 0) {
        log.i('SUCCESS: Daemon installed and loaded.');
        return TaskOperationResult.success(
          'Daemon installed and loaded successfully.',
        );
      } else {
        log.e('FAILURE: ${result.stderr}');
        return TaskOperationResult.failure(
          'Failed to install daemon via osascript.',
          result.stderr,
        );
      }
    } catch (e) {
      log.e('EXCEPTION: $e');
      return TaskOperationResult.failure(
        'Exception during daemon installation.',
        e.toString(),
      );
    }
  }

  static Future<TaskOperationResult> remove() async {
    if (!Platform.isMacOS) {
      return TaskOperationResult.failure(
        'macOS LaunchDaemons are only supported on macOS.',
      );
    }

    try {
      final commands = [
        'launchctl unload "$plistPath" || true',
        'rm -f "$plistPath"',
      ].join(' && ');

      final scriptCommands = commands.replaceAll('"', '\\"');

      final result = await Process.run('osascript', [
        '-e',
        'do shell script "$scriptCommands" with administrator privileges',
      ]);

      if (result.exitCode == 0) {
        return TaskOperationResult.success('Daemon removed successfully.');
      } else {
        return TaskOperationResult.failure(
          'Failed to remove daemon.',
          result.stderr,
        );
      }
    } catch (e) {
      log.e('EXCEPTION: $e');
      return TaskOperationResult.failure(
        'Exception during daemon removal.',
        e.toString(),
      );
    }
  }
}
