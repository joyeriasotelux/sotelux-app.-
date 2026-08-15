import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const SoteluxApp());
}

const kGold = Color(0xFFD4AF37);
const kBg = Colors.black;

const List<String> kCategories = [
  'Anillos',
  'Cadenas',
  'Aretes y Topos',
  'Pulseras',
];

class Pieza {
  String id;
  String imagePath;
  String proveedor;
  String categoria;
  String costoProveedor;
  String valorVenta;

  Pieza({
    required this.id,
    required this.imagePath,
    required this.proveedor,
    required this.categoria,
    this.costoProveedor = '',
    this.valorVenta = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'proveedor': proveedor,
        'categoria': categoria,
        'costoProveedor': costoProveedor,
        'valorVenta': valorVenta,
      };

  factory Pieza.fromJson(Map<String, dynamic> j) => Pieza(
        id: j['id'],
        imagePath: j['imagePath'],
        proveedor: j['proveedor'],
        categoria: j['categoria'],
        costoProveedor: j['costoProveedor'] ?? '',
        valorVenta: j['valorVenta'] ?? '',
      );
}

String clasificarPieza(String nombreArchivo) {
  int hash = 0;
  for (final r in nombreArchivo.runes) {
    hash = (hash * 31 + r) & 0x7fffffff;
  }
  return kCategories[hash % kCategories.length];
}

class SoteluxApp extends StatelessWidget {
  const SoteluxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Catálogo Sotelux',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kGold,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CatalogoHome(),
    );
  }
}

class CatalogoHome extends StatefulWidget {
  const CatalogoHome({super.key});

  @override
  State<CatalogoHome> createState() => _CatalogoHomeState();
}

class _CatalogoHomeState extends State<CatalogoHome> {
  final List<Pieza> piezas = [];
  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = const Uuid();
  final TextEditingController _proveedorCtrl = TextEditingController();

