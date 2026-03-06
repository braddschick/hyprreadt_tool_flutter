import 'package:flutter_test/flutter_test.dart';
import 'package:hyprready/checks/os_version.dart';
import 'package:hyprready/utils/cmd.dart';
import 'package:hyprready/checks/check.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OSVersionCheck Windows', () {
    test('Windows 10 Pro passes', () async {
      final check = OSVersionCheck(
        cmdRunner: (exec, args, {bool runInShell = false}) async {
          if (exec == 'wmic') {
            return CmdResult(
              0,
              'Caption=Microsoft Windows 10 Pro\nVersion=10.0.19045',
              '',
            );
          }
          return CmdResult(-1, '', 'Unknown command');
        },
      );

      final result = await check.checkWindows();
      expect(result.status, CheckStatus.pass);
      expect(result.message, contains('Windows 10 Pro detected'));
    });

    test('Windows 11 Pro passes', () async {
      final check = OSVersionCheck(
        cmdRunner: (exec, args, {bool runInShell = false}) async {
          if (exec == 'wmic') {
            return CmdResult(
              0,
              'Caption=Microsoft Windows 11 Pro\nVersion=10.0.22621',
              '',
            );
          }
          return CmdResult(-1, '', 'Unknown command');
        },
      );

      final result = await check.checkWindows();
      expect(result.status, CheckStatus.pass);
      expect(result.message, contains('Windows 11 Pro detected'));
    });

    test('Windows 10 Enterprise passes', () async {
      final check = OSVersionCheck(
        cmdRunner: (exec, args, {bool runInShell = false}) async {
          if (exec == 'wmic') {
            return CmdResult(
              0,
              'Caption=Microsoft Windows 10 Enterprise\nVersion=10.0.19045',
              '',
            );
          }
          return CmdResult(-1, '', 'Unknown command');
        },
      );

      final result = await check.checkWindows();
      expect(result.status, CheckStatus.pass);
      expect(result.message, contains('Windows 10 Enterprise detected'));
    });

    test('Windows 11 Enterprise passes', () async {
      final check = OSVersionCheck(
        cmdRunner: (exec, args, {bool runInShell = false}) async {
          if (exec == 'wmic') {
            return CmdResult(
              0,
              'Caption=Microsoft Windows 11 Enterprise\nVersion=10.0.22621',
              '',
            );
          }
          return CmdResult(-1, '', 'Unknown command');
        },
      );

      final result = await check.checkWindows();
      expect(result.status, CheckStatus.pass);
      expect(result.message, contains('Windows 11 Enterprise detected'));
    });

    test('Windows 10 Home fails', () async {
      final check = OSVersionCheck(
        cmdRunner: (exec, args, {bool runInShell = false}) async {
          if (exec == 'wmic') {
            return CmdResult(
              0,
              'Caption=Microsoft Windows 10 Home\nVersion=10.0.19045',
              '',
            );
          }
          return CmdResult(-1, '', 'Unknown command');
        },
      );

      final result = await check.checkWindows();
      expect(result.status, CheckStatus.fail);
      expect(
        result.message,
        contains('Windows Pro or Enterprise edition required'),
      );
    });
  });
}
