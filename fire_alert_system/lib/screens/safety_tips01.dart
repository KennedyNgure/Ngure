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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  String? editDocId;

  /// ➕ SAVE TIP
  Future<void> saveTip() async {
    if (descController.text.trim().isEmpty) return;

    setState(() {}); // Trigger loading if needed

    try {
      if (editDocId == null) {
        await tipsRef.add({
          "description": descController.text.trim(),
          "timestamp": FieldValue.serverTimestamp(),
        });
      } else {
        await tipsRef.doc(editDocId).update({
          "description": descController.text.trim(),
        });
      }

      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar(editDocId == null ? "Tip added!" : "Tip updated!", Colors.green);

      descController.clear();
      editDocId = null;
    } catch (e) {
      _showSnackBar("Error: $e", Colors.red);
    }
  }

  /// 📝 OPEN MODERN FORM
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
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(editDocId == null ? Icons.add_moderator : Icons.edit_note, color: Colors.orange[800]),
            const SizedBox(width: 10),
            Text(editDocId == null ? "Add Safety Tip" : "Edit Safety Tip"),
          ],
        ),
        content: TextField(
          controller: descController,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: "e.g. Keep a fire extinguisher in the kitchen...",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: saveTip,
            child: const Text("Save Tip", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 🗑 DELETE TIP WITH CONFIRMATION
  void deleteTip(String id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Tip?"),
        content: const Text("Are you sure you want to remove this safety advice?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await tipsRef.doc(id).delete();
      _showSnackBar("Tip deleted", Colors.grey[700]!);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Safety Management", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange[800],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 28),
            onPressed: () => openForm(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header & Search
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 25),
            decoration: BoxDecoration(
              color: Colors.orange[800],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search safety tips...",
                prefixIcon: const Icon(Icons.search, color: Colors.orange),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: tipsRef.orderBy("timestamp", descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Colors.orange));
                }

                var docs = snapshot.data!.docs.where((doc) {
                  return doc["description"].toString().toLowerCase().contains(_searchQuery);
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.health_and_safety_outlined, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 10),
                        Text("No safety tips found", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange[50],
                          child: Icon(Icons.shield_outlined, color: Colors.orange[800], size: 20),
                        ),
                        title: Text(
                          doc["description"],
                          style: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w500),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                              onPressed: () => openForm(doc: doc),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
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
          ),
        ],
      ),
    );
  }
}