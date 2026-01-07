import 'package:flutter/material.dart';

enum CheckStatus {
  pass,
  fail,
  warning,
  manual, // For questions/survey
}

class CheckResult {
  final CheckStatus status;
  final String message;

  CheckResult({required this.status, required this.message});
}

abstract class Check {
  String get id;
  String get title;
  String get description;

  // Returns true if this check applies to the current OS
  bool appliesToOS(String os);

  Future<CheckResult> execute(BuildContext context);
}
