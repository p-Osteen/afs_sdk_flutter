import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/benefit_service.dart';

class BenefitPaymentView extends StatefulWidget {
  final String paymentPageUrl;
  final String responseUrl;
  final String errorUrl;
  final BenefitService benefitService;
  final Function(Map<String, dynamic>) onPaymentResult;

  const BenefitPaymentView({
    super.key,
    required this.paymentPageUrl,
    required this.responseUrl,
    required this.errorUrl,
    required this.benefitService,
    required this.onPaymentResult,
  });

  @override
  State<BenefitPaymentView> createState() => _BenefitPaymentViewState();
}

class _BenefitPaymentViewState extends State<BenefitPaymentView> {
  InAppWebViewController? webViewController;
  bool _isFinished = false;

  void _finishWithResult(Map<String, dynamic> result) {
    if (_isFinished) return;
    _isFinished = true;

    if (kDebugMode) {
      debugPrint('[BENEFIT] Finishing with result: $result');
    }

    webViewController?.stopLoading();

    if (mounted) setState(() {});

    if (mounted) {
      Navigator.of(context).pop();
    }

    widget.onPaymentResult(result);
  }

  /// Evaluates [request] for redirection patterns. Returns true if intercepted.
  bool _checkRequest(URLRequest request) {
    final url = request.url;
    if (url == null) return false;
    final urlLower = url.toString().toLowerCase();

    Map<String, String> params = Map.from(url.queryParameters);

    if (request.method == 'POST' && request.body != null) {
      try {
        final bodyString = utf8.decode(request.body!);
        final bodyParams = Uri.splitQueryString(bodyString);
        params.addAll(bodyParams);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[BENEFIT_REDIRECT] Error parsing POST body: $e');
        }
      }
    }

    String? getParam(String key) {
      final k = key.toLowerCase();
      for (final entry in params.entries) {
        if (entry.key.toLowerCase() == k) return entry.value;
      }
      return null;
    }

    if (urlLower.startsWith('afs-gateway://')) {
      if (kDebugMode) {
        debugPrint('[BENEFIT] Custom scheme intercepted: $url');
      }
      if (urlLower.contains('success')) {
        final trandata = getParam('trandata');
        if (trandata != null) {
          _decryptAndFinish(Uri.decodeComponent(trandata));
        } else {
          _finishWithResult({"error": "No transaction data received"});
        }
      } else {
        final errorText = getParam('errorText') ?? 'Unknown Error';
        _finishWithResult({"error": errorText});
      }
      return true;
    }

    if (urlLower.contains('paymentcancel.htm')) {
      if (kDebugMode) {
        debugPrint('[BENEFIT] Payment cancelled by user');
      }
      final paymentId = getParam('paymentid') ?? '';
      _finishWithResult({"error": "Payment cancelled", "paymentId": paymentId});
      return true;
    }

    if (urlLower.contains('retrycancel.htm')) {
      final errorText = getParam('errorText');
      if (errorText != null) {
        if (kDebugMode) {
          debugPrint('[BENEFIT] Gateway error intercepted: $errorText');
        }
        final paymentId = getParam('paymentid') ?? '';
        _finishWithResult({"error": errorText, "paymentId": paymentId});
        return true;
      }
    }

