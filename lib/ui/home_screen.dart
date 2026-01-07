import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../checks/check.dart';
import '../checks/os_version.dart';
import '../checks/hardware.dart';
import '../checks/network.dart';
import '../checks/environment.dart';
import '../checks/certificate.dart';
// Note: We need to import the new checks
import '../checks/windows_security.dart';

import '../ui/widgets/check_item.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Define checks list inside the State class
  List<Check> get _checks => [
    OSVersionCheck(),
    HardwareCheck(),
    EnvironmentCheck(),
    NetworkCheck(),
    CertificateTemplateCheck(),
    WindowsSecurityCheck(),
  ];

  // Map to store results by check ID
  final Map<String, CheckResult> _results = {};
  bool _scanning = false;
  String _statusMessage = 'Ready to scan.';

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _results.clear();
      _statusMessage = 'Scanning...';
    });

    final platformOS = Platform.operatingSystem;

    for (var check in _checks) {
      if (!check.appliesToOS(platformOS)) continue;

      try {
        // Run checks sequentially to update UI
        final result = await check.execute(context);
        setState(() {
          _results[check.id] = result;
        });

        // Small delay for visual effect
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        setState(() {
          _results[check.id] = CheckResult(
            status: CheckStatus.fail,
            message: 'Check failed due to error: $e',
          );
        });
      }
    }

    setState(() {
      _scanning = false;
      _statusMessage = 'Scan complete.';
    });
  }

  Future<void> _exportReport() async {
    final buffer = StringBuffer();
    buffer.writeln('HYPR Readiness Tool - Scan Report');
    buffer.writeln('Date: ${DateTime.now()}');
    buffer.writeln(
      'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    buffer.writeln('--------------------------------------------------');
    buffer.writeln('');

    for (var check in _checks) {
      if (!_results.containsKey(check.id)) continue;

      final result = _results[check.id]!;
      buffer.writeln('[${result.status.name.toUpperCase()}] ${check.title}');
      buffer.writeln('Result: ${result.message}');
      buffer.writeln('');
    }

    try {
      final fileName =
          'hypr_readiness_report_${DateTime.now().millisecondsSinceEpoch}.txt';

      final FileSaveLocation? result = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Text files', extensions: ['txt']),
        ],
      );

      if (result == null) {
        // User canceled the picker
        return;
      }

      final String path = result.path;
      final file = File(path);
      await file.writeAsString(buffer.toString());

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Report saved to $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save report: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Collect all checks that apply
    final applicableChecks = _checks
        .where((c) => c.appliesToOS(Platform.operatingSystem))
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,

      body: Column(
        children: [
          // Header / Welcome / Action

          // Header / Welcome / Action
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo - Switches based on brightness
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 60),
                    child: Image.asset(
                      Theme.of(context).brightness == Brightness.dark
                          ? 'assets/logo_dark.png'
                          : 'assets/logo_light.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'System Pre-flight Check',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Verify this machine is ready for HYPR deployment.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _scanning ? null : _startScan,
                        icon: _scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(_scanning ? 'Scanning...' : 'Start Scan'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(
                            0xFF7553e0,
                          ), // Brand Purple
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 2,
                        ),
                      ),
                    ),
                    if (!_scanning && _results.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _exportReport,
                          icon: const Icon(Icons.download),
                          label: const Text('Export Report'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _statusMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          // Results List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: applicableChecks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final check = applicableChecks[index];
                final result = _results[check.id];

                return CheckItem(check: check, result: result);
              },
            ),
          ),
        ],
      ),
    );
  }
}
