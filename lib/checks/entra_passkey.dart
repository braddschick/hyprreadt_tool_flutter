import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/cmd.dart';
import '../utils/dsreg_service.dart';
import 'check.dart';

class EntraPasskeyCheck extends Check {
  @override
  String get id => 'ENTRA_PASSKEY_01';

  @override
  String get title => 'Enterprise Passkey';

  @override
  String get description =>
      'Verifies Entra ID Passkey configuration and Cloud Kerberos Trust';

  @override
  bool appliesToOS(String os) => Platform.isWindows;

  @override
  Future<CheckResult> execute([BuildContext? context]) async {
    final results = <String>[];
    int failedCount = 0;

    // --- Prepare Futures for Parallel Execution ---

    // 1. dsregcmd /status
    final dsRegFuture = DsRegService().getStatus();

    // 2. Registry Checks
    Future<String> runRegCheck(
      String name,
      String key,
      String valueName,
      String pattern,
    ) async {
      try {
        final res = await Cmd.run('reg', ['query', key, '/v', valueName]);
        if (res.exitCode == 0) {
          final out = res.stdout.toString();
          final regex = RegExp(pattern, caseSensitive: false);
          if (regex.hasMatch(out)) {
            final match = regex.firstMatch(out);
            return '✅ $name: ${match?.group(0)}';
          } else {
            return '✅ $name: Found (Details: ${out.trim().split(RegExp(r'\s+')).last})';
          }
        } else {
          return '⚠️ $name: Not found / Not configured';
        }
      } catch (e) {
        return '❌ $name: Error $e';
      }
    }

    final fidoAuthFuture = runRegCheck(
      'FIDO Authentication Logon',
      r'HKEY_LOCAL_MACHINE\SOFTWARE\policies\Microsoft\FIDO',
      'EnableFIDODeviceLogon',
      r'0x1\b',
    );

    final securityKeyFuture = runRegCheck(
      'Security Key Sign-In',
      r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Policies\PassportForWork\SecurityKey',
      'UseSecurityKeyForSignIn',
      r'0x1\b',
    );

    // --- Await All ---
    final resultsList = await Future.wait([
      dsRegFuture.then((value) => value as dynamic).catchError((e) => e),
      fidoAuthFuture,
      securityKeyFuture,
    ]);

    final dsResultOrError = resultsList[0];
    final fidoAuthResult = resultsList[1] as String;
    final securityKeyResult = resultsList[2] as String;

    // --- Process dsregcmd Results ---
    if (dsResultOrError is DsRegStatus) {
      final status = dsResultOrError;

      // We only care about CloudTgt and OnPremTgt here for Cloud Kerberos Trust
      if (status.isOnPremTgt) {
        results.add('✅ OnPremTgt: YES');
      } else {
        results.add('❌ OnPremTgt: NO');
        failedCount++;
      }
      if (status.isCloudTgt) {
        results.add('✅ CloudTgt: YES');
      } else {
        results.add('❌ CloudTgt: NO');
        failedCount++;
      }
    } else {
      results.add('❌ Failed to run dsregcmd: $dsResultOrError');
      failedCount++;
    }

    // --- Add Registry Results ---
    results.add(fidoAuthResult);
    if (fidoAuthResult.contains('⚠️') || fidoAuthResult.contains('❌')) {
      failedCount++;
    }

    results.add(securityKeyResult);
    if (securityKeyResult.contains('⚠️') || securityKeyResult.contains('❌')) {
      failedCount++;
    }

    if (failedCount == 0) {
      return CheckResult(status: CheckStatus.pass, message: results.join('\n'));
    } else {
      return CheckResult(
        status: CheckStatus.fail,
        message:
            'Enterprise Passkey Checks Failed/Warned:\n' + results.join('\n'),
      );
    }
  }
}
