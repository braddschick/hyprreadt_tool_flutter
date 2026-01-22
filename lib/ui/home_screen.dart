import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../checks/check.dart';
import '../ui/widgets/check_item.dart';

import '../config/app_config.dart';
import '../checks/check_registry.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Define checks list inside the State class
  List<Check> get _checks => CheckRegistry().checks;

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
    // Include target URL in report
    buffer.writeln('Target URL: ${AppConfig().targetUrl}');
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

  Future<void> _showSettingsDialog() async {
    final TextEditingController urlController = TextEditingController(
      text: AppConfig().targetUrl,
    );
    final formKey = GlobalKey<FormState>();

    // Determine initial state
    bool isDefault = urlController.text == 'show.gethypr.com';
    // If it's default, we might want to clear the text field for UX or keep it disabled with the value.
    // Let's keep the value so they see what "Default" means, but disable input.

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Settings'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      title: const Text('Use default URL'),
                      subtitle: const Text('show.gethypr.com'),
                      value: isDefault,
                      onChanged: (bool? value) {
                        setState(() {
                          isDefault = value ?? true;
                          if (isDefault) {
                            urlController.text = 'show.gethypr.com';
                          } else {
                            // Clear it so they can type, or leave it?
                            // Standard UX: leave it or clear only if it was exactly the default.
                            // Logic: If they uncheck, they probably want to change it.
                            if (urlController.text == 'show.gethypr.com') {
                              urlController.clear();
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: urlController,
                      enabled: !isDefault,
                      decoration: const InputDecoration(
                        labelText: 'Custom HYPR URL',
                        hintText: 'acme.hypr.com',
                        helperText: 'Must be *.hypr.com or *.gethypr.com',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (isDefault)
                          return null; // No validation if using default (it's hardcoded safe)

                        if (value == null || value.isEmpty) {
                          return 'Please enter a URL';
                        }
                        if (!AppConfig.isValidUrl(value)) {
                          return 'Invalid URL. Must be *.hypr.com or *.gethypr.com';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      // If default is checked, ensure we save the default URL even if they manipulated the disabled field somehow
                      final urlToSave = isDefault
                          ? 'show.gethypr.com'
                          : urlController.text.trim();

                      await AppConfig().setTargetUrl(urlToSave);
                      if (mounted) Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
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
                Stack(
                  alignment: Alignment.center,
                  children: [
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
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: _showSettingsDialog,
                        tooltip: 'Settings',
                      ),
                    ),
                  ],
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
