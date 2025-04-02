import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Referido {
  final String id;
  final String name;
  final double ventas;
  final DateTime fechaIngreso;

  Referido({
    required this.id,
    required this.name,
    required this.ventas,
    required this.fechaIngreso,
  });
}

class ReferidosTreeScreen extends StatefulWidget {
  final String rootId;
  final String rootName;

  const ReferidosTreeScreen({
    Key? key,
    required this.rootId,
    required this.rootName,
  }) : super(key: key);

  @override
  _ReferidosTreeScreenState createState() => _ReferidosTreeScreenState();
}

class _ReferidosTreeScreenState extends State<ReferidosTreeScreen> {
  /// Recupera los referidos del usuario [parentId] desde Firestore.
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

  /// Calcula la comisión en función de las ventas y el nivel.
  double calcularComision(double ventas, int nivel) {
    if (nivel == 2) return ventas * 0.10;
    if (nivel == 3) return ventas * 0.07;
    if (nivel == 4) return ventas * 0.03;
    return 0.0;
  }

  /// Construye recursivamente el árbol de referidos.
  Widget _buildReferralTree(String userId, String name, int nivel) {
    return FutureBuilder<List<Referido>>(
      future: _fetchReferidos(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final referidos = snapshot.data ?? [];

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          elevation: 2,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
            childrenPadding: const EdgeInsets.only(
                left: 16.0, right: 16.0, bottom: 8.0),
            initiallyExpanded: nivel == 1,
            leading: CircleAvatar(
              backgroundColor: const Color.fromARGB(255, 46, 161, 0),
              child: Text(
                '$nivel',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text("Referidos: ${referidos.length}"),
            children: referidos.map((ref) {
              final comision = calcularComision(ref.ventas, nivel + 1);
              return Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(ref.name),
                    subtitle: Row(
                      children: [
                        Text("Ventas: \$${ref.ventas.toStringAsFixed(2)}"),
                        const SizedBox(width: 10),
                        Text(
                            "Comisión: \$${comision.toStringAsFixed(2)}"),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                  _buildReferralTree(ref.id, ref.name, nivel + 1),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Árbol de Referidos"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: _buildReferralTree(widget.rootId, widget.rootName, 1),
      ),
    );
  }
}
