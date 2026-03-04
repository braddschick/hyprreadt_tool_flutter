import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/cmd.dart';
import '../utils/dsreg_service.dart';
import 'check.dart';

class WindowsSecurityCheck extends Check {
  @override
  String get id => 'WIN_SEC_01';

  @override
  String get title => 'Windows Security Standards';

  @override
  String get description => 'Verifies Domain/Azure Join, Policies, and .NET';

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
    // Helper to return a struct or tuple, but for simplicity we'll just return the result string from a helper function
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

    final scRemoveFuture = runRegCheck(
      'Smart Card Removal',
      r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon',
      'ScRemoveOption',
      r'0x[0-9a-fA-F]+',
    );

    final scForceFuture = runRegCheck(
      'Smart Card Force Logon',
      r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
      'scforceoption',
      r'0x[0-9a-fA-F]+',
    );

    final cachedCredsFuture = runRegCheck(
      'Cached Credential Count',
      r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon',
      'CachedLogonsCount',
      r'0x[0-9a-fA-F]+',
    );

    // 3. DC Trust
    Future<String> runDcTrust() async {
      final userDnsDomain = Platform.environment['USERDNSDOMAIN'];
      if (userDnsDomain != null && userDnsDomain.isNotEmpty) {
        // Security: Sanitize input to allow only alphanumeric, dots, and hyphens.
        if (!RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(userDnsDomain)) {
          return '❌ DC Trust: Skipped (Invalid characters in USERDNSDOMAIN)';
        }

        try {
          final nltest = await Cmd.run('nltest', ['/SC_VERIFY:$userDnsDomain']);
          if (nltest.exitCode == 0) {
            return '✅ DC Trust Verified ($userDnsDomain)';
          } else {
            return '❌ DC Trust Verification Failed';
          }
        } catch (_) {
          return '❌ Failed to run nltest';
        }
      } else {
        return 'ℹ️ Skipping DC Trust (USERDNSDOMAIN not set)';
      }
    }

    final dcTrustFuture = runDcTrust();

    // 4. DotNet (FS check is fast, but we can wrap it if we want full parallelism, or leave it)
    // It's IO so let's just await it inline or wrapping it doesn't save much.
    // We will await everything at once.

    // --- Await All ---
    final resultsList = await Future.wait([
      dsRegFuture.then((value) => value as dynamic).catchError((e) => e),
      scRemoveFuture,
      scForceFuture,
      cachedCredsFuture,
      dcTrustFuture,
    ]);

    final dsResultOrError = resultsList[0];
    final scRemoveResult = resultsList[1] as String;
    final scForceResult = resultsList[2] as String;
    final cachedCredsResult = resultsList[3] as String;
    final dcTrustResult = resultsList[4] as String;

    // --- Process dsregcmd Results ---
    if (dsResultOrError is DsRegStatus) {
      final status = dsResultOrError;
      results.add('ℹ️ Device Name: ${status.deviceName}');
      results.add(
        status.isDomainJoined ? '✅ Domain Joined: YES' : '⚠️ Domain Joined: NO',
      );
      results.add('Azure AD Joined: ${status.isAzureAdJoined ? "YES" : "NO"}');
      results.add(
        'Enterprise Joined: ${status.isEnterpriseJoined ? "YES" : "NO"}',
      );
      results.add('Azure SSO PRT: ${status.isAzureAdPrt ? "YES" : "NO"}');
      results.add(
        'Enterprise SSO PRT: ${status.isEnterprisePrt ? "YES" : "NO"}',
      );
    } else {
      results.add('❌ Failed to run dsregcmd: $dsResultOrError');
      failedCount++;
    }

    // --- Add Registry & System Results ---
    results.add(scRemoveResult);
    results.add(scForceResult);
    results.add(cachedCredsResult);

    results.add(dcTrustResult);
    if (dcTrustResult.contains('❌') || dcTrustResult.contains('Failed')) {
      // Only increment fail count for explicit failures, skipping isn't a fail
      if (!dcTrustResult.contains('Skipped')) {
        failedCount++;
      }
    }

    // --- DotNet Check ---
    final dotNetDir = Directory(r'C:\Windows\Microsoft.NET\Framework');
    if (await dotNetDir.exists()) {
      results.add('✅ .NET Framework Folder Found');
    } else {
      results.add('❌ .NET Framework Folder Missing');
      failedCount++;
    }

    if (failedCount == 0) {
      return CheckResult(status: CheckStatus.pass, message: results.join('\n'));
    } else {
      return CheckResult(
        status: CheckStatus.fail,
        message:
            'Windows Security Checks Failed/Warned:\n' + results.join('\n'),
      );
    }
  }
}
