import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
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
import 'package:image/image.dart' as img; 
import 'package:url_launcher/url_launcher.dart'; 

// IMPORTAÇÃO DO MENU (LOGOUT E PERFIL)
import '../../widgets/menu_usuario.dart';

class IniciarTurnoPage extends StatefulWidget {
  const IniciarTurnoPage({super.key});

  @override
  State<IniciarTurnoPage> createState() => _IniciarTurnoPageState();
}

class _IniciarTurnoPageState extends State<IniciarTurnoPage> with SingleTickerProviderStateMixin {
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
            // VERIFICAÇÃO DE PERFIL ATUALIZADA
            _isAdmin = perfil.contains('admin') || perfil.contains('desenvolvedor') || perfil.contains('operador central');
            _nomeDoVistoriadorLogado = data['nome'] ?? data['nome_completo'] ?? user!.email?.split('@').first.toUpperCase() ?? 'Vistoriador';
            _carregandoPerfil = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Erro ao buscar perfil: $e');
    }
    
    if(mounted) setState(() {
      _nomeDoVistoriadorLogado = user!.displayName ?? user!.email?.split('@').first.toUpperCase() ?? 'Vistoriador';
      _carregandoPerfil = false;
    });
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

    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
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

  Future<void> _enviarOcorrencia(Map<String, dynamic> semaforo, String falha, String detalhes, List<File> fotosLocais) async {
    String idSemaforo = semaforo['id']?.toString() ?? 'S/N';
    String endereco = semaforo['endereco'] ?? 'Endereço não cadastrado';

    String mensagem = '🚨 *OCORRÊNCIA REGISTRADA* 🚨\n\n'
        '*Semáforo:* $idSemaforo\n'
        '*Endereço:* $endereco\n'
        '*Vistoriador:* $_nomeDoVistoriadorLogado\n'
        '*Problema:* $falha\n'
        '*Detalhes:* ${detalhes.isEmpty ? "Sem detalhes" : detalhes}';

    try {
      if (fotosLocais.isNotEmpty) {
        List<XFile> xFiles = fotosLocais.map((f) => XFile(f.path)).toList();
        await Share.shareXFiles(xFiles, text: mensagem);
      } else {
        await Share.share(mensagem);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao compartilhar a ocorrência.'), backgroundColor: Colors.red));
    }
  }

  Future<File> _carimbarFoto(File arquivoOriginal, String semaforoInfo, String dataColetada, String gpsColetado) async {
    try {
      final bytes = await arquivoOriginal.readAsBytes();
      img.Image? imagemDecodificada = img.decodeImage(bytes);
      
      if (imagemDecodificada == null) return arquivoOriginal; 

      List<String> linhasTexto = [
        'Semaforo: $semaforoInfo',
        'Data: $dataColetada',
        'GPS: $gpsColetado'
      ];

      final fonteParaCarimbo = img.arial48;
      int yInicial = imagemDecodificada.height - (linhasTexto.length * fonteParaCarimbo.lineHeight) - 30;

      for (int i = 0; i < linhasTexto.length; i++) {
        String texto = linhasTexto[i];
        int posY = yInicial + (i * fonteParaCarimbo.lineHeight);

        img.drawString(imagemDecodificada, texto, font: fonteParaCarimbo, x: 23, y: posY + 3, color: img.ColorRgb8(0, 0, 0));
        img.drawString(imagemDecodificada, texto, font: fonteParaCarimbo, x: 20, y: posY, color: img.ColorRgb8(255, 255, 0));
      }

      final novosBytes = img.encodeJpg(imagemDecodificada, quality: 85); 
      await arquivoOriginal.writeAsBytes(novosBytes);
      return arquivoOriginal;
    } catch (e) {
      debugPrint('Erro ao carimbar foto: $e');
      return arquivoOriginal; 
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
              Positioned(top: 10, right: 10, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.white, size: 36), onPressed: () => Navigator.pop(context))),
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
              pw.Expanded(child: pw.Text('Relatório gerado pelo aplicativo Vistoria CTTU ($dataHora)', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
              pw.SizedBox(width: 50, child: pw.Text('Pág. ${context.pageNumber} / ${context.pagesCount}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
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

      for (String url in urlsFotos) {
        try {
          final imageBytes = await networkImage(url);
          imagensPdf.add(imageBytes);
        } catch (e) {
          debugPrint('Erro ao baixar imagem pro pdf: $e');
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
              pw.Text('Endereço: ${vistoria['semaforo_endereco']}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Início: ${vistoria['data_hora_inicio']}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Fim: ${vistoria['data_hora_fim']}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Coordenadas GPS: ${vistoria['gps_coordenadas']}', style: const pw.TextStyle(fontSize: 12)),
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
                    pw.Text(vistoria['falha_registrada'] ?? 'Nenhuma', style: const pw.TextStyle(fontSize: 14)),
                    pw.SizedBox(height: 8),
                    pw.Text('Detalhes:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: temFalha ? PdfColors.red : PdfColors.green)),
                    pw.Text(vistoria['detalhes_ocorrencia'] ?? 'Sem detalhes', style: const pw.TextStyle(fontSize: 12)),
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
                headers: ['Semáforo', 'Vistoriador', 'Endereço', 'Início', 'Fim', 'Status', 'Falha', 'Detalhes', 'Fotos (Links)'],
                data: vistorias.map((doc) {
                  var v = doc.data() as Map<String, dynamic>;
                  String status = v['teve_anormalidade'] == true ? 'COM FALHA' : 'OK';
                  List<dynamic> fotos = v['fotos'] ?? [];
                  return [ 
                    v['semaforo_id']?.toString() ?? '', nomeVistoriador, v['semaforo_endereco']?.toString() ?? '', 
                    v['data_hora_inicio']?.toString() ?? '', v['data_hora_fim']?.toString() ?? '', status, 
                    v['falha_registrada'] ?? '-', v['detalhes_ocorrencia']?.toString().replaceAll('\n', ' ') ?? '-', fotos.join('\n\n')
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
                cellAlignment: pw.Alignment.centerLeft, cellStyle: const pw.TextStyle(fontSize: 7),
                columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1.2), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1), 4: const pw.FlexColumnWidth(1), 5: const pw.FlexColumnWidth(1), 6: const pw.FlexColumnWidth(1.2), 7: const pw.FlexColumnWidth(1.5), 8: const pw.FlexColumnWidth(2) }
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


  void _abrirVistoriaSemaforo(Map<String, dynamic> semaforo, String turnoId) {
    bool vistoriaIniciada = false;
    bool salvando = false;
    String dataHoraInicio = '';
    String coordenadas = '';
    bool checklistConfirmado = false; 
    
    String temAnormalidade = 'Não';
    String? falhaSelecionada;
    List<Map<String, dynamic>> tiposDeFalhaLista = []; 
    List<File> fotos = []; 
    bool processandoFoto = false; 
    final ImagePicker picker = ImagePicker();
    final TextEditingController detalhesController = TextEditingController();

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
                var snapshot = await FirebaseFirestore.instance.collection('tipos_falha').orderBy('falha').get();
                setModalState(() {
                  tiposDeFalhaLista = snapshot.docs.map((doc) => {'id': doc.id, 'falha': doc['falha']}).toList();
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
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ================= TELA ANTES DE INICIAR A VISTORIA =================
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
                                icon: salvando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.play_arrow, size: 30),
                                label: Text(salvando ? 'Obtendo GPS...' : 'INICIAR VISTORIA NESTE LOCAL', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                onPressed: salvando ? null : () async {
                                  setModalState(() => salvando = true);
                                  try {
                                    Position pos = await _determinarPosicao();
                                    String dataFormatada = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
                                    setModalState(() {
                                      coordenadas = '${pos.latitude}, ${pos.longitude}';
                                      dataHoraInicio = dataFormatada;
                                      vistoriaIniciada = true;
                                      salvando = false;
                                    });
                                  } catch (e) {
                                    setModalState(() => salvando = false);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                                  }
                                },
                              ),
                            )
                          ],

                          // ================= TELA APÓS INICIAR A VISTORIA =================
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
                                    onChanged: (val) => setModalState(() { temAnormalidade = val!; falhaSelecionada = null; fotos.clear(); detalhesController.clear(); }),
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

                            if (temAnormalidade == 'Sim') ...[
                              const SizedBox(height: 12),
                              if (tiposDeFalhaLista.isEmpty)
                                const Center(child: CircularProgressIndicator())
                              else
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Selecione a Falha Encontrada', border: OutlineInputBorder()),
                                  value: falhaSelecionada,
                                  items: tiposDeFalhaLista.map((f) => DropdownMenuItem<String>(value: f['falha'], child: Text(f['falha'], overflow: TextOverflow.ellipsis))).toList(),
                                  onChanged: (val) => setModalState(() => falhaSelecionada = val),
                                ),
                              
                              const SizedBox(height: 16),
                              TextField(
                                controller: detalhesController,
                                maxLines: 3,
                                textCapitalization: TextCapitalization.sentences,
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

                              Wrap(
                                spacing: 12, runSpacing: 12,
                                children: [
                                  ...List.generate(fotos.length, (index) {
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _mostrarImagemExpandida(context, FileImage(fotos[index])),
                                          child: Container(
                                            width: 80, height: 80, 
                                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300), image: DecorationImage(image: FileImage(fotos[index]), fit: BoxFit.cover)),
                                            child: const Align(alignment: Alignment.bottomLeft, child: Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.zoom_in, color: Colors.white, size: 20))),
                                          ),
                                        ),
                                        Positioned(right: -8, top: -8, child: GestureDetector(onTap: () => setModalState(() => fotos.removeAt(index)), child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, color: Colors.white, size: 16))))
                                      ]
                                    );
                                  }),
                                  if (fotos.length < 4 && !processandoFoto)
                                    InkWell(
                                      onTap: () async {
                                        final XFile? fotoTirada = await picker.pickImage(source: ImageSource.camera, maxWidth: 1000, imageQuality: 80);
                                        if (fotoTirada != null) {
                                          setModalState(() => processandoFoto = true);
                                          File fotoCarimbada = await _carimbarFoto(File(fotoTirada.path), semaforo['id'].toString(), dataHoraInicio, coordenadas);
                                          setModalState(() {
                                            fotos.add(fotoCarimbada);
                                            processandoFoto = false;
                                          });
                                        }
                                      },
                                      child: Container(
                                        width: 80, height: 80, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid)),
                                        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt, color: Colors.grey, size: 32), Text('Tirar Foto', style: TextStyle(fontSize: 10, color: Colors.grey))]),
                                      ),
                                    ),
                                ],
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
                                onPressed: (salvando || processandoFoto) ? null : () async {
                                  if (!checklistConfirmado) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Você precisa marcar a caixa confirmando a verificação do checklist!'), backgroundColor: Colors.red));
                                    return;
                                  }
                                  
                                  String detalhesFinais = detalhesController.text.trim();

                                  if (temAnormalidade == 'Sim') {
                                    if (falhaSelecionada == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione qual foi a falha encontrada!'), backgroundColor: Colors.red)); return; }
                                    if (fotos.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('É obrigatório tirar pelo menos 1 foto do defeito!'), backgroundColor: Colors.red)); return; }
                                  } else {
                                    detalhesFinais = 'O semáforo foi vistoriado por completo e não foram identificadas anormalidades.';
                                  }

                                  setModalState(() => salvando = true);

                                  try {
                                    List<String> urlsDasFotos = [];
                                    
                                    if (fotos.isNotEmpty) {
                                      for (int i = 0; i < fotos.length; i++) {
                                        String nomeArquivo = 'vistoria_${semaforo['id']}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
                                        Reference ref = FirebaseStorage.instance.ref().child('vistorias_fotos/$nomeArquivo');
                                        UploadTask uploadTask = ref.putFile(fotos[i]);
                                        TaskSnapshot snapshotDaFoto = await uploadTask;
                                        urlsDasFotos.add(await snapshotDaFoto.ref.getDownloadURL());
                                      }
                                    }

                                    String dataFormatadaFim = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
                                    
                                    await FirebaseFirestore.instance.collection('vistorias').add({
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
                                      'fotos': urlsDasFotos, 
                                      'criado_em': FieldValue.serverTimestamp(),
                                    });

                                    // ==== COMPARTILHA PARA O WHATSAPP ====
                                    if (temAnormalidade == 'Sim') {
                                      await _enviarOcorrencia(semaforo, falhaSelecionada!, detalhesFinais, fotos);
                                    }

                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vistoria salva com sucesso!'), backgroundColor: Colors.green));
                                    }
                                  } catch (e) {
                                    setModalState(() => salvando = false);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao salvar vistoria! Verifique a conexão.'), backgroundColor: Colors.red));
                                  }
                                },
                                child: salvando 
                                  ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)), SizedBox(width: 12), Text('Enviando dados...', style: TextStyle(fontWeight: FontWeight.bold))])
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
      csv += 'SEMAFORO;VISTORIADOR;ENDERECO;INICIO;FIM;COORDENADAS;STATUS;FALHA;DETALHES;FOTOS\n';
      
      for (var doc in vistorias) {
        var v = doc.data() as Map<String, dynamic>;
        String status = v['teve_anormalidade'] == true ? 'COM FALHA' : 'OK';
        
        List<dynamic> fotos = v['fotos'] ?? [];
        String linksFotos = fotos.join(', ');

        csv += '${v['semaforo_id']};$nomeVistoriador;${v['semaforo_endereco']};${v['data_hora_inicio']};${v['data_hora_fim']};${v['gps_coordenadas']};$status;${v['falha_registrada']};${v['detalhes_ocorrencia']?.toString().replaceAll('\n', ' ')};$linksFotos\n';
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
                        children: fotos.map((url) => GestureDetector(
                          onTap: () => _mostrarImagemExpandida(context, NetworkImage(url)),
                          child: Container(
                            width: 100, height: 100,
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey), image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)),
                            child: const Align(alignment: Alignment.bottomLeft, child: Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.zoom_in, color: Colors.white, size: 24))),
                          ),
                        )).toList(),
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

  Future<void> _encerrarTurno(String turnoId, String veiculoId, String rotaId, int falta, List<QueryDocumentSnapshot> vistoriasConcluidas, String rotaNumero, String nomeVistoriador) async {
    final kmFinalController = TextEditingController();
    bool carregando = false;
    bool confirmouTermo = false;

    bool? sucessoEncerramento = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Encerrar Expediente', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (falta > 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red)),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Atenção! Faltam $falta semáforos para concluir a meta de hoje.', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green)),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Expanded(child: Text('Parabéns! Você concluiu 100% da meta de hoje.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  const Text('Para liberar a moto e gerar o relatório PDF, informe a quilometragem final:'),
                  const SizedBox(height: 12),
                  TextField(controller: kmFinalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'KM Final', border: OutlineInputBorder(), prefixIcon: Icon(Icons.speed), suffixText: 'km')),
                  
                  const SizedBox(height: 16),
                  
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: Colors.red,
                    title: const Text('Confirmo que os dados coletados são verdadeiros e concordo em gerar o relatório final do dia.', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    value: confirmouTermo,
                    onChanged: (val) {
                      setStateDialog(() => confirmouTermo = val ?? false);
                    },
                  )
                ],
              ),
            ),
            actions: [
              if (!carregando) TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: carregando ? null : () async {
                  if (kmFinalController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Digite o KM Final!'), backgroundColor: Colors.orange));
                    return;
                  }
                  if (!confirmouTermo) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Você precisa marcar a caixa de confirmação!'), backgroundColor: Colors.orange));
                    return;
                  }
                  setStateDialog(() => carregando = true);
                  Navigator.pop(context, true); 
                },
                child: carregando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Encerrar Turno'),
              ),
            ],
          );
        }
      ),
    );

    if (sucessoEncerramento == true) {
      try {
        await FirebaseFirestore.instance.collection('turnos').doc(turnoId).update({'status': 'finalizado', 'data_fim': FieldValue.serverTimestamp(), 'km_final': kmFinalController.text.trim()});
        await FirebaseFirestore.instance.collection('veiculos').doc(veiculoId).update({'em_uso': false});
        
        if (mounted) { 
          if (_isAdmin) {
            setState(() => _turnoSelecionadoAdmin = null);
          }
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turno encerrado! Gerando Relatório PDF...'), backgroundColor: Colors.green)); 
          await _gerarEMostrarPDF(vistoriasConcluidas, rotaNumero, nomeVistoriador);
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao encerrar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ============================================================================
  // TELA DO ADMIN: LISTA DE VISTORIADORES EM CAMPO
  // ============================================================================
  Widget _buildVisaoListaAdmin() {
    // Calculando o Grupo do Dia atual
    DateTime dataBase = DateTime(2024, 1, 1);
    int diasPassados = DateTime.now().difference(dataBase).inDays;
    String grupoDeHoje = (diasPassados % 2 == 0) ? 'A' : 'B';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoramento de Rotas', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange.shade400,
        foregroundColor: Colors.white,
        actions: const [MenuUsuario()], // MENU ADICIONADO AQUI
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

                        // Calcula a Meta (Total de semáforos desta rota QUE são do grupo de hoje)
                        List<DocumentSnapshot> todosDaRota = snapshotSemaforos.data!.docs.where((s) {
                          return (s.data() as Map<String, dynamic>)['rota'].toString().replaceFirst(RegExp(r'^0+'), '') == rotaTurnoLimpa;
                        }).toList();

                        int meta = todosDaRota.where((s) {
                          String lado = ((s.data() as Map)['lado_vistoria'] ?? (s.data() as Map)['grupo'] ?? 'A').toString().toUpperCase();
                          return lado == grupoDeHoje;
                        }).length;

                        // Acessa as vistorias deste turno específico para fazer a barra de progresso
                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('vistorias').where('turno_id', isEqualTo: doc.id).snapshots(),
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
                                      
                                      // Barra de Progresso do Admin
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
        actions: const [MenuUsuario()], // MENU ADICIONADO AQUI
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
          
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('vistorias').where('turno_id', isEqualTo: turnoDoc.id).snapshots(),
            builder: (context, snapshotVistoria) {
              if (!snapshotVistoria.hasData) return const Center(child: CircularProgressIndicator());

              List<QueryDocumentSnapshot> vistoriasConcluidas = snapshotVistoria.data!.docs;
              Set<String> vistoriadosIds = vistoriasConcluidas.map((doc) => doc['semaforo_id'].toString()).toSet();

              List<DocumentSnapshot> todosDaRota = snapshotSemaforo.data!.docs.where((doc) {
                return (doc.data() as Map<String, dynamic>)['rota'].toString().replaceFirst(RegExp(r'^0+'), '') == rotaTurnoLimpa;
              }).toList();

              DateTime dataBase = DateTime(2024, 1, 1);
              int diasPassados = DateTime.now().difference(dataBase).inDays;
              String grupoDeHoje = (diasPassados % 2 == 0) ? 'A' : 'B';

              List<DocumentSnapshot> semaforosDoGrupo = todosDaRota.where((doc) {
                // Lendo do lado_vistoria novo
                String grupoDb = ((doc.data() as Map)['lado_vistoria'] ?? (doc.data() as Map)['grupo'] ?? 'A').toString().toUpperCase();
                return grupoDb == grupoDeHoje;
              }).toList();

              int meta = semaforosDoGrupo.length;
              int concluidos = semaforosDoGrupo.where((doc) => vistoriadosIds.contains((doc.data() as Map)['id'].toString())).length;
              int falta = meta - concluidos;
              double percentual = meta == 0 ? 0.0 : (concluidos / meta);

              List<DocumentSnapshot> semaforosPendentes = semaforosDoGrupo.where((doc) {
                var semaforo = doc.data() as Map<String, dynamic>;
                String id = semaforo['id'].toString();
                return !vistoriadosIds.contains(id); 
              }).toList();

              var semaforosFiltradosPesquisa = semaforosPendentes.where((doc) {
                if (_textoPesquisaAndamento.isEmpty) return true;
                var data = doc.data() as Map<String, dynamic>;
                String id = (data['id'] ?? '').toString().toLowerCase();
                String end = (data['endereco'] ?? '').toString().toLowerCase();
                return id.contains(_textoPesquisaAndamento) || end.contains(_textoPesquisaAndamento);
              }).toList();

              // Ordena pelos itens da ordem de vistoria que definimos
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
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Rota $rotaNumero', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                                    Text('Seu Grupo de Hoje: $grupoDeHoje', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), 
                                  icon: const Icon(Icons.stop_circle, size: 18), 
                                  label: const Text('Encerrar', style: TextStyle(fontWeight: FontWeight.bold)), 
                                  onPressed: () => _encerrarTurno(turnoDoc.id, turnoData['veiculo_id'] ?? '', turnoData['rota_id'] ?? '', falta, vistoriasConcluidas, rotaNumero, nomeDoVistoriadorDesteTurno)
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              Icon(_isAdmin ? Icons.person : Icons.motorcycle, size: 18, color: Colors.grey), 
                              const SizedBox(width: 8), 
                              Text(_isAdmin ? 'Vistoriador: $nomeDoVistoriadorDesteTurno' : 'Moto: ${turnoData['placa'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87))
                            ]),
                            const SizedBox(height: 12),

                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Progresso: $concluidos de $meta', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700)), Text('Faltam: $falta', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700))]),
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
                                    onTap: () => _abrirVistoriaSemaforo(semaforo, turnoDoc.id),
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
                            ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white), icon: const Icon(Icons.picture_as_pdf), label: const Text('Baixar PDF de Hoje'), onPressed: () => _gerarEMostrarPDF(vistoriasConcluidas, rotaNumero, nomeDoVistoriadorDesteTurno)),
                            ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), icon: const Icon(Icons.grid_on), label: const Text('Exportar Excel'), onPressed: () => _exportarExcelConcluidos(vistoriasConcluidas, rotaNumero, nomeDoVistoriadorDesteTurno)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.white,
                        child: TextField(controller: _pesquisaConcluidosController, decoration: InputDecoration(hintText: 'Pesquisar na lista...', prefixIcon: const Icon(Icons.search), suffixIcon: _textoPesquisaConcluidos.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _pesquisaConcluidosController.clear()) : null, filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 0))),
                      ),
                      Expanded(
                        child: vistoriasConcluidas.isEmpty
                          ? const Center(child: Text('Nenhuma vistoria finalizada ainda.', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: vistoriasConcluidas.length,
                              itemBuilder: (context, index) {
                                var vistoria = vistoriasConcluidas[index].data() as Map<String, dynamic>;
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
              actions: const [MenuUsuario()], // MENU ADICIONADO AQUI
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