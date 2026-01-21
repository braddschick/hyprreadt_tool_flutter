import 'package:flutter/material.dart';

import 'dart:io';

import '../utils/cmd.dart';
import 'check.dart';

class EnvironmentCheck extends Check {
  @override
  String get id => 'ENVIRONMENT_01';

  @override
  String get title => 'Environment Information';

  @override
  String get description =>
      'Gathers environment information and security posture (FileVault, AD, Policies)';

  @override
  bool appliesToOS(String os) {
    return os == 'windows' || os == 'macos';
  }

  @override
  Future<CheckResult> execute([BuildContext? context]) async {
    final results = <String>[];
    int failedCount = 0;

    // Common Info
    final username =
        Platform.environment['USER'] ??
        Platform.environment['USERNAME'] ??
        'Unknown';
    results.add('ℹ️ User: $username');

    if (Platform.isMacOS) {
      // --- FileVault Checks ---
      // 1. Status
      try {
        final fvStatus = await Cmd.run('fdesetup', ['status']);
        if (fvStatus.stdout.toString().trim() == 'FileVault is On.') {
          results.add('✅ FileVault is On');
        } else {
          results.add(
            '❌ FileVault is NOT On (Output: ${fvStatus.stdout.trim()})',
          );
          failedCount++;
        }
      } catch (e) {
        results.add('❌ FileVault Check Failed: $e');
        failedCount++;
      }

      // 2. Personal Recovery Key (Requires Admin Privileges)
      try {
        // Use native macOS prompt for admin privileges
        // Output is returned in stdout if successful, or non-zero exit code if cancelled/failed
        final cmd = 'fdesetup haspersonalrecoverykey';
        final script = 'do shell script "$cmd" with administrator privileges';

        // Execute via osascript
        final result = await Cmd.run('osascript', ['-e', script]);

        if (result.exitCode == 0) {
          final output = result.stdout.trim();
          if (output == 'true') {
            results.add('✅ Has Personal Recovery Key');
          } else {
            results.add('❌ Missing Personal Recovery Key (Output: $output)');
            failedCount++;
          }
        } else {
          if (result.stderr.contains('User canceled')) {
            results.add(
              '⚠️ Personal Recovery Key check skipped (User cancelled auth)',
            );
          } else {
            results.add(
              '⚠️ Personal Recovery Key check failed: ${result.stderr}',
            );
          }
        }
      } catch (e) {
        results.add('⚠️ Personal Recovery Key check error: $e');
      }
      // 3. Using Recovery Key
      try {
        final fvUsingKey = await Cmd.run('fdesetup', ['usingrecoverykey']);
        if (fvUsingKey.stdout.toString().trim() == 'false') {
          results.add('✅ Not using Recovery Key');
        } else {
          results.add('❌ Using Recovery Key (or check failed)');
          failedCount++; // Strict?
        }
      } catch (_) {}

      // --- Plist Checks ---
      Future<void> checkPlist(
        String name,
        String path,
        String key,
        String expected, {
        bool isNilCheck = false,
      }) async {
        try {
          String cmdPath = path;
          if (cmdPath.endsWith('.plist')) {
            cmdPath = cmdPath.substring(0, cmdPath.length - 6);
          }

          final res = await Cmd.run('defaults', ['read', cmdPath, key]);
          final output = res.stdout.toString().trim();

          if (res.exitCode != 0) {
            if (isNilCheck &&
                res.stderr.toString().contains('does not exist')) {
              results.add('✅ $name: Not set (as expected)');
              return;
            }
            results.add('❌ $name: Failed to read key "$key" ($output)');
            failedCount++;
            return;
          }

          if (isNilCheck) {
            results.add('❌ $name: Value exists ("$output") but expected none');
            failedCount++;
          } else {
            if (output == expected) {
              results.add('✅ $name: $expected');
            } else {
              results.add('❌ $name: Expected "$expected", got "$output"');
              failedCount++;
            }
          }
        } catch (e) {
          results.add('❌ $name: Error $e');
          failedCount++;
        }
      }

      // JAMF (Info Only)
      try {
        final jamfRes = await Cmd.run('defaults', [
          'read',
          '/Library/Preferences/com.jamfsoftware.jamf',
          'jss_url',
        ]);
        if (jamfRes.exitCode == 0) {
          results.add('ℹ️ JAMF Server: ${jamfRes.stdout.toString().trim()}');
        } else {
          results.add('ℹ️ JAMF Server: Not configured or not readable');
        }
      } catch (_) {}

      // Screen Saver
      final home = Platform.environment['HOME'] ?? '/Users/Shared';
      await checkPlist(
        'Screen Saver Token Removal',
        '$home/Library/Preferences/com.apple.screensaver.plist',
        'tokenRemovalAction',
        '0',
      );

      // Auto Login
      await checkPlist(
        'Automatic Login',
        '/Library/Preferences/com.apple.loginwindow.plist',
        'autoLoginUser',
        '',
        isNilCheck: true,
      );

      // --- AD Configuration ---
      try {
        final dsResult = await Cmd.run('dsconfigad', ['-show']);
        final dsOut = dsResult.stdout.toString();
        if (dsOut.contains('Directory Domain')) {
          final lines = dsOut.split('\n');
          final domainLine = lines.firstWhere(
            (l) => l.contains('Directory Domain'),
            orElse: () => '',
          );
          if (domainLine.isNotEmpty) {
            final parts = domainLine.split('=');
            if (parts.length > 1) {
              results.add('✅ AD Binding: ${parts[1].trim()}');
            } else {
              results.add('✅ AD Binding: Configured');
            }
          }
        } else {
          results.add('⚠️ AD Binding: Not found / Not bound');
        }
      } catch (e) {
        results.add('❌ AD Check Failed: $e');
      }
    } else if (Platform.isWindows) {
      final result = await Cmd.run('wmic', [
        'computersystem',
        'get',
        'Domain,PartOfDomain',
        '/format:list',
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout;
        var partOfDomain = '';
        var domain = '';

        for (var line in output.split('\n')) {
          line = line.trim();
          if (line.startsWith('Domain=')) {
            domain = line.substring('Domain='.length);
          } else if (line.startsWith('PartOfDomain=')) {
            partOfDomain = line.substring('PartOfDomain='.length);
          }
        }

        if (partOfDomain.toLowerCase() == 'true') {
          results.add('✅ Domain Joined: $domain');
        } else {
          results.add('⚠️ Domain: Not Joined');
          if (domain.isNotEmpty) {
            results.add('ℹ️ Workgroup: $domain');
          }
        }
      } else {
        results.add('❌ Failed to Get Domain Info');
        failedCount++;
      }
    }

    if (failedCount == 0) {
      return CheckResult(status: CheckStatus.pass, message: results.join('\n'));
    } else {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Environment/Security Checks Failed:\n${results.join('\n')}',
      );
    }
  }
}
