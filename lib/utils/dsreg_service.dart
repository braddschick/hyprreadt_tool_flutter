import 'cmd.dart';

class DsRegStatus {
  final String deviceName;
  final bool isDomainJoined;
  final bool isAzureAdJoined;
  final bool isEnterpriseJoined;
  final bool isAzureAdPrt;
  final bool isEnterprisePrt;
  final bool isOnPremTgt;
  final bool isCloudTgt;

  DsRegStatus({
    required this.deviceName,
    required this.isDomainJoined,
    required this.isAzureAdJoined,
    required this.isEnterpriseJoined,
    required this.isAzureAdPrt,
    required this.isEnterprisePrt,
    required this.isOnPremTgt,
    required this.isCloudTgt,
  });

  factory DsRegStatus.fromOutput(String output) {
    String? extract(String pattern) {
      final regex = RegExp(pattern, caseSensitive: false, multiLine: true);
      final match = regex.firstMatch(output);
      return match?.group(1)?.trim();
    }

    bool isYes(String? val) => val?.toUpperCase() == 'YES';

    return DsRegStatus(
      deviceName: extract(r'Device Name\s*:\s*(.*)') ?? "Unknown",
      isDomainJoined: isYes(extract(r'DomainJoined\s*:\s*(YES|NO)')),
      isAzureAdJoined: isYes(extract(r'AzureAdJoined\s*:\s*(YES|NO)')),
      isEnterpriseJoined: isYes(extract(r'EnterpriseJoined\s*:\s*(YES|NO)')),
      isAzureAdPrt: isYes(extract(r'AzureAdPrt\s*:\s*(YES|NO)')),
      isEnterprisePrt: isYes(extract(r'EnterprisePrt\s*:\s*(YES|NO)')),
      isOnPremTgt: isYes(extract(r'OnPremTgt\s*:\s*(YES|NO)')),
      isCloudTgt: isYes(extract(r'CloudTgt\s*:\s*(YES|NO)')),
    );
  }
}

class DsRegService {
  Future<DsRegStatus> getStatus() async {
    final result = await Cmd.run('dsregcmd', ['/status']);
    if (result.exitCode != 0) {
      throw Exception('Failed to run dsregcmd: ${result.stderr}');
    }
    return DsRegStatus.fromOutput(result.stdout.toString());
  }
}
