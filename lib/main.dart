import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_register_screen.dart';
import 'winner_list_screen.dart';
import 'firebase_options.dart'; // Asegúrate de tener este archivo

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // ✅ Necesario para web
  );
  runApp(MultinivelApp());
}

class MultinivelApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'App Multinivel',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: AuthWrapper(),
      routes: {
        '/login': (context) => LoginRegisterScreen(), // para usar en logout
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) return WinnerListScreen();
        return LoginRegisterScreen();
      },
    );
  }
}
