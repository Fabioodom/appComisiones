import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginRegisterScreen extends StatefulWidget {
  @override
  _LoginRegisterScreenState createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _nameController = TextEditingController();
  final _referidoController = TextEditingController();
  bool isLogin = true;

  void _submit() async {
    final email = _emailController.text.trim();
    final pass = _passController.text.trim();
    final name = _nameController.text.trim();
    final referido = _referidoController.text.trim();

    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
      } else {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
        await FirebaseFirestore.instance.collection('winners').doc(cred.user!.uid).set({
          'name': name,
          'email': email,
          'fechaIngreso': DateTime.now().toIso8601String(),
          'ventasPropias': 0.0,
          'referidoPor': referido.isNotEmpty ? referido : null,
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Login' : 'Registro')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isLogin) ...[
              TextField(controller: _nameController, decoration: InputDecoration(labelText: 'Nombre')),
              TextField(controller: _referidoController, decoration: InputDecoration(labelText: 'Código de referido (opcional)')),
            ],
            TextField(controller: _emailController, decoration: InputDecoration(labelText: 'Correo')),
            TextField(controller: _passController, obscureText: true, decoration: InputDecoration(labelText: 'Contraseña')),
            SizedBox(height: 20),
            ElevatedButton(onPressed: _submit, child: Text(isLogin ? 'Iniciar Sesión' : 'Registrarse')),
            TextButton(
              onPressed: () => setState(() => isLogin = !isLogin),
              child: Text(isLogin ? '¿No tienes cuenta? Regístrate' : '¿Ya tienes cuenta? Inicia sesión'),
            )
          ],
        ),
      ),
    );
  }
}
