import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'checks/check.dart';
import 'checks/check_registry.dart';
import 'config/app_config.dart';
import 'utils/logger.dart';

class HeadlessRunner {
  static Future<void> run(List<String> args) async {
    // 1. Initialize Config
    await AppConfig().init();

    // 2. Determine Log Location
    // Default to a temporary file or specific log location
    // args might contain --log-file <path>
    // args might contain --log-file <path> or --log-file=<path>
    String? logPath;
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--log-file' && i + 1 < args.length) {
        logPath = args[i + 1];
        break;
      } else if (arg.startsWith('--log-file=')) {
        logPath = arg.substring('--log-file='.length);
        if (logPath.startsWith('"') && logPath.endsWith('"')) {
          logPath = logPath.substring(1, logPath.length - 1);
        }
        break;
      }
    }

    if (logPath == null) {
      final temp = await getTemporaryDirectory();
      final separator = Platform.pathSeparator;
      logPath = '${temp.path}${separator}hyprready_headless.log';
    }

    final File logFile = File(logPath);
    // Create parent if needed
    if (!await logFile.parent.exists()) {
      try {
        await logFile.parent.create(recursive: true);
      } catch (e) {
        log.e('Failed to create log directory: $e');
        // Fallback to local
        logPath = 'hyprready_headless_fallback.log';
      }
    }

    final buffer = StringBuffer();
    void customLog(String message) {
      final msg = '[${DateTime.now()}] $message';
      log.i(msg);
      buffer.writeln(msg);
    }

    customLog('Starting Headless Check...');
    customLog('Arguments: $args');
    customLog('Target URL: ${AppConfig().targetUrl}');
    if (AppConfig().adcsServer != null) {
      customLog('ADCS Configured: ${AppConfig().adcsServer}');
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

      log.i('Running Check: ${check.title}...');
      try {
        final result = await check.execute(); // No context
        switch (result.status) {
          case CheckStatus.pass:
            customLog('PASS: ${check.title} - ${result.message}');
            passCount++;
            break;
          case CheckStatus.fail:
            customLog('FAIL: ${check.title} - ${result.message}');
            failCount++;
            break;
          case CheckStatus.warning:
            customLog('WARN: ${check.title} - ${result.message}');
            warnCount++;
            break;
          case CheckStatus.manual:
            customLog('SKIP/MANUAL: ${check.title} - ${result.message}');
            break;
        }
      } catch (e) {
        customLog('ERROR: ${check.title} threw exception: $e');
        failCount++;
      }
    }

    customLog('--------------------------------------------------');
    customLog('Summary: PASS=$passCount, FAIL=$failCount, WARN=$warnCount');
    customLog('Headless Check Complete.');

    // 4. Write Log
    try {
      await logFile.writeAsString(buffer.toString(), mode: FileMode.append);
      log.i('Log written to: $logPath');
    } catch (e) {
      log.e('Failed to write log file: $e');
      log.e('Log Content:\n$buffer');
    }

    exit(failCount > 0 ? 1 : 0);
  }
}
