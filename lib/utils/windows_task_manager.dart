import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'task_operation_result.dart';

class WindowsTaskManager {
  static const String taskName = 'HYPRReady_Boot_Diagnostic';
  static const String configFileName = 'hyprready.json';

  /// Checks if the task is currently installed.
  static Future<bool> isTaskInstalled() async {
    if (!Platform.isWindows) return false;

    try {
      final result = await Process.run('powershell', [
        '-Command',
        'Get-ScheduledTask -TaskName "$taskName" -ErrorAction SilentlyContinue',
      ]);
      // If exit code is 0 and stdout is not empty, it exists.
      // If it doesn't exist, Get-ScheduledTask usually throws or returns nothing with error action.
      // Actually with SilentlyContinue, it might just return nothing.
      // But typically if it finds it, exit code 0. If not found, it might still be 0 but empty output or non-zero depending on ps version?
      // Better check: if output contains the task name.

      return result.exitCode == 0 &&
          result.stdout.toString().contains(taskName);
    } catch (e) {
      print('Failed to check task status: $e');
      return false;
    }
  }

  /// Registers the Windows Scheduled Task using parsed arguments.
  static Future<TaskOperationResult> registerTaskFromArgs(
    List<String> args,
  ) async {
    String logPath = r'C:\Temp\hyprready.log';
    String sslUrl = 'https://show.gethypr.com';
    int delaySeconds = 5;
    String? certTemplate;
    String? adcsServer;

    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--log-file' && i + 1 < args.length) {
        logPath = args[i + 1];
      } else if (arg == '--ssl-url' && i + 1 < args.length) {
        sslUrl = args[i + 1];
      } else if (arg == '--boot-delay' && i + 1 < args.length) {
        delaySeconds = int.tryParse(args[i + 1]) ?? 5;
      } else if (arg == '--cert-template' && i + 1 < args.length) {
        certTemplate = args[i + 1];
      } else if (arg == '--adcs-server' && i + 1 < args.length) {
        adcsServer = args[i + 1];
      }
    }

    return register(
      logPath: logPath,
      sslUrl: sslUrl,
      delaySeconds: delaySeconds,
      certTemplate: certTemplate,
      adcsServer: adcsServer,
    );
  }

  /// Registers the Windows Scheduled Task.
  static Future<TaskOperationResult> register({
    required String logPath,
    required String sslUrl,
    required int delaySeconds,
    String? certTemplate,
    String? adcsServer,
  }) async {
    if (!Platform.isWindows) {
      return TaskOperationResult.failure(
        'Windows Task Scheduler is only supported on Windows.',
      );
    }

    try {
      print('Starting Task Registration...');

      // 2. Create/Update Config File
      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);
      final configPath = p.join(exeDir, configFileName);

      final Map<String, dynamic> config = {
        'targetUrl': sslUrl,
        if (adcsServer != null) 'adcsServer': adcsServer,
        if (certTemplate != null) 'certTemplate': certTemplate,
      };

      final File configFile = File(configPath);
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );
      print('Configuration saved to: $configPath');

      // 3. Ensure Log Directory Exists
      final logDir = p.dirname(logPath);
      final dir = Directory(logDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 4. Register Task via PowerShell
      final arguments = '--headless --log-file "$logPath"';

      // PowerShell script to execute
      final psScript =
          '''
\$exePath = '${exePath.replaceAll("'", "''")}'
\$arguments = '$arguments'
\$taskName = '$taskName'
\$delaySeconds = $delaySeconds

\$action = New-ScheduledTaskAction -Execute \$exePath -Argument \$arguments
\$trigger = New-ScheduledTaskTrigger -AtStartup

if (\$delaySeconds -gt 0) {
    \$trigger.Delay = "PT\${delaySeconds}S"
}

\$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName \$taskName -Action \$action -Trigger \$trigger -Principal \$principal -Force
''';

      print('Executing PowerShell to register task...');
      final result = await Process.run('powershell', ['-Command', psScript]);

      if (result.exitCode == 0) {
        print(result.stdout);
        print('SUCCESS: Task "$taskName" registered successfully.');
        return TaskOperationResult.success(
          'Task "$taskName" registered successfully.',
        );
      } else {
        print('FAILURE: PowerShell returned exit code ${result.exitCode}');
        print('STDERR: ${result.stderr}');
        return TaskOperationResult.failure(
          'Failed to register task via PowerShell.',
          result.stderr,
        );
      }
    } catch (e) {
      print('EXCEPTION: Failed to register task: $e');
      return TaskOperationResult.failure(
        'Exception during task registration.',
        e.toString(),
      );
    }
  }

  /// Removes the Windows Scheduled Task.
  static Future<TaskOperationResult> removeTask() async {
    if (!Platform.isWindows) {
      return TaskOperationResult.failure(
        'Windows Task Scheduler is only supported on Windows.',
      );
    }

    try {
      print('Removing Task "$taskName"...');

      final result = await Process.run('powershell', [
        '-Command',
        'Unregister-ScheduledTask -TaskName "$taskName" -Confirm:\$false -ErrorAction Stop',
      ]);

      if (result.exitCode == 0) {
        print('SUCCESS: Task "$taskName" removed.');
        return TaskOperationResult.success('Task "$taskName" removed.');
      } else {
        // Check if error is simply that the task doesn't exist
        if (result.stderr.toString().contains(
          'No MSFT_ScheduledTask objects found',
        )) {
          print('Task "$taskName" was not found (nothing to remove).');
          return TaskOperationResult.success(
            'Task was not found (nothing to remove).',
          );
        }

        print('FAILURE: Failed to remove task.');
        print('STDERR: ${result.stderr}');
        return TaskOperationResult.failure(
          'Failed to remove task.',
          result.stderr,
        );
      }
    } catch (e) {
      print('EXCEPTION: Failed to remove task: $e');
      return TaskOperationResult.failure(
        'Exception during task removal.',
        e.toString(),
      );
    }
  }
}
