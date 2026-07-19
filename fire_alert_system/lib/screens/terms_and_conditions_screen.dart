import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Add this to your pubspec.yaml

class TermsAndConditionsScreen extends StatefulWidget {
  final bool isAdmin;

  const TermsAndConditionsScreen({super.key, required this.isAdmin});

  @override
  State<TermsAndConditionsScreen> createState() => _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🛠️ MODERN DIALOG FOR ADDING/EDITING
  void _showTermDialog({String? docId, String? currentTitle, String? currentContent}) {
    TextEditingController titleController = TextEditingController(text: currentTitle);
    TextEditingController contentController = TextEditingController(text: currentContent);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(docId == null ? Icons.add_moderator : Icons.edit_note, color: Colors.red),
            const SizedBox(width: 10),
            Text(docId == null ? "New Policy" : "Edit Policy"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: "Title (e.g., User Responsibilities)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: contentController,
                decoration: InputDecoration(
                  labelText: "Detailed Content",
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              if (titleController.text.isEmpty || contentController.text.isEmpty) return;

              Map<String, dynamic> data = {
                'title': titleController.text.trim(),
                'content': contentController.text.trim(),
                'createdAt': FieldValue.serverTimestamp(),
              };

              if (docId == null) {
                await _firestore.collection('terms_conditions').add(data);
              } else {
                await _firestore.collection('terms_conditions').doc(docId).update({
                  'title': titleController.text.trim(),
                  'content': contentController.text.trim(),
                });
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text("Save Changes", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 🗑️ DELETE CONFIRMATION
  void _deleteTerm(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Section?"),
        content: const Text("This legal section will be removed permanently."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              await _firestore.collection('terms_conditions').doc(docId).delete();
              if (mounted) Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Light grey background for professional look
      appBar: AppBar(
        title: const Text("Legal & Policies", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        elevation: 0,
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
        backgroundColor: Colors.red,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add Section", style: TextStyle(color: Colors.white)),
        onPressed: () => _showTermDialog(),
      )
          : null,
      body: Column(
        children: [
          // Header Summary Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            decoration: const BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "Terms of Service",
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 5),
                Text(
                  "Please read these terms carefully before using the Fire Alert System.",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('terms_conditions')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.red));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.gavel_rounded, size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 10),
                        const Text("No terms defined yet.", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    String title = data['title'] ?? "Untitled";
                    String content = data['content'] ?? "";

                    // Formatting Date
                    String dateStr = "Recently";
                    if (data['createdAt'] != null) {
                      DateTime dt = (data['createdAt'] as Timestamp).toDate();
                      dateStr = DateFormat('MMM d, yyyy').format(dt);
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                      Text(
                                        "Updated: $dateStr",
                                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.isAdmin)
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 22),
                                        onPressed: () => _showTermDialog(
                                          docId: doc.id,
                                          currentTitle: title,
                                          currentContent: content,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 22),
                                        onPressed: () => _deleteTerm(doc.id),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const Divider(indent: 16, endIndent: 16),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Text(
                              content,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.6, // Increased line height for readability
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}