import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
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

  // Variable para guardar el rango de fechas seleccionado
  DateTimeRange? _rangoFechas;
  // GlobalKey para el icono del calendario
  final GlobalKey _calendarIconKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser!.uid;
    _loadCurrentUser();

    // Mostramos el hint del calendario sutilmente cuando se cargue la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showCalendarHint();
    });
  }

  // Método para mostrar un overlay con el mensaje (posición ajustada para no salirse de la pantalla)
  void _showCalendarHint() {
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    RenderBox renderBox = _calendarIconKey.currentContext?.findRenderObject() as RenderBox;
    Offset position = renderBox.localToGlobal(Offset.zero);
    Size size = renderBox.size;

    double leftPos = position.dx - 100;
    if (leftPos < 0) leftPos = 0;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: position.dy + size.height + 5,
        left: leftPos,
        child: Material(
          color: Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Cambia el rango de fechas',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              SizedBox(width: 5),
              Icon(Icons.arrow_forward, color: Colors.black54, size: 20),
            ],
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
    Future.delayed(Duration(seconds: 3), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _loadCurrentUser() async {
    final doc = await FirebaseFirestore.instance
        .collection('winners')
        .doc(currentUserId)
        .get();
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
      if (meses == 0)
        total += w.ventas * 0.15;
      else if (meses == 1)
        total += w.ventas * 0.18;
      else
        total += w.ventas * 0.20;
    } else if (nivel == 2)
      total += w.ventas * 0.10;
    else if (nivel == 3)
      total += w.ventas * 0.07;
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 160,
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.85), color.withOpacity(0.65)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Colors.white),
            SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
            )
          ],
        ),
      ),
    );
  }

  // Selección del rango de fechas
  void _seleccionarRangoFechas() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _rangoFechas ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
    );

    if (rango != null) {
      setState(() {
        _rangoFechas = rango;
      });
    }
  }

  // Construcción del gráfico de ventas y comisiones filtrado por rango
  Widget _buildSalesChart() {
    final now = DateTime.now();
    final DateTime startDate = _rangoFechas?.start ?? DateTime(now.year, now.month - 11, 1);
    final DateTime endDate = _rangoFechas?.end ?? now;

    final List<DateTime> monthsInRange = [];
    DateTime cursor = DateTime(startDate.year, startDate.month, 1);
    while (!cursor.isAfter(endDate)) {
      monthsInRange.add(cursor);
      if (cursor.month == 12) {
        cursor = DateTime(cursor.year + 1, 1, 1);
      } else {
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
    }

    final List<FlSpot> ventasSpots = [];
    final List<FlSpot> comisionSpots = [];

    for (int i = 0; i < monthsInRange.length; i++) {
      final m = monthsInRange[i];
      final key = "${m.year}-${m.month.toString().padLeft(2, '0')}";
      final v = double.tryParse(ventasMensuales[key]?.toString() ?? '0') ?? 0;
      final c = comisionesMensuales[key] ?? 0;
      ventasSpots.add(FlSpot(i.toDouble(), v));
      comisionSpots.add(FlSpot(i.toDouble(), c));
    }

    String lastKey = "";
    double currentSales = 0;
    double currentCommission = 0;
    if (monthsInRange.isNotEmpty) {
      final lastDate = monthsInRange.last;
      lastKey = "${lastDate.year}-${lastDate.month.toString().padLeft(2, '0')}";
      currentSales = double.tryParse(ventasMensuales[lastKey]?.toString() ?? '0') ?? 0;
      currentCommission = comisionesMensuales[lastKey] ?? 0;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _rangoFechas != null
                ? "${DateFormat('dd/MM/yyyy').format(_rangoFechas!.start)} - ${DateFormat('dd/MM/yyyy').format(_rangoFechas!.end)}"
                : "Gráfico de Ventas y Comisiones",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Ventas", style: TextStyle(fontSize: 16, color: Color.fromARGB(255, 47, 202, 0))),
                  SizedBox(height: 4),
                  Text(
                    "\$${currentSales.toStringAsFixed(2)}",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Comisiones", style: TextStyle(fontSize: 16, color: Color.fromARGB(255, 179, 211, 0))),
                  SizedBox(height: 4),
                  Text(
                    "\$${currentCommission.toStringAsFixed(2)}",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.white,
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          "\$${spot.y.toStringAsFixed(2)}",
                          TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withOpacity(0.2),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= monthsInRange.length) {
                          return const SizedBox();
                        }
                        final date = monthsInRange[index];
                        final monthString = DateFormat('MMM').format(date);
                        return Text(monthString.toUpperCase());
                      },
                    ),
                  ),
                ),
                minY: 0,
                lineBarsData: [
                  // Línea de Ventas
                  LineChartBarData(
                    spots: ventasSpots,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [Color.fromARGB(255, 9, 255, 0), Color.fromARGB(255, 3, 255, 45)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    barWidth: 4,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color.fromARGB(255, 3, 255, 36).withOpacity(0.2),
                          const Color.fromARGB(255, 0, 231, 19).withOpacity(0.2),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  // Línea de Comisiones
                  LineChartBarData(
                    spots: comisionSpots,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [Color.fromARGB(255, 229, 255, 0), Color.fromARGB(255, 232, 236, 1)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    barWidth: 4,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color.fromARGB(255, 87, 119, 0).withOpacity(0.2),
                          const Color.fromARGB(255, 159, 161, 4).withOpacity(0.2),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
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
      backgroundColor: Color.fromARGB(255, 250, 251, 249),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color.fromARGB(255, 249, 253, 1), Color.fromARGB(255, 52, 163, 0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text("Panel Principal", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            key: _calendarIconKey,
            icon: Icon(Icons.date_range, color: Colors.white),
            onPressed: _seleccionarRangoFechas,
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
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
                _dashboardCard("Calculo Reconocimiento", Icons.edit_note, Colors.orange, _editarVentas),
                _dashboardCard("Añadir venta", Icons.add_chart, Colors.purple, _agregarVentaMes),
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
