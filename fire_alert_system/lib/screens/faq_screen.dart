import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FAQScreen extends StatefulWidget {
  final bool isAdmin;

  const FAQScreen({super.key, this.isAdmin = false});

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  /// Modern Dialog for Adding/Editing FAQs
  void _showFAQDialog({String? id, String? q, String? a}) {
    final questionController = TextEditingController(text: q ?? "");
    final answerController = TextEditingController(text: a ?? "");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(id == null ? Icons.add_circle : Icons.edit, color: Colors.red),
            const SizedBox(width: 10),
            Text(id == null ? "Add FAQ" : "Edit FAQ"),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: questionController,
                decoration: InputDecoration(
                  labelText: "Question",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.question_answer),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 15),
              TextField(
                controller: answerController,
                decoration: InputDecoration(
                  labelText: "Answer",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.description),
                ),
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Save FAQ", style: TextStyle(color: Colors.white)),
            onPressed: () async {
              if (questionController.text.trim().isEmpty || answerController.text.trim().isEmpty) return;

              if (id == null) {
                await FirebaseFirestore.instance.collection("faqs").add({
                  "question": questionController.text.trim(),
                  "answer": answerController.text.trim(),
                  "timestamp": Timestamp.now(),
                });
              } else {
                await FirebaseFirestore.instance.collection("faqs").doc(id).update({
                  "question": questionController.text.trim(),
                  "answer": answerController.text.trim(),
                });
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _deleteFAQ(String id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete FAQ?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await FirebaseFirestore.instance.collection("faqs").doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Help Center & FAQs", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        elevation: 0,
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white, size: 28),
              onPressed: () => _showFAQDialog(),
            ),
        ],
      ),
      body: Column(
        children: [
          // Modern Header & Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search for answers...",
                prefixIcon: const Icon(Icons.search, color: Colors.red),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("faqs")
                  .orderBy("timestamp", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Colors.red));
                }

                final docs = snapshot.data!.docs.where((doc) {
                  String q = doc['question'].toString().toLowerCase();
                  String a = doc['answer'].toString().toLowerCase();
                  return q.contains(_searchQuery) || a.contains(_searchQuery);
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 10),
                        Text("No matching FAQs found", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          iconColor: Colors.red,
                          collapsedIconColor: Colors.grey,
                          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          title: Text(
                            data["question"] ?? "",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(),
                                  const SizedBox(height: 10),
                                  Text(
                                    data["answer"] ?? "",
                                    style: TextStyle(fontSize: 15, height: 1.5, color: Colors.grey[800]),
                                  ),
                                  if (widget.isAdmin) ...[
                                    const SizedBox(height: 15),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                                          label: const Text("Edit"),
                                          onPressed: () => _showFAQDialog(
                                            id: docs[index].id,
                                            q: data["question"],
                                            a: data["answer"],
                                          ),
                                        ),
                                        TextButton.icon(
                                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                          label: const Text("Delete", style: TextStyle(color: Colors.red)),
                                          onPressed: () => _deleteFAQ(docs[index].id),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
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