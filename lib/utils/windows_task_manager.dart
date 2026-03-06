import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'task_operation_result.dart';
import 'logger.dart';

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
      log.e('Failed to check task status: $e');
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
      log.i('Starting Task Registration...');

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
      log.i('Configuration saved to: $configPath');

      // 3. Ensure Log Directory Exists
      final logDir = p.dirname(logPath);
      final dir = Directory(logDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 4. Register Task via PowerShell
      final arguments = '--headless --log-file "\$logPath"';

      // PowerShell script to execute (using parameters instead of interpolation for safety)
      final tempDir = Directory.systemTemp;
      final psScriptPath = p.join(
        tempDir.path,
        'hypr_task_install_\${DateTime.now().millisecondsSinceEpoch}.ps1',
      );
      final psScriptFile = File(psScriptPath);

      final psScript = r'''
param (
    [Parameter(Mandatory=$true)][string]$ExePath,
    [Parameter(Mandatory=$true)][string]$LogFile,
    [string]$TaskName,
    [int]$DelaySeconds
)

$arguments = "--headless --log-file `"$LogFile`""

$action = New-ScheduledTaskAction -Execute $ExePath -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtStartup

if ($DelaySeconds -gt 0) {
    $trigger.Delay = "PT${DelaySeconds}S"
}

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force
''';

      await psScriptFile.writeAsString(psScript);

      log.i('Executing PowerShell to register task...');
      final result = await Process.run('powershell', [
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        psScriptPath,
        '-ExePath',
        exePath,
        '-LogFile',
        logPath,
        '-TaskName',
        taskName,
        '-DelaySeconds',
        delaySeconds.toString(),
      ]);

      // Cleanup temp script
      try {
        if (await psScriptFile.exists()) await psScriptFile.delete();
      } catch (_) {}

      if (result.exitCode == 0) {
        log.i(result.stdout);
        log.i('SUCCESS: Task "$taskName" registered successfully.');
        return TaskOperationResult.success(
          'Task "$taskName" registered successfully.',
        );
      } else {
        log.w('FAILURE: PowerShell returned exit code ${result.exitCode}');
        log.e('STDERR: ${result.stderr}');
        return TaskOperationResult.failure(
          'Failed to register task via PowerShell.',
          result.stderr,
        );
      }
    } catch (e) {
      log.e('EXCEPTION: Failed to register task: $e');
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
      log.i('Removing Task "$taskName"...');

      final result = await Process.run('powershell', [
        '-Command',
        'Unregister-ScheduledTask -TaskName "$taskName" -Confirm:\$false -ErrorAction Stop',
      ]);

      if (result.exitCode == 0) {
        log.i('SUCCESS: Task "$taskName" removed.');
        return TaskOperationResult.success('Task "$taskName" removed.');
      } else {
        // Check if error is simply that the task doesn't exist
        if (result.stderr.toString().contains(
          'No MSFT_ScheduledTask objects found',
        )) {
          log.i('Task "$taskName" was not found (nothing to remove).');
          return TaskOperationResult.success(
            'Task was not found (nothing to remove).',
          );
        }

        log.w('FAILURE: Failed to remove task.');
        log.e('STDERR: ${result.stderr}');
        return TaskOperationResult.failure(
          'Failed to remove task.',
          result.stderr,
        );
      }
    } catch (e) {
      log.e('EXCEPTION: Failed to remove task: $e');
      return TaskOperationResult.failure(
        'Exception during task removal.',
        e.toString(),
      );
    }
  }
}
