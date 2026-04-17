import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart'; 

// IMPORTAÇÃO DO MENU (LOGOUT E PERFIL)
import '../../widgets/menu_usuario.dart';

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class FormularioRotaPage extends StatefulWidget {
  const FormularioRotaPage({super.key});

  @override
  State<FormularioRotaPage> createState() => _FormularioRotaPageState();
}

class _FormularioRotaPageState extends State<FormularioRotaPage> with SingleTickerProviderStateMixin {
  final User? user = FirebaseAuth.instance.currentUser;
  
  late TabController _tabController;
  final TextEditingController _pesquisaAndamentoController = TextEditingController();
  final TextEditingController _pesquisaConcluidosController = TextEditingController();
  
  String _textoPesquisaAndamento = '';
  String _textoPesquisaConcluidos = '';
  
  // Controle de Perfil
  String _nomeDoVistoriadorLogado = 'Carregando...';
  bool _isAdmin = false;
  bool _carregandoPerfil = true;
  
  // Para o Admin navegar entre a lista e a rota
  DocumentSnapshot? _turnoSelecionadoAdmin;

  // O texto resumido do checklist
  final String textoConfirmacaoChecklist = 'Confirmo que verifiquei a integridade física, elétrica e de funcionamento de todos os equipamentos (focos, estruturas, controladores, kit de energia e acessórios), bem como a visibilidade, sinalização associada e ausência de interferências externas.';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    _pesquisaAndamentoController.addListener(() {
      setState(() => _textoPesquisaAndamento = _pesquisaAndamentoController.text.toLowerCase());
    });
    
    _pesquisaConcluidosController.addListener(() {
      setState(() => _textoPesquisaConcluidos = _pesquisaConcluidosController.text.toLowerCase());
    });

