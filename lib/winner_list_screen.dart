import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // Para usar kIsWeb y compute
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'referidos_tree_screen.dart';
import 'login_register_screen.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:html' as html;
import 'html_helper.dart'
  if (dart.library.html) 'html_helper_web.dart';

/// Función auxiliar para abreviar números.
String formatAbbreviated(double number) {
  if (number >= 1000000) {
    double n = number / 1000000;
    return '${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 1)}M';
  } else if (number >= 1000) {
    double n = number / 1000;
    return '${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 1)}K';
  } else {
    return number.toStringAsFixed(0);
  }
}

/// Función que genera los bytes del Excel a partir de la lista de usuarios.
/// Se ejecuta en un isolate.
Uint8List generarExcelBytes(List<Map<String, dynamic>> usuarios) {
  final excel = Excel.createExcel();
  final Sheet sheet = excel.sheets['Sheet1']!;

  // Agregar encabezados
  sheet.appendRow([
    'ID',
    'Nombre',
    'Ventas Propias',
    'Fecha de Ingreso',
    'Referido Por',
  ]);

  // Agregar una fila por cada usuario, forzando conversión a String
  for (var usuario in usuarios) {
    sheet.appendRow([
      usuario['id']?.toString() ?? '',
      usuario['name']?.toString() ?? '',
      usuario['ventasPropias']?.toString() ?? '',
      usuario['fechaIngreso']?.toString() ?? '',
      usuario['referidoPor']?.toString() ?? '',
    ]);
  }

  final bytes = excel.encode();
  return Uint8List.fromList(bytes!);
}

class WinnerListScreen extends StatefulWidget {
  @override
  State<WinnerListScreen> createState() => _WinnerListScreenState();
}

class _WinnerListScreenState extends State<WinnerListScreen> {
  late String currentUserId;
  String? currentUserName;
  Map<String, dynamic> ventasMensuales = {}; // Llaves en formato "yyyy-MM"
  Map<String, double> comisionesMensuales = {}; // Llaves en formato "yyyy-MM"

  // Rango de fechas seleccionado
  DateTimeRange? _rangoFechas;
  final GlobalKey _calendarIconKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    currentUserId = FirebaseAuth.instance.currentUser!.uid;
    _loadCurrentUser();

