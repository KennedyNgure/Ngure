import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Admin page showing every ads-verified owner with their ad
/// display window: start date, stop date, and live status
/// (Active / Expired). Expired ones can be revoked here too.
class AdsVerificationTimingsPage extends StatefulWidget {
  const AdsVerificationTimingsPage({super.key});

  @override
  State<AdsVerificationTimingsPage> createState() =>
      _AdsVerificationTimingsPageState();
}

class _AdsVerificationTimingsPageState
    extends State<AdsVerificationTimingsPage> {
  static const Color _primaryGreen = Color(0xFF1FA85A);

  Future<void> _revoke(String uid) async {
    final firestore = FirebaseFirestore.instance;
    await firestore.collection('users').doc(uid).update({
      'adsverification': false,
      'adsStart': FieldValue.delete(),
      'adsStop': FieldValue.delete(),
    });

    final properties = await firestore
        .collection('properties')
        .where('ownerId', isEqualTo: uid)
        .get();

    final batch = firestore.batch();
    for (final doc in properties.docs) {
      batch.update(doc.reference, {
        'adsverification': false,
        'adsStart': FieldValue.delete(),
        'adsStop': FieldValue.delete(),
      });
    }
    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ads verification revoked.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ads Verification Timings'),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('adsverification', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _primaryGreen),
            );
          }

          final docs = snapshot.data!.docs;
          final now = DateTime.now();
          final fmt = DateFormat.yMMMd();

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No ads-verified owners yet.',
                style: TextStyle(color: Colors.black54, fontSize: 15),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, index) {
              final doc = docs[index];
              final data = doc.data();
              final name =
              (data['name'] ?? data['fullName'] ?? 'Unnamed').toString();
              final email = (data['email'] ?? '').toString();

              final adsStart = data['adsStart'];
              final adsStop = data['adsStop'];

              final DateTime? startDate =
              adsStart is Timestamp ? adsStart.toDate() : null;
              final DateTime? stopDate =
              adsStop is Timestamp ? adsStop.toDate() : null;

              final bool expired =
                  stopDate != null && stopDate.isBefore(now);
              final bool running =
                  startDate != null && stopDate != null && !expired;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                            (expired ? Colors.red : _primaryGreen)
                                .withValues(alpha: 0.10),
                            child: Icon(
                              Icons.campaign_outlined,
                              color: expired ? Colors.red : _primaryGreen,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                if (email.isNotEmpty)
                                  Text(
                                    email,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (expired ? Colors.red : _primaryGreen)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              expired
                                  ? 'EXPIRED'
                                  : running
                                  ? 'ACTIVE'
                                  : 'SCHEDULED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: expired
                                    ? Colors.red
                                    : _primaryGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.play_arrow,
                              size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            startDate != null
                                ? 'Start: ${fmt.format(startDate)}'
                                : 'Start: not set',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.stop,
                              size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            stopDate != null
                                ? 'Stop: ${fmt.format(stopDate)}'
                                : 'Stop: not set',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      if (expired) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                            onPressed: () => _revoke(doc.id),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Revoke ads verification'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}