    _buscarDadosIniciais();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pesquisaAndamentoController.dispose();
    _pesquisaConcluidosController.dispose();
    super.dispose();
  }

  // BUSCA DADOS DO USUÁRIO E VERIFICA SE É ADMIN/CENTRAL
  Future<void> _buscarDadosIniciais() async {
    if (user == null) return;

    try {
      var doc = await FirebaseFirestore.instance.collection('usuarios').doc(user!.uid).get();
      if (doc.exists && doc.data() != null) {
        var data = doc.data()!;
        String perfil = (data['perfil'] ?? '').toString().toLowerCase();
        
        if (mounted) {
          setState(() {
            // PRIORIDADE PARA nomeCompleto CONFORME SOLICITADO
            _nomeDoVistoriadorLogado = data['nomeCompleto'] ?? data['nome'] ?? data['nome_completo'] ?? user!.email?.split('@').first.toUpperCase() ?? 'Vistoriador';
            _isAdmin = perfil.contains('admin') || perfil.contains('desenvolvedor') || perfil.contains('operador central');
            _carregandoPerfil = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Erro ao buscar perfil: $e');
    }
    
    if(mounted) {
      setState(() {
        _nomeDoVistoriadorLogado = user!.displayName ?? user!.email?.split('@').first.toUpperCase() ?? 'Vistoriador';
        _carregandoPerfil = false;
      });
    }
  }

  Future<Position> _determinarPosicao() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Os serviços de localização estão desativados no celular.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('Permissão de localização negada.');
    }
    if (permission == LocationPermission.deniedForever) return Future.error('Permissão negada permanentemente.'); 

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  void _mostrarOpcoesGPS(String georeferencia) {
    if (georeferencia.trim().isEmpty || !georeferencia.contains(' ')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Semáforo sem coordenadas cadastradas!'), backgroundColor: Colors.orange));
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Como deseja chegar ao semáforo?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade400, 
                          foregroundColor: Colors.white, 
                          padding: const EdgeInsets.symmetric(vertical: 16), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                        icon: const Icon(Icons.directions_car, size: 28),
                        label: const Text('Waze', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(context);
                          _abrirAppNavegacao(georeferencia, 'waze');
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600, 
                          foregroundColor: Colors.white, 
                          padding: const EdgeInsets.symmetric(vertical: 16), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                        icon: const Icon(Icons.map, size: 28),
                        label: const Text('Maps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(context);
                          _abrirAppNavegacao(georeferencia, 'maps');
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Future<void> _abrirAppNavegacao(String georeferencia, String app) async {
    try {
      var partes = georeferencia.trim().split(RegExp(r'\s+'));
      String lat = partes[0].trim();
      String lng = partes[1].trim();

      Uri url;
      if (app == 'waze') {
        url = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
      } else {
        url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
      }

      bool abriu = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!abriu) throw 'Não foi possível abrir o aplicativo.';
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao abrir o $app. Verifique se ele está instalado!'), backgroundColor: Colors.red));
    }
  }

  // ==== GERAR NUMERO DA OCORRÊNCIA PARA A CENTRAL ====
  Future<String> _gerarNumeroOcorrencia() async {
    int anoAtual = DateTime.now().year;
    DocumentReference contadorRef = FirebaseFirestore.instance.collection('contadores').doc('ocorrencias_$anoAtual');
    return await FirebaseFirestore.instance.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(contadorRef);
      int sequencia = 1;
      if (snapshot.exists) {
        sequencia = ((snapshot.data() as Map<String, dynamic>)['atual'] ?? 0) + 1;
        transaction.update(contadorRef, {'atual': sequencia});
      } else {
        transaction.set(contadorRef, {'atual': 1});
      }
      return '$anoAtual-${sequencia.toString().padLeft(4, '0')}';
    });
  }

  Future<void> _compartilharOcorrenciaWhatsApp(Map<String, dynamic> semaforo, String falha, String detalhes, List<Uint8List> fotosLocais, String docId) async {
    String idSemaforo = semaforo['id']?.toString() ?? 'S/N';
    String endereco = semaforo['endereco'] ?? 'Endereço não cadastrado';

    String mensagem = '🚨 *OCORRÊNCIA REGISTRADA (VISTORIA)* 🚨\n\n'
        '*Semáforo:* $idSemaforo\n'
        '*Endereço:* $endereco\n'
        '*Vistoriador:* $_nomeDoVistoriadorLogado\n' 
        '*Problema:* $falha\n'
        '*Detalhes:* ${detalhes.isEmpty ? "Sem detalhes" : detalhes}';

    try {
      List<XFile> arquivosParaCompartilhar = [];
      if (kIsWeb) {
        for (int i = 0; i < fotosLocais.length; i++) {
          arquivosParaCompartilhar.add(XFile.fromData(
              fotosLocais[i],
              mimeType: 'image/jpeg',
              name: 'foto_${docId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg'));
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        for (int i = 0; i < fotosLocais.length; i++) {
          final file = File('${tempDir.path}/foto_${docId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
          await file.writeAsBytes(fotosLocais[i], flush: true);
          arquivosParaCompartilhar.add(XFile(file.path));
        }
      }

      if (arquivosParaCompartilhar.isNotEmpty) {
        await Share.shareXFiles(arquivosParaCompartilhar, text: mensagem);
      } else {
        await Share.share(mensagem);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao compartilhar a ocorrência no WhatsApp.'), backgroundColor: Colors.red));
    }
  }

  // ==== CARIMBAR FOTOS EM MEMÓRIA ====
  Future<Uint8List> _adicionarCarimboNaFoto(Uint8List imageBytes, String semaforoInfo, String dataColetada, String gpsColetado) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes, targetWidth: 800);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(image, Offset.zero, Paint());

      final paintRect = Paint()..color = Colors.black54;
      canvas.drawRect(
        Rect.fromLTWH(0, image.height.toDouble() - 60, image.width.toDouble(), 60),
        paintRect,
      );

      final textStyle = ui.TextStyle(color: Colors.yellowAccent, fontSize: 16, fontWeight: FontWeight.bold);
      final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.right);
      final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
        ..pushStyle(textStyle)
        ..addText('SEMÁFORO: $semaforoInfo  DATA: $dataColetada  GPS: $gpsColetado');

      final paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: image.width.toDouble() - 20));
      canvas.drawParagraph(paragraph, Offset(0, image.height.toDouble() - 40));

      final picture = recorder.endRecording();
      final img = await picture.toImage(image.width, image.height);
      final jpgBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      if (jpgBytes == null) return imageBytes;
      return jpgBytes.buffer.asUint8List();
    } catch (e) {
      return imageBytes;
    }
  }

  void _mostrarImagemExpandida(BuildContext context, ImageProvider imageProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(panEnabled: true, minScale: 0.5, maxScale: 4.0, child: Image(image: imageProvider, fit: BoxFit.contain)),
              Positioned(top: 10, right: 10, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 36), onPressed: () => Navigator.pop(context))),
            ],
          ),
        );
      },
    );
  }

  pw.Widget _buildRodapePDF(pw.Context context, String dataHora) {
    return pw.Container(
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.SizedBox(width: 50),
              pw.Expanded(child: pw.Text('Relatório gerado pelo aplicativo Vistoria CTTU ($dataHora)', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
              pw.SizedBox(width: 50, child: pw.Text('Pág. ${context.pageNumber} / ${context.pagesCount}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
            ]
          )
        ]
      )
    );
  }

  Future<void> _exportarPDFIndividual(Map<String, dynamic> vistoria, String nomeVistoriador) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Baixando fotos e gerando PDF...'), backgroundColor: Colors.teal));
    
    try {
      bool temFalha = vistoria['teve_anormalidade'] == true;
      List<dynamic> urlsFotos = vistoria['fotos'] ?? [];
      List<pw.ImageProvider> imagensPdf = [];

      for (String base64Str in urlsFotos) {
        try {
          if(base64Str.startsWith('http')) {
            final imageBytes = await networkImage(base64Str);
            imagensPdf.add(imageBytes);
          } else {
            final imageBytes = base64Decode(base64Str);
            imagensPdf.add(pw.MemoryImage(imageBytes));
          }
        } catch (e) {
          debugPrint('Erro ao decodificar imagem pro pdf: $e');
        }
      }

      String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.only(left: 32, right: 32, top: 32, bottom: 20),
          footer: (pw.Context context) => _buildRodapePDF(context, dataHoraAtual),
          build: (pw.Context context) {
            return [
              pw.Row(
                children: [
                  pw.Container(width: 30, height: 30, decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: temFalha ? PdfColors.red : PdfColors.green)),
                  pw.SizedBox(width: 12),
                  pw.Text('Semáforo Nº ${vistoria['semaforo_id']}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                ]
              ),
              pw.Divider(thickness: 2, height: 32),
              pw.Text('Vistoriador: $nomeVistoriador', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('Endereço: ${vistoria['semaforo_endereco']}', style: pw.TextStyle(fontSize: 12)),
              pw.Text('Início: ${vistoria['data_hora_inicio']}', style: pw.TextStyle(fontSize: 12)),
              pw.Text('Fim: ${vistoria['data_hora_fim']}', style: pw.TextStyle(fontSize: 12)),
              pw.Text('Coordenadas GPS: ${vistoria['gps_coordenadas']}', style: pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(12), width: double.infinity, decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Text(vistoria['resumo_checklist'] ?? 'Checklist verificado.', style: pw.TextStyle(color: PdfColors.blue800, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(12), width: double.infinity,
                decoration: pw.BoxDecoration(color: temFalha ? PdfColors.red50 : PdfColors.green50, border: pw.Border.all(color: temFalha ? PdfColors.red : PdfColors.green), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(temFalha ? 'FALHA REGISTRADA:' : 'STATUS:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: temFalha ? PdfColors.red : PdfColors.green)),
                    pw.Text(vistoria['falha_registrada'] ?? 'Nenhuma', style: pw.TextStyle(fontSize: 14)),
                    pw.SizedBox(height: 8),
                    pw.Text('Detalhes:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: temFalha ? PdfColors.red : PdfColors.green)),
                    pw.Text(vistoria['detalhes_ocorrencia'] ?? 'Sem detalhes', style: pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ),

              if (imagensPdf.isNotEmpty) ...[
                pw.SizedBox(height: 24),
                pw.Text('Fotos da Ocorrência:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.SizedBox(height: 12),
                pw.Wrap(
                  spacing: 12, runSpacing: 12,
                  children: imagensPdf.map((img) => pw.Container(width: 150, height: 150, decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey), borderRadius: pw.BorderRadius.circular(8), image: pw.DecorationImage(image: img, fit: pw.BoxFit.cover)))).toList(),
                )
              ],
            ];
          }
        )
      );

      String idStr = vistoria['semaforo_id']?.toString() ?? 'SN';
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Ficha_Semaforo_$idStr.pdf');
      
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar PDF da ficha!'), backgroundColor: Colors.red));
    }
  }

  Future<void> _gerarEMostrarPDF(List<QueryDocumentSnapshot> vistorias, String rotaNumero, String nomeVistoriador) async {
    if (vistorias.isEmpty) return;
    try {
      String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape, 
          margin: const pw.EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 20),
          footer: (pw.Context context) => _buildRodapePDF(context, dataHoraAtual),
          build: (pw.Context context) {
            return [
              pw.Header(level: 0, child: pw.Text('Relatório de Vistorias Concluídas - Rota $rotaNumero', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                context: context,
                headers: ['Semáforo', 'Vistoriador', 'Endereço', 'Início', 'Fim', 'Status', 'Falha', 'Detalhes'],
                data: vistorias.map((doc) {
                  var v = doc.data() as Map<String, dynamic>;
                  String status = v['teve_anormalidade'] == true ? 'COM FALHA' : 'OK';
                  return [ 
                    v['semaforo_id']?.toString() ?? '', nomeVistoriador, v['semaforo_endereco']?.toString() ?? '', 
                    v['data_hora_inicio']?.toString() ?? '', v['data_hora_fim']?.toString() ?? '', status, 
                    v['falha_registrada'] ?? '-', v['detalhes_ocorrencia']?.toString().replaceAll('\n', ' ') ?? '-'
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
                cellAlignment: pw.Alignment.centerLeft, cellStyle: pw.TextStyle(fontSize: 7),
                columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1.2), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1), 4: const pw.FlexColumnWidth(1), 5: const pw.FlexColumnWidth(1), 6: const pw.FlexColumnWidth(1.2), 7: const pw.FlexColumnWidth(1.5) }
              ),
            ];
          }
        )
      );
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Vistorias_Concluidas_Rota$rotaNumero.pdf');
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar PDF!'), backgroundColor: Colors.red));
    }
  }

  // ==== MODAL DE VISTORIA DO SEMAFORO ====
  void _abrirVistoriaSemaforo(Map<String, dynamic> semaforo, String turnoId, String rotaNumeroDaAba) {
    bool vistoriaIniciada = false;
    String statusSalvando = ''; 
    String dataHoraInicio = '';
    String coordenadas = '';
    bool checklistConfirmado = false; 
    
    String temAnormalidade = 'Não';
    String? falhaSelecionada;
    List<Map<String, dynamic>> tiposDeFalhaLista = []; 
    List<Uint8List> fotosSelecionadas = []; 
    bool processandoFoto = false; 
    final ImagePicker picker = ImagePicker();
    
    final TextEditingController detalhesController = TextEditingController();
    final TextEditingController falhaMenuCtrl = TextEditingController();
    final TextEditingController origemCtrl = TextEditingController(text: 'ROTA $rotaNumeroDaAba');

    String geoRefSemaforo = (semaforo['georeferencia'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            
            Future<void> carregarFalhas() async {
              if (tiposDeFalhaLista.isEmpty) {
                var snapshot = await FirebaseFirestore.instance.collection('falhas').get();
                setModalState(() {
                  var listaTemp = snapshot.docs.map((doc) {
                    var d = doc.data();
                    return {
                      'id': doc.id,
                      'falha': (d['tipo_da_falha'] ?? d['falha'] ?? '').toString().toUpperCase(),
                      'prazo': (d['prazo'] ?? '').toString(),
                    };
                  }).where((e) => e['falha'].toString().isNotEmpty).toList();
                  
                  Map<String, Map<String, dynamic>> falhasUnicas = {};
                  for (var item in listaTemp) {
                    falhasUnicas[item['falha'] as String] = item;
                  }
                  
                  tiposDeFalhaLista = falhasUnicas.values.toList();
                  tiposDeFalhaLista.sort((a, b) => a['falha'].toString().compareTo(b['falha'].toString()));
                });
              }
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
                    child: Row(
                      children: [
                        CircleAvatar(backgroundColor: Colors.orange.shade800, child: Text(semaforo['id'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Vistoria do Semáforo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              Text(semaforo['endereco'] ?? 'Sem endereço', style: const TextStyle(fontSize: 14)),
                            ],
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!vistoriaIniciada) ...[
                            const Text('Opções para este semáforo:', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
                            const SizedBox(height: 24),
                            
                            SizedBox(
                              width: double.infinity, height: 55,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                icon: const Icon(Icons.directions, size: 28),
                                label: const Text('COMO CHEGAR (GPS)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  _mostrarOpcoesGPS(geoRefSemaforo);
                                },
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            const Row(
                              children: [
                                Expanded(child: Divider(thickness: 1)),
                                Padding(padding: EdgeInsets.symmetric(horizontal: 8.0), child: Text("OU", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                                Expanded(child: Divider(thickness: 1)),
                              ],
                            ),
                            const SizedBox(height: 16),

                            SizedBox(
                              width: double.infinity, height: 65,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                icon: statusSalvando.isNotEmpty ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.play_arrow, size: 30),
                                label: Text(statusSalvando.isNotEmpty ? 'Obtendo GPS...' : 'INICIAR VISTORIA NESTE LOCAL', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                onPressed: statusSalvando.isNotEmpty ? null : () async {
                                  setModalState(() => statusSalvando = 'Buscando GPS...');
                                  try {
                                    Position pos = await _determinarPosicao();
                                    String dataFormatada = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
                                    setModalState(() {
                                      coordenadas = '${pos.latitude}, ${pos.longitude}';
                                      dataHoraInicio = dataFormatada;
                                      vistoriaIniciada = true;
                                      statusSalvando = '';
                                    });
                                  } catch (e) {
                                    setModalState(() => statusSalvando = '');
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                                  }
                                },
                              ),
                            )
                          ],

                          if (vistoriaIniciada) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                              child: Column(
                                children: [
                                  Row(children: [const Icon(Icons.access_time, size: 16), const SizedBox(width: 8), Text('Iniciado em: $dataHoraInicio', style: const TextStyle(fontWeight: FontWeight.bold))]),
                                  const SizedBox(height: 4),
                                  Row(children: [const Icon(Icons.gps_fixed, size: 16), const SizedBox(width: 8), Text('GPS: $coordenadas', style: const TextStyle(fontSize: 12))]),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            
                            const Text('CHECKLIST DE VERIFICAÇÃO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
                            const Divider(thickness: 2),
                            
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              activeColor: Colors.indigo,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(textoConfirmacaoChecklist, style: const TextStyle(fontSize: 14)),
                              value: checklistConfirmado,
                              onChanged: (bool? value) => setModalState(() => checklistConfirmado = value ?? false),
                            ),

                            const SizedBox(height: 24),
                            
                            const Text('ANORMALIDADES E REGISTRO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                            const Divider(thickness: 2),
                            const Text('Foi encontrada alguma anormalidade neste semáforo?', style: TextStyle(fontSize: 16)),
                            Row(
                              children: [
                                Expanded(
                                  child: RadioListTile<String>(
                                    title: const Text('Não', style: TextStyle(fontWeight: FontWeight.bold)),
                                    value: 'Não', groupValue: temAnormalidade, activeColor: Colors.green,
                                    onChanged: (val) => setModalState(() { temAnormalidade = val!; falhaSelecionada = null; fotosSelecionadas.clear(); detalhesController.clear(); }),
                                  ),
                                ),
                                Expanded(
                                  child: RadioListTile<String>(
                                    title: const Text('Sim', style: TextStyle(fontWeight: FontWeight.bold)),
                                    value: 'Sim', groupValue: temAnormalidade, activeColor: Colors.red,
                                    onChanged: (val) { setModalState(() { temAnormalidade = val!; }); carregarFalhas(); },
                                  ),
                                ),
                              ],
                            ),

                            // ================= ÁREA DE NOVA OCORRÊNCIA INCORPORADA =================
                            if (temAnormalidade == 'Sim') ...[
                              const SizedBox(height: 12),
                              
                              TextFormField(
                                initialValue: '${semaforo['id']} - ${semaforo['endereco']}',
                                readOnly: true,
                                decoration: const InputDecoration(labelText: 'Semáforo Vistoriado *', border: OutlineInputBorder(), filled: true, fillColor: Colors.black12, isDense: true),
                              ),
                              const SizedBox(height: 12),

                              if (tiposDeFalhaLista.isEmpty)
                                const Center(child: CircularProgressIndicator())
                              else
                                DropdownMenu<String>(
                                  expandedInsets: EdgeInsets.zero,
                                  controller: falhaMenuCtrl,
                                  enableFilter: true, enableSearch: true,
                                  label: const Text('Tipo da Falha Encontrada *'),
                                  inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                                  dropdownMenuEntries: tiposDeFalhaLista.map((f) => DropdownMenuEntry<String>(value: f['falha'].toString(), label: f['falha'].toString())).toList(),
                                  onSelected: (val) => setModalState(() => falhaSelecionada = val),
                                ),
                              const SizedBox(height: 12),

                              TextFormField(
                                controller: origemCtrl,
                                readOnly: true,
                                decoration: const InputDecoration(labelText: 'Origem *', border: OutlineInputBorder(), filled: true, fillColor: Colors.black12, isDense: true),
                              ),
                              const SizedBox(height: 12),
                              
                              TextFormField(
                                controller: detalhesController,
                                maxLines: 3,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [UpperCaseTextFormatter()],
                                decoration: const InputDecoration(labelText: 'Detalhes da Ocorrência', hintText: 'Descreva a anormalidade...', border: OutlineInputBorder(), alignLabelWithHint: true),
                              ),
                              
                              const SizedBox(height: 24),
                              const Text('FOTOS DO PROBLEMA (Obrigatório, Máx. 4)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                              const SizedBox(height: 12),
                              
                              if (processandoFoto)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 12.0),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                      SizedBox(width: 12),
                                      Text('Gravando GPS e Data na foto...', style: TextStyle(color: Colors.blue, fontStyle: FontStyle.italic))
                                    ],
                                  ),
                                ),

                              if (fotosSelecionadas.isNotEmpty)
                                SizedBox(
                                  height: 100,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: fotosSelecionadas.length,
                                    itemBuilder: (context, index) {
                                      return Stack(
                                        children: [
                                          Container(
                                            margin: const EdgeInsets.only(right: 8),
                                            width: 100, height: 100,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.grey.shade300),
                                              image: DecorationImage(image: MemoryImage(fotosSelecionadas[index]), fit: BoxFit.cover),
                                            ),
                                          ),
                                          Positioned(
                                            top: 2, right: 10,
                                            child: GestureDetector(
                                              onTap: () => setModalState(() => fotosSelecionadas.removeAt(index)),
                                              child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(height: 8),
                              
                              // ================= BOTÃO CÂMERA ÚNICO =================
                              if (fotosSelecionadas.length < 4)
                                SizedBox(
                                  width: double.infinity, height: 60,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.blue, width: 2),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      backgroundColor: Colors.blue.shade50
                                    ),
                                    icon: const Icon(Icons.camera_alt, color: Colors.blue, size: 28),
                                    label: const Text('ABRIR CÂMERA', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16)),
                                    onPressed: (statusSalvando.isNotEmpty || processandoFoto) ? null : () async {
                                      final XFile? foto = await picker.pickImage(source: ImageSource.camera, imageQuality: 40);
                                      if (foto != null) {
                                        setModalState(() => processandoFoto = true);
                                        Uint8List bytes = await foto.readAsBytes();
                                        Uint8List carimbada = await _adicionarCarimboNaFoto(bytes, semaforo['id'].toString(), dataHoraInicio, coordenadas);
                                        setModalState(() {
                                          fotosSelecionadas.add(carimbada);
                                          processandoFoto = false;
                                        });
                                      }
                                    },
                                  ),
                                ),
                            ],
                            
                            if (temAnormalidade == 'Não') ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.green.shade50, border: Border.all(color: Colors.green), borderRadius: BorderRadius.circular(8)),
                                child: const Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green, size: 36),
                                    SizedBox(width: 12),
                                    Expanded(child: Text('Você confirma que o semáforo foi vistoriado por completo e NÃO apresenta defeitos?', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 32),

                            SizedBox(
                              width: double.infinity, height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                onPressed: (statusSalvando.isNotEmpty || processandoFoto) ? null : () async {
                                  if (!checklistConfirmado) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Você precisa marcar a caixa confirmando a verificação do checklist!'), backgroundColor: Colors.red));
                                    return;
                                  }
                                  
                                  String detalhesFinais = detalhesController.text.trim();

                                  if (temAnormalidade == 'Sim') {
                                    if (falhaMenuCtrl.text.isEmpty) { 
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione qual foi a falha encontrada!'), backgroundColor: Colors.red)); 
                                      return; 
                                    }
                                    
                                    bool falhaValida = tiposDeFalhaLista.any((f) => f['falha'] == falhaMenuCtrl.text);
                                    if (!falhaValida) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma falha válida da lista!'), backgroundColor: Colors.red)); 
                                      return; 
                                    }

                                    if (fotosSelecionadas.isEmpty) { 
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('É obrigatório anexar pelo menos 1 foto do defeito!'), backgroundColor: Colors.red)); 
                                      return; 
                                    }
                                    falhaSelecionada = falhaMenuCtrl.text;
                                  } else {
                                    detalhesFinais = 'O semáforo foi vistoriado por completo e não foram identificadas anormalidades.';
                                  }

                                  final scaffoldMsg = ScaffoldMessenger.of(context);
                                  final nav = Navigator.of(context);

                                  setModalState(() => statusSalvando = 'Iniciando salvamento...');

                                  try {
                                    List<String> fotosEmBase64ParaOcorrencia = [];
                                    
                                    if (fotosSelecionadas.isNotEmpty) {
                                      for (int i = 0; i < fotosSelecionadas.length; i++) {
                                        setModalState(() => statusSalvando = 'Salvando foto ${i + 1} de ${fotosSelecionadas.length}...');
                                        fotosEmBase64ParaOcorrencia.add(base64Encode(fotosSelecionadas[i]));
                                      }
                                    }

                                    setModalState(() => statusSalvando = 'Salvando vistoria...');
                                    String dataFormatadaFim = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
                                    
                                    await FirebaseFirestore.instance.collection('vistoria').add({
                                      'turno_id': turnoId,
                                      'vistoriador_uid': user!.uid,
                                      'semaforo_id': semaforo['id'],
                                      'semaforo_endereco': semaforo['endereco'],
                                      'data_hora_inicio': dataHoraInicio,
                                      'data_hora_fim': dataFormatadaFim,
                                      'gps_coordenadas': coordenadas,
                                      'resumo_checklist': textoConfirmacaoChecklist, 
                                      'teve_anormalidade': temAnormalidade == 'Sim',
                                      'falha_registrada': falhaSelecionada ?? 'Nenhuma',
                                      'detalhes_ocorrencia': detalhesFinais, 
                                      'fotos': fotosEmBase64ParaOcorrencia, 
                                      'criado_em': FieldValue.serverTimestamp(),
                                    });

                                    if (temAnormalidade == 'Sim') {
                                      setModalState(() => statusSalvando = 'Criando ocorrência para a central...');
                                      String numOcorrencia = await _gerarNumeroOcorrencia();
                                      
                                      String prazoFalha = '';
                                      try {
                                        var falhaCadastrada = tiposDeFalhaLista.firstWhere((x) => x['falha'] == falhaSelecionada);
                                        prazoFalha = falhaCadastrada['prazo'] ?? '';
                                      } catch(_) {}

                                      await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').add({
                                        'numero_da_ocorrencia': numOcorrencia,
                                        'semaforo': semaforo['id'],
                                        'endereco': semaforo['endereco'],
                                        'bairro': semaforo['bairro'] ?? '',
                                        'empresa_semaforo': semaforo['empresa'] ?? '',
                                        'georeferencia': coordenadas,
                                        'tipo_da_falha': falhaSelecionada,
                                        'detalhes': detalhesFinais,
                                        'origem_da_ocorrencia': origemCtrl.text.toUpperCase(), 
                                        'status': 'Aberto', 
                                        'data_de_abertura': FieldValue.serverTimestamp(),
                                        'data_atualizacao': FieldValue.serverTimestamp(),
                                        'usuario_abertura': _nomeDoVistoriadorLogado,
                                        'fotos': fotosEmBase64ParaOcorrencia, 
                                        'prazo': prazoFalha,
                                      });

                                      nav.pop(); 
                                      scaffoldMsg.showSnackBar(const SnackBar(content: Text('Vistoria e Ocorrência salvas com sucesso!'), backgroundColor: Colors.green));
                                      
                                      await _compartilharOcorrenciaWhatsApp(semaforo, falhaSelecionada!, detalhesFinais, fotosSelecionadas, numOcorrencia);
                                    } else {
                                      nav.pop(); 
                                      scaffoldMsg.showSnackBar(const SnackBar(content: Text('Vistoria salva com sucesso!'), backgroundColor: Colors.green));
                                    }
                                  } catch (e) {
                                    setModalState(() => statusSalvando = '');
                                    scaffoldMsg.showSnackBar(SnackBar(content: Text('Erro ao salvar vistoria! $e'), backgroundColor: Colors.red));
                                  }
                                },
                                child: statusSalvando.isNotEmpty 
                                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)), const SizedBox(width: 12), Text(statusSalvando, style: const TextStyle(fontWeight: FontWeight.bold))])
                                  : const Text('SALVAR E CONCLUIR VISTORIA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _exportarExcelConcluidos(List<QueryDocumentSnapshot> vistorias, String rotaNumero, String nomeVistoriador) async {
    if (vistorias.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando Excel...'), backgroundColor: Colors.green));
    try {
      String csv = '\uFEFF'; 
      csv += 'SEMAFORO;VISTORIADOR;ENDERECO;INICIO;FIM;COORDENADAS;STATUS;FALHA;DETALHES\n';
      
      for (var doc in vistorias) {
        var v = doc.data() as Map<String, dynamic>;
        String status = v['teve_anormalidade'] == true ? 'COM FALHA' : 'OK';
        
        csv += '${v['semaforo_id']};$nomeVistoriador;${v['semaforo_endereco']};${v['data_hora_inicio']};${v['data_hora_fim']};${v['gps_coordenadas']};$status;${v['falha_registrada']};${v['detalhes_ocorrencia']?.toString().replaceAll('\n', ' ')}\n';
      }
      
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/Vistorias_Rota$rotaNumero.csv';
      final file = File(path);
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(path)], text: 'Planilha de Vistorias Concluídas - Rota $rotaNumero.');
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar Excel!'), backgroundColor: Colors.red));
    }
  }

  void _mostrarDetalhesVistoria(Map<String, dynamic> vistoria, String rotaDaAba, String nomeVistoriador) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        bool temFalha = vistoria['teve_anormalidade'] == true;
        List<dynamic> fotos = vistoria['fotos'] ?? [];

        return DraggableScrollableSheet(
          initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(temFalha ? Icons.warning_amber_rounded : Icons.check_circle, color: temFalha ? Colors.red : Colors.green, size: 36),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Semáforo Nº ${vistoria['semaforo_id']}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800))),
                      ],
                    ),
                    const Divider(thickness: 2, height: 32),
                    
                    _buildInfoRow('Vistoriador', nomeVistoriador),
                    _buildInfoRow('Endereço', vistoria['semaforo_endereco']),
                    _buildInfoRow('Início', vistoria['data_hora_inicio']),
                    _buildInfoRow('Fim', vistoria['data_hora_fim']),
                    _buildInfoRow('Coordenadas GPS', vistoria['gps_coordenadas']),
                    const SizedBox(height: 16),
                    
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.playlist_add_check, color: Colors.blue, size: 28),
                          const SizedBox(width: 12),
                          Expanded(child: Text(vistoria['resumo_checklist'] ?? 'Checklist não registrado.', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(12), width: double.infinity,
                      decoration: BoxDecoration(color: temFalha ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: temFalha ? Colors.red : Colors.green)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(temFalha ? 'FALHA REGISTRADA:' : 'STATUS:', style: TextStyle(fontWeight: FontWeight.bold, color: temFalha ? Colors.red : Colors.green)),
                          Text(vistoria['falha_registrada'] ?? 'Nenhuma', style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('Detalhes:', style: TextStyle(fontWeight: FontWeight.bold, color: temFalha ? Colors.red : Colors.green)),
                          Text(vistoria['detalhes_ocorrencia'] ?? 'Sem detalhes', style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),

                    if (fotos.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text('Fotos da Ocorrência:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12, runSpacing: 12,
                        children: fotos.map((base64Str) {
                          try {
                            return GestureDetector(
                              onTap: () => _mostrarImagemExpandida(context, MemoryImage(base64Decode(base64Str.toString()))),
                              child: Container(
                                width: 100, height: 100,
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey)),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(base64Decode(base64Str.toString()), fit: BoxFit.cover),
                                ),
                              ),
                            );
                          } catch (_) { return const SizedBox.shrink(); }
                        }).toList(),
                      )
                    ],
                    
                    const SizedBox(height: 32),
                    
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Exportar PDF Desta Vistoria', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => _exportarPDFIndividual(vistoria, nomeVistoriador),
                      ),
                    ),
                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade300, foregroundColor: Colors.black87),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fechar Ficha', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(text: TextSpan(style: const TextStyle(color: Colors.black87, fontSize: 15), children: [
        TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        TextSpan(text: value ?? '-'),
      ])),
    );
  }

  // ============================================================================
  // TELA DO ADMIN: LISTA DE VISTORIADORES EM CAMPO
  // ============================================================================
  Widget _buildVisaoListaAdmin() {
    DateTime dataBase = DateTime(2024, 1, 1);
    int diasPassados = DateTime.now().difference(dataBase).inDays;
    String grupoDeHoje = (diasPassados % 2 == 0) ? 'A' : 'B';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoramento de Rotas', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange.shade400,
        foregroundColor: Colors.white,
        actions: const [MenuUsuario()],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.orange.shade50,
            child: Column(
              children: [
                Icon(Icons.dashboard_customize, size: 48, color: Colors.orange.shade700),
                const SizedBox(height: 8),
                const Text('Vistoriadores em Rota', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Grupo do dia em vigência: Lado $grupoDeHoje', style: TextStyle(color: Colors.orange.shade900)),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('semaforos').snapshots(),
              builder: (context, snapshotSemaforos) {
                if (snapshotSemaforos.hasError) return const Center(child: Text('Erro ao carregar dados.'));
                if (!snapshotSemaforos.hasData) return const Center(child: CircularProgressIndicator());

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('turnos').where('status', isEqualTo: 'ativo').snapshots(),
                  builder: (context, snapshotTurnos) {
                    if (snapshotTurnos.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (snapshotTurnos.hasError) return Center(child: Text('Erro: ${snapshotTurnos.error}', style: const TextStyle(color: Colors.red)));
                    
                    final turnos = snapshotTurnos.data!.docs.toList();
                    
                    turnos.sort((a, b) {
                      var dataA = a.data() as Map<String, dynamic>;
                      var dataB = b.data() as Map<String, dynamic>;
                      Timestamp? tempoA = dataA['data_inicio'] as Timestamp?;
                      Timestamp? tempoB = dataB['data_inicio'] as Timestamp?;
                      if (tempoA == null && tempoB == null) return 0;
                      if (tempoA == null) return 1;
                      if (tempoB == null) return -1;
                      return tempoB.compareTo(tempoA);
                    });

                    if (turnos.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.motorcycle_outlined, size: 60, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text('Nenhuma rota em andamento no momento.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: turnos.length,
                      itemBuilder: (context, index) {
                        var doc = turnos[index];
                        var t = doc.data() as Map<String, dynamic>;
                        
                        String rotaNumero = t['rota_numero'] ?? 'S/R';
                        String rotaTurnoLimpa = rotaNumero.replaceFirst(RegExp(r'^0+'), '');

                        List<DocumentSnapshot> todosDaRota = snapshotSemaforos.data!.docs.where((s) {
                          return (s.data() as Map<String, dynamic>)['rota'].toString().replaceFirst(RegExp(r'^0+'), '') == rotaTurnoLimpa;
                        }).toList();

                        int meta = todosDaRota.where((s) {
                          String lado = ((s.data() as Map)['lado_vistoria'] ?? (s.data() as Map)['grupo'] ?? 'A').toString().toUpperCase();
                          return lado == grupoDeHoje;
                        }).length;

                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('vistoria').where('turno_id', isEqualTo: doc.id).snapshots(),
                          builder: (context, snapshotVistorias) {
                            int concluidos = snapshotVistorias.hasData ? snapshotVistorias.data!.docs.length : 0;
                            double percentual = meta == 0 ? 0.0 : (concluidos / meta);

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(() {
                                    _turnoSelecionadoAdmin = doc;
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 24,
                                                backgroundColor: Colors.orange.shade100, 
                                                child: Text(rotaNumero, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontSize: 16))
                                              ),
                                              const SizedBox(width: 12),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Rota $rotaNumero', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(color: Colors.deepOrange.shade50, borderRadius: BorderRadius.circular(4)),
                                                    child: Text('Grupo $grupoDeHoje', style: TextStyle(color: Colors.deepOrange.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
                                                  )
                                                ],
                                              ),
                                            ],
                                          ),
                                          const Icon(Icons.arrow_forward_ios, color: Colors.orange),
                                        ],
                                      ),
                                      const Divider(height: 24),
                                      
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(children: [const Icon(Icons.person, size: 16, color: Colors.grey), const SizedBox(width: 6), Text(t['vistoriador_nome'] ?? 'Vistoriador', style: const TextStyle(fontWeight: FontWeight.bold))]),
                                          Row(children: [const Icon(Icons.motorcycle, size: 16, color: Colors.grey), const SizedBox(width: 6), Text(t['placa'] ?? 'S/P', style: const TextStyle(fontWeight: FontWeight.bold))]),
                                        ],
                                      ),
                                      
                                      const SizedBox(height: 16),
                                      
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                                        children: [
                                          Text('Progresso: $concluidos de $meta', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700, fontSize: 12)), 
                                          Text('${(percentual * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12))
                                        ]
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8), 
                                        child: LinearProgressIndicator(
                                          value: percentual, 
                                          minHeight: 8, 
                                          backgroundColor: Colors.grey.shade300, 
                                          color: percentual >= 1.0 ? Colors.blue : Colors.green
                                        )
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                        );
                      },
                    );
                  },
                );
              }
            ),
          )
        ],
      )
    );
  }

  Widget _buildVisaoDetalheTurno(DocumentSnapshot turnoDoc) {
    var turnoData = turnoDoc.data() as Map<String, dynamic>;
    String rotaNumero = turnoData['rota_numero'] ?? 'S/N';
    String rotaTurnoLimpa = rotaNumero.replaceFirst(RegExp(r'^0+'), ''); 
    String nomeDoVistoriadorDesteTurno = turnoData['vistoriador_nome'] ?? 'Desconhecido';

    return Scaffold(
      appBar: AppBar(
        leading: _isAdmin ? IconButton(
          icon: const Icon(Icons.arrow_back), 
          onPressed: () => setState(() => _turnoSelecionadoAdmin = null) 
        ) : null,
        title: Text(_isAdmin ? 'Vistoriando Rota $rotaNumero' : 'Vistoria em Campo', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange.shade300,
        actions: const [MenuUsuario()], 
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black87,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.orange.shade900,
          tabs: const [
            Tab(icon: Icon(Icons.map), text: 'Em Andamento'),
            Tab(icon: Icon(Icons.checklist), text: 'Concluídos'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('semaforos').snapshots(),
        builder: (context, snapshotSemaforo) {
          if (!snapshotSemaforo.hasData) return const Center(child: CircularProgressIndicator());
          
          DateTime now = DateTime.now();
          DateTime startOfDay = DateTime(now.year, now.month, now.day);
          
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('vistoria')
                .where('criado_em', isGreaterThanOrEqualTo: startOfDay)
                .snapshots(),
            builder: (context, snapshotVistoriasDoDia) {
              if (!snapshotVistoriasDoDia.hasData) return const Center(child: CircularProgressIndicator());

              List<QueryDocumentSnapshot> vistoriasConcluidasDoTurnoAtual = snapshotVistoriasDoDia.data!.docs.where((doc) => (doc.data() as Map<String, dynamic>)['turno_id'] == turnoDoc.id).toList();

              Set<String> vistoriadosIdsHoje = snapshotVistoriasDoDia.data!.docs.map((doc) => (doc.data() as Map)['semaforo_id'].toString()).toSet();

              List<DocumentSnapshot> todosDaRota = snapshotSemaforo.data!.docs.where((doc) {
                return (doc.data() as Map<String, dynamic>)['rota'].toString().replaceFirst(RegExp(r'^0+'), '') == rotaTurnoLimpa;
              }).toList();

              DateTime dataBase = DateTime(2024, 1, 1);
              int diasPassados = DateTime.now().difference(dataBase).inDays;
              String grupoDeHoje = (diasPassados % 2 == 0) ? 'A' : 'B';

              List<DocumentSnapshot> semaforosDoGrupo = todosDaRota.where((doc) {
                String grupoDb = ((doc.data() as Map)['lado_vistoria'] ?? (doc.data() as Map)['grupo'] ?? 'A').toString().toUpperCase();
                return grupoDb == grupoDeHoje;
              }).toList();

              int meta = semaforosDoGrupo.length;
              int concluidosGerais = semaforosDoGrupo.where((doc) => vistoriadosIdsHoje.contains((doc.data() as Map)['id'].toString())).length;
              int falta = meta - concluidosGerais;
              double percentual = meta == 0 ? 0.0 : (concluidosGerais / meta);

              List<DocumentSnapshot> semaforosPendentes = semaforosDoGrupo.where((doc) {
                var semaforo = doc.data() as Map<String, dynamic>;
                String id = semaforo['id'].toString();
                return !vistoriadosIdsHoje.contains(id); 
              }).toList();

              var semaforosFiltradosPesquisa = semaforosPendentes.where((doc) {
                if (_textoPesquisaAndamento.isEmpty) return true;
                var data = doc.data() as Map<String, dynamic>;
                String id = (data['id'] ?? '').toString().toLowerCase();
                String end = (data['endereco'] ?? '').toString().toLowerCase();
                return id.contains(_textoPesquisaAndamento) || end.contains(_textoPesquisaAndamento);
              }).toList();

              semaforosFiltradosPesquisa.sort((a, b) {
                int ordemA = (a.data() as Map)['ordem_vistoria'] ?? 999;
                int ordemB = (b.data() as Map)['ordem_vistoria'] ?? 999;
                return ordemA.compareTo(ordemB);
              });

              return TabBarView(
                controller: _tabController,
                children: [
                  // ==== ABA 1: EM ANDAMENTO ====
                  Column(
                    children: [
                      Container(
                        color: Colors.orange.shade50, padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Rota $rotaNumero', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                            Text('Seu Grupo de Hoje: $grupoDeHoje', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                            const SizedBox(height: 8),
                            Row(children: [
                              Icon(_isAdmin ? Icons.person : Icons.motorcycle, size: 18, color: Colors.grey), 
                              const SizedBox(width: 8), 
                              Text(_isAdmin ? 'Vistoriador: $nomeDoVistoriadorDesteTurno' : 'Moto: ${turnoData['placa'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87))
                            ]),
                            const SizedBox(height: 12),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Progresso (Geral Hoje): $concluidosGerais de $meta', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700)), Text('Faltam: $falta', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700))]),
                            const SizedBox(height: 6),
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: percentual, minHeight: 10, backgroundColor: Colors.grey.shade300, color: Colors.green)),
                            const SizedBox(height: 4),
                            Align(alignment: Alignment.centerRight, child: Text('${(percentual * 100).toStringAsFixed(1)}% Concluído', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green))),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), color: Colors.white,
                        child: TextField(controller: _pesquisaAndamentoController, decoration: InputDecoration(hintText: 'Pesquisar nº ou endereço...', prefixIcon: const Icon(Icons.search), suffixIcon: _textoPesquisaAndamento.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _pesquisaAndamentoController.clear()) : null, filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 0))),
                      ),
                      Expanded(
                        child: semaforosFiltradosPesquisa.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(falta == 0 && meta > 0 ? Icons.emoji_events : Icons.search_off, size: 80, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(falta == 0 && meta > 0 ? '🎉 Rota Finalizada!' : 'Nenhum semáforo pendente do Grupo $grupoDeHoje.', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              )
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1),
                              itemCount: semaforosFiltradosPesquisa.length,
                              itemBuilder: (context, index) {
                                var semaforo = semaforosFiltradosPesquisa[index].data() as Map<String, dynamic>;
                                String rawId = semaforo['id']?.toString() ?? '0';
                                String idSemaforo = rawId.padLeft(3, '0');
                                String enderecoSemaforo = semaforo['endereco'] ?? 'Sem endereço cadastrado';
                                
                                return Tooltip(
                                  message: enderecoSemaforo, triggerMode: TooltipTriggerMode.longPress,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(100),
                                    onTap: () => _abrirVistoriaSemaforo(semaforo, turnoDoc.id, rotaNumero),
                                    child: Container(
                                      decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle, border: Border.all(color: Colors.orange, width: 2), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2))]),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(idSemaforo, style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 18)),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                      ),
                    ],
                  ),
                  
                  // ==== ABA 2: CONCLUÍDOS ====
                  Column(
                    children: [
                      Container(
                        color: Colors.white, padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white), icon: const Icon(Icons.picture_as_pdf), label: const Text('Baixar PDF de Hoje'), onPressed: () => _gerarEMostrarPDF(vistoriasConcluidasDoTurnoAtual, rotaNumero, nomeDoVistoriadorDesteTurno)),
                            ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), icon: const Icon(Icons.grid_on), label: const Text('Exportar Excel'), onPressed: () => _exportarExcelConcluidos(vistoriasConcluidasDoTurnoAtual, rotaNumero, nomeDoVistoriadorDesteTurno)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.white,
                        child: TextField(controller: _pesquisaConcluidosController, decoration: InputDecoration(hintText: 'Pesquisar na lista...', prefixIcon: const Icon(Icons.search), suffixIcon: _textoPesquisaConcluidos.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _pesquisaConcluidosController.clear()) : null, filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 0))),
                      ),
                      Expanded(
                        child: vistoriasConcluidasDoTurnoAtual.isEmpty
                          ? const Center(child: Text('Nenhuma vistoria finalizada neste turno ainda.', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: vistoriasConcluidasDoTurnoAtual.length,
                              itemBuilder: (context, index) {
                                var vistoria = vistoriasConcluidasDoTurnoAtual[index].data() as Map<String, dynamic>;
                                String idSemaforo = vistoria['semaforo_id']?.toString() ?? '';
                                String endSemaforo = vistoria['semaforo_endereco']?.toString() ?? '';
                                
                                if (_textoPesquisaConcluidos.isNotEmpty && !idSemaforo.toLowerCase().contains(_textoPesquisaConcluidos) && !endSemaforo.toLowerCase().contains(_textoPesquisaConcluidos)) return const SizedBox.shrink();

                                bool temFalha = vistoria['teve_anormalidade'] == true;
                                Color corFundo = temFalha ? Colors.red.shade50 : Colors.grey.shade200;
                                Color corIcone = temFalha ? Colors.red.shade700 : Colors.grey.shade600;

                                return Card(
                                  color: corFundo,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(backgroundColor: corIcone, child: Text(idSemaforo, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                    title: Text('Semáforo $idSemaforo', style: TextStyle(fontWeight: FontWeight.bold, color: corIcone)),
                                    subtitle: Text(endSemaforo, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: Icon(temFalha ? Icons.warning_amber_rounded : Icons.check_circle, color: corIcone),
                                    onTap: () => _mostrarDetalhesVistoria(vistoria, rotaNumero, nomeDoVistoriadorDesteTurno), 
                                  ),
                                );
                              },
                            )
                      )
                    ],
                  )
                ],
              );
            }
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) return const Scaffold(body: Center(child: Text('Erro: Usuário não logado.')));
    if (_carregandoPerfil) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_isAdmin && _turnoSelecionadoAdmin == null) {
      return _buildVisaoListaAdmin();
    }

    if (_isAdmin && _turnoSelecionadoAdmin != null) {
      return _buildVisaoDetalheTurno(_turnoSelecionadoAdmin!);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('turnos').where('vistoriador_uid', isEqualTo: user!.uid).where('status', isEqualTo: 'ativo').limit(1).snapshots(),
      builder: (context, snapshotTurno) {
        if (snapshotTurno.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        
        if (!snapshotTurno.hasData || snapshotTurno.data!.docs.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Vistoria em Campo'), 
              backgroundColor: Colors.orange.shade300,
              actions: const [MenuUsuario()],
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  Icon(Icons.block, size: 80, color: Colors.red.shade300), 
                  const SizedBox(height: 16), 
                  const Text('Nenhum turno ativo.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), 
                  ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar ao Início'))
                ]
              )
            )
          );
        }

        return _buildVisaoDetalheTurno(snapshotTurno.data!.docs.first);
      }
    );
  }
}