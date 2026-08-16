import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
  'Conjuntos',
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
  String material;
  String piedra;
  String tamanoPiedra;
  String tamanoTotal;

  Pieza({
    required this.id,
    required this.imageUrl,
    required this.proveedor,
    required this.categoria,
    this.costoProveedor = '',
    this.valorVenta = '',
    this.stock = true,
    this.material = '',
    this.piedra = '',
    this.tamanoPiedra = '',
    this.tamanoTotal = '',
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
      material: d['material'] ?? '',
      piedra: d['piedra'] ?? '',
      tamanoPiedra: d['tamanoPiedra'] ?? '',
      tamanoTotal: d['tamanoTotal'] ?? '',
    );
  }
}

const List<String> kMateriales = ['Oro', 'Plata'];
const List<String> kPiedras = [
  'Ninguna',
  'Esmeralda en piedra',
  'Esmeralda en balines',
  'Cuarzo',
  'Ónix',
  'Neopreno',
];

List<String> tamanosPara(String categoria) {
  switch (categoria) {
    case 'Cadenas':
      return ['45 cm', '50 cm', '60 cm'];
    case 'Pulseras':
      return ['19 cm', '20 cm', '21 cm', '22 cm'];
    case 'Anillos':
      return ['#5', '#6', '#7', '#8', '#9', '#10', '#11'];
    default:
      return [];
  }
}

String formatoLista(String valor) {
  final partes = valor.split(',').where((s) => s.trim().isNotEmpty).toList();
  if (partes.isEmpty) return '';
  return partes.join(' y ');
}

