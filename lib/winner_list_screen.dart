import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'referidos_tree_screen.dart';

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
  String? currentUserName;

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser!.uid;
    _loadCurrentUser();
  }

  void _loadCurrentUser() async {
    final doc = await FirebaseFirestore.instance.collection('winners').doc(currentUserId).get();
    setState(() {
      currentUserName = doc['name'] ?? 'Usuario';
    });
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

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Tus comisiones", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Total: \$${total.toStringAsFixed(2)}", style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text("Reconocimiento: $reco", style: TextStyle(fontSize: 16, color: Colors.teal)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cerrar", style: TextStyle(color: Colors.teal)),
          )
        ],
      ),
    );
  }

  void _editarVentas() async {
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Actualizar ventas"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: "Total de ventas",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(shape: StadiumBorder()),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text("Guardar"),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final ventas = double.tryParse(result);
      if (ventas != null) {
        await FirebaseFirestore.instance
            .collection('winners')
            .doc(currentUserId)
            .update({'ventasPropias': ventas});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Ventas actualizadas a \$${ventas.toStringAsFixed(2)}")),
          );
        }
      }
    }
  }

  void _abrirArbolReferidos() {
    if (currentUserName != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReferidosTreeScreen(
            rootId: currentUserId,
            rootName: currentUserName!,
          ),
        ),
      );
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text("Panel Principal", style: TextStyle(color: Colors.black)),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.black),
            onPressed: _logout,
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              _dashboardCard("Ver comisiones", Icons.paid, Colors.green, _verComisiones),
              _dashboardCard("Ver árbol de referidos", Icons.account_tree_outlined, Colors.blue, _abrirArbolReferidos),
              _dashboardCard("Editar mis ventas", Icons.edit_note, Colors.orange, _editarVentas),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            )
          ],
        ),
      ),
    );
  }
}
