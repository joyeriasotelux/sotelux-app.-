import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

const kGold = Color(0xFFD4AF37);
const kBg = Colors.black;

const List<String> kCategories = [
  'Anillos',
  'Cadenas',
  'Aretes y Topos',
  'Pulseras',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SoteluxApp());
}

class Pieza {
  String id;
  String imageUrl;
  String proveedor;
  String categoria;
  String costoProveedor;
  String valorVenta;
  bool stock;

  Pieza({
    required this.id,
    required this.imageUrl,
    required this.proveedor,
    required this.categoria,
    this.costoProveedor = '',
    this.valorVenta = '',
    this.stock = true,
  });

  factory Pieza.fromDoc(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Pieza(
      id: doc.id,
      imageUrl: d['imageUrl'] ?? '',
      proveedor: d['proveedor'] ?? '',
      categoria: d['categoria'] ?? 'Anillos',
      costoProveedor: d['costoProveedor'] ?? '',
      valorVenta: d['valorVenta'] ?? '',
      stock: d['stock'] ?? true,
    );
  }
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
  final CollectionReference _col =
      FirebaseFirestore.instance.collection('piezas');

  bool vistaInterna = true;
  String filtroCategoria = 'Todos';
  bool conectando = true;
  bool subiendo = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {}

    _col.orderBy('creadoEn', descending: true).snapshots().listen((snap) {
      setState(() {
        piezas.clear();
        piezas.addAll(snap.docs.map((d) => Pieza.fromDoc(d)));
        conectando = false;
      });
    }, onError: (_) {
      setState(() => conectando = false);
    });
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

    setState(() => subiendo = true);

    for (final img in imgs) {
      try {
        final bytes = await img.readAsBytes();
        final id = _uuid.v4();
        final ref = FirebaseStorage.instance.ref('piezas/$id.jpg');
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        final url = await ref.getDownloadURL();

        await _col.doc(id).set({
          'imageUrl': url,
          'proveedor': _proveedorCtrl.text.trim(),
          'categoria': clasificarPieza(img.name),
          'costoProveedor': '',
          'valorVenta': '',
          'stock': true,
          'creadoEn': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al subir una foto: $e')),
          );
        }
      }
    }

    if (mounted) setState(() => subiendo = false);
  }

  Future<void> _actualizarCampo(Pieza p, Map<String, dynamic> valores) async {
    try {
      await _col.doc(p.id).update(valores);
    } catch (_) {}
  }

  Future<void> _eliminar(Pieza p) async {
    try {
      await _col.doc(p.id).delete();
    } catch (_) {}
  }

  String _formatoCOP(String valor) {
    final n = num.tryParse(valor);
    if (n == null || valor.isEmpty) return '';
    return "\$" + n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (m) => '.',
        );
  }

  Future<Uint8List> _generarPdf() async {
    final visibles = filtroCategoria == 'Todos'
        ? piezas
        : piezas.where((p) => p.categoria == filtroCategoria).toList();

    final doc = pw.Document();
    final imagenes = <String, pw.MemoryImage>{};
    for (final p in visibles) {
      try {
        final resp = await http.get(Uri.parse(p.imageUrl));
        if (resp.statusCode == 200) {
          imagenes[p.id] = pw.MemoryImage(resp.bodyBytes);
        }
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

  void _elegirCategoria(Pieza p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Elige la categoría correcta',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              ...kCategories.map((cat) {
                return ListTile(
                  title: Text(cat, style: const TextStyle(color: Colors.white)),
                  trailing: p.categoria == cat
                      ? const Icon(Icons.check, color: kGold)
                      : null,
                  onTap: () {
                    _actualizarCampo(p, {'categoria': cat});
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
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
            Expanded(
              child: conectando
                  ? const Center(
                      child: CircularProgressIndicator(color: kGold))
                  : _buildGrid(visibles),
            ),
          ],
        ),
      ),
    );
  }
