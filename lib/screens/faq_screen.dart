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

  void _showFAQDialog({String? id, String? q, String? a}) {
    final questionController = TextEditingController(text: q ?? "");
    final answerController = TextEditingController(text: a ?? "");

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(id == null ? "Add FAQ" : "Edit FAQ"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: questionController,
                decoration: const InputDecoration(labelText: "Question"),
              ),
              TextField(
                controller: answerController,
                decoration: const InputDecoration(labelText: "Answer"),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: const Text("Save"),
            onPressed: () async {
              if (id == null) {
                await FirebaseFirestore.instance.collection("faqs").add({
                  "question": questionController.text,
                  "answer": answerController.text,
                  "timestamp": Timestamp.now(),
                });
              } else {
                await FirebaseFirestore.instance
                    .collection("faqs")
                    .doc(id)
                    .update({
                  "question": questionController.text,
                  "answer": answerController.text,
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
    await FirebaseFirestore.instance.collection("faqs").doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("FAQs"),
        backgroundColor: Colors.green,
        actions: [
          if (widget.isAdmin)
            TextButton(
              onPressed: () => _showFAQDialog(),
              child: const Text(
                "Add FAQs",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("faqs")
            .orderBy("timestamp", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No FAQs yet"));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;

              return Card(
                child: ExpansionTile(
                  title: Text(data["question"] ?? ""),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(data["answer"] ?? ""),
                    ),

                    if (widget.isAdmin)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showFAQDialog(
                              id: docs[index].id,
                              q: data["question"],
                              a: data["answer"],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteFAQ(docs[index].id),
                          ),
                        ],
                      )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}