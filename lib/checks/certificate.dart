import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/cmd.dart';
import 'check.dart';

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
  Future<CheckResult> execute(BuildContext context) async {
    if (Platform.isMacOS) {
      return _checkMacOS(context);
    } else if (Platform.isWindows) {
      return _checkWindows(context);
    } else {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Unsupported operating system for this check.',
      );
    }
  }

  Future<CheckResult> _checkMacOS(BuildContext context) async {
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
      // 1. Generate CSR (OpenSSL)
      // openssl req -new -newkey rsa:2048 -nodes -keyout key.pem -out req.csr -subj "/CN=HyprCheck"
      // We use a simple socket check just to ensure openssl is installed?
      // Check logic assumes openssl is in path.

      final cn = username.split('\\').last; // Simple CN from username
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
      // Need to clean CSR content for URL encoding?
      // Actually curl --data-urlencode handles it if we pass it right,
      // but standard ADCS expects specific formatting.
      // Let's rely on standard form variables.
      // Important: ADCS expects CRLF newlines in PEM? Usually fine.

      // 2. Submit CSR to ADCS
      // POST data:
      // Mode=newreq
      // CertRequest={CSR}
      // CertAttrib=CertificateTemplate:{Template}
      // TargetStoreFlags=0
      // SaveCert=yes

      // We use curl to handle NTLM and Form submission
      // IMPORTANT: Use --data-urlencode for CertRequest because Base64 contains '+'
      // which 'curl -d' would send as '+', but the server interprets as space
      // unless it is properly percent-encoded (%2B).
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
      // We expect: "CertReq.exe -Retrieve <ID>" or a link "certnew.cer?ReqID=<ID>"
      // Regex to find ReqID - Try multiple patterns
      // Pattern 1: ReqID=123
      final reqIdRegEx = RegExp(r'ReqID\s*=\s*(\d+)', caseSensitive: false);
      var match = reqIdRegEx.firstMatch(responseBody);

      // Pattern 2: "The Id of the certificate request is 123"
      if (match == null) {
        final idRegex2 = RegExp(r'request is\s+(\d+)', caseSensitive: false);
        match = idRegex2.firstMatch(responseBody);
      }

      if (match == null) {
        // Did it fail? check for "Denied"
        if (responseBody.contains('Denied')) {
          return CheckResult(
            status: CheckStatus.fail,
            message: 'Certificate Request Denied by CA.',
          );
        }

        // Truncate response for display
        final snippet = responseBody.length > 200
            ? '${responseBody.substring(0, 200)}...'
            : responseBody;
        return CheckResult(
          status: CheckStatus.fail,
          message:
              'Could not parse Request ID from ADCS response. Connectivity OK.\nResponse Snippet: $snippet',
        );
      }

      final reqId = match.group(1)!;

      // 4. Retrieve Certificate
      // GET certnew.cer?ReqID=<ID>&Enc=b64
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
      // Basic check if it looks like a cert
      if (!certContent.contains('BEGIN CERTIFICATE')) {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'Retrieved content does not look like a certificate.',
        );
      }

      await File(certPath).writeAsString(certContent);

      // 5. Verify EKUs with OpenSSL
      // openssl x509 -in cert.pem -noout -text
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
          certText.contains(
            '1.3.6.1.5.5.7.3.2',
          ); // Keep OID distinct? String check is fine

      final hasSmartCard =
          lowerCertText.contains(
            'smart card logon',
          ) || // "Microsoft Smartcardlogin" or "Smart Card Logon"
          lowerCertText.contains('smartcardlogin') ||
          lowerCertText.contains(
            'smartcard login',
          ) || // "Microsoft Smartcard Login"
          certText.contains('1.3.6.1.4.1.311.20.2.2');

      // Emulate Go: Check for Digital Signature in Key Usage
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

  Future<CheckResult> _checkWindows(BuildContext context) async {
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

    // 2. Check Template with CertUtil
    // certutil -v -template <TemplateName>
    // Note: certutil might dump A LOT of data.
    // We specifically want to check if it exists and has Client Auth + Smart Card Logon.
    // However, `certutil -template` typically lists templates installed on the LOCAL machine or available in AD?
    // Actually `certutil -template` dumps template info from AD.

    try {
      // We'll try to find the template in the output of `certutil -template` or specific query.
      // `certutil -dsTemplate <TemplateName>` might be better if RSAT is installed, but standard certutil is safer.
      // Let's stick to `certutil -v -template <TemplateName>` and parse.

      final result = await Cmd.run('certutil', [
        '-v',
        '-template',
        templateName,
      ]);

      if (result.exitCode != 0) {
        // It might return non-zero if template not found?
        return CheckResult(
          status: CheckStatus.fail,
          message:
              'Failed to query template "$templateName". Error: ${result.stdout}',
        );
      }

      final output = result.stdout;

      // Validation Logic
      // Check for usages
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
