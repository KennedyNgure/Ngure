import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class InterstationCommunicationScreen extends StatefulWidget {
  final String stationName;

  const InterstationCommunicationScreen({
    super.key,
    required this.stationName,
  });

  @override
  State<InterstationCommunicationScreen> createState() =>
      _InterstationCommunicationScreenState();
}

class _InterstationCommunicationScreenState
    extends State<InterstationCommunicationScreen> {
  TextEditingController searchController = TextEditingController();
  String searchQuery = "";

  String getChatId(String a, String b) {
    if (a.trim().isEmpty || b.trim().isEmpty) return "";
    List<String> stations = [a.trim(), b.trim()];
    stations.sort();
    return stations.join("_");
  }

  /// 🗑️ DELETE FULL CONVERSATION
  Future<void> _confirmDeleteChat(String chatId) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Conversation?"),
        content: const Text("All messages in this chat will be permanently removed."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ??
        false;

    if (confirm) {
      var chatRef = FirebaseFirestore.instance.collection("interstation_chats").doc(chatId);
      var messages = await chatRef.collection("messages").get();
      for (var doc in messages.docs) {
        await doc.reference.delete();
      }
      await chatRef.delete();
    }
  }

  void startNewChat(BuildContext context) async {
    var stationsSnapshot = await FirebaseFirestore.instance
        .collection("stations")
        .where("status", isEqualTo: "verified")
        .where("role", isEqualTo: "station")
        .get();

    List<String> stations = stationsSnapshot.docs.map((doc) => doc["station_name"] as String).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Start New Chat", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: stations.length,
                itemBuilder: (context, index) {
                  String other = stations[index];
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.blue[100], child: const Icon(Icons.fire_truck, color: Colors.blue)),
                    title: Text(other == widget.stationName ? "You ($other)" : other),
                    onTap: () async {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => StationChatPage(stationName: widget.stationName, otherStation: other)));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? getOtherStation(String chatId) {
    List<String> stations = chatId.split("_");
    if (stations.length < 2) return null;
    if (stations[0] == widget.stationName && stations[1] == widget.stationName) return widget.stationName;
    return stations.firstWhere((s) => s != widget.stationName, orElse: () => widget.stationName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Station Comms", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.blue[800],
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red,
        child: const Icon(Icons.message, color: Colors.white),
        onPressed: () => startNewChat(context),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            decoration: BoxDecoration(
              color: Colors.blue[800],
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
            ),
            child: TextField(
              controller: searchController,
              onChanged: (v) => setState(() => searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search conversations...",
                prefixIcon: const Icon(Icons.search, color: Colors.blue),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("interstation_chats")
                  .orderBy("lastTimestamp", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var filtered = snapshot.data!.docs.where((doc) {
                  String? other = getOtherStation(doc.id);
                  return other != null && other.toLowerCase().contains(searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 10),
                          Text("No messages yet", style: TextStyle(color: Colors.grey[600])),
                        ],
                      ));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    var data = filtered[index].data() as Map<String, dynamic>;
                    String chatId = filtered[index].id;
                    String other = getOtherStation(chatId)!;
                    int unread = data["unread_${widget.stationName}"] ?? 0;

                    DateTime? lastTime = data["lastTimestamp"]?.toDate();
                    String timeStr = lastTime != null ? DateFormat("HH:mm").format(lastTime) : "";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[50],
                          child: const Icon(Icons.fire_truck, color: Colors.blue),
                        ),
                        title: Text(other == widget.stationName ? "You ($other)" : other,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(data["lastMessage"] ?? "...", maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            const SizedBox(height: 5),
                            if (unread > 0)
                              CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.red,
                                  child: Text(unread.toString(),
                                      style: const TextStyle(color: Colors.white, fontSize: 10))),
                          ],
                        ),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => StationChatPage(stationName: widget.stationName, otherStation: other))),
                        onLongPress: () => _confirmDeleteChat(chatId),
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

class StationChatPage extends StatefulWidget {
  final String stationName;
  final String otherStation;

  const StationChatPage({super.key, required this.stationName, required this.otherStation});

  @override
  State<StationChatPage> createState() => _StationChatPageState();
}

class _StationChatPageState extends State<StationChatPage> {
  final TextEditingController messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String getChatId() {
    List<String> stations = [widget.stationName, widget.otherStation];
    stations.sort();
    return stations.join("_");
  }

  @override
  void initState() {
    super.initState();
    _resetUnread();
  }

  void _resetUnread() {
    FirebaseFirestore.instance
        .collection("interstation_chats")
        .doc(getChatId())
        .set({"unread_${widget.stationName}": 0}, SetOptions(merge: true));
  }

  void sendMessage() async {
    if (messageController.text.trim().isEmpty) return;
    String text = messageController.text.trim();
    messageController.clear();

    String chatId = getChatId();
    await FirebaseFirestore.instance.collection("interstation_chats").doc(chatId).collection("messages").add({
      "sender": widget.stationName,
      "text": text,
      "timestamp": FieldValue.serverTimestamp(),
      "isPinned": false,
    });

    await FirebaseFirestore.instance.collection("interstation_chats").doc(chatId).set({
      "lastMessage": text,
      "lastTimestamp": FieldValue.serverTimestamp(),
      "unread_${widget.otherStation}": FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  /// ✏️ EDIT MESSAGE
  void _editMessage(String docId, String currentText) {
    TextEditingController editController = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Message"),
        content: TextField(controller: editController, decoration: const InputDecoration(hintText: "Update message...")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance
                  .collection("interstation_chats")
                  .doc(getChatId())
                  .collection("messages")
                  .doc(docId)
                  .update({"text": editController.text.trim(), "isEdited": true});
              Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  /// 🗑️ DELETE MESSAGE
  void _deleteMessage(String docId) {
    FirebaseFirestore.instance
        .collection("interstation_chats")
        .doc(getChatId())
        .collection("messages")
        .doc(docId)
        .delete();
  }

  /// 📌 PIN MESSAGE
  void _togglePin(String docId, bool currentPinStatus) {
    FirebaseFirestore.instance
        .collection("interstation_chats")
        .doc(getChatId())
        .collection("messages")
        .doc(docId)
        .update({"isPinned": !currentPinStatus});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: Colors.blue[800],
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.otherStation == widget.stationName ? "You" : widget.otherStation,
            style: const TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("interstation_chats")
                  .doc(getChatId())
                  .collection("messages")
                  .orderBy("timestamp", descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var doc = messages[index];
                    var data = doc.data() as Map<String, dynamic>;
                    bool isMe = data["sender"] == widget.stationName;
                    bool isPinned = data["isPinned"] ?? false;
                    bool isEdited = data["isEdited"] ?? false;
                    DateTime? time = data["timestamp"]?.toDate();

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.only(left: 12, right: 8, top: 8, bottom: 4),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(15),
                            topRight: const Radius.circular(15),
                            bottomLeft: Radius.circular(isMe ? 15 : 0),
                            bottomRight: Radius.circular(isMe ? 0 : 15),
                          ),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isPinned)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Icon(Icons.push_pin, size: 12, color: Colors.grey),
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  child: Text(
                                    data["text"] ?? "",
                                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                // THE DROP DOWN MENU (Like WhatsApp)
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 20),
                                    onSelected: (value) {
                                      if (value == 'edit') _editMessage(doc.id, data["text"]);
                                      if (value == 'delete') _deleteMessage(doc.id);
                                      if (value == 'pin') _togglePin(doc.id, isPinned);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'edit', child: Text("Edit")),
                                      const PopupMenuItem(value: 'delete', child: Text("Delete")),
                                      PopupMenuItem(value: 'pin', child: Text(isPinned ? "Unpin" : "Pin")),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isEdited)
                                  const Text("edited ", style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
                                Text(
                                  time != null ? DateFormat("HH:mm").format(time) : "",
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                ),
                              ],
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
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.blue[800],
                    child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: sendMessage),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}