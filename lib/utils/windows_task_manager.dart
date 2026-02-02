import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;

class WindowsTaskManager {
  static const String taskName = 'HYPRReady_Boot_Diagnostic';
  static const String configFileName = 'hyprready.json';

  /// Registers the Windows Scheduled Task.
  ///
  /// returns true if successful, false otherwise.
  static Future<bool> registerTask(List<String> args) async {
    if (!Platform.isWindows) {
      print('Error: Windows Task Scheduler is only supported on Windows.');
      return false;
    }

    try {
      print('Starting Task Registration...');

      // 1. Gather Configuration (defaults matching the PowerShell script)
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
      // We use the exact logic from the PS1 script

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
        return true;
      } else {
        print('FAILURE: PowerShell returned exit code ${result.exitCode}');
        print('STDERR: ${result.stderr}');
        return false;
      }
    } catch (e) {
      print('EXCEPTION: Failed to register task: $e');
      return false;
    }
  }

  /// Removes the Windows Scheduled Task.
  static Future<bool> removeTask() async {
    if (!Platform.isWindows) {
      print('Error: Windows Task Scheduler is only supported on Windows.');
      return false;
    }

    try {
      print('Removing Task "$taskName"...');

      final result = await Process.run('powershell', [
        '-Command',
        'Unregister-ScheduledTask -TaskName "$taskName" -Confirm:\$false -ErrorAction Stop',
      ]);

      if (result.exitCode == 0) {
        print('SUCCESS: Task "$taskName" removed.');
        return true;
      } else {
        // Check if error is simply that the task doesn't exist
        if (result.stderr.toString().contains(
          'No MSFT_ScheduledTask objects found',
        )) {
          print('Task "$taskName" was not found (nothing to remove).');
          return true;
        }

        print('FAILURE: Failed to remove task.');
        print('STDERR: ${result.stderr}');
        return false;
      }
    } catch (e) {
      print('EXCEPTION: Failed to remove task: $e');
      return false;
    }
  }
}
