import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;

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

class TelaRelatorioEquipes extends StatefulWidget {
  const TelaRelatorioEquipes({super.key});

  @override
  State<TelaRelatorioEquipes> createState() => _TelaRelatorioEquipesState();
}

class _TelaRelatorioEquipesState extends State<TelaRelatorioEquipes> {
  // Filtros
  DateTime? _dataInicio;
  DateTime? _dataFim;
  String _filtroEmpresa = '';
  String _filtroTipo = '';
  String _filtroStatus = '';

  final TextEditingController _filtroPlacaCtrl = TextEditingController();
  final TextEditingController _filtroIntegranteCtrl = TextEditingController();
  final TextEditingController _filtroSemaforoCtrl = TextEditingController();

  final FocusNode _focusPlaca = FocusNode();
  final FocusNode _focusIntegrante = FocusNode();
  final FocusNode _focusSemaforo = FocusNode();

  List<String> _empresas = [];
  List<String> _tiposVeiculo = [];
  List<QueryDocumentSnapshot> _todasOcorrencias = [];
  
  // Lista global de integrantes para cruzamento de empresas
  List<Map<String, dynamic>> _todosIntegrantes = [];

  // Listas para o Autocomplete
  List<String> _opcoesPlacas = [];
  List<String> _opcoesIntegrantes = [];
  List<String> _opcoesSemaforos = [];

  @override
  void initState() {
    super.initState();
    _carregarAuxiliares();
  }

  @override
  void dispose() {
    _filtroPlacaCtrl.dispose();
    _filtroIntegranteCtrl.dispose();
    _filtroSemaforoCtrl.dispose();
    _focusPlaca.dispose();
    _focusIntegrante.dispose();
    _focusSemaforo.dispose();
    super.dispose();
  }

  Future<void> _carregarAuxiliares() async {
    // Carrega as ocorrências para cruzar com as equipes
    final resOcorrencias = await FirebaseFirestore.instance
        .collection('Gerenciamento_ocorrencias')
        .get();
    _todasOcorrencias = resOcorrencias.docs;

    // Busca Empresas, Equipes, Veículos, Semáforos e Integrantes
    final resEmpresas = await FirebaseFirestore.instance.collection('empresas').get();
    final resEquipes = await FirebaseFirestore.instance.collection('equipes').get();
    final resVeiculos = await FirebaseFirestore.instance.collection('veiculos').get();
    final resSemaforos = await FirebaseFirestore.instance.collection('semaforos').get();
    final resIntegrantes = await FirebaseFirestore.instance.collection('integrantes').get();

    Set<String> empSet = {};
    Set<String> tipoSet = {};
    Set<String> placaSet = {};
    Set<String> intSet = {};
    Set<String> semaforoSet = {};

    // Salva os integrantes na memória para uso no filtro de empresa
    List<Map<String, dynamic>> intsLocal = [];
    for (var doc in resIntegrantes.docs) {
      intsLocal.add(doc.data());
    }

    // Pega as empresas da coleção oficial de empresas
    for (var doc in resEmpresas.docs) {
      String emp = (doc.data()['nome'] ?? doc.data()['empresa'] ?? doc.id).toString().toUpperCase();
      if (emp.isNotEmpty) empSet.add(emp);
    }

    // Pega os dados das equipes
    for (var doc in resEquipes.docs) {
      var d = doc.data();
      
      String emp = (d['empresa'] ?? '').toString().toUpperCase();
      if (emp.isNotEmpty) empSet.add(emp);

      String placa = (d['placa'] ?? '').toString().toUpperCase();
      if (placa.isNotEmpty) placaSet.add(placa);

      String ints = (d['integrantes_str'] ?? '').toString().toUpperCase();
      if (ints.isNotEmpty) {
        var partes = ints.split(',');
        for (var p in partes) {
          if (p.trim().isNotEmpty) intSet.add(p.trim());
        }
      }
    }

    for (var doc in resVeiculos.docs) {
      String tipo = (doc.data()['tipo'] ?? doc.data()['tipo_veiculo'] ?? '').toString().toUpperCase();
      if (tipo.isNotEmpty) tipoSet.add(tipo);
    }

    for (var doc in resSemaforos.docs) {
      String sem = (doc.data()['numero'] ?? doc.data()['id'] ?? '').toString().toUpperCase();
      if (sem.isNotEmpty) semaforoSet.add(sem);
    }

    setState(() {
      _todosIntegrantes = intsLocal;
      _empresas = empSet.toList()..sort();
      _tiposVeiculo = tipoSet.toList()..sort();
      _opcoesPlacas = placaSet.toList()..sort();
      _opcoesIntegrantes = intSet.toList()..sort();
      _opcoesSemaforos = semaforoSet.toList()..sort();
    });
  }

