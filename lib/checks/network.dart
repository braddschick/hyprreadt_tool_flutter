import 'package:flutter/material.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'check.dart';

import '../config/app_config.dart';

class NetworkCheck extends Check {
  String get _host {
    String? url = AppConfig().targetUrl;
    if (url == null) {
      url = AppConfig.defaultTargetUrl;
    }
    // Strip scheme if present to ensure we have a raw hostname for SecureSocket
    if (url.startsWith('https://') || url.startsWith('http://')) {
      try {
        return Uri.parse(url).host;
      } catch (e) {
        // Fallback or let it fail later if parse fails
      }
    }
    return url;
  }

  static const int _port = 443;
  static const List<String> _validPinningHashes = [
    'Eyf4LHdUkuN5SJPZlO8OwetAmP3pNDvv3S/FH1ajZZQ=',
    '18tkPyr2nckv4fgo0dhAkaUtJ2hu2831xlO2SKhq8dg=',
    '++MBgDH5WGvL9Bcn5Be30cRcL0f5O+NyoXuWtQdX1aI=',
    'Nx3GmQ2soqxY/+CZNbJN+gkJbY6Oc7pRZPfZcf3u71M=', // *.hypr.com (bayview)
  ];

  @override
  String get id => 'NETWORK_01';

  @override
  String get title => 'Network Connectivity & SSL Pinning';

  @override
  String get description =>
      'Verifies HTTPS connectivity to $_host and validates SSL certificate pinning';

  @override
  bool appliesToOS(String os) {
    return true;
  }

  @override
  Future<CheckResult> execute([BuildContext? context]) async {
    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect(
        _host,
        _port,
        timeout: const Duration(seconds: 10),
      );

      final cert = socket.peerCertificate;
      if (cert == null) {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'No peer certificates received from server.',
        );
      }

      // Extract SPKI from DER
      Uint8List? spkiBytes;
      try {
        spkiBytes = _extractSPKI(cert.der);
      } catch (e) {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'Failed to parse certificate for pinning: $e',
        );
      }

      if (spkiBytes == null) {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'Could not locate SubjectPublicKeyInfo in certificate.',
        );
      }

      // SHA256 Hash
      final digest = sha256.convert(spkiBytes);
      final hashBase64 = base64.encode(digest.bytes);

      // Check both hardcoded and configured valid hashes
      final configHashes = AppConfig().validPinningHashes ?? [];
      final validHashes = [..._validPinningHashes, ...configHashes];

      // Verify
      if (validHashes.contains(hashBase64)) {
        return CheckResult(
          status: CheckStatus.pass,
          message:
              'Successfully connected to $_host and verified SSL pinning (Hash: $hashBase64).',
        );
      } else {
        return CheckResult(
          status: CheckStatus.fail,
          message: 'SSL Pinning Mismatch. Server hash: $hashBase64',
        );
      }
    } catch (e) {
      return CheckResult(
        status: CheckStatus.fail,
        message: 'Cannot establish TLS connection to $_host. Error: $e',
      );
    } finally {
      socket?.destroy();
    }
  }

  /// Minimal ASN.1 parser to extract SubjectPublicKeyInfo from X.509 Certificate
  /// Returns the raw bytes of the SubjectPublicKeyInfo sequence
  Uint8List? _extractSPKI(Uint8List der) {
    // Helper to read length and return (length_value, bytes_consumed_for_header)
    (int, int) readLength(Uint8List data, int offset) {
      if (offset >= data.length) throw Exception('Unexpected EOF');
      int b = data[offset];
      if ((b & 0x80) == 0) {
        return (b, 1); // Short form
      } else {
        int numBytes = b & 0x7F;
        if (numBytes == 0 || numBytes > 4) throw Exception('Invalid length');
        int len = 0;
        for (int i = 0; i < numBytes; i++) {
          if (offset + 1 + i >= data.length) throw Exception('Unexpected EOF');
          len = (len << 8) | data[offset + 1 + i];
        }
        return (len, 1 + numBytes);
      }
    }

    int offset = 0;

    // 1. Certificate SEQUENCE
    if (der[offset++] != 0x30) throw Exception('Not a SEQUENCE');
    var (_, headerLen) = readLength(der, offset);
    offset += headerLen;

    // 2. TBSCertificate SEQUENCE
    if (der[offset++] != 0x30) throw Exception('Not a SEQUENCE (TBS)');
    (_, headerLen) = readLength(der, offset);
    offset += headerLen;

    // Inside TBSCertificate:
    // [0] EXPLICIT Version OPTIONAL (Tag 0xA0)
    if ((der[offset] & 0xF0) == 0xA0) {
      // Skip Version
      offset++; // Tag
      var (vLen, vHeadLen) = readLength(der, offset);
      offset += vHeadLen + vLen;
    }

    // Serial Number (Integer: 0x02)
    if (der[offset++] != 0x02) throw Exception('Expected Serial Number');
    var (sLen, sHeadLen) = readLength(der, offset);
    offset += sHeadLen + sLen;

    // Signature (Sequence: 0x30)
    if (der[offset++] != 0x30) throw Exception('Expected Signature');
    var (sigLen, sigHeadLen) = readLength(der, offset);
    offset += sigHeadLen + sigLen;

    // Issuer (Sequence: 0x30)
    if (der[offset++] != 0x30) throw Exception('Expected Issuer');
    var (issLen, issHeadLen) = readLength(der, offset);
    offset += issHeadLen + issLen;

    // Validity (Sequence: 0x30)
    if (der[offset++] != 0x30) throw Exception('Expected Validity');
    var (valLen, valHeadLen) = readLength(der, offset);
    offset += valHeadLen + valLen;

    // Subject (Sequence: 0x30)
    if (der[offset++] != 0x30) throw Exception('Expected Subject');
    var (subLen, subHeadLen) = readLength(der, offset);
    offset += subHeadLen + subLen;

    // SubjectPublicKeyInfo (Sequence: 0x30) - THIS IS IT
    if (der[offset] != 0x30) throw Exception('Expected SubjectPublicKeyInfo');

    // We want to capture this entire sequence (Tag + Length + Value)
    int spkiStart = offset;
    offset++; // Tag
    var (spkiLen, spkiHeadLen) = readLength(der, offset);
    int totalSpkiLen = 1 + spkiHeadLen + spkiLen;

    return der.sublist(spkiStart, spkiStart + totalSpkiLen);
  }
}
