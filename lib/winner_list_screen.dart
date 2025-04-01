import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'referidos_tree_screen.dart';
import 'login_register_screen.dart';


class WinnerListScreen extends StatefulWidget {
  @override
  State<WinnerListScreen> createState() => _WinnerListScreenState();
}

class _WinnerListScreenState extends State<WinnerListScreen> {
  late String currentUserId;
  String? currentUserName;
  Map<String, dynamic> ventasMensuales = {};
  Map<String, double> comisionesMensuales = {};

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser!.uid;
    _loadCurrentUser();
  }

  void _loadCurrentUser() async {
    final doc = await FirebaseFirestore.instance.collection('winners').doc(currentUserId).get();
    final ventas = doc['ventasPorMes'] ?? {};
    final comisiones = await _calcularComisionesMensuales(currentUserId);
    setState(() {
      currentUserName = doc['name'] ?? 'Usuario';
      ventasMensuales = ventas;
      comisionesMensuales = comisiones;
    });
  }

  Future<Map<String, double>> _calcularComisionesMensuales(String userId) async {
    Map<String, double> totalComisiones = {};

    Future<void> calcular(String uid, int nivel) async {
      if (nivel > 4) return;
      final query = await FirebaseFirestore.instance
          .collection('winners')
          .where('referidoPor', isEqualTo: uid)
          .get();

      for (var doc in query.docs) {
        final data = doc.data();
        final subVentas = Map<String, dynamic>.from(data['ventasPorMes'] ?? {});
        double porcentaje = nivel == 2 ? 0.10 : nivel == 3 ? 0.07 : 0.03;

        subVentas.forEach((mes, valor) {
          final val = double.tryParse(valor.toString()) ?? 0;
          totalComisiones[mes] = (totalComisiones[mes] ?? 0) + (val * porcentaje);
        });

        await calcular(doc.id, nivel + 1);
      }
    }

    await calcular(userId, 2);
    return totalComisiones;
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

  double _calcularComisiones(Winner w, int nivel) {
    double total = 0;
    final meses = DateTime.now().difference(w.fechaIngreso).inDays ~/ 30;

    if (nivel == 1) {
      if (meses == 0) total += w.ventas * 0.15;
      else if (meses == 1) total += w.ventas * 0.18;
      else total += w.ventas * 0.20;
    } else if (nivel == 2) total += w.ventas * 0.10;
    else if (nivel == 3) total += w.ventas * 0.07;
    else if (nivel == 4) total += w.ventas * 0.03;

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
    final total = _calcularComisiones(user, 1);
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
  if (mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginRegisterScreen()),
      (route) => false,
    );
  }
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

  Widget _buildSalesChart() {
    final now = DateTime.now();
    final List<FlSpot> ventasSpots = [];
    final List<FlSpot> comisionSpots = [];

    for (int i = 0; i < 12; i++) {
      final key = "${now.year}-${(i + 1).toString().padLeft(2, '0')}";
      final v = double.tryParse(ventasMensuales[key]?.toString() ?? '0') ?? 0;
      final c = comisionesMensuales[key] ?? 0;
      ventasSpots.add(FlSpot(i.toDouble(), v));
      comisionSpots.add(FlSpot(i.toDouble(), c));
    }

    return Container(
      height: 260,
      padding: EdgeInsets.all(16),
      margin: EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Resumen mensual", style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text("(${now.year}) Ventas vs Comisiones", style: TextStyle(color: Colors.teal)),
          SizedBox(height: 10),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: ventasSpots,
                    isCurved: true,
                    color: Colors.teal,
                    barWidth: 3,
                    belowBarData: BarAreaData(show: true, color: Colors.teal.withOpacity(0.2)),
                    dotData: FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: comisionSpots,
                    isCurved: true,
                    color: Colors.deepPurple,
                    barWidth: 3,
                    belowBarData: BarAreaData(show: true, color: Colors.deepPurple.withOpacity(0.15)),
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _agregarVentaMes() async {
    final controller = TextEditingController();
    final now = DateTime.now();
    final key = "${now.year}-${now.month.toString().padLeft(2, '0')}";

    final cantidad = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Registrar ventas en $key"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: "Monto a registrar"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancelar")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text("Guardar"),
          ),
        ],
      ),
    );

    if (cantidad == null || cantidad.isEmpty) return;
    final monto = double.tryParse(cantidad);
    if (monto == null) return;

    final docRef = FirebaseFirestore.instance.collection('winners').doc(currentUserId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snapshot = await tx.get(docRef);
      final ventas = Map<String, dynamic>.from(snapshot.data()?['ventasPorMes'] ?? {});
      final actual = (ventas[key] ?? 0).toDouble();
      ventas[key] = actual + monto;
      tx.update(docRef, {'ventasPorMes': ventas});
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Registrado \$${monto.toStringAsFixed(2)} para $key")),
      );
      _loadCurrentUser();
    }
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildSalesChart(),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _dashboardCard("Ver comisiones", Icons.paid, Colors.green, _verComisiones),
                _dashboardCard("Ver árbol de referidos", Icons.account_tree_outlined, Colors.blue, _abrirArbolReferidos),
                _dashboardCard("Editar mis ventas", Icons.edit_note, Colors.orange, _editarVentas),
                _dashboardCard("Añadir venta mensual", Icons.add_chart, Colors.purple, _agregarVentaMes),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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