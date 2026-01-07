import 'dart:io';
import 'dart:convert';

class CmdResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  CmdResult(this.exitCode, this.stdout, this.stderr);
}

class Cmd {
  static Future<CmdResult> run(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        runInShell: runInShell,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return CmdResult(
        result.exitCode,
        result.stdout.toString().trim(),
        result.stderr.toString().trim(),
      );
    } catch (e) {
      return CmdResult(-1, '', e.toString());
    }
  }
}
