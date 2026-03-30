import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Importações para Exportação PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';

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

class TelaEquipes extends StatefulWidget {
  const TelaEquipes({super.key});

  @override
  State<TelaEquipes> createState() => _TelaEquipesState();
}

class _TelaEquipesState extends State<TelaEquipes> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _buscaPlacaController = TextEditingController();
  final TextEditingController _buscaIntegranteController = TextEditingController();
  
  String _termoPlaca = '';
  String _termoIntegrante = '';

  List<Map<String, dynamic>> _semaforosAux = [];
  List<Map<String, dynamic>> _falhasAux = [];
  List<String> _opcoesFalhas = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); 
    });
    _carregarSemaforosEFalhas();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaPlacaController.dispose();
    _buscaIntegranteController.dispose();
    super.dispose();
  }

  Future<void> _carregarSemaforosEFalhas() async {
    try {
      final sSnap = await FirebaseFirestore.instance.collection('semaforos').get();
      List<Map<String, dynamic>> listaSemaforos = [];
      for (var doc in sSnap.docs) {
        var d = doc.data();
        String idSemaforo = _formatarId(d['id']?.toString() ?? d['numero']?.toString() ?? doc.id);
        listaSemaforos.add({
          'id': idSemaforo,
          'empresa': (d['empresa'] ?? '').toString(),
        });
      }

      final fSnap = await FirebaseFirestore.instance.collection('falhas').get();
      List<Map<String, dynamic>> listaFalhas = [];
      List<String> opcoesFalhas = [];
      for (var doc in fSnap.docs) {
        var d = doc.data();
        String tipo = (d['tipo_da_falha'] ?? d['falha'] ?? '').toString();
        if (tipo.isNotEmpty) {
          listaFalhas.add({'falha': tipo, 'prazo': (d['prazo'] ?? '').toString()});
          opcoesFalhas.add(tipo);
        }
      }

      if (mounted) {
        setState(() {
          _semaforosAux = listaSemaforos;
          _falhasAux = listaFalhas;
          _opcoesFalhas = opcoesFalhas.toSet().toList()..sort();
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar semáforos/falhas: $e");
    }
  }

  String _formatarId(String idStr) {
    if (idStr.isEmpty || idStr.toUpperCase().contains('NUMERO')) return '000';
    String numeros = idStr.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeros.isEmpty) return idStr;
    return numeros.padLeft(3, '0');
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return '---';
    DateTime dt = timestamp.toDate();
    return DateFormat('dd/MM/yy HH:mm').format(dt);
  }

  String _formatarDataCurta(Timestamp? timestamp) {
    if (timestamp == null) return '---';
    DateTime dt = timestamp.toDate();
    return DateFormat('dd/MM/yy, HH:mm\'h\'').format(dt);
  }

  String _formatarDataHoraStr() {
    final now = DateTime.now();
    final dia = now.day.toString().padLeft(2, '0');
    final mes = now.month.toString().padLeft(2, '0');
    final ano = now.year.toString();
    final hora = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$ano às $hora:$min';
  }

  Future<String> _getNomeUsuario() async {
    User? usuarioLogado = FirebaseAuth.instance.currentUser;
    if (usuarioLogado == null) return 'SISTEMA';

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('usuarios').doc(usuarioLogado.uid).get();
      if (doc.exists && doc.data() != null) {
        var data = doc.data() as Map<String, dynamic>;
        if (data['nomeCompleto'] != null && data['nomeCompleto'].toString().isNotEmpty) {
          return data['nomeCompleto'].toString().toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar nome do usuário: $e');
    }
    return (usuarioLogado.displayName ?? usuarioLogado.email ?? 'SISTEMA').toUpperCase();
  }

  Future<Uint8List> _adicionarCarimboNaFoto(Uint8List imageBytes) async {
    try {
      final codec = kIsWeb ? await ui.instantiateImageCodec(imageBytes) : await ui.instantiateImageCodec(imageBytes, targetWidth: 800);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(image, Offset.zero, Paint());
      final paintRect = Paint()..color = Colors.black54;
      canvas.drawRect(Rect.fromLTWH(0, image.height.toDouble() - 60, image.width.toDouble(), 60), paintRect);
      final textStyle = ui.TextStyle(color: Colors.yellowAccent, fontSize: 24, fontWeight: FontWeight.bold);
      final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.right);
      final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
        ..pushStyle(textStyle)
        ..addText('REGISTRO: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}');
      final paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: image.width.toDouble() - 20));
      canvas.drawParagraph(paragraph, Offset(0, image.height.toDouble() - 45));
      final picture = recorder.endRecording();
      final img = await picture.toImage(image.width, image.height);
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (pngBytes == null) return imageBytes;
      return pngBytes.buffer.asUint8List();
    } catch (e) {
      return imageBytes;
    }
  }

  Color _corStatus(String status) {
    String st = status.toLowerCase();
    if (st == 'ativo') return Colors.green;
    if (st == 'finalizado' || st.contains('conclu')) return Colors.blueGrey;
    if (st.contains('aberto')) return Colors.redAccent;
    if (st.contains('atendimento')) return Colors.green;
    if (st.contains('deslocamento')) return Colors.orange;
    return Colors.grey;
  }

  // =========================================================================
  // MOTOR DE CRUZAMENTO: QUAIS OCORRÊNCIAS ESTA EQUIPE ATENDEU?
  // =========================================================================
  List<Map<String, dynamic>> _obterOcorrenciasDaEquipe(String eqId, Map<String, dynamic> eqData, List<QueryDocumentSnapshot> todasOcorrencias) {
    String placa = (eqData['placa'] ?? '').toString().toUpperCase().trim();
    String intsStr = (eqData['integrantes_str'] ?? '').toString().toUpperCase();
    String nomeLider = intsStr.split(',').first.trim();
    bool isAtivo = (eqData['status'] ?? '').toString().toLowerCase() == 'ativo';

    List<Map<String, dynamic>> atendidas = [];

    for (var doc in todasOcorrencias) {
      Map<String, dynamic> oc = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
      oc['doc_id'] = doc.id; 

      String eqRespId = (oc['equipe_responsavel_id'] ?? '').toString().trim();
      String equipeResp = (oc['equipe_responsavel'] ?? oc['equipe_atrelada'] ?? '').toString().toUpperCase().trim();
      String placaResp = (oc['placa_veiculo'] ?? '').toString().toUpperCase().trim();

      bool bateuId = eqRespId.isNotEmpty && eqRespId == eqId;
      bool bateuPlaca = placa.isNotEmpty && placaResp.contains(placa);
      bool bateuNome = nomeLider.isNotEmpty && equipeResp.contains(nomeLider);

      if (bateuId || bateuPlaca || bateuNome) {
        String st = (oc['status'] ?? '').toString().toLowerCase();
        bool isFinalizada = st.contains('conclu') || st.contains('finaliz');

        if (isAtivo) {
          if (!isFinalizada) {
            atendidas.add(oc); 
          } else {
            Timestamp? tsFin = oc['data_de_finalizacao'] ?? oc['data_atendimento'];
            Timestamp? tsIniEq = eqData['data_inicio'];
            
            if (tsFin != null && tsIniEq != null) {
              if (tsFin.toDate().isAfter(tsIniEq.toDate().subtract(const Duration(hours: 1)))) {
                atendidas.add(oc);
              }
            } else {
              atendidas.add(oc);
            }
          }
        } else {
          Timestamp? tsIniEq = eqData['data_inicio'];
          Timestamp? tsFimEq = eqData['data_fim'];
          Timestamp? tsOc = oc['data_de_finalizacao'] ?? oc['data_atendimento'] ?? oc['data_de_abertura'];
          
          if (tsIniEq != null && tsFimEq != null && tsOc != null) {
            DateTime dtOc = tsOc.toDate();
            if (dtOc.isAfter(tsIniEq.toDate().subtract(const Duration(hours: 1))) && 
                dtOc.isBefore(tsFimEq.toDate().add(const Duration(hours: 4)))) {
              atendidas.add(oc);
            }
          } else {
            atendidas.add(oc);
          }
        }
      }
    }
    return atendidas;
  }

  // =========================================================================
  // GERAR PDF INDIVIDUAL DO TURNO DA EQUIPE
  // =========================================================================
  Future<void> _exportarPdfIndividual(Map<String, dynamic> data, List<Map<String, dynamic>> ocorrencias) async {
    final pdf = pw.Document();
    String placa = data['placa'] ?? 'S_PLACA';
    final dataHora = _formatarDataHoraStr();

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(40),
        footer: (pw.Context context) {
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Relatório gerado pelo Sistema de Ocorrências Semafóricas - SOS - $dataHora',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Página ${context.pageNumber} de ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) => [
          pw.Text('RELATÓRIO DE TURNO DA EQUIPE', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text('Veículo / Placa: $placa (${data['tipo'] ?? data['tipo_veiculo'] ?? '-'})', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Empresa Responsável: ${data['empresa'] ?? '-'}'),
          pw.Text('Status do Turno: ${(data['status'] ?? '-').toString().toUpperCase()}'),
          pw.SizedBox(height: 15),
          
          pw.Text('DADOS DE TEMPO E KM', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
          pw.Text('Início do Turno: ${_formatarData(data['data_inicio'])}'),
          pw.Text('Fim do Turno: ${_formatarData(data['data_fim'])}'),
          pw.Text('KM Inicial: ${data['km_inicial'] ?? 0} | KM Final: ${data['km_final'] ?? '-'} | Rodado: ${data['km_rodado'] ?? 0} km'),
          pw.SizedBox(height: 15),
          
          pw.Text('INTEGRANTES', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
          pw.Text(data['integrantes_str'] ?? '-'),
          pw.SizedBox(height: 15),
          
          pw.Text('OBSERVAÇÕES DO TURNO', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
          pw.Text(data['observacoes'] ?? 'Nenhuma observação registrada.'),
          pw.SizedBox(height: 20),

          pw.Text('OCORRÊNCIAS ATENDIDAS NESTE TURNO (${ocorrencias.length})', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
          pw.SizedBox(height: 10),

          if (ocorrencias.isEmpty) 
            pw.Text('Nenhum atendimento registrado para esta equipe neste período.', style: const pw.TextStyle(color: PdfColors.grey)),

          ...ocorrencias.map((oc) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(8),
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Semáforo: ${oc['semaforo']} - ${oc['endereco']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.Text('Nº Ocorrência: ${oc['numero_da_ocorrencia'] ?? oc['doc_id'] ?? 'S/N'}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Falha Relatada: ${oc['tipo_da_falha'] ?? '---'}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
                  pw.Text('Falha Encontrada: ${oc['falha_aparente_final'] ?? '---'}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
                  pw.Text('Status da Ocorrência: ${(oc['status'] ?? '').toString().toUpperCase()}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ]
              )
            );
          }),

          pw.SizedBox(height: 60),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(width: 250, height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 5),
                  pw.Text('Assinatura do Responsável da Equipe', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ]
              )
            ]
          )
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Turno_Equipe_$placa.pdf');
  }

  Future<Map<String, dynamic>> _buscarRecursosLivres(String? equipeAtualId) async {
    final equipesAtivas = await FirebaseFirestore.instance.collection('equipes').where('status', isEqualTo: 'ativo').get();
    
    Set<String> placasOcupadas = {};
    Set<String> integrantesOcupados = {};

    for (var doc in equipesAtivas.docs) {
      if (doc.id == equipeAtualId) continue; 

      var data = doc.data();
      if (data['placa'] != null) {
        placasOcupadas.add(data['placa'].toString().toUpperCase());
      }
      if (data['integrantes_str'] != null && data['integrantes_str'].toString().isNotEmpty) {
        List<String> ints = data['integrantes_str'].toString().split(',');
        for (var i in ints) {
          integrantesOcupados.add(i.trim().toUpperCase());
        }
      }
    }

    final veiculos = await FirebaseFirestore.instance.collection('veiculos').get();
    Map<String, Map<String, dynamic>> veiculosLivresData = {}; 
    for (var doc in veiculos.docs) {
      String placa = (doc.data()['placa'] ?? '').toString().toUpperCase().trim();
      if (placa.isNotEmpty && !placasOcupadas.contains(placa)) {
        veiculosLivresData[placa] = doc.data();
      }
    }

    final integrantes = await FirebaseFirestore.instance.collection('integrantes').get();
    Set<String> integrantesLivresSet = {}; 
    for (var doc in integrantes.docs) {
      String nome = (doc.data()['nomeCompleto'] ?? '').toString().toUpperCase().trim();
      if (nome.isNotEmpty && !integrantesOcupados.contains(nome)) {
        integrantesLivresSet.add(nome);
      }
    }

    List<String> integrantesLivres = integrantesLivresSet.toList()..sort();

    return {
      'veiculosData': veiculosLivresData,
      'integrantes': integrantesLivres,
    };
  }

  void _abrirModalNovaEquipe({String? docId, Map<String, dynamic>? dadosAtuais}) async {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.green))
    );

    Map<String, dynamic> recursosLivres;
    try {
      recursosLivres = await _buscarRecursosLivres(docId);
    } catch (e) {
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao buscar recursos.'), backgroundColor: Colors.red));
      return;
    }
    
    if(!mounted) return;
    Navigator.pop(context); 

    final formKey = GlobalKey<FormState>();
    bool estaCarregando = false;
    
    final kmInicialController = TextEditingController(text: dadosAtuais?['km_inicial']?.toString() ?? '');
    final observacoesController = TextEditingController(text: dadosAtuais?['observacoes'] ?? '');
    
    Map<String, Map<String, dynamic>> veiculosLivresData = recursosLivres['veiculosData'];
    List<String> veiculosPlacas = veiculosLivresData.keys.toSet().toList()..sort();

    String? placaSelecionada = dadosAtuais?['placa'];
    if (placaSelecionada != null && !veiculosPlacas.contains(placaSelecionada)) {
      veiculosPlacas.add(placaSelecionada!); 
      veiculosLivresData[placaSelecionada!] = {
        'tipo': dadosAtuais?['tipo'],
        'empresa': dadosAtuais?['empresa']
      };
    }

    List<String> equipeSelecionada = [];
    if (dadosAtuais != null && dadosAtuais['integrantes_str'] != null && dadosAtuais['integrantes_str'].toString().isNotEmpty) {
      equipeSelecionada = dadosAtuais['integrantes_str'].toString().split(',').map((e) => e.trim()).toList();
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {

            List<String> opcoesIntegrantes = (recursosLivres['integrantes'] as List<String>)
                .where((nome) => !equipeSelecionada.contains(nome))
                .toSet()
                .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.90, 
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(docId == null ? 'Nova Equipe / Despacho' : 'Editando Equipe', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2f3b4c))),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(thickness: 1),
                  const SizedBox(height: 10),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: 'Viatura (Apenas Livres) *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car)),
                              value: (placaSelecionada != null && veiculosPlacas.contains(placaSelecionada)) ? placaSelecionada : null,
                              items: veiculosPlacas.toSet().map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setStateModal(() => placaSelecionada = val);
                                }
                              },
                              validator: (val) => val == null ? 'Selecione uma viatura' : null,
                            ),
                            const SizedBox(height: 16),
                            
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blueGrey.shade200)
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Montar Equipe', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          key: ValueKey(equipeSelecionada.join('-')), 
                                          decoration: const InputDecoration(labelText: 'Adicionar Integrante Livre', border: OutlineInputBorder(), isDense: true),
                                          value: null, 
                                          items: opcoesIntegrantes.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setStateModal(() {
                                                equipeSelecionada.add(val);
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  if (equipeSelecionada.isEmpty)
                                    const Text('Nenhum integrante adicionado.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.redAccent, fontSize: 12)),
                                  
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: equipeSelecionada.map((membro) {
                                      return Chip(
                                        label: Text(membro, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        backgroundColor: Colors.white,
                                        deleteIconColor: Colors.red,
                                        onDeleted: () {
                                          setStateModal(() {
                                            equipeSelecionada.remove(membro);
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: kmInicialController,
                              decoration: const InputDecoration(labelText: 'KM Inicial', border: OutlineInputBorder(), prefixIcon: Icon(Icons.speed)),
                              keyboardType: TextInputType.number,
                              validator: (val) => val == null || val.isEmpty ? 'Obrigatório' : null,
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: observacoesController,
                              decoration: const InputDecoration(labelText: 'Observações (Opcional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.note)),
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27ae60), padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: estaCarregando ? null : () async {
                      if (equipeSelecionada.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A equipe precisa ter pelo menos 1 integrante!'), backgroundColor: Colors.red));
                        return;
                      }

                      if (formKey.currentState!.validate()) {
                        setStateModal(() => estaCarregando = true);
                        try {
String integrantesStr = equipeSelecionada.join(', ');

Map<String, dynamic>? dadosDoVeiculo = veiculosLivresData[placaSelecionada];
String tipoVeiculo = dadosDoVeiculo?['tipo'] ?? dadosAtuais?['tipo'] ?? '';
String empresaVeiculo = dadosDoVeiculo?['empresa'] ?? dadosAtuais?['empresa'] ?? '';

Map<String, dynamic> dadosParaSalvar = {
                            'placa': placaSelecionada,
                            'tipo': tipoVeiculo,
                            'empresa': empresaVeiculo,
                            'integrantes_str': integrantesStr,
                            'km_inicial': kmInicialController.text.trim(),
                            'observacoes': observacoesController.text.trim(),
                          };

                          if (docId != null) {
                            await FirebaseFirestore.instance.collection('equipes').doc(docId).update(dadosParaSalvar);
                          } else {
                            dadosParaSalvar['status'] = 'ativo';
                            dadosParaSalvar['data_inicio'] = FieldValue.serverTimestamp();
                            await FirebaseFirestore.instance.collection('equipes').add(dadosParaSalvar);
                          }

                          if (mounted) Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(docId == null ? 'Equipe Despachada!' : 'Equipe Atualizada!'), backgroundColor: Colors.green));
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao salvar'), backgroundColor: Colors.red));
                        } finally {
                          setStateModal(() => estaCarregando = false);
                        }
                      }
                    },
                    child: estaCarregando 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : Text(docId == null ? 'Salvar Despacho' : 'Atualizar Equipe', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  Future<void> _finalizarEquipe(String docId, Map<String, dynamic> dadosAtuais, List<Map<String, dynamic>> ocorrenciasDaEquipe) async {
    bool temPendente = ocorrenciasDaEquipe.any((o) {
      String st = (o['status'] ?? '').toString().toLowerCase();
      return !st.contains('conclu') && !st.contains('finaliz');
    });

    if (temPendente) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não é possível finalizar a equipe! Existem semáforos em atendimento ou deslocamento.', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        )
      );
      return;
    }

    final kmFinalController = TextEditingController();

    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar Equipe', style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Deseja realmente encerrar os trabalhos desta equipe? A viatura e os integrantes ficarão livres para novos despachos.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: kmFinalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'KM Final do Veículo *', border: OutlineInputBorder()),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (kmFinalController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o KM Final!'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Finalizar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirmar) {
      int kmInicial = int.tryParse(dadosAtuais['km_inicial']?.toString() ?? '0') ?? 0;
      int kmFinal = int.tryParse(kmFinalController.text) ?? kmInicial;
      int kmRodado = kmFinal - kmInicial;

      await FirebaseFirestore.instance.collection('equipes').doc(docId).update({
        'status': 'finalizado',
        'data_fim': FieldValue.serverTimestamp(),
        'km_final': kmFinal.toString(),
        'km_rodado': kmRodado.toString(),
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Equipe Finalizada! Os recursos estão livres.'), backgroundColor: Colors.grey));
    }
  }

  // =========================================================================
  // MODAL DE AÇÕES RÁPIDAS DA OCORRÊNCIA (Em deslocamento / Em atendimento)
  // =========================================================================
  void _abrirModalOcorrenciaAcao(String docIdOcorrencia, Map<String, dynamic> dadosOcorrencia) {
    String st = (dadosOcorrencia['status'] ?? 'aberto').toString().toLowerCase();

    if (st.contains('atendimento')) {
      _abrirModalFinalizarAcao(docIdOcorrencia, dadosOcorrencia); 
    } else if (st.contains('deslocamento')) {
      _registrarChegadaAcao(docIdOcorrencia);
    }
  }

  void _registrarChegadaAcao(String docId) async {
    bool? conf = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar Chegada', style: TextStyle(color: Colors.orange)),
        content: const Text('Confirmar que a equipe chegou ao local e iniciará o atendimento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (conf == true) {
      await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').doc(docId).update({
        'status': 'Em atendimento',
        'data_atendimento': FieldValue.serverTimestamp(),
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atendimento iniciado com sucesso!'), backgroundColor: Colors.green));
    }
  }

  void _abrirModalFinalizarAcao(String docId, Map<String, dynamic> dados) {
    bool defeitoConstatado = true;
    bool estaSalvando = false;
    bool estaArrastandoArea = false;

    String falha = dados['tipo_da_falha']?.toString() ?? '';
    final descricaoCtrl = TextEditingController();
    final acaoCtrl = TextEditingController();
    List<Uint8List> fotosSelecionadas = [];

    if (falha.isNotEmpty && !_opcoesFalhas.contains(falha)) {
      _opcoesFalhas.add(falha);
    }
    final falhaMenuCtrl = TextEditingController(text: falha);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => Padding(
          padding: EdgeInsets.only(top: 24, left: 24, right: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Finalizar Ocorrência', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.all(10),
                  color: Colors.blue.shade50,
                  child: Text('Falha Original: ${dados['tipo_da_falha'] ?? '---'}\nDetalhes: ${dados['detalhes'] ?? '---'}', style: const TextStyle(fontSize: 12)),
                ),
                SwitchListTile(
                  title: const Text('Foi constatado defeito?', style: TextStyle(fontWeight: FontWeight.bold)),
                  value: defeitoConstatado,
                  activeColor: Colors.green,
                  onChanged: (v) {
                    setStateModal(() {
                      defeitoConstatado = v;
                      if (!defeitoConstatado) {
                        acaoCtrl.text = 'A EQUIPE RELATA QUE REALIZOU UMA VISTORIA COMPLETA E O SEMÁFORO NÃO APRESENTOU DEFEITO.';
                      } else {
                        acaoCtrl.clear();
                      }
                    });
                  },
                ),
                if (defeitoConstatado) ...[
                  DropdownMenu<String>(
                    expandedInsets: EdgeInsets.zero,
                    controller: falhaMenuCtrl,
                    enableFilter: true, enableSearch: true,
                    label: const Text('Falha Encontrada *'),
                    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                    initialSelection: falha.isEmpty ? null : falha,
                    dropdownMenuEntries: _opcoesFalhas.map((f) => DropdownMenuEntry(value: f, label: f)).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: descricaoCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    decoration: const InputDecoration(labelText: 'Como encontrou o semáforo? *', border: OutlineInputBorder()),
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: acaoCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(labelText: 'Ação Técnica da Equipe *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),

                const Text('Fotos do Serviço (Max: 4)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 8),

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
                                onTap: () => setStateModal(() => fotosSelecionadas.removeAt(index)),
                                child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt), label: const Text('Câmera'),
                        onPressed: fotosSelecionadas.length >= 4 ? null : () async {
                          final XFile? foto = await _picker.pickImage(source: ImageSource.camera);
                          if (foto != null) {
                            Uint8List bytes = await foto.readAsBytes();
                            Uint8List carimbada = await _adicionarCarimboNaFoto(bytes);
                            setStateModal(() => fotosSelecionadas.add(carimbada));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library), label: const Text('Galeria / PC'),
                        onPressed: fotosSelecionadas.length >= 4 ? null : () async {
                          final List<XFile> fotos = await _picker.pickMultiImage();
                          for (var foto in fotos) {
                            if (fotosSelecionadas.length >= 4) break;
                            Uint8List bytes = await foto.readAsBytes();
                            Uint8List carimbada = await _adicionarCarimboNaFoto(bytes);
                            setStateModal(() => fotosSelecionadas.add(carimbada));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (fotosSelecionadas.length < 4)
                  DropTarget(
                    onDragEntered: (detail) => setStateModal(() => estaArrastandoArea = true),
                    onDragExited: (detail) => setStateModal(() => estaArrastandoArea = false),
                    onDragDone: (detail) async {
                      setStateModal(() => estaArrastandoArea = false);
                      for (var file in detail.files) {
                        if (fotosSelecionadas.length >= 4) break;
                        if (file.mimeType?.startsWith('image/') ?? true) {
                          Uint8List bytes = await file.readAsBytes();
                          Uint8List carimbada = await _adicionarCarimboNaFoto(bytes);
                          setStateModal(() => fotosSelecionadas.add(carimbada));
                        }
                      }
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          final List<XFile> fotos = await _picker.pickMultiImage();
                          for (var foto in fotos) {
                            if (fotosSelecionadas.length >= 4) break;
                            Uint8List bytes = await foto.readAsBytes();
                            Uint8List carimbada = await _adicionarCarimboNaFoto(bytes);
                            setStateModal(() => fotosSelecionadas.add(carimbada));
                          }
                        },
                        child: Container(
                          height: 90, width: double.infinity,
                          decoration: BoxDecoration(
                            color: estaArrastandoArea ? Colors.green.withValues(alpha: 0.1) : Colors.grey.shade50,
                            border: Border.all(color: estaArrastandoArea ? Colors.green : Colors.grey.shade300, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_upload, color: estaArrastandoArea ? Colors.green : Colors.blueGrey, size: 28),
                                const SizedBox(height: 4),
                                Text(
                                  'Ou arraste as imagens e solte aqui\n(Clique para abrir a galeria)',
                                  style: TextStyle(color: estaArrastandoArea ? Colors.green : Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: estaSalvando
                      ? null
                      : () async {
                          if (defeitoConstatado && (falhaMenuCtrl.text.isEmpty || descricaoCtrl.text.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha a falha e descrição!')));
                            return;
                          }
                          if (acaoCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Descreva a ação realizada!')));
                            return;
                          }

                          setStateModal(() => estaSalvando = true);

                          try {
                            List<String> fotosBase64 = [];
                            for (Uint8List fotoBytes in fotosSelecionadas) {
                              fotosBase64.add(base64Encode(fotoBytes));
                            }

                            String nomeUsuario = await _getNomeUsuario();

                            await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').doc(docId).update({
                              'status': 'Finalizado',
                              'data_de_finalizacao': FieldValue.serverTimestamp(),
                              'falha_aparente_final': defeitoConstatado ? falhaMenuCtrl.text : 'DEFEITO NÃO CONSTATADO',
                              'descricao_encontro': defeitoConstatado ? descricaoCtrl.text.toUpperCase() : 'DEFEITO NÃO CONSTATADO',
                              'acao_equipe': acaoCtrl.text.toUpperCase(),
                              'fotos_finalizacao': fotosBase64,
                              'usuario_finalizacao': nomeUsuario, 
                            });

                            if (mounted) Navigator.pop(context);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atendimento concluído!'), backgroundColor: Colors.green));
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
                            setStateModal(() => estaSalvando = false);
                          }
                        },
                  child: estaSalvando
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Concluir Atendimento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _atribuirEquipeOcorrencia(String docIdOcorrencia) async {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (_) => const Center(child: CircularProgressIndicator())
    );

    // Busca todas as equipes ativas agora
    final snap = await FirebaseFirestore.instance.collection('equipes').where('status', isEqualTo: 'ativo').get();
    final equipesAtivas = snap.docs;

    if(mounted) Navigator.pop(context); 

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView( 
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Trocar Equipe (Transferir)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
                const SizedBox(height: 10),
                if (equipesAtivas.isEmpty)
                  const Padding(padding: EdgeInsets.all(20), child: Text('Nenhuma outra equipe ATIVA encontrada.'))
                else
                  ...equipesAtivas.map((eq) {
                    var data = eq.data();
                    String placa = data['placa'] ?? 'S/ PLACA';
                    String empresa = data['empresa'] ?? 'EXTERNA';
                    String ints = data['integrantes_str'] ?? '';
                    String nomeLider = ints.split(',').first.trim().toUpperCase();
                    if (nomeLider.isEmpty) nomeLider = "EQUIPE $placa";

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.directions_car, color: Colors.blueGrey),
                        title: Text('$placa - $empresa', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(ints, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.check_circle_outline, color: Colors.green),
                        onTap: () async {
                          await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').doc(docIdOcorrencia).update({
                            'equipe_atrelada': nomeLider,
                            'equipe_responsavel': nomeLider,
                            'integrantes_equipe': ints, 
                            'placa_veiculo': placa,
                            'equipe_responsavel_id': eq.id,
                            'status': 'Em deslocamento', // Zera o status para a nova equipe
                          });
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Equipe trocada com sucesso!'), backgroundColor: Colors.green));
                          }
                        },
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================================================================
  // MODAL DE DETALHES COMPLETOS (SOMENTE LEITURA PARA FINALIZADAS)
  // =========================================================================
  void _abrirDetalhesCompletosFinalizada(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Detalhes: ${data['numero_da_ocorrencia'] ?? data['doc_id'] ?? 'S/N'}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoRow('Semáforo', '${data['semaforo']} - ${data['endereco']}'),
                _buildInfoRow('Origem', data['origem_da_ocorrencia']),
                const Divider(),
                _buildInfoRow('Data Abertura', _formatarData(data['data_de_abertura'])),
                _buildInfoRow('Data Atendimento', _formatarData(data['data_atendimento'])),
                _buildInfoRow('Data Finalização', _formatarData(data['data_de_finalizacao'])),
                const Divider(),
                _buildInfoRow('Usuário Abertura', data['usuario_abertura']),
                _buildInfoRow('Equipe Resp.', data['equipe_atrelada'] ?? data['equipe_responsavel']),
                const Divider(),
                _buildInfoRow('Falha Relatada', data['tipo_da_falha']),
                _buildInfoRow('Detalhes Abertura', data['detalhes']),
                _buildInfoRow('Falha Encontrada', data['falha_aparente_final']),
                _buildInfoRow('Descrição Equipe', data['descricao_encontro']),
                _buildInfoRow('Ação Técnica', data['acao_equipe']),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            TextSpan(text: (value ?? '---').toString()),
          ],
        ),
      ),
    );
  }

// --- COMPONENTE: GRID DE EQUIPES ---
  Widget _buildGrid(List<QueryDocumentSnapshot> lista, bool isAtivo, List<QueryDocumentSnapshot> ocorrenciasDocs) {
    if (lista.isEmpty) {
      return Center(
        child: Text(
          isAtivo ? 'Nenhuma equipe ATIVA no momento.' : 'Nenhuma equipe FINALIZADA encontrada.', 
          style: const TextStyle(color: Colors.white, fontSize: 16, fontStyle: FontStyle.italic)
        )
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16, top: 16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: lista.map((doc) {
              var data = doc.data() as Map<String, dynamic>;
              
              Color corStatus = isAtivo ? const Color(0xFF2ecc71) : const Color(0xFF7f8c8d);
              String txtStatus = isAtivo ? 'ATIVO' : 'FINALIZADO';
              
              String dtInicio = _formatarDataCurta(data['data_inicio']);
              String dtFim = isAtivo ? '' : _formatarDataCurta(data['data_fim']);

              String placa = data['placa'] ?? 'S/ PLACA';
              String tipo = data['tipo'] ?? data['tipo_veiculo'] ?? '';
              String empresa = data['empresa'] ?? '';
              
              String headerTextoCarro = tipo.isNotEmpty ? '$placa ($tipo)' : placa;

              // CRUZAMENTO DE OCORRÊNCIAS
              var ocorrenciasDaEquipe = _obterOcorrenciasDaEquipe(doc.id, data, ocorrenciasDocs);
              
              // Separa por Status
              var ocDeslocamento = ocorrenciasDaEquipe.where((o) => (o['status'] ?? '').toString().toLowerCase().contains('deslocamento')).toList();
              var ocAtendimento = ocorrenciasDaEquipe.where((o) => (o['status'] ?? '').toString().toLowerCase().contains('atendimento')).toList();
              var ocFinalizadas = ocorrenciasDaEquipe.where((o) => (o['status'] ?? '').toString().toLowerCase().contains('conclu') || (o['status'] ?? '').toString().toLowerCase().contains('finaliz')).toList();

              return Container(
                width: 420,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // CABEÇALHO AZUL
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF5A78FF),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('ID DA EQUIPE: ${doc.id.substring(0, 5).toUpperCase()}', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('🚗 $headerTextoCarro${empresa.isNotEmpty ? ' - $empresa' : ''}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(color: corStatus, borderRadius: BorderRadius.circular(12)),
                            child: Text(txtStatus, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          )
                        ],
                      ),
                    ),
                    
                    // CORPO BRANCO
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('📱 Comunicação: ---', style: TextStyle(fontSize: 12, color: Colors.black87)),
                              Text('Início: $dtInicio', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.blue.shade400, borderRadius: BorderRadius.circular(4)),
                                child: const Text('KM', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text('Inicial: ${data['km_inicial'] ?? '0'}', style: const TextStyle(fontSize: 11, color: Colors.black87))),
                              Expanded(child: Text('Km Final: ${isAtivo ? '---' : (data['km_final'] ?? '---')}', style: const TextStyle(fontSize: 11, color: Colors.black54))),
                              Expanded(child: Text('Km Rodado: ${isAtivo ? '---' : (data['km_rodado'] ?? '---')}', style: const TextStyle(fontSize: 11, color: Colors.black54))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          
                          const Row(
                            children: [
                              Icon(Icons.person, size: 14, color: Color(0xFF444444)),
                              SizedBox(width: 4),
                              Text('Integrantes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF444444))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (data['integrantes_str'] ?? '-').toString().split(',').map((e) => '— ${e.trim()}').join('\n'), 
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Icon(Icons.inventory_2, size: 14, color: Colors.brown),
                              SizedBox(width: 4),
                              Text('Materiais:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF444444))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text('— SEM MATERIAIS', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          
                          const SizedBox(height: 16),

                          // BOX DE SEMÁFOROS COM ROLAGEM
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 350), // DEFINE A ALTURA MÁXIMA DA CAIXA
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: const Color(0xFFf5f6f8), border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                              child: ocorrenciasDaEquipe.isEmpty 
                                ? const Center(child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text('Nenhuma ocorrência vinculada a esta equipe.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12)),
                                  ))
                                : Scrollbar(
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (isAtivo && ocAtendimento.isNotEmpty) ...[
                                            Text('EM ATENDIMENTO (${ocAtendimento.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                                            ...ocAtendimento.map((oc) => _buildCardOcorrencia(oc, Colors.green, true)).toList(),
                                            const SizedBox(height: 8),
                                          ],
                                          if (isAtivo && ocDeslocamento.isNotEmpty) ...[
                                            Text('EM DESLOCAMENTO (${ocDeslocamento.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
                                            ...ocDeslocamento.map((oc) => _buildCardOcorrencia(oc, Colors.orange, true)).toList(),
                                            const SizedBox(height: 8),
                                          ],
                                          if (ocFinalizadas.isNotEmpty) ...[
                                            Text(isAtivo ? 'FINALIZADOS NESTE TURNO (${ocFinalizadas.length})' : 'TODOS OS FINALIZADOS (${ocFinalizadas.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                            ...ocFinalizadas.map((oc) => _buildCardOcorrencia(oc, Colors.blueGrey, false)).toList(),
                                          ]
                                        ],
                                      ),
                                    ),
                                  ),
                            ),
                          )
                        ],
                      ),
                    ),

                    // FOOTER ACTIONS
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        border: Border(top: BorderSide(color: Colors.grey.shade200))
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: isAtivo ? [
                          TextButton(
                            onPressed: () => _abrirModalNovaEquipe(docId: doc.id, dadosAtuais: data), 
                            child: const Text('Editar', style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 12))
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFeb4c4c), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                            onPressed: () => _finalizarEquipe(doc.id, data, ocorrenciasDaEquipe),
                            child: const Text('Finalizar Equipe', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        ] : [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF34495e), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 16),
                            label: const Text('Exportar PDF', style: TextStyle(color: Colors.white, fontSize: 12)),
                            onPressed: () => _exportarPdfIndividual(data, ocorrenciasDaEquipe),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // Card Interno de Ocorrência blindado contra crash de layout
  Widget _buildCardOcorrencia(Map<String, dynamic> oc, Color corBarra, bool isAtiva) {
    String numOc = (oc['numero_da_ocorrencia'] ?? oc['doc_id'] ?? 'S/N').toString();
    String semaforo = (oc['semaforo'] ?? '---').toString();
    String endereco = (oc['endereco'] ?? '---').toString();
    String falha = (oc['tipo_da_falha'] ?? '---').toString();
    String falhaConstatada = (oc['falha_aparente_final'] ?? '---').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8, top: 4),
      clipBehavior: Clip.hardEdge, // Essencial para o container interno respeitar os cantos redondos
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        // BORDA UNIFORME: Resolve o erro silencioso do Flutter
        border: Border.all(color: Colors.grey.shade300, width: 1), 
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Container(
        // Desenhamos a borda colorida da esquerda aqui dentro
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: corBarra, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min, 
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(Icons.traffic, size: 12, color: Colors.blueGrey),
                          const SizedBox(width: 4),
                          Text('$semaforo - ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
                          InkWell(
                            onTap: () {
                              if (isAtiva) {
                                _abrirModalOcorrenciaAcao(oc['doc_id']?.toString() ?? '', oc);
                              } else {
                                _abrirDetalhesCompletosFinalizada(oc);
                              }
                            },
                            child: Text(
                              numOc, 
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue, decoration: TextDecoration.underline)
                            ),
                          ),
                        ],
                      ),
                      if (!isAtiva) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.check_circle, color: Colors.green, size: 14))
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, size: 10, color: Colors.redAccent),
                      const SizedBox(width: 4),
                      Expanded(child: Text(endereco, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black54))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Relatada: $falha', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isAtiva ? Colors.orange.shade800 : Colors.black54, fontWeight: isAtiva ? FontWeight.bold : FontWeight.normal)),
                  
                  if (!isAtiva) ...[
                    const SizedBox(height: 4),
                    Text('Constatada: $falhaConstatada', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
            
            // AÇÕES BOTTOM
            // Substituí a borda superior complexa por um Divider limpo, evitando o mesmo erro
            const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
              ),
              child: isAtiva 
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: corBarra,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () => _abrirModalOcorrenciaAcao(oc['doc_id']?.toString() ?? '', oc),
                        child: Text(
                          corBarra == Colors.orange ? 'INFORMAR CHEGADA' : 'FINALIZAR', 
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () => _atribuirEquipeOcorrencia(oc['doc_id']?.toString() ?? ''),
                        child: const Text('TROCAR EQUIPE', style: TextStyle(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  )
                : Center(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      icon: const Icon(Icons.list_alt, size: 14),
                      label: const Text('VER DETALHES COMPLETOS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      onPressed: () => _abrirDetalhesCompletosFinalizada(oc),
                    ),
                  )
            )
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Equipes Formadas', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [MenuUsuario()],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.green,
          tabs: const [
            Tab(icon: Icon(Icons.directions_car), text: 'Ativas'),
            Tab(icon: Icon(Icons.check_circle), text: 'Finalizadas'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0 
        ? FloatingActionButton.extended(
            backgroundColor: const Color(0xFF2ecc71), 
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Nova Equipe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => _abrirModalNovaEquipe(),
          )
        : null, 
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/tela.png',
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.4),
            colorBlendMode: BlendMode.darken,
          ),
          
          Column(
            children: [
              const SizedBox(height: 190), 

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _buscaPlacaController,
                            decoration: const InputDecoration(labelText: 'Filtrar por Placa', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                            onChanged: (v) => setState(() => _termoPlaca = v.toLowerCase()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _buscaIntegranteController,
                            decoration: const InputDecoration(labelText: 'Filtrar por Integrante', prefixIcon: Icon(Icons.person_search), border: OutlineInputBorder(), isDense: true),
                            onChanged: (v) => setState(() => _termoIntegrante = v.toLowerCase()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('equipes').orderBy('data_inicio', descending: true).snapshots(),
                  builder: (context, snapshotEquipes) {
                    if (snapshotEquipes.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
                    if (snapshotEquipes.hasError) return const Center(child: Text('Erro ao carregar equipes.', style: TextStyle(color: Colors.white)));
                    
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').snapshots(),
                      builder: (context, snapshotOcorrencias) {
                        if (snapshotOcorrencias.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.green));
                        
                        final docsEquipes = snapshotEquipes.data?.docs ?? [];
                        final docsOcorrencias = snapshotOcorrencias.data?.docs ?? [];
                        
                        final filtrados = docsEquipes.where((doc) {
                          var d = doc.data() as Map<String, dynamic>;
                          String placa = (d['placa'] ?? '').toString().toLowerCase();
                          String ints = (d['integrantes_str'] ?? '').toString().toLowerCase();

                          if (_termoPlaca.isNotEmpty && !placa.contains(_termoPlaca)) return false;
                          if (_termoIntegrante.isNotEmpty && !ints.contains(_termoIntegrante)) return false;
                          return true;
                        }).toList();

                        final equipesAtivas = filtrados.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'ativo').toList();
                        final equipesFinalizadas = filtrados.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'finalizado').toList();

                        return TabBarView(
                          controller: _tabController,
                          children: [
                            _buildGrid(equipesAtivas, true, docsOcorrencias),
                            _buildGrid(equipesFinalizadas, false, docsOcorrencias),
                          ],
                        );
                      }
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}