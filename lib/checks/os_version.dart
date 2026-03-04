import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart'; // for visibleForTesting
import 'dart:io';

import '../utils/cmd.dart';
import 'check.dart';

typedef CmdRunner =
    Future<CmdResult> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });

class OSVersionCheck extends Check {
  final CmdRunner _cmdRunner;

  OSVersionCheck({CmdRunner? cmdRunner}) : _cmdRunner = cmdRunner ?? Cmd.run;

  @override
  String get id => 'OS_VERSION_01';

  @override
  String get title => 'OS Version Compatibility';

  @override
  String get description =>
      'Verifies OS version: Windows 10 Pro or Windows 11 Pro, or macOS 13/14.1/15+';

  @override
  bool appliesToOS(String os) {
    return os == 'windows' || os == 'macos';
  }

  @override
  Future<CheckResult> execute([BuildContext? context]) async {
    if (Platform.isMacOS) {
      return checkMacOS();
    } else if (Platform.isWindows) {
      return checkWindows();
    } else {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Unsupported operating system: ${Platform.operatingSystem}',
      );
    }
  }

  @visibleForTesting
  Future<CheckResult> checkMacOS() async {
    final result = await _cmdRunner('sw_vers', ['-productVersion']);
    if (result.exitCode != 0) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Unable to determine macOS version. Error: ${result.stderr}',
      );
    }

    final versionStr = result.stdout;
    final parts = versionStr.split('.');

    if (parts.isEmpty) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Unable to parse macOS version: $versionStr',
      );
    }

    try {
      final major = int.parse(parts[0]);
      final minor = parts.length > 1 ? int.parse(parts[1]) : 0;

      if (major == 13) {
        return CheckResult(
          status: CheckStatus.pass,
          message: 'macOS $versionStr detected (compatible version)',
        );
      }

      if (major == 14) {
        if (minor >= 1) {
          return CheckResult(
            status: CheckStatus.pass,
            message: 'macOS $versionStr detected (compatible version)',
          );
        }
        return CheckResult(
          status: CheckStatus.fail,
          message:
              'macOS $versionStr detected. Required: macOS 13, 14.1+, or 15+. macOS 14.0 is not supported.',
        );
      }

      if (major >= 15) {
        return CheckResult(
          status: CheckStatus.pass,
          message: 'macOS $versionStr detected (compatible version)',
        );
      }

      return CheckResult(
        status: CheckStatus.fail,
        message:
            'macOS $versionStr detected. Required: macOS 13, 14.1+, or 15+',
      );
    } catch (e) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Error parsing version: $e',
      );
    }
  }

  @visibleForTesting
  Future<CheckResult> checkWindows() async {
    // WMI command to get OS Caption and Version
    final result = await _cmdRunner('wmic', [
      'os',
      'get',
      'Caption,Version',
      '/format:list',
    ]);

    // If wmic fails, try systeminfo (fallback logic similar to Go)
    if (result.exitCode != 0) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'WMI command failed. Unable to verify Windows version.',
      );
    }

    final output = result.stdout;
    String caption = '';
    String version = '';

    final lines = output.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.startsWith('Caption=')) {
        caption = line.substring('Caption='.length);
      } else if (line.startsWith('Version=')) {
        version = line.substring('Version='.length);
      }
    }

    if (caption.isEmpty) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Unable to parse Windows version from WMI output.',
      );
    }

    final isWindows10 = caption.contains('Windows 10');
    final isWindows11 = caption.contains('Windows 11');
    final isPro = caption.contains('Pro');
    final isEnterprise = caption.contains('Enterprise');

    if (!isPro && !isEnterprise) {
      return CheckResult(
        status: CheckStatus.fail,
        message:
            'Windows Pro or Enterprise edition required. Detected: $caption',
      );
    }

    if (isWindows10) {
      return CheckResult(
        status: CheckStatus.pass,
        message:
            'Windows 10 ${isPro ? "Pro" : "Enterprise"} detected ($version)',
      );
    }

    if (isWindows11) {
      return CheckResult(
        status: CheckStatus.pass,
        message:
            'Windows 11 ${isPro ? "Pro" : "Enterprise"} detected ($version)',
      );
    }

    return CheckResult(
      status: CheckStatus.fail,
      message:
          'Unsupported Windows version: $caption. Required: Windows 10/11 Pro or Enterprise',
    );
  }
}
