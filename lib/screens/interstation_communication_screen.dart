import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InterstationCommunicationScreen extends StatelessWidget {
  final String stationName;

  const InterstationCommunicationScreen({super.key, required this.stationName});

  String getChatId(String a, String b) {
    List stations = [a, b];
    stations.sort();
    return stations.join("_");
  }

  void startNewChat(BuildContext context) async {

    var stationsSnapshot =
    await FirebaseFirestore.instance.collection("stations").get();

    List<String> stations = stationsSnapshot.docs
        .map((doc) => doc["station_name"] as String)
        .where((name) => name != stationName)
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

                return ListTile(
                  title: Text(otherStation),
                  onTap: () async {
                    Navigator.pop(context);

                    String chatId = getChatId(stationName, otherStation);

                    var chatRef = FirebaseFirestore.instance
                        .collection("interstation_chats")
                        .doc(chatId);

                    await chatRef.set({
                      "participants": [stationName, otherStation],
                      "lastMessage": "",
                      "lastTimestamp": Timestamp.now(),
                      "unread_$stationName": 0,
                      "unread_$otherStation": 0,
                    }, SetOptions(merge: true));

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StationChatPage(
                          stationName: stationName,
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

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("interstation_chats")
            .orderBy("lastTimestamp", descending: true)
            .snapshots(),
        builder: (context, snapshot) {

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var chats = snapshot.data!.docs;

          List relevantChats =
          chats.where((doc) => doc.id.contains(stationName)).toList();

          if (relevantChats.isEmpty) {
            return const Center(child: Text("No conversations yet"));
          }

          return ListView.builder(
            itemCount: relevantChats.length,
            itemBuilder: (context, index) {

              var chatDoc = relevantChats[index];
              var data = chatDoc.data() as Map<String, dynamic>? ?? {};

              String chatId = chatDoc.id;

              List stations = chatId.split("_");

              String otherStation =
              stations.firstWhere((s) => s != stationName);

              int unreadCount = data["unread_$stationName"] ?? 0;

              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.red,
                  child: Icon(Icons.local_fire_department,
                      color: Colors.white),
                ),

                title: Text(otherStation),

                subtitle: Text(
                  data["lastMessage"] ?? "No messages yet",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                trailing: unreadCount > 0
                    ? CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.red,
                  child: Text(
                    unreadCount.toString(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12),
                  ),
                )
                    : null,

                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StationChatPage(
                        stationName: stationName,
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
    List stations = [widget.stationName, widget.otherStation];
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
        title: Text(widget.otherStation),
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

                    return Align(
                      alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue : Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          data["text"] ?? "",
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black,
                          ),
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