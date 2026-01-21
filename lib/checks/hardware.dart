import 'package:flutter/material.dart';

import 'dart:io';

import '../utils/cmd.dart';
import 'check.dart';

class HardwareCheck extends Check {
  @override
  String get id => 'HARDWARE_01';

  @override
  String get title => 'Secure Element Detection';

  @override
  String get description =>
      'Verifies the presence of TPM (Windows) or Secure Enclave/T2 chip (macOS)';

  @override
  bool appliesToOS(String os) {
    return os == 'windows' || os == 'macos';
  }

  @override
  Future<CheckResult> execute([BuildContext? context]) async {
    if (Platform.isMacOS) {
      return _checkMacOSSecureEnclave();
    } else if (Platform.isWindows) {
      return _checkWindowsTPM();
    } else {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Unsupported operating system: ${Platform.operatingSystem}',
      );
    }
  }

  Future<CheckResult> _checkMacOSSecureEnclave() async {
    final result = await Cmd.run('system_profiler', ['SPHardwareDataType']);

    if (result.exitCode != 0) {
      return CheckResult(
        status: CheckStatus.fail,
        message:
            'Unable to detect hardware information. system_profiler command failed.',
      );
    }

    final output = result.stdout;

    // Check for Apple Silicon
    if (output.contains('Chip: Apple') || output.contains('Apple Silicon')) {
      return CheckResult(
        status: CheckStatus.pass,
        message: 'Apple Silicon detected - Secure Enclave is present.',
      );
    }

    // Check for T2
    if (output.contains('T2') || output.contains('Secure Enclave')) {
      return CheckResult(
        status: CheckStatus.pass,
        message: 'T2 chip detected - Secure Enclave is present.',
      );
    }

    // Intel check
    if (output.contains('Intel')) {
      return CheckResult(
        status: CheckStatus.warning,
        message:
            'Intel-based Mac detected. T2 chip may not be present. Verify Secure Enclave availability.',
      );
    }

    return CheckResult(
      status: CheckStatus.warning,
      message:
          'Unable to definitively determine Secure Enclave status. Please verify hardware manually.',
    );
  }

  Future<CheckResult> _checkWindowsTPM() async {
    final result = await Cmd.run('wmic', [
      'path',
      'Win32_Tpm',
      'get',
      'IsEnabled_InitialValue',
      '/format:list',
    ]);

    if (result.exitCode != 0) {
      return CheckResult(
        status: CheckStatus.fail,
        message:
            'Unable to detect TPM. WMI query failed. Ensure TPM is enabled in BIOS/UEFI settings.',
      );
    }

    final output = result.stdout;
    if (output.contains('IsEnabled_InitialValue=TRUE') ||
        output.contains('IsEnabled_InitialValue=True')) {
      return CheckResult(
        status: CheckStatus.pass,
        message: 'TPM detected and enabled on this system.',
      );
    }

    return CheckResult(
      status: CheckStatus.warning,
      message:
          'TPM hardware detected but may not be fully enabled. Check BIOS/UEFI settings.',
    );
  }
}
