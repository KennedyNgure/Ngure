import 'package:flutter/material.dart';

class SafetyPage extends StatelessWidget {
  const SafetyPage({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          'Property Safety',
        ),

        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [

            const Icon(
              Icons.shield_rounded,
              size: 60,
              color: Color(0xFF1565C0),
            ),

            const SizedBox(height: 15),

            const Text(
              'Stay safe while searching for property',
              style:
              TextStyle(
                fontSize: 27,
                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'A few simple precautions can help make '
                  'your property search safer and more comfortable.',

              style:
              TextStyle(
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 30),

            _tip(
              icon: Icons.visibility_outlined,
              title: 'View the property first',
              text:
              'Personally tour the property before '
                  'sending money or committing to a transaction.',
            ),

            _tip(
              icon: Icons.person_outline,
              title: 'Know who you are dealing with',
              text:
              'Communicate clearly with the property owner '
                  'or relevant contact and ask questions about '
                  'the property.',
            ),

            _tip(
              icon: Icons.receipt_long_outlined,
              title: 'Understand the transaction',
              text:
              'Make sure you understand the price, terms, '
                  'deposit, rent or purchase arrangements before '
                  'making a payment.',
            ),

            _tip(
              icon: Icons.warning_amber_rounded,
              title: 'Be cautious of unusual requests',
              text:
              'Take extra care if someone pressures you to '
                  'send money quickly or asks you to bypass the '
                  'normal viewing or transaction process.',
            ),

            _tip(
              icon: Icons.flag_outlined,
              title: 'Report suspicious listings',
              text:
              'If a property listing or transaction seems '
                  'suspicious, use the report option available '
                  'on the property details page.',
            ),

            const SizedBox(height: 25),

            Container(
              padding:
              const EdgeInsets.all(18),

              decoration:
              BoxDecoration(
                color:
                const Color(0xFFEAF3FF),

                borderRadius:
                BorderRadius.circular(18),
              ),

              child: const Text(
                'Remember: A property listing is the beginning '
                    'of your search. Take time to view the property '
                    'and understand the transaction before sending money.',
                style:
                TextStyle(
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tip({
    required IconData icon,
    required String title,
    required String text,
  }) {

    return Padding(
      padding:
      const EdgeInsets.only(bottom: 20),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [

          Container(
            width: 48,
            height: 48,

            decoration:
            BoxDecoration(
              color:
              const Color(0xFFEAF3FF),

              borderRadius:
              BorderRadius.circular(14),
            ),

            child: Icon(
              icon,
              color:
              const Color(0xFF1565C0),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [

                Text(
                  title,

                  style:
                  const TextStyle(
                    fontSize: 16,
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  text,

                  style:
                  TextStyle(
                    color:
                    Colors.grey.shade700,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}