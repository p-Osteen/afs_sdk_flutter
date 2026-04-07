import 'dart:ui';

import 'package:afs_gateway/afs_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PremiumColors {
  static const background = Color(0xFF0A1128);
  static const cardBg = Color(0xFF1B264F);
  static const accent = Color(0xFFFFD700);
  static const textSecondary = Color(0xFFCFD8DC);
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFEF5350);
  static const accentDim = Color(0x44FFD700);
}

class _PaymentPageState extends State<PaymentPage>
    with SingleTickerProviderStateMixin {
  late final BenefitService _benefitService;

  bool _isLoading = false;
  final _amountController = TextEditingController(text: '10.500');

  String _status = 'Ready for Benefit Payment';
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    final transportalId = dotenv.env['BENEFIT_TRANSPORTAL_ID'] ?? '';
    final transportalPassword =
        dotenv.env['BENEFIT_TRANSPORTAL_PASSWORD'] ?? '';
    final resourceKey = dotenv.env['BENEFIT_RESOURCE_KEY'] ?? '';
    final isTest = dotenv.env['BENEFIT_IS_TEST']?.toLowerCase() == 'true';

    _benefitService = BenefitService(
      transportalId: transportalId,
      transportalPassword: transportalPassword,
      resourceKey: resourceKey,
      isTest: isTest,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _startBenefitPayment() async {
    if (_benefitService.transportalId.isEmpty ||
        _benefitService.transportalPassword.isEmpty ||
        _benefitService.resourceKey.isEmpty) {
      setState(() {
        _isLoading = false;
        _status = 'Configuration Error: Missing Credentials';
      });
      _showErrorDialog(
        'Please provide your BENEFIT credentials in a .env file.\n\n'
        'Check .env.example for required fields.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Initiating Benefit Payment...';
    });

    try {
      final amount = double.tryParse(_amountController.text) ?? 10.500;

      final result = await _benefitService.initiatePayment(amount: amount);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _status = 'Redirecting to Benefit...';
        });

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => BenefitPaymentView(
              paymentPageUrl: result['paymentPageUrl']!,
              benefitService: _benefitService,
              onPaymentResult: (data) {
                _handlePaymentResult(data);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
          _isLoading = false;
        });
        if (kDebugMode) {
          debugPrint('Error: $e');
        }
        _showErrorDialog('$e');
      }
    }
  }

  void _handlePaymentResult(Map<String, dynamic> data) {
    if (kDebugMode) {
      debugPrint('Payment Result: $data');
    }
    final result = data['result']?.toString().toUpperCase();
    final success = result == 'CAPTURED';

    final message = _benefitService.getResultMessage(data);

    final paymentId = data['paymentId'] ?? 'N/A';
    final transId = data['transId'] ?? 'N/A';
    final trackId = data['trackId'] ?? 'N/A';

    setState(() {
      _status = success ? 'Payment Successful 🎉' : 'Payment Failed: $message';
    });

    _showResultSheet(
      success,
      'Payment ID: $paymentId\n'
      'Transaction ID: $transId\n'
      'Track ID: $trackId\n'
      'Status: $message',
    );
  }

  void _showTestCardsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(
          color: _PremiumColors.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SANDBOX TEST CARDS',
              style: TextStyle(
                color: _PremiumColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 24),
            _buildTestCardRow('4600410123456789', 'Approved'),
            _buildTestCardRow('4550120123456789', 'Expired Card'),
            _buildTestCardRow('4415550123456789', 'Insufficient Funds'),
            _buildTestCardRow('4845550123456789', 'Invalid PIN'),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _PremiumColors.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('GOT IT'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCardRow(String number, String result) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Expected: $result',
            style: const TextStyle(color: Colors.white30, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _PremiumColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _PremiumColors.accent),
            SizedBox(width: 12),
            Text('Error', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: _PremiumColors.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: _PremiumColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _showResultSheet(bool success, String message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: const BoxDecoration(
          color: _PremiumColors.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success ? Icons.check_circle_outline : Icons.error_outline,
              color: success ? _PremiumColors.success : _PremiumColors.error,
              size: 64,
            ),
            const SizedBox(height: 24),
            Text(
              success ? 'Payment Successful' : 'Payment Failed',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _PremiumColors.textSecondary),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _PremiumColors.accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PremiumColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -80,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (_, _) => Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _PremiumColors.accent.withValues(
                    alpha: 0.03 + (_pulseController.value * 0.04),
                  ),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _PremiumColors.accentDim,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: _PremiumColors.accent,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Benefit Checkout',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Hosted Payment Gateway • BHD',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: _showTestCardsSheet,
                        icon: const Icon(
                          Icons.info_outline,
                          color: _PremiumColors.accent,
                        ),
                        tooltip: 'View Test Cards',
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: _PremiumColors.cardBg,
                      border: Border.all(
                        color: _PremiumColors.accent.withValues(alpha: .15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TRANSACTION DETAILS',
                          style: TextStyle(
                            color: _PremiumColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildTextField(
                          controller: _amountController,
                          label: 'Amount (BHD)',
                          prefixIcon: Icons.payments_outlined,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _startBenefitPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _PremiumColors.accent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: _PremiumColors.accent
                            .withValues(alpha: .3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Text(
                              'PAY WITH BENEFIT',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _status.contains('Error')
                            ? _PremiumColors.error
                            : Colors.white24,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData prefixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            prefixIcon: Icon(
              prefixIcon,
              color: _PremiumColors.accent,
              size: 20,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white12),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _PremiumColors.accent),
            ),
          ),
        ),
      ],
    );
  }
}