  void _limparFiltros() {
    setState(() {
      _dataInicio = null;
      _dataFim = null;
      _filtroEmpresa = '';
      _filtroTipo = '';
      _filtroStatus = '';
      _filtroPlacaCtrl.clear();
      _filtroIntegranteCtrl.clear();
      _filtroSemaforoCtrl.clear();
    });
  }

  String _formatarData(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yy HH:mm\'h\'').format(t.toDate());
  }

  String _formatarDataCompleta(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(t.toDate());
  }

  Color _corStatus(String status) {
    String st = status.toLowerCase();
    if (st == 'ativo') return Colors.green;
    if (st == 'finalizado' || st.contains('conclu')) return Colors.blueGrey;
    if (st.contains('aberto')) return Colors.redAccent;
    if (st.contains('atendimento')) return Colors.blue;
    if (st.contains('deslocamento')) return Colors.orange;
    return Colors.grey;
  }

  // --- MOTOR DE CRUZAMENTO: QUAIS OCORRÊNCIAS ESTA EQUIPE ATENDEU? ---
  List<Map<String, dynamic>> _obterOcorrenciasDaEquipe(Map<String, dynamic> eqData) {
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

    for (var doc in _todasOcorrencias) {
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

  // --- POPUP DE DETALHES COMPLETOS DA OCORRÊNCIA (Reutilizado do Relatorio Ocorrencias) ---
  void _abrirDetalhesOcorrencia(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Detalhes da Ocorrência: ${data['numero_da_ocorrencia'] ?? data['id'] ?? 'S/N'}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Semáforo / End.', '${data['semaforo']} - ${data['endereco']}'),
                _buildDetailRow('Bairro', data['bairro']),
                _buildDetailRow('Empresa', data['empresa_semaforo']),
                _buildDetailRow('Origem', data['origem_da_ocorrencia']),
                const Divider(),
                _buildDetailRow('Data Abertura', _formatarDataCompleta(data['data_de_abertura'])),
                _buildDetailRow('Data Atendimento', _formatarDataCompleta(data['data_atendimento'])),
                _buildDetailRow('Data Finalização', _formatarDataCompleta(data['data_de_finalizacao'])),
                const Divider(),
                _buildDetailRow('Usuário Abertura', data['usuario_abertura']),
                _buildDetailRow('Usuário Finalização', data['usuario_finalizacao']),
                _buildDetailRow('Equipe Resp.', data['equipe_atrelada'] ?? data['equipe_responsavel']),
                _buildDetailRow('Placa', data['placa_veiculo']),
                const Divider(),
                _buildDetailRow('Falha Relatada', data['tipo_da_falha']),
                _buildDetailRow('Detalhes Relatados', data['detalhes']),
                _buildDetailRow('Falha Encontrada (Final)', data['falha_aparente_final']),
                _buildDetailRow('Descrição do Encontro', data['descricao_encontro']),
                _buildDetailRow('Ação Técnica', data['acao_equipe']),
                
                if (data['fotos_finalizacao'] != null && (data['fotos_finalizacao'] as List).isNotEmpty) ...[
                  const Divider(),
                  const Text('Fotos da Finalização:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2c3e50), fontSize: 13)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: (data['fotos_finalizacao'] as List).map((base64Str) {
                      try {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(base64Decode(base64Str), width: 100, height: 100, fit: BoxFit.cover),
                        );
                      } catch (e) {
                        return const SizedBox.shrink();
                      }
                    }).toList(),
                  ),
                ]
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // --- MODAL DE DETALHES DO TURNO DA EQUIPE ---
  void _abrirDetalhes(Map<String, dynamic> data, List<Map<String, dynamic>> ocorrencias) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Detalhes do Turno da Equipe',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDetailRow('Veículo', '${data['placa'] ?? '-'} (${data['tipo'] ?? data['tipo_veiculo'] ?? '-'})'),
                  _buildDetailRow('Empresa', data['empresa']),
                  _buildDetailRow('Data Início', _formatarDataCompleta(data['data_inicio'])),
                  _buildDetailRow('Data Fim', _formatarDataCompleta(data['data_fim'])),
                  _buildDetailRow('Status', data['status']?.toString().toUpperCase()),
                  _buildDetailRow('KM', 'Ini: ${data['km_inicial'] ?? 0} | Fim: ${data['km_final'] ?? '-'} | Rodado: ${data['km_rodado'] ?? 0}'),
                  const Divider(),
                  const Text('👤 INTEGRANTES:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                  Text(data['integrantes_str'] ?? '-', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 10),
                  const Text('📝 OBSERVAÇÕES:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                  Text(data['observacoes'] ?? 'Nenhuma observação', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  
                  const Divider(height: 30, thickness: 2, color: Colors.blue),
                  const Text('🚦 OCORRÊNCIAS ATENDIDAS NESTE TURNO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
                  const SizedBox(height: 10),
                  
                  if (ocorrencias.isEmpty)
                    const Text('Nenhuma ocorrência vinculada.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                    
                  ...ocorrencias.map((oc) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border(left: BorderSide(color: _corStatus(oc['status'] ?? ''), width: 4)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${oc['semaforo'] ?? '---'} - ${oc['endereco'] ?? '---'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2c3e50))),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Text('Nº Ocorrência: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              InkWell(
                                onTap: () => _abrirDetalhesOcorrencia(oc),
                                child: Text(
                                  '${oc['numero_da_ocorrencia'] ?? oc['id'] ?? 'S/N'}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue, decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Falha Relatada: ${oc['tipo_da_falha'] ?? '---'}', style: const TextStyle(fontSize: 12)),
                          Text('Falha Encontrada: ${oc['falha_aparente_final'] ?? '---'}', style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text('Status: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              Text(
                                (oc['status'] ?? '').toString().toUpperCase(),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _corStatus(oc['status'] ?? '')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              label: const Text('Baixar PDF deste Turno', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onPressed: () => _gerarPdfIndividual(data, ocorrencias),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2c3e50))),
            TextSpan(text: (value ?? '---').toString()),
          ],
        ),
      ),
    );
  }

  // --- PDF INDIVIDUAL DO TURNO DA EQUIPE (COM ASSINATURA) ---
  Future<void> _gerarPdfIndividual(Map<String, dynamic> data, List<Map<String, dynamic>> ocorrencias) async {
    final pdf = pw.Document();
    String placa = data['placa'] ?? 'S_PLACA';

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
                    'Relatório gerado pelo Sistema de Ocorrências semafóricas - SOS em ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}',
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
          pw.Text('Início do Turno: ${_formatarDataCompleta(data['data_inicio'])}'),
          pw.Text('Fim do Turno: ${_formatarDataCompleta(data['data_fim'])}'),
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

          // --- CAMPO DE ASSINATURA NO FINAL ---
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

  // --- PDF GLOBAL DAS EQUIPES ---
  Future<void> _exportarPdfGlobal(List<QueryDocumentSnapshot> docs) async {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não há dados para gerar PDF.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando PDF... Aguarde!'), backgroundColor: Colors.orange));

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
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
                    'Relatório gerado pelo Sistema de Ocorrências semafóricas - SOS em ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}',
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
        build: (context) => [
          pw.Text('Relatório Global de Equipes em Campo', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Text('Total de Registros filtrados: ${docs.length}'),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: ['Início', 'Fim', 'Status', 'Placa', 'Empresa', 'Líder', 'Atendimentos', 'KM Rodado'],
            data: docs.map((doc) {
              var d = doc.data() as Map<String, dynamic>;
              String lider = (d['integrantes_str'] ?? '').toString().split(',').first.trim();
              
              var ocorrenciasDestaEquipe = _obterOcorrenciasDaEquipe(d);
              List<String> sems = ocorrenciasDestaEquipe.map((o) => o['semaforo'].toString()).toSet().toList();

              return [
                _formatarData(d['data_inicio']),
                _formatarData(d['data_fim']),
                (d['status'] ?? '-').toString().toUpperCase().replaceAll(' ', '\n'),
                d['placa'] ?? '-',
                d['empresa'] ?? 'Externa',
                lider,
                sems.isEmpty ? '-' : sems.join(', '),
                '${d['km_rodado'] ?? 0} km',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.center,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Relatorio_Global_Equipes.pdf');
  }

  // --- EXPORTAÇÃO EXCEL (XLSX) GLOBAL ---
  void _baixarExcel(List<QueryDocumentSnapshot> docs) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Relatório'];
    excel.setDefaultSheet('Relatório');

    sheetObject.appendRow([TextCellValue("Relatório Global de Equipes")]);
    sheetObject.appendRow([TextCellValue("Filtros Aplicados:")]);
    sheetObject.appendRow([TextCellValue("Placa:"), TextCellValue(_filtroPlacaCtrl.text.isEmpty ? 'Todas' : _filtroPlacaCtrl.text)]);
    sheetObject.appendRow([TextCellValue("Integrante:"), TextCellValue(_filtroIntegranteCtrl.text.isEmpty ? 'Todos' : _filtroIntegranteCtrl.text)]);
    sheetObject.appendRow([TextCellValue("Semáforo:"), TextCellValue(_filtroSemaforoCtrl.text.isEmpty ? 'Todos' : _filtroSemaforoCtrl.text)]);
    sheetObject.appendRow([TextCellValue("Empresa:"), TextCellValue(_filtroEmpresa.isEmpty ? 'Todas' : _filtroEmpresa)]);
    sheetObject.appendRow([TextCellValue("Tipo:"), TextCellValue(_filtroTipo.isEmpty ? 'Todos' : _filtroTipo)]);
    sheetObject.appendRow([TextCellValue("Status:"), TextCellValue(_filtroStatus.isEmpty ? 'Todos' : _filtroStatus)]);
    
    String dtIni = _dataInicio != null ? DateFormat('dd/MM/yyyy').format(_dataInicio!) : '-';
    String dtFim = _dataFim != null ? DateFormat('dd/MM/yyyy').format(_dataFim!) : '-';
    sheetObject.appendRow([TextCellValue("Período:"), TextCellValue("$dtIni até $dtFim")]);
    
    sheetObject.appendRow([TextCellValue("")]);

    sheetObject.appendRow([
      TextCellValue("Início do Turno"),
      TextCellValue("Fim do Turno"),
      TextCellValue("Status do Turno"),
      TextCellValue("Placa do Veículo"),
      TextCellValue("Tipo do Veículo"),
      TextCellValue("Empresa"),
      TextCellValue("Integrantes"),
      TextCellValue("KM Inicial"),
      TextCellValue("KM Final"),
      TextCellValue("KM Rodado"),
      TextCellValue("Qtd. Ocorrências"),
      TextCellValue("Semáforos Atendidos"),
      TextCellValue("Observações")
    ]);

    for (var doc in docs) {
      var d = doc.data() as Map<String, dynamic>;
      var ocorrencias = _obterOcorrenciasDaEquipe(d);
      List<String> sems = ocorrencias.map((o) => o['semaforo'].toString()).toSet().toList();

      sheetObject.appendRow([
        TextCellValue(_formatarDataCompleta(d['data_inicio'])),
        TextCellValue(_formatarDataCompleta(d['data_fim'])),
        TextCellValue((d['status'] ?? '-').toString().toUpperCase()),
        TextCellValue((d['placa'] ?? '-').toString()),
        TextCellValue((d['tipo'] ?? d['tipo_veiculo'] ?? '-').toString()),
        TextCellValue((d['empresa'] ?? '-').toString()),
        TextCellValue((d['integrantes_str'] ?? '-').toString()),
        TextCellValue((d['km_inicial'] ?? '0').toString()),
        TextCellValue((d['km_final'] ?? '-').toString()),
        TextCellValue((d['km_rodado'] ?? '0').toString()),
        TextCellValue(ocorrencias.length.toString()),
        TextCellValue(sems.isEmpty ? 'Nenhum' : sems.join(', ')),
        TextCellValue((d['observacoes'] ?? '-').toString()),
      ]);
    }

    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(Uint8List.fromList(fileBytes), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', name: 'Relatorio_Equipes.xlsx');
      await Share.shareXFiles([xfile], text: 'Relatório de Equipes');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilha Excel baixada com sucesso!'), backgroundColor: Colors.green));
    }
  }

  // --- EXPORTAÇÃO EXCEL (XLSX) INDIVIDUAL DE 1 EQUIPE ---
  void _baixarExcelIndividual(Map<String, dynamic> d) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Turno Equipe'];
    excel.setDefaultSheet('Turno Equipe');

    String placa = d['placa'] ?? 'S_PLACA';
    var ocorrencias = _obterOcorrenciasDaEquipe(d);
    List<String> sems = ocorrencias.map((o) => o['semaforo'].toString()).toSet().toList();

    sheetObject.appendRow([TextCellValue("Relatório Individual de Turno")]);
    sheetObject.appendRow([TextCellValue("")]);

    sheetObject.appendRow([
      TextCellValue("Início do Turno"),
      TextCellValue("Fim do Turno"),
      TextCellValue("Status do Turno"),
      TextCellValue("Placa do Veículo"),
      TextCellValue("Tipo do Veículo"),
      TextCellValue("Empresa"),
      TextCellValue("Integrantes"),
      TextCellValue("KM Inicial"),
      TextCellValue("KM Final"),
      TextCellValue("KM Rodado"),
      TextCellValue("Qtd. Ocorrências"),
      TextCellValue("Semáforos Atendidos"),
      TextCellValue("Observações")
    ]);

    sheetObject.appendRow([
      TextCellValue(_formatarDataCompleta(d['data_inicio'])),
      TextCellValue(_formatarDataCompleta(d['data_fim'])),
      TextCellValue((d['status'] ?? '-').toString().toUpperCase()),
      TextCellValue((d['placa'] ?? '-').toString()),
      TextCellValue((d['tipo'] ?? d['tipo_veiculo'] ?? '-').toString()),
      TextCellValue((d['empresa'] ?? '-').toString()),
      TextCellValue((d['integrantes_str'] ?? '-').toString()),
      TextCellValue((d['km_inicial'] ?? '0').toString()),
      TextCellValue((d['km_final'] ?? '-').toString()),
      TextCellValue((d['km_rodado'] ?? '0').toString()),
      TextCellValue(ocorrencias.length.toString()),
      TextCellValue(sems.isEmpty ? 'Nenhum' : sems.join(', ')),
      TextCellValue((d['observacoes'] ?? '-').toString()),
    ]);

    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(Uint8List.fromList(fileBytes), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', name: 'Turno_$placa.xlsx');
      await Share.shareXFiles([xfile], text: 'Turno Equipe $placa');
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilha individual baixada!'), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Relatório de Equipes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [MenuUsuario()],
      ),
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
              const SizedBox(height: 100),

              // --- PAINEL DE FILTROS ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3f5066),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Wrap(
                      spacing: 15,
                      runSpacing: 15,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        _buildAutocompleteField('Placa:', _filtroPlacaCtrl, _focusPlaca, _opcoesPlacas),
                        _buildAutocompleteField('Integrante:', _filtroIntegranteCtrl, _focusIntegrante, _opcoesIntegrantes),
                        _buildAutocompleteField('Semáforo Atendido:', _filtroSemaforoCtrl, _focusSemaforo, _opcoesSemaforos),

                        _buildDropdown('Empresa:', _filtroEmpresa, ['Todas', ..._empresas], (v) => setState(() => _filtroEmpresa = v == 'Todas' ? '' : v!)),
                        _buildDropdown('Tipo Veículo:', _filtroTipo, ['Todos', ..._tiposVeiculo], (v) => setState(() => _filtroTipo = v == 'Todos' ? '' : v!)),
                        _buildDropdown('Status do Turno:', _filtroStatus, ['Todos', 'Ativo', 'Finalizado'], (v) => setState(() => _filtroStatus = v == 'Todos' ? '' : v!)),

                        _buildDateFilter('De (Início):', _dataInicio, (d) => setState(() => _dataInicio = d)),
                        _buildDateFilter('Até (Início):', _dataFim, (d) => setState(() => _dataFim = d)),

                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          ),
                          onPressed: _limparFiltros,
                          child: const Text('Limpar Filtros'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // --- TABELA DE RESULTADOS ---
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('equipes')
                            .orderBy('data_inicio', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData) return const Center(child: Text('Nenhum dado.'));

                          // Aplica Filtros
                          var docs = snapshot.data!.docs.where((doc) {
                            var d = doc.data() as Map<String, dynamic>;

                            // --- NOVO: CHECAGEM DE EMPRESA AMPLIADA ---
                            // Verifica se a empresa está na equipe ou em qualquer integrante da equipe
                            if (_filtroEmpresa.isNotEmpty) {
                              bool empresaBate = (d['empresa'] ?? '').toString().toUpperCase() == _filtroEmpresa;
                              if (!empresaBate) {
                                String intsEquipe = (d['integrantes_str'] ?? '').toString().toUpperCase();
                                // Procura nos integrantes salvos na memória se algum que está nessa equipe pertence à empresa filtrada
                                bool algumIntBate = _todosIntegrantes.any((integranteMap) {
                                  String nomeInt = (integranteMap['nomeCompleto'] ?? '').toString().toUpperCase();
                                  String empInt = (integranteMap['empresa'] ?? '').toString().toUpperCase();
                                  return intsEquipe.contains(nomeInt) && empInt == _filtroEmpresa;
                                });
                                if (!algumIntBate) return false;
                              }
                            }
                            
                            if (_filtroTipo.isNotEmpty && (d['tipo'] ?? d['tipo_veiculo'] ?? '').toString().toUpperCase() != _filtroTipo) return false;
                            if (_filtroStatus.isNotEmpty && (d['status'] ?? '').toString().toUpperCase() != _filtroStatus.toUpperCase()) return false;

                            if (_filtroPlacaCtrl.text.isNotEmpty && !(d['placa'] ?? '').toString().toUpperCase().contains(_filtroPlacaCtrl.text.toUpperCase())) return false;
                            if (_filtroIntegranteCtrl.text.isNotEmpty && !(d['integrantes_str'] ?? '').toString().toUpperCase().contains(_filtroIntegranteCtrl.text.toUpperCase())) return false;

                            if (_dataInicio != null || _dataFim != null) {
                              if (d['data_inicio'] == null) return false;
                              DateTime dt = (d['data_inicio'] as Timestamp).toDate();
                              if (_dataInicio != null && dt.isBefore(_dataInicio!)) return false;
                              if (_dataFim != null && dt.isAfter(_dataFim!.add(const Duration(days: 1)))) return false;
                            }

                            return true;
                          }).toList();

                          // Filtro complexo: Se filtrou por "Semáforo Atendido"
                          if (_filtroSemaforoCtrl.text.isNotEmpty) {
                            docs = docs.where((doc) {
                              var d = doc.data() as Map<String, dynamic>;
                              var ocorrencias = _obterOcorrenciasDaEquipe(d);
                              return ocorrencias.any((oc) => (oc['semaforo'] ?? '').toString().contains(_filtroSemaforoCtrl.text));
                            }).toList();
                          }

                          if (docs.isEmpty) {
                            return const Center(child: Text('Nenhum registro encontrado com estes filtros.'));
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total: ${docs.length} registros',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                                    ),
                                    Row(
                                      children: [
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                          icon: const Icon(Icons.download, color: Colors.white, size: 16),
                                          label: const Text('Baixar Planilha (XLSX)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                          onPressed: () => _baixarExcel(docs),
                                        ),
                                        const SizedBox(width: 10),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                          icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 16),
                                          label: const Text('Baixar PDF Global', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                          onPressed: () => _exportarPdfGlobal(docs),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      scrollDirection: Axis.vertical,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                          child: DataTable(
                                            headingRowColor: WidgetStateProperty.all(const Color(0xFFeceff1)),
                                            columnSpacing: 20,
                                            dataRowMinHeight: 60,
                                            dataRowMaxHeight: 90,
                                            columns: const [
                                              DataColumn(label: Expanded(child: Center(child: Text('Início', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Fim', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Status', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Placa', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Empresa', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Integrantes', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Atendimentos', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('KM Rodado', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Ações', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                            ],
                                            rows: docs.map((doc) {
                                              var d = doc.data() as Map<String, dynamic>;
                                              String st = d['status'] ?? 'ativo';
                                              String stQuebrado = st.toUpperCase().replaceAll(' ', '\n');

                                              var ocorrenciasDestaEquipe = _obterOcorrenciasDaEquipe(d);
                                              List<String> sems = ocorrenciasDestaEquipe.map((o) => o['semaforo'].toString()).toSet().toList();

                                              return DataRow(
                                                cells: [
                                                  DataCell(Center(child: Text(_formatarData(d['data_inicio']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
                                                  DataCell(Center(child: Text(_formatarData(d['data_fim']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
                                                  DataCell(
                                                    Center(
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(color: _corStatus(st), borderRadius: BorderRadius.circular(4)),
                                                        child: Text(stQuebrado, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(Center(child: Text(d['placa'] ?? '---', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
                                                  DataCell(Center(child: Text(d['empresa'] ?? 'Externa', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
                                                  DataCell(
                                                    Center(
                                                      child: SizedBox(
                                                        width: 150,
                                                        child: Text(d['integrantes_str'] ?? '', textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Center(
                                                      child: Text(
                                                        sems.isEmpty ? '-' : sems.join(', '),
                                                        textAlign: TextAlign.center,
                                                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(Center(child: Text('${d['km_rodado'] ?? 0} km', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
                                                  DataCell(
                                                    Center(
                                                      child: SizedBox(
                                                        width: 120,
                                                        child: Row(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            IconButton(
                                                              icon: const Icon(Icons.visibility, color: Colors.blueGrey, size: 20),
                                                              tooltip: 'Ver Detalhes do Turno',
                                                              onPressed: () => _abrirDetalhes(d, ocorrenciasDestaEquipe),
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(Icons.download_outlined, color: Colors.green, size: 20),
                                                              tooltip: 'Baixar Planilha Individual',
                                                              onPressed: () => _baixarExcelIndividual(d),
                                                            ),
                                                            IconButton(
                                                              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 20),
                                                              tooltip: 'Baixar PDF',
                                                              onPressed: () => _gerarPdfIndividual(d, ocorrenciasDestaEquipe),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- WIDGETS AUXILIARES COM LARGURA PADRONIZADA (180px) ---

  Widget _buildAutocompleteField(String label, TextEditingController controller, FocusNode focus, List<String> options) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            height: 42,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
            child: RawAutocomplete<String>(
              textEditingController: controller,
              focusNode: focus,
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                return options.where((String option) => option.contains(textEditingValue.text.toUpperCase()));
              },
              onSelected: (String selection) {
                controller.text = selection;
                setState(() {});
              },
              fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                return TextField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  onChanged: (v) => setState(() {}),
                  inputFormatters: [UpperCaseTextFormatter()],
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12), isDense: true),
                );
              },
              optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4.0,
                    borderRadius: BorderRadius.circular(4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200, maxWidth: 180),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final String option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                              child: Text(option, style: const TextStyle(fontSize: 11)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilter(String label, DateTime? val, Function(DateTime) onPicked) {
    return SizedBox(
      width: 180, 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          InkWell(
            onTap: () async {
              DateTime? picked = await showDatePicker(context: context, initialDate: val ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
              if (picked != null) onPicked(picked);
            },
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Text(val == null ? 'dd/mm/aaaa' : DateFormat('dd/MM/yyyy').format(val), style: const TextStyle(color: Colors.black87)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return SizedBox(
      width: 180, 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true, 
                value: value.isEmpty ? items.first : value,
                items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}