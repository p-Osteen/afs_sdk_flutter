import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' hide Key;
import 'package:http/http.dart' as http;

class BenefitService {
  final String transportalId;
  final String transportalPassword;
  final String resourceKey;
  final bool isTest;

  static const String _ivString = "PGKEYENCDECIVSPC";

  String get _baseUrl => isTest
      ? "https://test.benefit-gateway.bh/payment/API/hosted.htm"
      : "https://www.benefit-gateway.bh/payment/API/hosted.htm";

  BenefitService({
    required this.transportalId,
    required this.transportalPassword,
    required this.resourceKey,
    this.isTest = true,
  });

  /// Encrypts [plainText] using AES-256-CBC and the [resourceKey].
  String encrypt(String plainText) {
    final encodedText = Uri.encodeComponent(plainText);

    final key = Key.fromUtf8(resourceKey);
    final iv = IV.fromUtf8(_ivString);

    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
    final encrypted = encrypter.encrypt(encodedText, iv: iv);

    // The gateway expects Hex string in uppercase
    return encrypted.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('')
        .toUpperCase();
  }

  /// Decrypts [hexString] using AES-256-CBC and the [resourceKey].
  String decrypt(String hexString) {
    final key = Key.fromUtf8(resourceKey);
    final iv = IV.fromUtf8(_ivString);

    final encrypted = Encrypted(Uint8List.fromList(_hexToBytes(hexString)));
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));

    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    return Uri.decodeComponent(decrypted);
  }

  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  /// Mapping of standard response codes to status messages.
  static const Map<String, String> authResponseMessages = {
    '00': 'Approved',
    '05': 'Please contact issuer',
    '14': 'Invalid card number',
    '33': 'Expired card',
    '36': 'Restricted card',
    '38': 'Allowable PIN tries exceeded',
    '51': 'Insufficient funds',
    '54': 'Expired card',
    '55': 'Incorrect PIN',
    '61': 'Exceeds withdrawal amount limit',
    '62': 'Restricted Card',
    '65': 'Exceeds withdrawal frequency limit',
    '75': 'Allowable number PIN tries exceeded',
    '76': 'Ineligible account',
    '78': 'Refer to Issuer',
    '91': 'Issuer is inoperative',
  };

  /// Resolves the final state and message from the gateway response.
  String getResultMessage(Map<String, dynamic> data) {
    final result = data['result']?.toString().toUpperCase();
    if (result == 'CAPTURED') return 'Approved';
    if (result == 'CANCELED') return 'Transaction was canceled by user';
    if (result == 'DENIED BY RISK') {
      return 'Maximum number of transactions exceeded';
    }
    if (result == 'HOST TIMEOUT') {
      return 'Unable to process transaction temporarily';
    }

    final authRespCode = data['authRespCode']?.toString();
    if (authRespCode != null &&
        authResponseMessages.containsKey(authRespCode)) {
      return authResponseMessages[authRespCode]!;
    }

    return data['error'] ?? data['result'] ?? 'Unknown Error';
  }

  /// Starts a new hosted payment session.
  Future<Map<String, String>> initiatePayment({
    required double amount,
    String? trackId,
    String? udf2,
    String? udf3,
    String? udf4,
    String? udf5,
  }) async {
    final effectiveTrackId =
        trackId ?? 'TRK_${DateTime.now().millisecondsSinceEpoch}';
    // These URLs are intercepted by the JS-Bridge; they do not need to exist
    const responseUrl = 'https://benefit.internal/success';
    const errorUrl = 'https://benefit.internal/error';

    final requestData = [
      {
        "amt": amount.toStringAsFixed(
          3,
        ), // Benefit usually uses 3 decimal places for BHD
        "action": "1",
        "password": transportalPassword,
        "id": transportalId,
        "currencycode": "048", // BHD
        "trackId": effectiveTrackId,
        "udf1": "",
        "udf2": udf2 ?? "",
        "udf3": udf3 ?? "",
        "udf4": udf4 ?? "",
        "udf5": udf5 ?? "",
        "responseURL": responseUrl,
        "errorURL": errorUrl,
      },
    ];

    final jsonPayload = jsonEncode(requestData);
    final encryptedData = encrypt(jsonPayload);

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode([
        {"id": transportalId, "trandata": encryptedData},
      ]),
    );

    if (response.statusCode == 200) {
      final List<dynamic> responseData = jsonDecode(response.body);
      if (responseData.isNotEmpty) {
        final item = responseData[0];
        if (item['status'] == "1") {
          final String result = item['result'];
          if (kDebugMode) {
            debugPrint('[BENEFIT_SERVICE] Raw result string: $result');
          }

          String pageUrl;
          String paymentId = '';

          // Case 1: Result is already a full absolute URL
          if (result.startsWith('http')) {
            pageUrl = result;
            try {
              final uri = Uri.parse(pageUrl);
              paymentId = uri.queryParameters['PaymentID'] ?? '';
            } catch (_) {}
          }
          // Case 2: Result is in "PaymentID:URL" or "PaymentID:RelativeURL" format
          else if (result.contains(':')) {
            final parts = result.split(':');
            paymentId = parts[0];
            pageUrl = parts.sublist(1).join(':');

            // If the extracted pageUrl is relative/missing scheme, fix it
            if (!pageUrl.startsWith('http')) {
              if (pageUrl.contains('.') && !pageUrl.startsWith('/')) {
                pageUrl = "https://$pageUrl";
              } else {
                final baseUri = Uri.parse(_baseUrl);
                final scheme = baseUri.scheme;
                final host = baseUri.host;
                if (pageUrl.startsWith('/')) {
                  pageUrl = "$scheme://$host$pageUrl";
                } else {
                  pageUrl = "$scheme://$host/payment/API/$pageUrl";
                }
              }
            }
          }
          // Case 3: Result is just the PaymentID (fallback)
          else {
            paymentId = result;
            pageUrl = "$_baseUrl?PaymentID=$paymentId";
          }

          // Ensure PaymentID is in the query params if missing
          if (paymentId.isNotEmpty && !pageUrl.contains('PaymentID=')) {
            pageUrl = pageUrl.contains('?')
                ? "$pageUrl&PaymentID=$paymentId"
                : "$pageUrl?PaymentID=$paymentId";
          }

          if (kDebugMode) {
            debugPrint('[BENEFIT_SERVICE] Final Payment Page URL: $pageUrl');
          }

          return {"paymentId": paymentId, "paymentPageUrl": pageUrl};
        } else {
          throw Exception(
            "Benefit Initialization Failed: ${item['errorText'] ?? 'Unknown Error'}",
          );
        }
      }
      throw Exception("Unexpected Response Format: ${response.body}");
    } else {
      throw Exception("HTTP Error ${response.statusCode}: ${response.body}");
    }
  }
}
