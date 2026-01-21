import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'checks/check.dart';
import 'checks/check_registry.dart';
import 'config/app_config.dart';

class HeadlessRunner {
  static Future<void> run(List<String> args) async {
    // 1. Initialize Config
    await AppConfig().init();

    // 2. Determine Log Location
    // Default to a temporary file or specific log location
    // args might contain --log-file <path>
    String? logPath;
    for (int i = 0; i < args.length; i++) {
      if (args[i] == '--log-file' && i + 1 < args.length) {
        logPath = args[i + 1];
        break;
      }
    }

    if (logPath == null) {
      if (Platform.isMacOS || Platform.isLinux) {
        logPath = '/tmp/hyprready_headless.log';
      } else if (Platform.isWindows) {
        logPath = 'C:\\ProgramData\\HyprReady\\headless.log';
        // Note: Writing to ProgramData might require admin rights usually.
        // Fallback to temp if we can't write?
        // For now let's use temp dir as safe default if not specified
        final temp = await getTemporaryDirectory();
        logPath = '${temp.path}\\hyprready_headless.log';
      } else {
        logPath = 'hyprready_headless.log';
      }
    }

    final File logFile = File(logPath);
    // Create parent if needed
    if (!await logFile.parent.exists()) {
      try {
        await logFile.parent.create(recursive: true);
      } catch (e) {
        print('Failed to create log directory: $e');
        // Fallback to local
        logPath = 'hyprready_headless_fallback.log';
      }
    }

    final buffer = StringBuffer();
    void log(String message) {
      final msg = '[${DateTime.now()}] $message';
      print(msg);
      buffer.writeln(msg);
    }

    log('Starting Headless Check...');
    log('Arguments: $args');
    log('Target URL: ${AppConfig().targetUrl}');
    if (AppConfig().adcsServer != null) {
      log('ADCS Configured: ${AppConfig().adcsServer}');
    }

    // 3. Run Checks
    final checks = CheckRegistry().checks;
    int passCount = 0;
    int failCount = 0;
    int warnCount = 0;

    for (var check in checks) {
      if (!check.appliesToOS(Platform.operatingSystem)) {
        continue;
      }

      log('Running Check: ${check.title}...');
      try {
        final result = await check.execute(); // No context
        switch (result.status) {
          case CheckStatus.pass:
            log('PASS: ${check.title}');
            passCount++;
            break;
          case CheckStatus.fail:
            log('FAIL: ${check.title} - ${result.message}');
            failCount++;
            break;
          case CheckStatus.warning:
            log('WARN: ${check.title} - ${result.message}');
            warnCount++;
            break;
          case CheckStatus.manual:
            log('SKIP/MANUAL: ${check.title} - ${result.message}');
            break;
        }
      } catch (e) {
        log('ERROR: ${check.title} threw exception: $e');
        failCount++;
      }
    }

    log('--------------------------------------------------');
    log('Summary: PASS=$passCount, FAIL=$failCount, WARN=$warnCount');
    log('Headless Check Complete.');

    // 4. Write Log
    try {
      await logFile.writeAsString(buffer.toString(), mode: FileMode.append);
      print('Log written to: $logPath');
    } catch (e) {
      print('Failed to write log file: $e');
      print('Log Content:\n$buffer');
    }

    exit(failCount > 0 ? 1 : 0);
  }
}
