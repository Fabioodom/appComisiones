import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Referido {
  final String id;
  final String name;
  final double ventas;
  final DateTime fechaIngreso;

  Referido({required this.id, required this.name, required this.ventas, required this.fechaIngreso});
}

class ReferidosTreeScreen extends StatefulWidget {
  final String rootId;
  final String rootName;

  ReferidosTreeScreen({required this.rootId, required this.rootName});

  @override
  _ReferidosTreeScreenState createState() => _ReferidosTreeScreenState();
}

class _ReferidosTreeScreenState extends State<ReferidosTreeScreen> {
  Future<List<Referido>> _fetchReferidos(String parentId) async {
    final query = await FirebaseFirestore.instance
        .collection('winners')
        .where('referidoPor', isEqualTo: parentId)
        .get();

    return query.docs.map((doc) {
      final data = doc.data();
      return Referido(
        id: doc.id,
        name: data['name'],
        ventas: (data['ventasPropias'] ?? 0.0).toDouble(),
        fechaIngreso: DateTime.parse(data['fechaIngreso']),
      );
    }).toList();
  }

  Widget _buildTree(String userId, String name, [int nivel = 1]) {
    return FutureBuilder<List<Referido>>(
      future: _fetchReferidos(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListTile(title: Text("Cargando referidos de $name..."));
        }
        final referidos = snapshot.data ?? [];

        return ExpansionTile(
          title: Text("$name (Nivel $nivel)"),
          subtitle: Text("Referidos: ${referidos.length}"),
          children: referidos.map((r) => _buildTree(r.id, r.name, nivel + 1)).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Árbol de Referidos")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _buildTree(widget.rootId, widget.rootName),
        ),
      ),
    );
  }
}

// Cómo usar esta pantalla desde otra:
// Navigator.push(
//   context,
//   MaterialPageRoute(
//     builder: (_) => ReferidosTreeScreen(
//       rootId: FirebaseAuth.instance.currentUser!.uid,
//       rootName: 'Tu Nombre o desde Firestore',
//     ),
//   ),
// );
