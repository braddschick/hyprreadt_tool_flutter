import 'check.dart';
import 'os_version.dart';
import 'hardware.dart';
import 'environment.dart';
import 'network.dart';
import 'certificate.dart';
import 'windows_security.dart';

class CheckRegistry {
  static final CheckRegistry _instance = CheckRegistry._internal();
  factory CheckRegistry() => _instance;
  CheckRegistry._internal();

  final List<Check> _checks = [
    OSVersionCheck(),
    HardwareCheck(),
    EnvironmentCheck(),
    NetworkCheck(),
    CertificateTemplateCheck(),
    WindowsSecurityCheck(),
  ];

  List<Check> get checks => _checks;
}