    // Muestra un hint para cambiar el rango de fechas al iniciar la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showCalendarHint();
    });
  }

  void _showCalendarHint() {
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    RenderBox renderBox =
        _calendarIconKey.currentContext?.findRenderObject() as RenderBox;
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

  /// Tarjeta dinámica de reconocimiento.
  /// Esta widget usa FutureBuilder para obtener los referidos y el ganador actual.
  Widget _buildReconocimientoCard() {
  return FutureBuilder<Winner>(
    future: _fetchWinner(currentUserId),
    builder: (context, winnerSnapshot) {
      if (winnerSnapshot.connectionState != ConnectionState.done ||
          winnerSnapshot.data == null) {
        return SizedBox.shrink();
      }
      final currentWinner = winnerSnapshot.data!;
      final now = DateTime.now();
      final mesAnterior = DateTime(now.year, now.month - 1);
      final mesesDesdeIngreso = mesAnterior
              .difference(DateTime(
                  currentWinner.fechaIngreso.year, currentWinner.fechaIngreso.month))
              .inDays ~/
          30;
      // Calcular porcentaje igual que en _verComisiones()
      double porcentaje;
      if (mesesDesdeIngreso < 1) {
        porcentaje = 0.15;
      } else if (mesesDesdeIngreso == 1) {
        porcentaje = 0.18;
      } else {
        porcentaje = 0.20;
      }

      final ventasPropias = currentWinner.ventas;
      final baseTotal = ventasPropias * porcentaje;

      // Calcular comisión por referidos: si hay rango de fechas se filtra, sino se suma todo.
      double referidosComision = 0.0;
      if (_rangoFechas != null) {
        final rangeStart = _rangoFechas!.start;
        final rangeEnd = _rangoFechas!.end;
        comisionesMensuales.forEach((key, value) {
          DateTime monthDate = DateTime.parse("$key-01");
          if (!monthDate.isBefore(rangeStart) && !monthDate.isAfter(rangeEnd)) {
            referidosComision += value;
          }
        });
      } else {
        referidosComision = comisionesMensuales.values.fold(0, (prev, element) => prev + element);
      }

      final totalComision = baseTotal + referidosComision;

      // Obtener los referidos para usar en el cálculo del reconocimiento
      return FutureBuilder<List<Winner>>(
        future: _fetchReferidos(currentUserId),
        builder: (context, referidosSnapshot) {
          if (referidosSnapshot.connectionState != ConnectionState.done) {
            return SizedBox.shrink();
          }
          final referidos = referidosSnapshot.data ?? [];
          final reconocimiento = _obtenerReconocimiento(totalComision, referidos.length);

          // Elegir un icono según el reconocimiento
          IconData icon;
          if (reconocimiento == 'Zafiro Blanco')
            icon = Icons.diamond;
          else if (reconocimiento == 'Zafiro Morado')
            icon = Icons.stars;
          else if (reconocimiento == 'Zafiro Amarillo')
            icon = Icons.star_half;
          else if (reconocimiento == 'Zafiro Verde')
            icon = Icons.emoji_nature;
          else
            icon = Icons.person;

          return Card(
            color: Colors.white,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: Icon(icon, size: 40, color: const Color.fromARGB(255, 2, 151, 14)),
              title: Text("Reconocimiento WoW"),
              subtitle: Text(
                reconocimiento,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        },
      );
    },
  );
}

  /// Función para exportar usuarios a Excel, adaptada para Web y móvil.
  Future<void> _exportarUsuariosAExcel() async {
    if (kIsWeb) {
      try {
        final query =
            await FirebaseFirestore.instance.collection('winners').get();
        final usuarios = query.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name'],
            'ventasPropias': data['ventasPropias'],
            'fechaIngreso': data['fechaIngreso'],
            'referidoPor': data['referidoPor'],
          };
        }).toList();
        print("Documentos obtenidos: ${usuarios.length}");
        final bytes = await compute(generarExcelBytes, usuarios);
        final blob = html.Blob(
          [bytes],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..download = 'usuarios_exportados.xlsx'
          ..style.display = 'none';
        html.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
        html.Url.revokeObjectUrl(url);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Archivo descargado: usuarios_exportados.xlsx")),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al exportar: $e")),
        );
      }
      return;
    }
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Permiso de almacenamiento denegado")),
        );
        return;
      }
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator()),
    );
    try {
      final query =
          await FirebaseFirestore.instance.collection('winners').get();
      final usuarios = query.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'],
          'ventasPropias': data['ventasPropias'],
          'fechaIngreso': data['fechaIngreso'],
          'referidoPor': data['referidoPor'],
        };
      }).toList();
      final bytes = await compute(generarExcelBytes, usuarios);
      final dir = Directory('/storage/emulated/0/Download');
      final path = '${dir.path}/usuarios_exportados.xlsx';
      final file = File(path);
      await file.writeAsBytes(bytes);
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Guardado en Descargas: usuarios_exportados.xlsx")),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al exportar: $e")),
      );
    }
  }

  // Carga el usuario actual y los datos mensuales desde Firestore.
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

  // Calcula las comisiones totales a partir de las ventas de los referidos.
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
    final now = DateTime.now();
    final mesAnterior = DateTime(now.year, now.month - 1);
    final mesesDesdeIngreso = mesAnterior
            .difference(DateTime(w.fechaIngreso.year, w.fechaIngreso.month))
            .inDays ~/
        30;
    if (nivel == 1) {
      double porcentaje;
      if (mesesDesdeIngreso < 1) {
        porcentaje = 0.15;
      } else if (mesesDesdeIngreso == 1) {
        porcentaje = 0.18;
      } else {
        porcentaje = 0.20;
      }
      total += w.ventas * porcentaje;
    } else if (nivel == 2) {
      total += w.ventas * 0.10;
    } else if (nivel == 3) {
      total += w.ventas * 0.07;
    } else if (nivel == 4) {
      total += w.ventas * 0.03;
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

  // Al pulsar "Ver comisiones", se muestran las comisiones ganadas y el reconocimiento.
  void _verComisiones() async {
    final user = await _fetchWinner(currentUserId);
    final now = DateTime.now();
    final mesAnterior = DateTime(now.year, now.month - 1);
    final mesesDesdeIngreso = mesAnterior
            .difference(DateTime(user.fechaIngreso.year, user.fechaIngreso.month))
            .inDays ~/
        30;
    double porcentaje;
    if (mesesDesdeIngreso < 1) {
      porcentaje = 0.15;
    } else if (mesesDesdeIngreso == 1) {
      porcentaje = 0.18;
    } else {
      porcentaje = 0.20;
    }
    final doc = await FirebaseFirestore.instance
        .collection('winners')
        .doc(currentUserId)
        .get();
    double ventasPropias = (doc.data()?['ventasPropias'] ?? 0).toDouble();
    final double baseTotal = ventasPropias * porcentaje;
    double referidosComision = 0;
    if (_rangoFechas != null) {
      final DateTime rangeStart = _rangoFechas!.start;
      final DateTime rangeEnd = _rangoFechas!.end;
      comisionesMensuales.forEach((key, value) {
        DateTime monthDate = DateTime.parse("$key-01");
        if (!monthDate.isBefore(rangeStart) && !monthDate.isAfter(rangeEnd)) {
          referidosComision += value;
        }
      });
    } else {
      referidosComision = comisionesMensuales.values.fold(0, (prev, element) => prev + element);
    }
    final totalComision = baseTotal + referidosComision;
    final referidos = await _fetchReferidos(currentUserId);
    final reco = _obtenerReconocimiento(totalComision, referidos.length);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Comisiones ganadas", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Por tus ventas: €${baseTotal.toStringAsFixed(2)} ($porcentaje%)", style: TextStyle(fontSize: 16)),
            SizedBox(height: 4),
            Text("Por tus referidos: €${referidosComision.toStringAsFixed(2)}", style: TextStyle(fontSize: 16)),
            SizedBox(height: 8),
            Text("Total: €${totalComision.toStringAsFixed(2)}", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text("Reconocimiento WoW: $reco", style: TextStyle(fontSize: 16, color: Colors.teal)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cerrar", style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
  }

  // Permite editar las ventas mensuales del mes actual (clave "yyyy-MM")
  void _editarVentaMes() async {
    final now = DateTime.now();
    final key = "${now.year}-${now.month.toString().padLeft(2, '0')}";
    final currentValue = double.tryParse(ventasMensuales[key]?.toString() ?? '0') ?? 0;
    final controller = TextEditingController(text: currentValue.toString());
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Editar ventas para $key"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: "Nuevo total de ventas",
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
      final newSales = double.tryParse(result);
      if (newSales == null) return;
      final docRef = FirebaseFirestore.instance.collection('winners').doc(currentUserId);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snapshot = await tx.get(docRef);
        final data = snapshot.data() ?? {};
        final ventas = Map<String, dynamic>.from(data['ventasPorMes'] ?? {});
        final oldSales = (ventas[key] ?? 0).toDouble();
        final diferencia = newSales - oldSales;
        ventas[key] = newSales;
        final ventasPropiasActual = (data['ventasPropias'] ?? 0).toDouble();
        final ventasPropiasNueva = ventasPropiasActual + diferencia;
        tx.update(docRef, {
          'ventasPorMes': ventas,
          'ventasPropias': ventasPropiasNueva,
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ventas para $key actualizadas a \€${newSales.toStringAsFixed(2)}")),
      );
      _loadCurrentUser();
    }
  }

  // Agregar ventas para el mes actual (acumulando el valor)
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
      final data = snapshot.data() ?? {};
      final ventas = Map<String, dynamic>.from(data['ventasPorMes'] ?? {});
      final actual = (ventas[key] ?? 0).toDouble();
      ventas[key] = actual + monto;
      final ventasPropiasActual = (data['ventasPropias'] ?? 0).toDouble();
      final ventasPropiasNueva = ventasPropiasActual + monto;
      tx.update(docRef, {
        'ventasPorMes': ventas,
        'ventasPropias': ventasPropiasNueva,
      });
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Registrado \€${monto.toStringAsFixed(2)} para $key")),
      );
      _loadCurrentUser();
    }
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

  // Construcción del gráfico en resolución mensual (con números abreviados)
  Widget _buildSalesChart() {
    final now = DateTime.now();
    final DateTime startDate = _rangoFechas?.start ?? DateTime(now.year, now.month, 1);
    final DateTime endDate = _rangoFechas?.end ?? now;
    List<DateTime> timePoints = [];
    DateTime cursor = DateTime(startDate.year, startDate.month, 1);
    while (!cursor.isAfter(endDate)) {
      timePoints.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    if (timePoints.length == 1) {
      timePoints.add(DateTime(timePoints[0].year, timePoints[0].month + 1, 1));
    }
    final List<FlSpot> ventasSpots = [];
    final List<FlSpot> comisionSpots = [];
    for (int i = 0; i < timePoints.length; i++) {
      final dt = timePoints[i];
      final key = "${dt.year}-${dt.month.toString().padLeft(2, '0')}";
      final v = double.tryParse(ventasMensuales[key]?.toString() ?? '0') ?? 0;
      final c = comisionesMensuales[key] ?? 0;
      ventasSpots.add(FlSpot(i.toDouble(), v));
      comisionSpots.add(FlSpot(i.toDouble(), c));
    }
    double aggregatedSales = 0;
    double aggregatedCommission = 0;
    if (_rangoFechas != null) {
      final rangeStart = _rangoFechas!.start;
      final rangeEnd = _rangoFechas!.end;
      ventasMensuales.forEach((key, value) {
        final monthDate = DateTime.parse("$key-01");
        if (!monthDate.isBefore(rangeStart) && !monthDate.isAfter(rangeEnd)) {
          aggregatedSales += double.tryParse(value.toString()) ?? 0;
        }
      });
      comisionesMensuales.forEach((key, value) {
        final monthDate = DateTime.parse("$key-01");
        if (!monthDate.isBefore(rangeStart) && !monthDate.isAfter(rangeEnd)) {
          aggregatedCommission += value;
        }
      });
    } else {
      final key = "${now.year}-${now.month.toString().padLeft(2, '0')}";
      aggregatedSales = double.tryParse(ventasMensuales[key]?.toString() ?? '0') ?? 0;
      aggregatedCommission = comisionesMensuales[key] ?? 0;
    }
    final double maxY = [
      ...ventasSpots.map((e) => e.y),
      ...comisionSpots.map((e) => e.y),
    ].fold(0, (prev, curr) => curr > prev ? curr : prev);
    final double intervalY = maxY == 0 ? 1 : (maxY / 4).ceilToDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
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
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Ventas", style: TextStyle(fontSize: 16, color: Colors.green[700])),
                  const SizedBox(height: 4),
                  Text("\€${aggregatedSales.toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Comisiones", style: TextStyle(fontSize: 16, color: Colors.amber[800])),
                  const SizedBox(height: 4),
                  Text("\€${aggregatedCommission.toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(width: 10, height: 10, color: Colors.green),
                  const SizedBox(width: 4),
                  const Text("Ventas"),
                ],
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  Container(width: 10, height: 10, color: Colors.amber),
                  const SizedBox(width: 4),
                  const Text("Comisiones"),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY + intervalY,
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
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 64,
                      interval: intervalY,
                      getTitlesWidget: (value, meta) {
                        String formatted = formatAbbreviated(value);
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Text(
                            "\€$formatted",
                            style: const TextStyle(fontSize: 10, color: Colors.black54),
                            textAlign: TextAlign.right,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= timePoints.length) return const SizedBox.shrink();
                        final dt = timePoints[index];
                        String label = DateFormat('MMM', 'es').format(dt).toUpperCase();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Transform.rotate(
                            angle: -0.3,
                            child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.black87)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                    if (!event.isInterestedForInteractions || touchResponse == null || touchResponse.lineBarSpots == null) return;
                    if (event is FlTapUpEvent) {
                      final index = touchResponse.lineBarSpots![0].x.toInt();
                      if (index >= 0 && index < timePoints.length) {
                        final selectedMonth = timePoints[index];
                        final key = "${selectedMonth.year}-${selectedMonth.month.toString().padLeft(2, '0')}";
                        final sales = double.tryParse(ventasMensuales[key]?.toString() ?? '0') ?? 0;
                        final commission = comisionesMensuales[key] ?? 0;
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text("Detalle para ${DateFormat('MMMM yyyy', 'es').format(selectedMonth)}"),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Ventas: \€${sales.toStringAsFixed(2)}"),
                                const SizedBox(height: 8),
                                Text("Comisiones: \€${commission.toStringAsFixed(2)}"),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text("Cerrar"),
                              )
                            ],
                          ),
                        );
                      }
                    }
                  },
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.white,
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final index = spot.x.toInt();
                        if (index < 0 || index >= timePoints.length) return null;
                        final dt = timePoints[index];
                        final label = DateFormat('MMMM yyyy', 'es').format(dt);
                        final isVenta = spot.barIndex == 0;
                        final title = isVenta ? 'Ventas' : 'Comisiones';
                        return LineTooltipItem(
                          "$label\n$title: \€${spot.y.toStringAsFixed(2)}",
                          const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: ventasSpots,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C853), Color(0xFFB9F6CA)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                        radius: 4,
                        color: Colors.white,
                        strokeWidth: 2,
                        strokeColor: bar.gradient?.colors.first ?? Colors.green,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00C853).withOpacity(0.2),
                          const Color(0xFFB9F6CA).withOpacity(0.1),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  LineChartBarData(
                    spots: comisionSpots,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD600), Color(0xFFFFF59D)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                        radius: 4,
                        color: Colors.white,
                        strokeWidth: 2,
                        strokeColor: bar.gradient?.colors.first ?? Colors.amber,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFFD600).withOpacity(0.2),
                          const Color(0xFFFFF59D).withOpacity(0.1),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
            ),
          ),
        ],
      ),
    );
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

  Widget _buildBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        image: DecorationImage(
          image: AssetImage('assets/animations/logo.gif'),
          fit: BoxFit.cover,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.black.withOpacity(0.3),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "WinoWin",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "Ingresos extras con Win O Win.\n"
                "Gracias al excelente plan de regalías nuestros socios pueden llegar a recibir de nuestra winowin.shop",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  // Acción al pulsar el botón
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: const StadiumBorder(),
                ),
                child: const Text("Read more"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.fromARGB(255, 250, 251, 249),
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/animations/logo.webp'),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color.fromARGB(255, 87, 88, 1), Color.fromARGB(255, 52, 163, 0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          "Panel Principal",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            key: _calendarIconKey,
            icon: Icon(Icons.date_range, color: Colors.white),
            onPressed: _seleccionarRangoFechas,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildSalesChart(),
            _buildBanner(),
            SizedBox(height: 16),
            _buildReconocimientoCard(),  // Tarjeta dinámica de reconocimiento
            SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _dashboardCard("Ver comisiones", Icons.paid, Colors.green, _verComisiones),
                _dashboardCard("Ver árbol de referidos", Icons.account_tree_outlined, Colors.blue, _abrirArbolReferidos),
                _dashboardCard("Editar ventas mensuales", Icons.edit, Colors.orange, _editarVentaMes),
                _dashboardCard("Añadir venta", Icons.add_chart, Colors.purple, _agregarVentaMes),
                _dashboardCard("Exportar usuarios a Excel", Icons.file_download, Colors.teal, _exportarUsuariosAExcel),
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
