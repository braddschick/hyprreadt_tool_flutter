import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/cmd.dart';
import 'check.dart';
import '../config/app_config.dart';

class CertificateTemplateCheck extends Check {
  @override
  String get id => 'CERT_TEMPLATE_01';

  @override
  String get title => 'Certificate Template Availability';

  @override
  String get description =>
      'Verifies the availability and configuration of the specified Certificate Template';

  @override
  bool appliesToOS(String os) {
    return os == 'windows' || os == 'macos';
  }

  @override
  Future<CheckResult> execute([BuildContext? context]) async {
    // If running headless (no context) or if explicit config is present, try config first
    final config = AppConfig();
    if (context == null ||
        (config.adcsServer != null && config.certTemplate != null)) {
      return _checkHeadlessOrConfigured(context);
    }

    if (context == null) {
      // Should not happen if logic above flows right, but safe fallback
      return CheckResult(
        status: CheckStatus.fail,
        message:
            'Interactive check requires UI or configuration file (hyprready.json).',
      );
    }

    if (Platform.isMacOS) {
      return _checkMacOSInteractive(context);
    } else if (Platform.isWindows) {
      return _checkWindowsInteractive(context);
    } else {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Unsupported operating system for this check.',
      );
    }
  }

  Future<CheckResult> _checkHeadlessOrConfigured([
    BuildContext? context,
  ]) async {
    // Logic for headless/configured execution
    final config = AppConfig();
    final server = config.adcsServer;
    final template = config.certTemplate;

    if (server == null || template == null) {
      return CheckResult(
        status: CheckStatus
            .manual, // or skip? user said "skip the cert check" if file missing
        message:
            'Skipping: Missing configuration for ADCS Server or Template in hyprready.json',
      );
    }

    // Attempt to run check with specific logic
    // We reuse logic but might need adaptations for lacking credentials
    // For Windows, we might use current user context.
    // For macOS, we likely can't do much without credentials unless we have them in config (which we don't support yet securely)

    if (Platform.isWindows) {
      return _checkWindowsInternal(server, template);
    } else if (Platform.isMacOS) {
      // MacOS typically requires explicit credentials for ADCS via curl unless using Kerberos ticket
      // Let's assume for now we skip or try.
      return CheckResult(
        status: CheckStatus.manual,
        message:
            'Headless check on macOS requires authentication implementation. Skipped.',
      );
    }

    return CheckResult(
      status: CheckStatus.manual,
      message: 'Headless unsupported on this OS',
    );
  }

  // Refactored interactive flows to call internal logic
  Future<CheckResult> _checkMacOSInteractive(BuildContext context) async {
    // ... (Existing interactive logic, might need refactoring to separate UI from Logic if we want to reuse)
    // For now, leaving as is but renaming to avoid confusion
    // Actually, let's just keep the existing logic structure but wrapped.
    // The existing _checkMacOS uses _showInputDialog then runs logic.
    // To reuse logic, we should extract the "RUN" part.

    // Due to complexity of refactoring the whole file deeply, I'll keep the interactive methods
    // and just ensure the execute routing is correct.
    // But wait, the previous `_checkMacOS` had everything inline.
    // I should probably leave `_checkMacOS` logic alone but rename it to `_checkMacOSInteractive`.

    return _originalCheckMacOS(context);
  }

  Future<CheckResult> _checkWindowsInteractive(BuildContext context) async {
    return _originalCheckWindows(context);
  }

  // ... (I need to keep the original methods but rename them or call them)
  // To avoid massive diff, I will just paste the original logic back with renamed headers if needed,
  // OR I will modify the original methods to take optional params.

  // Let's try to adapt the existing methods to take defaults?
  // `_checkMacOS` takes context.

  Future<CheckResult> _originalCheckMacOS(BuildContext context) async {
    final input = await _showInputDialog(
      context,
      title: 'Certificate Template Info',
      fields: [
        'ADCS Server (URL/IP)',
        'Template Name',
        'Username (DOMAIN\\username)',
        'Password',
      ],
    );

    if (input == null) {
      return CheckResult(
        status: CheckStatus.manual,
        message: 'Check skipped by user.',
      );
    }

    final server = input['ADCS Server (URL/IP)'];
    final template = input['Template Name'];
    final username = input['Username (DOMAIN\\username)'];
    final password = input['Password'];

    if (server == null ||
        server.isEmpty ||
        template == null ||
        template.isEmpty ||
        username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Missing required information. Check skipped.',
      );
    }

    return _runMacOSLogic(server, template, username, password);
  }

  Future<CheckResult> _runMacOSLogic(
    String server,
    String template,
    String username,
    String password,
  ) async {
    // ... Logic from original _checkMacOS ...
    // Prepare URLs
    String baseUrl = server;
    if (!baseUrl.startsWith('http')) {
      baseUrl = 'https://$baseUrl/certsrv/';
    } else {
      if (!baseUrl.endsWith('/certsrv/')) {
        baseUrl = '$baseUrl/certsrv/';
      }
    }
    final submitUrl = '${baseUrl}certfnsh.asp';
    final fetchUrl = '${baseUrl}certnew.cer';

    // Helper for Cleanup
    final tempDir = await getTemporaryDirectory();
    final uniqueId = DateTime.now().millisecondsSinceEpoch;
    final keyPath = '${tempDir.path}/hypr_temp_$uniqueId.key';
    final csrPath = '${tempDir.path}/hypr_temp_$uniqueId.csr';
    final certPath = '${tempDir.path}/hypr_temp_$uniqueId.cer';

    Future<void> cleanup() async {
      try {
        if (await File(keyPath).exists()) await File(keyPath).delete();
        if (await File(csrPath).exists()) await File(csrPath).delete();
        if (await File(certPath).exists()) await File(certPath).delete();
      } catch (_) {} // Ignore cleanup errors
    }

    try {
      final cn = username.split('\\').last;
      final csrResult = await Cmd.run('openssl', [
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        keyPath,
        '-out',
        csrPath,
        '-subj',
        '/CN=HyprReadinessTool_$cn',
      ]);

      if (csrResult.exitCode != 0) {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'Failed to generate CSR with OpenSSL: ${csrResult.stderr}',
        );
      }

      final csrContent = await File(csrPath).readAsString();

      final submitResult = await Cmd.run('curl', [
        '-k', // Insecure
        '-s', // Silent
        '--ntlm',
        '-u',
        '$username:$password',
        '-d',
        'Mode=newreq',
        '--data-urlencode', // Encodes the next argument
        'CertRequest=$csrContent',
        '-d',
        'CertAttrib=CertificateTemplate:$template',
        '-d',
        'TargetStoreFlags=0',
        '-d',
        'SaveCert=yes',
        submitUrl,
      ]);

      if (submitResult.exitCode != 0) {
        return CheckResult(
          status: CheckStatus.fail,
          message:
              'Failed to submit CSR to ADCS ($submitUrl): ${submitResult.stderr}',
        );
      }

      final responseBody = submitResult.stdout;
      debugPrint('ADCS Response: $responseBody');

      // 3. Parse Request ID
      final reqIdRegEx = RegExp(r'ReqID\s*=\s*(\d+)', caseSensitive: false);
      var match = reqIdRegEx.firstMatch(responseBody);

      if (match == null) {
        final idRegex2 = RegExp(r'request is\s+(\d+)', caseSensitive: false);
        match = idRegex2.firstMatch(responseBody);
      }

      if (match == null) {
        if (responseBody.contains('Denied')) {
          return CheckResult(
            status: CheckStatus.fail,
            message: 'Certificate Request Denied by CA.',
          );
        }

        final snippet = responseBody.length > 200
            ? '${responseBody.substring(0, 200)}...'
            : responseBody;
        return CheckResult(
          status: CheckStatus.fail,
          message:
              'Username or password was incorrect.\nResponse Snippet: $snippet',
        );
      }

      final reqId = match.group(1)!;

      // 4. Retrieve Certificate
      final fetchResult = await Cmd.run('curl', [
        '-k',
        '-s',
        '--ntlm',
        '-u',
        '$username:$password',
        '$fetchUrl?ReqID=$reqId&Enc=b64',
      ]);

      if (fetchResult.exitCode != 0) {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'Failed to fetch issued certificate (ID: $reqId).',
        );
      }

      final certContent = fetchResult.stdout;
      if (!certContent.contains('BEGIN CERTIFICATE')) {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'Retrieved content does not look like a certificate.',
        );
      }

      await File(certPath).writeAsString(certContent);

      // 5. Verify EKUs with OpenSSL
      final verifyResult = await Cmd.run('openssl', [
        'x509',
        '-in',
        certPath,
        '-noout',
        '-text',
      ]);

      if (verifyResult.exitCode != 0) {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'Failed to parse certificate with OpenSSL.',
        );
      }

      final certText = verifyResult.stdout;
      debugPrint('OpenSSL Output:\n$certText');

      final lowerCertText = certText.toLowerCase();

      final hasClientAuth =
          lowerCertText.contains('client authentication') ||
          certText.contains('1.3.6.1.5.5.7.3.2');

      final hasSmartCard =
          lowerCertText.contains('smart card logon') ||
          lowerCertText.contains('smartcardlogin') ||
          lowerCertText.contains('smartcard login') ||
          certText.contains('1.3.6.1.4.1.311.20.2.2');

      final hasDigitalSignature = lowerCertText.contains('digital signature');

      if (hasClientAuth && hasSmartCard && hasDigitalSignature) {
        return CheckResult(
          status: CheckStatus.pass,
          message:
              'Successfully enrolled and verified template "$template". EKUs present: Client Auth, Smart Card Logon.',
        );
      } else {
        final missing = <String>[];
        if (!hasClientAuth) missing.add('Client Authentication');
        if (!hasSmartCard) missing.add('Smart Card Logon');
        if (!hasDigitalSignature) missing.add('Digital Signature');

        return CheckResult(
          status: CheckStatus.fail,
          message:
              'Enrolled successfully, but certificate missing required EKUs: ${missing.join(', ')}',
        );
      }
    } catch (e) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Enrollment check failed with error: $e',
      );
    } finally {
      await cleanup();
    }
  }

  Future<CheckResult> _originalCheckWindows(BuildContext context) async {
    final input = await _showInputDialog(
      context,
      title: 'Certificate Template Info',
      fields: ['ADCS Server (Hostname)', 'Template Name'],
    );

    if (input == null) {
      return CheckResult(
        status: CheckStatus.manual,
        message: 'Check skipped by user.',
      );
    }

    final server = input['ADCS Server (Hostname)'];
    final templateName = input['Template Name'];

    if (server == null ||
        server.isEmpty ||
        templateName == null ||
        templateName.isEmpty) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Missing required information. Check skipped.',
      );
    }

    return _checkWindowsInternal(server, templateName);
  }

  Future<CheckResult> _checkWindowsInternal(
    String server,
    String templateName,
  ) async {
    // 1. Verify Connectivity (Ping)
    try {
      final pingResult = await Cmd.run('ping', ['-n', '1', server]);
      if (pingResult.exitCode != 0) {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'Could not ping ADCS Server: $server',
        );
      }
    } catch (e) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Error verifying connectivity to $server: $e',
      );
    }

    try {
      final result = await Cmd.run('certutil', [
        '-v',
        '-template',
        templateName,
      ]);

      if (result.exitCode != 0) {
        return CheckResult(
          status: CheckStatus.fail,
          message:
              'Failed to query template "$templateName". Error: ${result.stdout}',
        );
      }

      final output = result.stdout;
      final hasClientAuth =
          output.contains('Client Authentication') ||
          output.contains('1.3.6.1.5.5.7.3.2');
      final hasSmartCard =
          output.contains('Smart Card Logon') ||
          output.contains('1.3.6.1.4.1.311.20.2.2');

      if (hasClientAuth && hasSmartCard) {
        return CheckResult(
          status: CheckStatus.pass,
          message:
              'Template "$templateName" found with Client Authentication and Smart Card Logon.',
        );
      } else {
        final missing = [];
        if (!hasClientAuth) missing.add('Client Authentication');
        if (!hasSmartCard) missing.add('Smart Card Logon');

        return CheckResult(
          status: CheckStatus.fail,
          message:
              'Template "$templateName" found but missing EKU(s): ${missing.join(', ')}',
        );
      }
    } catch (e) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Error executing certutil: $e',
      );
    }
  }

  Future<Map<String, String>?> _showInputDialog(
    BuildContext context, {
    required String title,
    required List<String> fields,
  }) async {
    final controllers = <String, TextEditingController>{};
    for (var field in fields) {
      controllers[field] = TextEditingController();
    }

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false, // Force user to choose
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: fields.map((field) {
                final isPassword = field.toLowerCase().contains('password');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: TextField(
                    controller: controllers[field],
                    obscureText: isPassword,
                    decoration: InputDecoration(
                      labelText: field,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(null); // Cancel/Skip
              },
              child: const Text('Skip Check'),
            ),
            ElevatedButton(
              onPressed: () {
                final result = <String, String>{};
                for (var entry in controllers.entries) {
                  result[entry.key] = entry.value.text.trim();
                }
                Navigator.of(context).pop(result);
              },
              child: const Text('Run Check'),
            ),
          ],
        );
      },
    );
  }
}
