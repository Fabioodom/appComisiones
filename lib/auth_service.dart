import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<User?> register(String name, String email, String password) async {
    final userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    await _db.collection('winners').doc(userCredential.user!.uid).set({
      'name': name,
      'email': email,
      'fechaIngreso': DateTime.now().toIso8601String(),
      'ventasPropias': 0.0,
      'referidos': [],
      'nivel': 1,
    });
    return userCredential.user;
  }

  Future<User?> login(String email, String password) async {
    final userCredential = await _auth.signInWithEmailAndPassword(email: email, password: password);
    return userCredential.user;
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  Stream<User?> get user => _auth.authStateChanges();
}