String categoriaMaterial(String material) {
  final set = material.split(',').where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toSet();
  final tieneOro = set.contains('Oro');
  final tienePlata = set.contains('Plata');
  if (tieneOro && tienePlata) return 'Oro y Plata';
  if (tieneOro) return 'Oro';
  if (tienePlata) return 'Plata';
  return '';
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
  final TextEditingController _buscarCodigoCtrl = TextEditingController();
  final CollectionReference _col =
      FirebaseFirestore.instance.collection('piezas');

  bool vistaInterna = true;
  String filtroCategoria = 'Todos';
  String busquedaCodigo = '';
  String filtroMaterial = 'Todos';
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
          'material': '',
          'piedra': '',
          'tamanoPiedra': '',
          'tamanoTotal': '',
          'creadoEn': Timestamp.now(),
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
        ? piezas.where((p) => p.stock)
        : piezas.where((p) => p.categoria == filtroCategoria && p.stock);

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

    pw.MemoryImage? logoImg;
    try {
      final logoData = await rootBundle.load('assets/icon/icon.png');
      logoImg = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    final goldColor = PdfColor.fromHex('#D4AF37');
    final greyColor = PdfColor.fromHex('#B0B0B0');
    final cardColor = PdfColor.fromHex('#161616');
    final greenColor = PdfColor.fromHex('#3DDC84');

    final Map<String, List<Pieza>> agrupado = {};
    for (final p in visibles) {
      agrupado.putIfAbsent(p.categoria, () => []).add(p);
    }

    // Portada
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Container(
          color: PdfColors.black,
          alignment: pw.Alignment.center,
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              if (logoImg != null)
                pw.ClipOval(
                  child: pw.Image(logoImg, width: 90, height: 90, fit: pw.BoxFit.cover),
                ),
              pw.SizedBox(height: 20),
              pw.Text('CATÁLOGO SOTELUX',
                  style: pw.TextStyle(
                      fontSize: 26, fontWeight: pw.FontWeight.bold, color: goldColor)),
              pw.SizedBox(height: 6),
              pw.Text('Joyería', style: pw.TextStyle(fontSize: 13, color: PdfColors.white)),
            ],
          ),
        ),
      ),
    );

    // Páginas por categoría
    for (final entry in agrupado.entries) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(),
          build: (context) => [
            pw.Container(
              color: PdfColors.black,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      if (logoImg != null)
                        pw.ClipOval(
                            child: pw.Image(logoImg, width: 28, height: 28, fit: pw.BoxFit.cover)),
                      pw.SizedBox(width: 10),
                      pw.Text(entry.key.toUpperCase(),
                          style: pw.TextStyle(
                              fontSize: 18, fontWeight: pw.FontWeight.bold, color: goldColor)),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(color: goldColor, thickness: 0.7),
                  pw.SizedBox(height: 12),
                  pw.Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: entry.value.map((p) {
                      final precio = _formatoCOP(p.valorVenta);
                      final caract = <String>[
                        if (p.material.isNotEmpty) formatoLista(p.material),
                        if (p.piedra.isNotEmpty) formatoLista(p.piedra),
                        if (p.tamanoPiedra.isNotEmpty) p.tamanoPiedra,
                        if (p.tamanoTotal.isNotEmpty) 'Tamaño: ${p.tamanoTotal}',
                      ].join(' · ');
                      return pw.Container(
                        width: 155,
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                          color: cardColor,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            if (imagenes[p.id] != null)
                              pw.ClipRRect(
                                horizontalRadius: 4,
                                verticalRadius: 4,
                                child: pw.Image(imagenes[p.id]!,
                                    height: 140, width: 139, fit: pw.BoxFit.cover),
                              ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              precio.isEmpty ? 'Consultar precio' : precio,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold, fontSize: 12, color: goldColor),
                            ),
                            if (caract.isNotEmpty) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(
                                caract,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(fontSize: 7, color: greyColor),
                              ),
                            ],
                            pw.SizedBox(height: 3),
                            pw.Text('● Disponible',
                                style: pw.TextStyle(fontSize: 7, color: greenColor)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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

  void _editarCaracteristicas(Pieza p) {
    final tamanoPiedraCtrl = TextEditingController(text: p.tamanoPiedra);
    final materialSet = p.material.split(',').where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toSet();
    final piedraSet = p.piedra.split(',').where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toSet();
    String tamanoTotal = p.tamanoTotal;
    final opcionesTamano = tamanosPara(p.categoria);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Características de la pieza',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),

                    const Text('Material (puedes elegir varios)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: kMateriales.map((m) {
                        final activo = materialSet.contains(m);
                        return FilterChip(
                          label: Text(m),
                          selected: activo,
                          selectedColor: kGold,
                          backgroundColor: Colors.grey.shade800,
                          labelStyle: TextStyle(color: activo ? Colors.black : Colors.white),
                          onSelected: (sel) => setModalState(() {
                            if (sel) {
                              materialSet.add(m);
                            } else {
                              materialSet.remove(m);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    const Text('Piedra / material de la piedra (puedes elegir varios)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kPiedras.map((pi) {
                        final activo = piedraSet.contains(pi);
                        return FilterChip(
                          label: Text(pi),
                          selected: activo,
                          selectedColor: kGold,
                          backgroundColor: Colors.grey.shade800,
                          labelStyle: TextStyle(color: activo ? Colors.black : Colors.white, fontSize: 12),
                          onSelected: (sel) => setModalState(() {
                            if (sel) {
                              piedraSet.add(pi);
                            } else {
                              piedraSet.remove(pi);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    if (piedraSet.isNotEmpty) ...[
                      const Text('Tamaño de la piedra o balín (mm)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: tamanoPiedraCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Ej. 6 mm',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          filled: true,
                          fillColor: Colors.black,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (opcionesTamano.isNotEmpty) ...[
                      Text('Tamaño total (${p.categoria})', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: opcionesTamano.map((t) {
                          final activo = tamanoTotal == t;
                          return ChoiceChip(
                            label: Text(t),
                            selected: activo,
                            selectedColor: kGold,
                            backgroundColor: Colors.grey.shade800,
                            labelStyle: TextStyle(color: activo ? Colors.black : Colors.white),
                            onSelected: (_) => setModalState(() => tamanoTotal = t),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _actualizarCampo(p, {
                            'material': materialSet.join(','),
                            'piedra': piedraSet.join(','),
                            'tamanoPiedra': piedraSet.isEmpty ? '' : tamanoPiedraCtrl.text.trim(),
                            'tamanoTotal': tamanoTotal,
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kGold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Guardar características'),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  void _verGrande(Pieza p) {
    final venta = _formatoCOP(p.valorVenta);
    final caracteristicas = <String>[
      if (p.material.isNotEmpty) formatoLista(p.material),
      if (p.piedra.isNotEmpty) formatoLista(p.piedra),
      if (p.tamanoPiedra.isNotEmpty) '${p.tamanoPiedra}',
      if (p.tamanoTotal.isNotEmpty) 'Tamaño: ${p.tamanoTotal}',
    ];
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Image.network(p.imageUrl, fit: BoxFit.cover),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(p.categoria.toUpperCase(),
                        style: const TextStyle(color: kGold, fontSize: 11, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(venta.isEmpty ? 'Consultar precio' : venta,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    if (caracteristicas.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(caracteristicas.join(' · '),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    ],
                    const SizedBox(height: 6),
                    Text(p.stock ? '● Disponible' : '● Sin inventario',
                        style: TextStyle(color: p.stock ? Colors.greenAccent : Colors.grey, fontSize: 12)),
                    if (p.stock) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _preguntarPorPieza(p);
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.greenAccent),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Preguntar por esta pieza',
                              style: TextStyle(color: Colors.greenAccent)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var visibles = filtroCategoria == 'Todos'
        ? piezas
        : piezas.where((p) => p.categoria == filtroCategoria).toList();

    if (vistaInterna && busquedaCodigo.trim().isNotEmpty) {
      final q = busquedaCodigo.trim().toLowerCase();
      visibles = visibles
          .where((p) => p.id.substring(0, 6).toLowerCase().contains(q))
          .toList();
    }

    if (!vistaInterna && filtroMaterial != 'Todos') {
      visibles = visibles
          .where((p) => categoriaMaterial(p.material) == filtroMaterial)
          .toList();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (vistaInterna) _buildPanelSubida(),
            if (vistaInterna) _buildBuscadorCodigo(),
            _buildTabsCategorias(),
            if (!vistaInterna) _buildFiltroMaterial(),
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
              onPressed: subiendo ? null : _subirFotos,
              icon: subiendo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload),
              label: Text(subiendo ? 'Subiendo...' : 'Seleccionar fotos'),
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

  Widget _buildBuscadorCodigo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _buscarCodigoCtrl,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        onChanged: (v) => setState(() => busquedaCodigo = v),
        decoration: InputDecoration(
          hintText: 'Buscar por código (ej. 4b0f2c)',
          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
          suffixIcon: busquedaCodigo.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                  onPressed: () {
                    _buscarCodigoCtrl.clear();
                    setState(() => busquedaCodigo = '');
                  },
                ),
          filled: true,
          fillColor: Colors.grey.shade900,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFiltroMaterial() {
    final opciones = ['Todos', 'Oro', 'Plata', 'Oro y Plata'];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: opciones.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final op = opciones[i];
          final activo = filtroMaterial == op;
          return GestureDetector(
            onTap: () => setState(() => filtroMaterial = op),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: activo ? kGold : Colors.transparent,
                border: Border.all(color: activo ? kGold : Colors.grey.shade700),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                op,
                style: TextStyle(
                  color: activo ? Colors.black : Colors.grey.shade400,
                  fontSize: 11,
                ),
              ),
            ),
          );
        },
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
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: vistaInterna ? 0.56 : 0.72,
      ),
      itemCount: visibles.length,
      itemBuilder: (context, i) => _buildCard(visibles[i]),
    );
  }

  Widget _buildCard(Pieza p) {
    final venta = _formatoCOP(p.valorVenta);
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
                GestureDetector(
                  onTap: !vistaInterna ? () => _verGrande(p) : null,
                  child: Image.network(
                    p.imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                          child: CircularProgressIndicator(
                              color: kGold, strokeWidth: 2));
                    },
                    errorBuilder: (context, error, stack) =>
                        const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: GestureDetector(
                    onTap: vistaInterna ? () => _elegirCategoria(p) : null,
                    child: _badge(
                      vistaInterna ? '${p.categoria} ✏️' : p.categoria,
                      kGold,
                    ),
                  ),
                ),
                if (!vistaInterna && p.material.isNotEmpty)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: _badge(formatoLista(p.material), Colors.white70),
                  ),
                if (vistaInterna)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _badge(
                        '${p.proveedor} · ${p.id.substring(0, 6)}',
                        Colors.grey.shade400),
                  ),
                if (!p.stock)
                  const Positioned(
                    right: 6,
                    bottom: 6,
                    child: _StockBadge(),
                  ),
                if (vistaInterna)
                  GestureDetector(
                    onTap: () => _eliminar(p),
                    child: Container(
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.all(4),
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
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _precioInput('Costo', p.costoProveedor,
                            (v) => _actualizarCampo(p, {'costoProveedor': v})),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _precioInput('Venta', p.valorVenta,
                            (v) => _actualizarCampo(p, {'valorVenta': v})),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('En stock',
                          style: TextStyle(color: Colors.grey, fontSize: 11)),
                      Switch(
                        value: p.stock,
                        activeColor: kGold,
                        onChanged: (v) =>
                            _actualizarCampo(p, {'stock': v}),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => _editarCaracteristicas(p),
                      icon: const Icon(Icons.tune, size: 14, color: kGold),
                      label: const Text('Características',
                          style: TextStyle(color: kGold, fontSize: 11)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        minimumSize: const Size(0, 28),
                      ),
                    ),
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
                    venta.isEmpty ? 'Consultar precio' : venta,
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
                      onPressed: p.stock ? () => _preguntarPorPieza(p) : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        side: BorderSide(
                            color: p.stock
                                ? Colors.greenAccent
                                : Colors.grey.shade700),
                      ),
                      child: Text(
                        p.stock ? 'Preguntar' : 'Sin inventario',
                        style: TextStyle(
                            fontSize: 11,
                            color: p.stock
                                ? Colors.greenAccent
                                : Colors.grey.shade600),
                      ),
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

class _StockBadge extends StatelessWidget {
  const _StockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withOpacity(0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text('Agotado',
          style: TextStyle(fontSize: 9, color: Colors.white)),
    );
  }
}