  bool vistaInterna = true;
  String filtroCategoria = 'Todos';

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('piezas');
    if (data != null) {
      final List<dynamic> lista = jsonDecode(data);
      setState(() {
        piezas.clear();
        piezas.addAll(lista.map((e) => Pieza.fromJson(e)));
      });
    }
  }

  Future<void> _guardarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(piezas.map((p) => p.toJson()).toList());
    await prefs.setString('piezas', data);
  }

  Future<void> _subirFotos() async {
    if (_proveedorCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe el proveedor primero')),
      );
      return;
    }
    final List<XFile> imgs = await _picker.pickMultiImage();
    if (imgs.isEmpty) return;

    for (final img in imgs) {
      final pieza = Pieza(
        id: _uuid.v4(),
        imagePath: img.path,
        proveedor: _proveedorCtrl.text.trim(),
        categoria: clasificarPieza(img.name),
      );
      setState(() => piezas.insert(0, pieza));
    }
    await _guardarDatos();
  }

  void _actualizarPrecio(Pieza p, {String? costo, String? venta}) {
    setState(() {
      if (costo != null) p.costoProveedor = costo;
      if (venta != null) p.valorVenta = venta;
    });
    _guardarDatos();
  }

  void _eliminar(Pieza p) {
    setState(() => piezas.remove(p));
    _guardarDatos();
  }

  String _formatoCOP(String valor) {
    final n = num.tryParse(valor);
    if (n == null || valor.isEmpty) return '';
    return '\$${n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (m) => '.',
        )}';
  }

  Future<Uint8List> _generarPdf() async {
    final visibles = filtroCategoria == 'Todos'
        ? piezas
        : piezas.where((p) => p.categoria == filtroCategoria).toList();

    final doc = pw.Document();
    final imagenes = <String, pw.MemoryImage>{};
    for (final p in visibles) {
      try {
        final bytes = await File(p.imagePath).readAsBytes();
        imagenes[p.id] = pw.MemoryImage(bytes);
      } catch (_) {}
    }

    final Map<String, List<Pieza>> agrupado = {};
    for (final p in visibles) {
      agrupado.putIfAbsent(p.categoria, () => []).add(p);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Catálogo Sotelux Joyería',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          for (final entry in agrupado.entries) ...[
            pw.SizedBox(height: 12),
            pw.Text(entry.key,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: entry.value.map((p) {
                final precio = _formatoCOP(p.valorVenta);
                return pw.Container(
                  width: 150,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (imagenes[p.id] != null)
                        pw.Container(
                          height: 150,
                          width: 150,
                          decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: PdfColors.grey300)),
                          child: pw.Image(imagenes[p.id]!, fit: pw.BoxFit.cover),
                        ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        precio.isEmpty ? 'Consultar precio' : precio,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  Future<void> _compartirCatalogoPdf() async {
    final bytes = await _generarPdf();
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: 'catalogo-sotelux.pdf',
    );
  }

  Future<void> _preguntarPorPieza(Pieza p) async {
    final precio = _formatoCOP(p.valorVenta);
    final codigo = p.id.substring(0, 6);
    final texto = Uri.encodeComponent(
      'Hola, me interesa esta pieza:\n'
      '${p.categoria} — código $codigo\n'
      'Precio: ${precio.isEmpty ? "consultar" : precio}\n'
      '¿Está disponible?',
    );
    final url = Uri.parse('https://wa.me/573183676909?text=$texto');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }


  Future<void> _abrirWhatsApp() async {
    final visibles = filtroCategoria == 'Todos'
        ? piezas
        : piezas.where((p) => p.categoria == filtroCategoria).toList();

    final buffer = StringBuffer('✨ *Catálogo Sotelux Joyería* ✨\n');
    final Map<String, List<Pieza>> agrupado = {};
    for (final p in visibles) {
      agrupado.putIfAbsent(p.categoria, () => []).add(p);
    }
    agrupado.forEach((cat, items) {
      buffer.write('\n*$cat*\n');
      for (var i = 0; i < items.length; i++) {
        final precio = _formatoCOP(items[i].valorVenta);
        buffer.write(
            '${i + 1}. Pieza ${cat.substring(0, cat.length - 1)} — ${precio.isEmpty ? "Consultar precio" : precio}\n');
      }
    });
    buffer.write('\nEscríbenos para separar tu pieza 💛');

    final texto = Uri.encodeComponent(buffer.toString());
    final url = Uri.parse('https://wa.me/573183676909?text=$texto');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibles = filtroCategoria == 'Todos'
        ? piezas
        : piezas.where((p) => p.categoria == filtroCategoria).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (vistaInterna) _buildPanelSubida(),
            _buildTabsCategorias(),
            Expanded(child: _buildGrid(visibles)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: Image.asset('assets/icon/icon.png',
                    width: 40, height: 40, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              const Text(
                'Catálogo Sotelux',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _toggleButton('Vista interna', vistaInterna, () {
                setState(() => vistaInterna = true);
              }),
              const SizedBox(width: 8),
              _toggleButton('Vista cliente', !vistaInterna, () {
                setState(() => vistaInterna = false);
              }),
              const Spacer(),
              if (!vistaInterna)
                IconButton(
                  onPressed: _compartirCatalogoPdf,
                  icon: const Icon(Icons.picture_as_pdf, color: kGold),
                  tooltip: 'Compartir PDF',
                ),
              if (!vistaInterna)
                IconButton(
                  onPressed: _abrirWhatsApp,
                  icon: const Icon(Icons.chat, color: Colors.greenAccent),
                  tooltip: 'Abrir en WhatsApp',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggleButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kGold : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.grey.shade400,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildPanelSubida() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Proveedor de este lote',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          TextField(
            controller: _proveedorCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Ej. Proveedor Palmira',
              hintStyle: TextStyle(color: Colors.grey.shade600),
              filled: true,
              fillColor: Colors.grey.shade900,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _subirFotos,
              icon: const Icon(Icons.upload),
              label: const Text('Seleccionar fotos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabsCategorias() {
    final opciones = ['Todos', ...kCategories];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: opciones.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = opciones[i];
          final activo = filtroCategoria == cat;
          final count = cat == 'Todos'
              ? piezas.length
              : piezas.where((p) => p.categoria == cat).length;
          return GestureDetector(
            onTap: () => setState(() => filtroCategoria = cat),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: activo ? Colors.white : Colors.transparent,
                border: Border.all(color: Colors.grey.shade700),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$cat ($count)',
                style: TextStyle(
                  color: activo ? Colors.black : Colors.grey.shade400,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid(List<Pieza> visibles) {
    if (visibles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aún no hay piezas cargadas. Sube las fotos del proveedor.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: visibles.length,
      itemBuilder: (context, i) => _buildCard(visibles[i]),
    );
  }

  Widget _buildCard(Pieza p) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(p.imagePath), fit: BoxFit.cover),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: _badge(p.categoria, kGold),
                ),
                if (vistaInterna)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _badge(p.proveedor, Colors.grey.shade400),
                  ),
                if (vistaInterna)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: GestureDetector(
                      onTap: () => _eliminar(p),
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (vistaInterna)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Expanded(
                    child: _precioInput('Costo', p.costoProveedor,
                        (v) => _actualizarPrecio(p, costo: v)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _precioInput('Venta', p.valorVenta,
                        (v) => _actualizarPrecio(p, venta: v)),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Column(
                children: [
                  Text(
                    p.valorVenta.isEmpty
                        ? 'Consultar precio'
                        : _formatoCOP(p.valorVenta),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kGold,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _preguntarPorPieza(p),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        side: const BorderSide(color: Colors.greenAccent),
                      ),
                      child: const Text('Preguntar',
                          style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        texto,
        style: TextStyle(fontSize: 9, color: color),
      ),
    );
  }

  Widget _precioInput(String label, String value, Function(String) onChanged) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 11),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(fontSize: 9, color: Colors.grey),
        filled: true,
        fillColor: Colors.black,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