    final responseUrl = widget.responseUrl.toLowerCase();
    final errorUrl = widget.errorUrl.toLowerCase();
    if (urlLower.startsWith(responseUrl) || urlLower.startsWith(errorUrl)) {
      if (kDebugMode) {
        debugPrint('[BENEFIT] Redirect URL matched: $url');
      }
      final trandata = getParam('trandata');
      final errorText = getParam('errorText');

      if (trandata != null) {
        _decryptAndFinish(trandata);
        return true;
      } else if (errorText != null) {
        final paymentId = getParam('paymentid') ?? '';
        _finishWithResult({"error": errorText, "paymentId": paymentId});
        return true;
      } else {
        // If it's a POST or has other query params but trandata is missing, it's an error state
        if ((request.method == 'POST' || url.hasQuery) && trandata == null) {
          // Let it load, it might be handled by the JS bridge
        }
      }
    }
    return false;
  }

  void _decryptAndFinish(String trandata) {
    try {
      final decrypted = widget.benefitService.decrypt(trandata);
      final List<dynamic> dataList = jsonDecode(decrypted);
      if (dataList.isNotEmpty) {
        _finishWithResult(dataList[0] as Map<String, dynamic>);
      } else {
        _finishWithResult({"error": "Empty transaction data"});
      }
    } catch (e) {
      _finishWithResult({"error": "Decryption failed: $e"});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Benefit Payment'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              webViewController?.stopLoading();
              Navigator.of(context).pop();
            },
          ),
        ),
        body: _isFinished
            ? const Center(child: CircularProgressIndicator())
            : InAppWebView(
                initialUrlRequest:
                    URLRequest(url: WebUri(widget.paymentPageUrl)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  allowFileAccessFromFileURLs: true,
                  allowUniversalAccessFromFileURLs: true,
                  clearCache: true,
                ),
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    source: """
                      (function() {
                        function handleForm(form) {
                          try {
                            var data = {};
                            for (var i = 0; i < form.elements.length; i++) {
                                var e = form.elements[i];
                                if (e.name) data[e.name] = e.value;
                            }
                            console.log('[BENEFIT_JS_BRIDGE] Intercepting form submission to: ' + form.action);
                            window.flutter_inappwebview.callHandler('onBenefitFormSubmit', form.action, data);
                          } catch (err) {
                            console.error('[BENEFIT_JS_BRIDGE] Error capturing form: ' + err);
                          }
                        }

                        // Intercept manual .submit() calls
                        var originalSubmit = HTMLFormElement.prototype.submit;
                        HTMLFormElement.prototype.submit = function() {
                          handleForm(this);
                          originalSubmit.apply(this);
                        };

                        // Intercept standard 'submit' events
                        window.addEventListener('submit', function(e) {
                          handleForm(e.target);
                        }, true);
                      })();
                    """,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                ]),
                onWebViewCreated: (controller) {
                  if (kDebugMode) {
                    debugPrint(
                        '[BENEFIT_WEBVIEW] Loading: ${widget.paymentPageUrl}');
                  }
                  webViewController = controller;

                  controller.addJavaScriptHandler(
                    handlerName: 'onBenefitFormSubmit',
                    callback: (args) {
                      final String action = (args[0] as String).toLowerCase();
                      final Map<String, dynamic> data =
                          Map<String, dynamic>.from(args[1] as Map);

                      if (kDebugMode) {
                        debugPrint('[BENEFIT_JS_BRIDGE] Intercepted Form Data to: $action');
                      }
                      
                      final responseUrl = widget.responseUrl.toLowerCase();
                      final errorUrl = widget.errorUrl.toLowerCase();

                      if (action.contains(responseUrl) || action.contains(errorUrl)) {
                        final trandata = data['trandata'];
                        final errorText = data['errorText'];

                        if (trandata != null) {
                          if (kDebugMode) {
                            debugPrint('[BENEFIT_JS_BRIDGE] Success: Found trandata');
                          }
                          _decryptAndFinish(trandata.toString());
                        } else if (errorText != null) {
                          if (kDebugMode) {
                            debugPrint('[BENEFIT_JS_BRIDGE] Error: Found errorText -> $errorText');
                          }
                          _finishWithResult({
                            "error": errorText,
                            "paymentId": data['paymentId'] ?? data['PaymentID'] ?? '',
                          });
                        }
                      }
                    },
                  );
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  if (_checkRequest(navigationAction.request)) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onLoadStart: (controller, url) {
                  if (url != null && !_isFinished) {
                    _checkRequest(URLRequest(url: url));
                  }
                },
                onLoadStop: (controller, url) {
                  if (url != null && !_isFinished) {
                    _checkRequest(URLRequest(url: url));
                  }
                },
                onReceivedError: (controller, request, error) {
                  if (kDebugMode) {
                    debugPrint(
                        '[BENEFIT_WEBVIEW] Error: ${error.description}');
                  }
                },
                onConsoleMessage: (controller, consoleMessage) {
                },
              ),
      ),
    );
  }
}
