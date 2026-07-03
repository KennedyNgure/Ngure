import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {

  static Future<String?> getDeviceToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    print("FCM Token: $token");
    return token;
  }

}