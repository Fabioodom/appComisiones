import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';

class LoginRegisterScreen extends StatefulWidget {
  const LoginRegisterScreen({super.key});

  @override
  _LoginRegisterScreenState createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  final _nameController = TextEditingController();
  final _referidoController = TextEditingController();
  bool isLogin = true;
  bool isLoading = false;

  void _submit() async {
    final email = _emailController.text.trim();
    final pass = _passController.text.trim();
    final name = _nameController.text.trim();
    final referido = _referidoController.text.trim();

    if (!isLogin && referido.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes ingresar un código de referido para registrarte.')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
        // No navegamos manualmente, el AuthWrapper detectará el login automáticamente
      } else {
        final refSnapshot = await FirebaseFirestore.instance
            .collection('winners')
            .where('codigo', isEqualTo: referido)
            .limit(1)
            .get();

        if (refSnapshot.docs.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El código de referido no es válido.')),
          );
          setState(() => isLoading = false);
          return;
        }

        final ventasController = TextEditingController();
        final now = DateTime.now();
        final key = "${now.year}-${now.month.toString().padLeft(2, '0')}";

        final cantidad = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text("¿Cuánto has vendido este mes? ($key)"),
            content: TextField(
              controller: ventasController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "Ventas iniciales en €"),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, ventasController.text.trim()),
                child: const Text("Guardar"),
              ),
            ],
          ),
        );

        final ventasValor = double.tryParse(cantidad ?? '');
        final ventasPorMes = ventasValor != null ? {key: ventasValor} : {};

        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
        await FirebaseFirestore.instance.collection('winners').doc(cred.user!.uid).set({
          'name': name,
          'email': email,
          'fechaIngreso': DateTime.now().toIso8601String(),
          'ventasPropias': ventasValor ?? 0.0,
          'ventasPorMes': ventasPorMes,
          'referidoPor': refSnapshot.docs.first.id,
        });

        // No navegamos manualmente, el AuthWrapper detectará el login automáticamente
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildTextField(TextEditingController controller, String label, {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset(
                  'assets/animations/login.json',
                  width: 160,
                  repeat: true,
                ),
                const SizedBox(height: 12),
                Text(
                  isLogin ? 'Iniciar Sesión' : 'Crear Cuenta',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                if (!isLogin) ...[
                  _buildTextField(_nameController, 'Nombre'),
                  const SizedBox(height: 16),
                  _buildTextField(_referidoController, 'Código de Winner que te invitó'),
                  const SizedBox(height: 16),
                ],
                _buildTextField(_emailController, 'Correo electrónico'),
                const SizedBox(height: 16),
                _buildTextField(_passController, 'Contraseña', isPassword: true),
                const SizedBox(height: 24),
                isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: Colors.teal,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          isLogin ? 'Entrar' : 'Registrarse',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => isLogin = !isLogin),
                  child: Text(
                    isLogin ? '¿No tienes cuenta? Regístrate' : '¿Ya tienes cuenta? Inicia sesión',
                    style: const TextStyle(color: Colors.teal),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
