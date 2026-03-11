import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future registerUser(String email, String password, String role) async {

    UserCredential userCredential =
    await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userCredential.user!.uid)
        .set({
      'email': email,
      'role': role
    });
  }

  Future loginUser(String email, String password) async {

    UserCredential userCredential =
    await _auth.signInWithEmailAndPassword(
        email: email,
        password: password);

    return userCredential.user!.uid;
  }

}