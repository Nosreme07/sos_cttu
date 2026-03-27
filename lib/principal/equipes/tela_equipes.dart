import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Importações para PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../widgets/menu_usuario.dart'; 

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); 
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaPlacaController.dispose();
    _buscaIntegranteController.dispose();
    super.dispose();
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return '---';
    DateTime dt = timestamp.toDate();
    return DateFormat('dd/MM/yy HH:mm').format(dt);
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

  // =========================================================================
  // MOTOR DE CRUZAMENTO: QUAIS OCORRÊNCIAS ESTA EQUIPE ATENDEU?
  // =========================================================================
  List<Map<String, dynamic>> _obterOcorrenciasDaEquipe(Map<String, dynamic> eqData, List<QueryDocumentSnapshot> todasOcorrencias) {
    String placa = (eqData['placa'] ?? '').toString().toUpperCase();
    String intsStr = (eqData['integrantes_str'] ?? '').toString().toUpperCase();
    String nomeLider = intsStr.split(',').first.trim();

    Timestamp? tsInicio = eqData['data_inicio'];
    Timestamp? tsFim = eqData['data_fim'];

    DateTime dtInicio = tsInicio != null
        ? tsInicio.toDate().subtract(const Duration(minutes: 10))
        : DateTime.fromMillisecondsSinceEpoch(0);
    DateTime dtFim = tsFim != null
        ? tsFim.toDate().add(const Duration(minutes: 10))
        : DateTime.now().add(const Duration(days: 1));

    List<Map<String, dynamic>> atendidas = [];

    for (var doc in todasOcorrencias) {
      var oc = doc.data() as Map<String, dynamic>;
      String equipeResp = (oc['equipe_responsavel'] ?? oc['equipe_atrelada'] ?? '').toString().toUpperCase();
      String placaResp = (oc['placa_veiculo'] ?? '').toString().toUpperCase();

      bool bateuNome = nomeLider.isNotEmpty && equipeResp.contains(nomeLider);
      bool bateuPlaca = placa.isNotEmpty && (placaResp == placa || equipeResp.contains(placa));

      if (bateuNome || bateuPlaca) {
        Timestamp? tsAtend = oc['data_atendimento'] ?? oc['data_de_abertura'];
        if (tsAtend != null) {
          DateTime dtAtend = tsAtend.toDate();
          if (dtAtend.isAfter(dtInicio) && dtAtend.isBefore(dtFim)) {
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
                  pw.Text('Nº Ocorrência: ${oc['numero_da_ocorrencia'] ?? oc['id'] ?? 'S/N'}', style: const pw.TextStyle(fontSize: 10)),
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

  // =========================================================================
  // "CÉREBRO" DO DESPACHO: Cruza os dados para saber quem está livre
  // =========================================================================
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

  // =========================================================================
  // MODAL INTELIGENTE: FORMAR NOVA EQUIPE
  // =========================================================================
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
                            // --- Viatura ---
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
                            
                            // --- Integrantes ---
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

                            // --- KM e Observações ---
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

  // --- Função Finalizar Equipe ---
  Future<void> _finalizarEquipe(String docId, Map<String, dynamic> dadosAtuais) async {
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
        constraints: const BoxConstraints(maxWidth: 1200),
        child: GridView.builder(
          padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16, top: 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 380, 
            mainAxisExtent: 300, // Aumentei a altura para caber os semáforos
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: lista.length,
          itemBuilder: (context, index) {
            var doc = lista[index];
            var data = doc.data() as Map<String, dynamic>;
            
            Color corStatus = isAtivo ? const Color(0xFF2ecc71) : const Color(0xFF7f8c8d);
            String txtStatus = isAtivo ? 'ATIVO' : 'FINALIZADO';
            
            String dtInicio = _formatarData(data['data_inicio']);
            String dtFim = isAtivo ? '' : _formatarData(data['data_fim']);

            String placa = data['placa'] ?? 'S/ PLACA';
            String tipo = data['tipo'] ?? data['tipo_veiculo'] ?? '';
            String empresa = data['empresa'] ?? '';
            
            String headerTextoCarro = tipo.isNotEmpty ? '$placa ($tipo)' : placa;

            // BUSCA INTELIGENTE DE OCORRÊNCIAS/SEMÁFOROS
            var ocorrenciasDaEquipe = _obterOcorrenciasDaEquipe(data, ocorrenciasDocs);
            List<String> semaforosAtendidos = ocorrenciasDaEquipe
                .map((o) => (o['semaforo'] ?? '').toString())
                .toSet()
                .where((s) => s.isNotEmpty)
                .toList();

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 6,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // CABEÇALHO AZUL
                  Container(
                    color: const Color(0xFF448aff),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🚗 $headerTextoCarro', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        if (empresa.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(empresa, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(color: corStatus, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white, width: 1.5)),
                          child: Text(txtStatus, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        )
                      ],
                    ),
                  ),
                  
                  // CORPO BRANCO
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Início: $dtInicio', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                              if (!isAtivo) Text('Fim: $dtFim', style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Divider(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('KM Ini: ${data['km_inicial'] ?? '0'}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                              Text('KM Fim: ${data['km_final'] ?? '---'}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                              Text('Rodado: ${data['km_rodado'] ?? '---'}', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          const Text('👤 Integrantes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF444444))),
                          Text(
                            data['integrantes_str'] ?? '-', 
                            style: const TextStyle(fontSize: 11, color: Colors.black87),
                            maxLines: 2, 
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),

                          // BOX DE SEMÁFOROS
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('🚦 Semáforos Atendidos:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                const SizedBox(height: 4),
                                semaforosAtendidos.isEmpty 
                                  ? const Text('Nenhum semáforo vinculado no momento.', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey))
                                  : Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: semaforosAtendidos.map((s) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue.shade200)),
                                        child: Text(s, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                                      )).toList(),
                                    ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),

                  // FOOTER ACTIONS
                  Container(
                    color: Colors.grey.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: isAtivo ? [
                        TextButton(
                          onPressed: () => _abrirModalNovaEquipe(docId: doc.id, dadosAtuais: data), 
                          child: const Text('Editar', style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 12))
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFeb4c4c), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          onPressed: () => _finalizarEquipe(doc.id, data),
                          child: const Text('Finalizar Equipe', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        )
                      ] : [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF34495e), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 14),
                          label: const Text('Exportar PDF', style: TextStyle(color: Colors.white, fontSize: 11)),
                          onPressed: () => _exportarPdfIndividual(data, ocorrenciasDaEquipe),
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          },
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
                // Duplo StreamBuilder para carregar as Equipes e as Ocorrências simultaneamente
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