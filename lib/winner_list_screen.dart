import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Winner {
  final String id;
  final String name;
  final DateTime fechaIngreso;
  final double ventas;
  final String? referidoPor;

  Winner({
    required this.id,
    required this.name,
    required this.fechaIngreso,
    required this.ventas,
    this.referidoPor,
  });
}

class WinnerListScreen extends StatefulWidget {
  @override
  State<WinnerListScreen> createState() => _WinnerListScreenState();
}

class _WinnerListScreenState extends State<WinnerListScreen> {
  late String currentUserId;

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser!.uid;
  }

  Future<Winner> _fetchWinner(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('winners').doc(uid).get();
    final data = doc.data()!;
    return Winner(
      id: uid,
      name: data['name'],
      ventas: (data['ventasPropias'] ?? 0).toDouble(),
      fechaIngreso: DateTime.parse(data['fechaIngreso']),
      referidoPor: data['referidoPor'],
    );
  }

  Future<List<Winner>> _fetchReferidos(String parentId) async {
    final query = await FirebaseFirestore.instance
        .collection('winners')
        .where('referidoPor', isEqualTo: parentId)
        .get();
    return query.docs.map((doc) {
      final data = doc.data();
      return Winner(
        id: doc.id,
        name: data['name'],
        ventas: (data['ventasPropias'] ?? 0).toDouble(),
        fechaIngreso: DateTime.parse(data['fechaIngreso']),
        referidoPor: data['referidoPor'],
      );
    }).toList();
  }

  Future<double> _calcularComisiones(Winner w, int nivel) async {
    double total = 0;
    final meses = DateTime.now().difference(w.fechaIngreso).inDays ~/ 30;

    if (nivel == 1) {
      if (meses == 0) total += w.ventas * 0.15;
      else if (meses == 1) total += w.ventas * 0.18;
      else total += w.ventas * 0.20;
    } else if (nivel == 2) {
      total += w.ventas * 0.10;
    } else if (nivel == 3) {
      total += w.ventas * 0.07;
    } else if (nivel == 4) {
      total += w.ventas * 0.03;
    }

    final referidos = await _fetchReferidos(w.id);
    for (var ref in referidos) {
      total += await _calcularComisiones(ref, nivel + 1);
    }

    return total;
  }

  String _obtenerReconocimiento(double total, int referidos) {
    if (total > 50000 && referidos > 50) return 'Zafiro Blanco';
    if (total > 25000) return 'Zafiro Morado';
    if (total > 10000) return 'Zafiro Amarillo';
    if (total > 5000) return 'Zafiro Verde';
    return 'Sin reconocimiento';
  }

  void _verComisiones() async {
    final user = await _fetchWinner(currentUserId);
    final total = await _calcularComisiones(user, 1);
    final referidos = await _fetchReferidos(currentUserId);
    final reco = _obtenerReconocimiento(total, referidos.length);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Tus comisiones"),
        content: Text("Total: \$${total.toStringAsFixed(2)}\nReconocimiento: $reco"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK"),
          )
        ],
      ),
    );
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Mi Red"),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: Icon(Icons.logout),
          )
        ],
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _verComisiones,
          child: Text("Ver comisiones y reconocimiento"),
        ),
      ),
    );
  }
}
