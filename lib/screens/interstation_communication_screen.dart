import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InterstationCommunicationScreen extends StatefulWidget {
  final String stationName;

  const InterstationCommunicationScreen({super.key, required this.stationName});

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

    if (a == b) {
      return "${a.trim()}_${a.trim()}"; // self chat
    }

    List<String> stations = [a.trim(), b.trim()];
    stations.sort();
    return stations.join("_");
  }

  Future deleteChat(String chatId) async {
    var chatRef =
    FirebaseFirestore.instance.collection("interstation_chats").doc(chatId);

    var messages = await chatRef.collection("messages").get();

    for (var doc in messages.docs) {
      await doc.reference.delete();
    }

    await chatRef.delete();
  }

  void startNewChat(BuildContext context) async {
    var stationsSnapshot =
    await FirebaseFirestore.instance.collection("stations").get();

    // Include self for self-chat
    List<String> stations = stationsSnapshot.docs
        .map((doc) => doc["station_name"] as String)
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Start New Station Chat"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: stations.length,
              itemBuilder: (context, index) {
                String otherStation = stations[index];

                // Display "You (StationName)" for current station
                String displayName = otherStation == widget.stationName
                    ? "You (${widget.stationName})"
                    : otherStation;

                return ListTile(
                  title: Text(displayName),
                  onTap: () async {
                    Navigator.pop(context);

                    String chatId = getChatId(widget.stationName, otherStation);

                    if (chatId.isEmpty) return;

                    var chatRef = FirebaseFirestore.instance
                        .collection("interstation_chats")
                        .doc(chatId);

                    await chatRef.set({
                      "participants": [widget.stationName, otherStation],
                      "lastMessage": "",
                      "lastTimestamp": Timestamp.now(),
                      "unread_${widget.stationName}": 0,
                      "unread_$otherStation": 0,
                    }, SetOptions(merge: true));

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StationChatPage(
                          stationName: widget.stationName,
                          otherStation: otherStation,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  String? getOtherStation(String chatId) {
    List<String> stations = chatId.split("_");

    if (stations.length < 2) return null;

    // ✅ SELF CHAT DISPLAY
    if (stations[0] == widget.stationName &&
        stations[1] == widget.stationName) {
      return widget.stationName;
    }

    if (!stations.contains(widget.stationName)) return null;

    return stations.firstWhere(
          (s) => s != widget.stationName,
      orElse: () => widget.stationName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Interstation Communication"),
        backgroundColor: Colors.blue,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red,
        child: const Icon(Icons.add),
        onPressed: () => startNewChat(context),
      ),
      body: Column(
        children: [
          /// SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: "Search station...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              },
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("interstation_chats")
                  .orderBy("lastTimestamp", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var chats = snapshot.data!.docs;

                List relevantChats = chats.where((doc) {
                  String? otherStation = getOtherStation(doc.id);

                  if (otherStation == null || otherStation.isEmpty) {
                    return false;
                  }

                  return otherStation
                      .toLowerCase()
                      .contains(searchQuery);
                }).toList();

                if (relevantChats.isEmpty) {
                  return const Center(child: Text("No conversations yet"));
                }

                return ListView.builder(
                  itemCount: relevantChats.length,
                  itemBuilder: (context, index) {
                    var chatDoc = relevantChats[index];
                    var data =
                        chatDoc.data() as Map<String, dynamic>? ?? {};

                    String chatId = chatDoc.id;

                    String? otherStation = getOtherStation(chatId);

                    if (otherStation == null || otherStation.isEmpty) {
                      return const SizedBox();
                    }

                    int unreadCount =
                        data["unread_${widget.stationName}"] ?? 0;

                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.red,
                        child: Icon(Icons.local_fire_department,
                            color: Colors.white),
                      ),
                      title: SelectableText(
                        otherStation == widget.stationName
                            ? "You (${widget.stationName})"
                            : otherStation,
                      ),
                      subtitle: Text(
                        data["lastMessage"] ?? "No messages yet",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unreadCount > 0)
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.red,
                              child: Text(
                                unreadCount.toString(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                          IconButton(
                            icon:
                            const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("Delete Chat"),
                                  content: const Text(
                                      "Are you sure you want to delete this conversation?"),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context),
                                      child: const Text("Cancel"),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.pop(context);
                                        await deleteChat(chatId);
                                      },
                                      child: const Text("Delete"),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => StationChatPage(
                              stationName: widget.stationName,
                              otherStation: otherStation,
                            ),
                          ),
                        );
                      },
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

  const StationChatPage({
    super.key,
    required this.stationName,
    required this.otherStation,
  });

  @override
  State<StationChatPage> createState() => _StationChatPageState();
}

class _StationChatPageState extends State<StationChatPage> {
  final TextEditingController messageController = TextEditingController();

  String getChatId() {
    List<String> stations = [widget.stationName, widget.otherStation];
    stations.sort();
    return stations.join("_");
  }

  @override
  void initState() {
    super.initState();
    resetUnread();
  }

  void resetUnread() async {
    String chatId = getChatId();

    await FirebaseFirestore.instance
        .collection("interstation_chats")
        .doc(chatId)
        .set({
      "unread_${widget.stationName}": 0
    }, SetOptions(merge: true));
  }

  void sendMessage() async {
    if (messageController.text.trim().isEmpty) return;

    String chatId = getChatId();

    var chatRef =
    FirebaseFirestore.instance.collection("interstation_chats").doc(chatId);

    var messageRef = chatRef.collection("messages");

    await messageRef.add({
      "sender": widget.stationName,
      "text": messageController.text.trim(),
      "timestamp": Timestamp.now(),
    });

    await chatRef.set({
      "lastMessage": messageController.text.trim(),
      "lastTimestamp": Timestamp.now(),
      "unread_${widget.otherStation}": FieldValue.increment(1),
    }, SetOptions(merge: true));

    messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    String chatId = getChatId();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherStation == widget.stationName
            ? "You (${widget.stationName})"
            : widget.otherStation),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("interstation_chats")
                  .doc(chatId)
                  .collection("messages")
                  .orderBy("timestamp", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var data =
                    messages[index].data() as Map<String, dynamic>;

                    bool isMe = data["sender"] == widget.stationName;

                    String senderLabel = isMe
                        ? "You (${widget.stationName})"
                        : data["sender"] ?? "";

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue : Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              senderLabel,
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe
                                    ? Colors.white70
                                    : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              data["text"] ?? "",
                              style: TextStyle(
                                color: isMe
                                    ? Colors.white
                                    : Colors.black,
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
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    textInputAction: TextInputAction.send, // shows send button on keyboard
                    onSubmitted: (value) {
                      sendMessage();
                    },
                    decoration: const InputDecoration(
                      hintText: "Type message...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: sendMessage,
                  child: const Icon(Icons.send),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}