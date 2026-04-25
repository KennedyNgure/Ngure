import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SafetyTips01 extends StatefulWidget {
  const SafetyTips01({super.key});

  @override
  State<SafetyTips01> createState() => _SafetyTips01State();
}

class _SafetyTips01State extends State<SafetyTips01> {
  final CollectionReference tipsRef =
  FirebaseFirestore.instance.collection('safety_tips');

  final TextEditingController descController = TextEditingController();
  String? editDocId;

  /// ➕ SAVE TIP (ONLY DESCRIPTION)
  void saveTip() async {
    if (descController.text.isEmpty) return;

    if (editDocId == null) {
      await tipsRef.add({
        "description": descController.text,
        "timestamp": FieldValue.serverTimestamp(),
      });
    } else {
      await tipsRef.doc(editDocId).update({
        "description": descController.text,
      });
    }

    descController.clear();
    editDocId = null;

    if (!mounted) return;
    Navigator.pop(context);
  }

  /// 📝 OPEN FORM
  void openForm({DocumentSnapshot? doc}) {
    if (doc != null) {
      descController.text = doc["description"];
      editDocId = doc.id;
    } else {
      descController.clear();
      editDocId = null;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(editDocId == null ? "Add Safety Tip" : "Edit Safety Tip"),
        content: TextField(
          controller: descController,
          decoration: const InputDecoration(
            labelText: "Enter safety tip description",
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: saveTip,
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  /// 🗑 DELETE TIP
  void deleteTip(String id) async {
    await tipsRef.doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Safety Tips"),
        backgroundColor: Colors.green,

        /// 🔥 TEXT BUTTON INSTEAD OF "+"
        actions: [
          TextButton(
            onPressed: () => openForm(),
            child: const Text(
              "Add Safety Tip",
              style: TextStyle(color: Colors.white),
            ),
          )
        ],
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: tipsRef.orderBy("timestamp", descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No safety tips available"));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var doc = docs[index];

              return Card(
                margin: const EdgeInsets.all(10),
                child: ListTile(
                  title: Text(doc["description"]),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => openForm(doc: doc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => deleteTip(doc.id),
                      ),
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
