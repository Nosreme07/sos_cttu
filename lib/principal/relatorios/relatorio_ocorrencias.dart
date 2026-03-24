import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide TextSpan, Border; 

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

class TelaRelatorioOcorrencias extends StatefulWidget {
  const TelaRelatorioOcorrencias({super.key});

  @override
  State<TelaRelatorioOcorrencias> createState() =>
      _TelaRelatorioOcorrenciasState();
}

class _TelaRelatorioOcorrenciasState extends State<TelaRelatorioOcorrencias> {
  // Filtros
  final TextEditingController _filtroSemaforoCtrl = TextEditingController();
  final TextEditingController _filtroEnderecoCtrl = TextEditingController();
  final TextEditingController _filtroFalhaCtrl = TextEditingController();
  
  final FocusNode _focusSemaforo = FocusNode();
  final FocusNode _focusEndereco = FocusNode();
  final FocusNode _focusFalha = FocusNode();

  String _filtroEmpresa = '';
  String _filtroStatus = '';
  String _filtroPrazo = ''; 
  DateTime? _dataInicioAbertura;
  DateTime? _dataFimFechamento;

  List<String> _empresas = [];
  List<Map<String, dynamic>> _falhasAux = []; 
  
  List<String> _opcoesSemaforos = [];
  List<String> _opcoesEnderecos = [];
  List<String> _opcoesFalhas = [];

  @override
  void initState() {
    super.initState();
    _carregarFiltros();
  }

  @override
  void dispose() {
    _filtroSemaforoCtrl.dispose();
    _filtroEnderecoCtrl.dispose();
    _filtroFalhaCtrl.dispose();
    _focusSemaforo.dispose();
    _focusEndereco.dispose();
    _focusFalha.dispose();
    super.dispose();
  }

  Future<void> _carregarFiltros() async {
    final resFalhas = await FirebaseFirestore.instance.collection('falhas').get();
    final resSemaforos = await FirebaseFirestore.instance.collection('semaforos').get();

    Set<String> empSet = {};
    List<Map<String, dynamic>> semaforosLocal = [];
    
    for (var doc in resSemaforos.docs) {
      var d = doc.data();
      String emp = (d['empresa'] ?? '').toString().toUpperCase();
      if (emp.isNotEmpty) empSet.add(emp);
      
      semaforosLocal.add({
        'id': (d['numero'] ?? d['id'] ?? '').toString(),
        'endereco': (d['endereco'] ?? '').toString(),
      });
    }

    List<Map<String, dynamic>> falhasLocal = [];
    for (var doc in resFalhas.docs) {
      var d = doc.data();
      falhasLocal.add({
        'falha': (d['tipo_da_falha'] ?? d['falha'] ?? '').toString(),
        'prazo': (d['prazo'] ?? '').toString(),
      });
    }

    setState(() {
      _falhasAux = falhasLocal;
      _empresas = empSet.toList()..sort();
      
      _opcoesSemaforos = semaforosLocal.map((s) => s['id'] as String).where((e) => e.isNotEmpty).toSet().toList()..sort();
      _opcoesEnderecos = semaforosLocal.map((s) => s['endereco'] as String).where((e) => e.isNotEmpty).toSet().toList()..sort();
      _opcoesFalhas = falhasLocal.map((f) => f['falha'] as String).where((e) => e.isNotEmpty).toSet().toList()..sort();
    });
  }

  void _limparFiltros() {
    setState(() {
      _filtroSemaforoCtrl.clear();
      _filtroEnderecoCtrl.clear();
      _filtroFalhaCtrl.clear();
      _filtroEmpresa = '';
      _filtroStatus = '';
      _filtroPrazo = '';
      _dataInicioAbertura = null;
      _dataFimFechamento = null;
    });
  }

  String _formatarDataHora(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yyyy - HH:mm\'h\'').format(t.toDate());
  }

  String _formatarDataHoraCompleta(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(t.toDate());
  }

  Color _corStatus(String status) {
    String st = status.toLowerCase();
    if (st.contains('aberto') || st.contains('pendente')) return Colors.redAccent;
    if (st.contains('deslocamento')) return Colors.orange;
    if (st.contains('atendimento')) return Colors.blue;
    if (st.contains('conclu') || st.contains('finaliz')) return Colors.green;
    return Colors.grey;
  }

  Map<String, dynamic> _calcularTempoVencido(Map<String, dynamic> d) {
    if (d['data_de_abertura'] == null) return {'vencido': false, 'texto': '---'};

    DateTime aberturaDt = (d['data_de_abertura'] as Timestamp).toDate();
    
    String prazoStr = (d['prazo'] ?? '').toString();
    if (prazoStr.isEmpty) {
      var falhaDoc = _falhasAux.firstWhere((f) => f['falha'] == d['tipo_da_falha'], orElse: () => <String, dynamic>{});
      prazoStr = (falhaDoc['prazo'] ?? '0').toString();
    }
    int prazoMinutos = int.tryParse(prazoStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (prazoMinutos <= 0) return {'vencido': false, 'texto': 'Sem prazo'};

    DateTime limite = aberturaDt.add(Duration(minutes: prazoMinutos));
    DateTime dataRef = d['data_de_finalizacao'] != null ? (d['data_de_finalizacao'] as Timestamp).toDate() : DateTime.now();

    if (dataRef.isAfter(limite)) {
      Duration diff = dataRef.difference(limite);
      String horas = diff.inHours > 0 ? '${diff.inHours}h ' : '';
      String minutos = '${diff.inMinutes.remainder(60)}m';
      return {'vencido': true, 'texto': '$horas$minutos'};
    }
    return {'vencido': false, 'texto': 'No prazo'};
  }

  void _abrirDetalhes(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Detalhes: ${data['numero_da_ocorrencia'] ?? data['id'] ?? 'S/N'}',
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
                _buildDetailRow('Data Abertura', _formatarDataHoraCompleta(data['data_de_abertura'])),
                _buildDetailRow('Data Atendimento', _formatarDataHoraCompleta(data['data_atendimento'])),
                _buildDetailRow('Data Finalização', _formatarDataHoraCompleta(data['data_de_finalizacao'])),
                _buildDetailRow('Tempo Vencido', _calcularTempoVencido(data)['texto']),
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
            TextButton.icon(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              label: const Text('Baixar PDF', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onPressed: () => _gerarPdfIndividual(data),
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
      padding: const EdgeInsets.only(bottom: 8.0),
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

  Future<void> _gerarPdfIndividual(Map<String, dynamic> dados) async {
    final pdf = pw.Document();
    String numOcc = dados['numero_da_ocorrencia'] ?? dados['id'] ?? 'N/A';
    Map<String, dynamic> vencimentoInfo = _calcularTempoVencido(dados);
    String textoVencimento = vencimentoInfo['vencido'] ? 'Sim (${vencimentoInfo['texto']} excedidos)' : 'Não';

    List<pw.Widget> imagensPdf = [];
    if (dados['fotos_finalizacao'] != null) {
      for (String base64Str in (dados['fotos_finalizacao'] as List)) {
        try {
          final imageBytes = base64Decode(base64Str);
          imagensPdf.add(
            pw.Container(
              margin: const pw.EdgeInsets.all(4),
              height: 110, width: 110,
              child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.cover)
            )
          );
        } catch (e) {}
      }
    }

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
          pw.Text('RELATÓRIO DE OCORRÊNCIA', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text('Nº da ocorrência: $numOcc', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Semáforo: ${dados['semaforo'] ?? '---'} - ${dados['endereco'] ?? '---'}'),
          pw.Text('Bairro: ${dados['bairro'] ?? '---'}'),
          pw.Text('Origem: ${dados['origem_da_ocorrencia'] ?? '---'}'),
          pw.SizedBox(height: 15),
          pw.Text('DATAS E PRAZOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
          pw.Text('Data de abertura: ${_formatarDataHoraCompleta(dados['data_de_abertura'])}'),
          pw.Text('Data de atendimento: ${_formatarDataHoraCompleta(dados['data_atendimento'])}'),
          pw.Text('Data de finalização: ${_formatarDataHoraCompleta(dados['data_de_finalizacao'])}'),
          pw.Text('Ocorrência venceu: $textoVencimento', style: pw.TextStyle(color: vencimentoInfo['vencido'] ? PdfColors.red : PdfColors.black)),
          pw.SizedBox(height: 15),
          pw.Text('ENVOLVIDOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
          pw.Text('Gerada por: ${dados['usuario_abertura'] ?? 'Sistema'}'),
          pw.Text('Finalizada por: ${dados['usuario_finalizacao'] ?? '---'}'),
          pw.Text('Equipe responsável: ${dados['integrantes_equipe'] ?? dados['equipe_responsavel'] ?? '---'}'),
          pw.Text('Veículo: ${dados['placa_veiculo'] ?? '---'}'),
          pw.SizedBox(height: 15),
          pw.Text('DADOS TÉCNICOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
          pw.Text('Falha Relatada: ${dados['tipo_da_falha'] ?? '---'}'),
          pw.Text('Falha encontrada: ${dados['falha_aparente_final'] ?? '---'}'),
          pw.Text('Ação técnica: ${dados['acao_equipe'] ?? '---'}'),
          
          if (imagensPdf.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text('FOTOS ANEXADAS:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Wrap(spacing: 10, runSpacing: 10, children: imagensPdf)
          ]
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Ocorrencia_$numOcc.pdf');
  }

  Future<void> _exportarPdfGlobal(List<QueryDocumentSnapshot> docs) async {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não há ocorrências para gerar PDF.')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando PDF... Aguarde! Isso pode levar alguns segundos.'), backgroundColor: Colors.orange));

    final pdf = pw.Document();

    for (var doc in docs) {
      var dados = doc.data() as Map<String, dynamic>;
      String numOcc = dados['numero_da_ocorrencia'] ?? dados['id'] ?? 'N/A';
      Map<String, dynamic> vencimentoInfo = _calcularTempoVencido(dados);
      String textoVencimento = vencimentoInfo['vencido'] ? 'Sim (${vencimentoInfo['texto']} excedidos)' : 'Não';

      List<pw.Widget> imagensPdf = [];
      if (dados['fotos_finalizacao'] != null) {
        for (String base64Str in (dados['fotos_finalizacao'] as List)) {
          try {
            final imageBytes = base64Decode(base64Str);
            imagensPdf.add(
              pw.Container(
                margin: const pw.EdgeInsets.all(4),
                height: 110, width: 110,
                child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.cover)
              )
            );
          } catch (e) {}
        }
      }

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
            pw.Text('RELATÓRIO DE OCORRÊNCIA', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text('Nº da ocorrência: $numOcc', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('Semáforo: ${dados['semaforo'] ?? '---'} - ${dados['endereco'] ?? '---'}'),
            pw.Text('Bairro: ${dados['bairro'] ?? '---'}'),
            pw.Text('Origem: ${dados['origem_da_ocorrencia'] ?? '---'}'),
            pw.SizedBox(height: 15),
            pw.Text('DATAS E PRAZOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
            pw.Text('Data de abertura: ${_formatarDataHoraCompleta(dados['data_de_abertura'])}'),
            pw.Text('Data de atendimento: ${_formatarDataHoraCompleta(dados['data_atendimento'])}'),
            pw.Text('Data de finalização: ${_formatarDataHoraCompleta(dados['data_de_finalizacao'])}'),
            pw.Text('Ocorrência venceu: $textoVencimento', style: pw.TextStyle(color: vencimentoInfo['vencido'] ? PdfColors.red : PdfColors.black)),
            pw.SizedBox(height: 15),
            pw.Text('ENVOLVIDOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
            pw.Text('Gerada por: ${dados['usuario_abertura'] ?? 'Sistema'}'),
            pw.Text('Finalizada por: ${dados['usuario_finalizacao'] ?? '---'}'),
            pw.Text('Equipe responsável: ${dados['integrantes_equipe'] ?? dados['equipe_responsavel'] ?? '---'}'),
            pw.Text('Veículo: ${dados['placa_veiculo'] ?? '---'}'),
            pw.SizedBox(height: 15),
            pw.Text('DADOS TÉCNICOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
            pw.Text('Falha Relatada: ${dados['tipo_da_falha'] ?? '---'}'),
            pw.Text('Falha encontrada: ${dados['falha_aparente_final'] ?? '---'}'),
            pw.Text('Ação técnica: ${dados['acao_equipe'] ?? '---'}'),
            
            if (imagensPdf.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text('FOTOS ANEXADAS:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Wrap(spacing: 10, runSpacing: 10, children: imagensPdf)
            ]
          ],
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Relatorio_Global_Ocorrencias.pdf');
  }

  void _baixarExcel(List<QueryDocumentSnapshot> docs) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Relatório'];
    excel.setDefaultSheet('Relatório');

    // FILTROS
    sheetObject.appendRow([TextCellValue("Relatório Global de Ocorrências")]);
    sheetObject.appendRow([TextCellValue("Filtros Aplicados:")]);
    sheetObject.appendRow([TextCellValue("Nº Semáforo:"), TextCellValue(_filtroSemaforoCtrl.text.isEmpty ? 'Todos' : _filtroSemaforoCtrl.text)]);
    sheetObject.appendRow([TextCellValue("Endereço:"), TextCellValue(_filtroEnderecoCtrl.text.isEmpty ? 'Todos' : _filtroEnderecoCtrl.text)]);
    sheetObject.appendRow([TextCellValue("Falha:"), TextCellValue(_filtroFalhaCtrl.text.isEmpty ? 'Todas' : _filtroFalhaCtrl.text)]);
    sheetObject.appendRow([TextCellValue("Empresa:"), TextCellValue(_filtroEmpresa.isEmpty ? 'Todas' : _filtroEmpresa)]);
    sheetObject.appendRow([TextCellValue("Status Ocorrência:"), TextCellValue(_filtroStatus.isEmpty ? 'Todos' : _filtroStatus)]);
    sheetObject.appendRow([TextCellValue("Status Prazo:"), TextCellValue(_filtroPrazo.isEmpty ? 'Todos' : _filtroPrazo)]);
    
    String dtIni = _dataInicioAbertura != null ? DateFormat('dd/MM/yyyy').format(_dataInicioAbertura!) : '-';
    String dtFim = _dataFimFechamento != null ? DateFormat('dd/MM/yyyy').format(_dataFimFechamento!) : '-';
    sheetObject.appendRow([TextCellValue("Período:"), TextCellValue("$dtIni até $dtFim")]);
    
    sheetObject.appendRow([TextCellValue("")]); // Linha em branco

    // CABEÇALHOS DA TABELA COMPLETOS
    sheetObject.appendRow([
      TextCellValue("Nº Ocorrência"),
      TextCellValue("Semáforo"),
      TextCellValue("Endereço"),
      TextCellValue("Bairro"),
      TextCellValue("Empresa"),
      TextCellValue("Origem"),
      TextCellValue("Status"),
      TextCellValue("Abertura"),
      TextCellValue("Atendimento"),
      TextCellValue("Finalização"),
      TextCellValue("Tempo Vencido"),
      TextCellValue("Usuário Abertura"),
      TextCellValue("Usuário Finalização"),
      TextCellValue("Equipe Responsável"),
      TextCellValue("Placa"),
      TextCellValue("Falha Relatada"),
      TextCellValue("Detalhes Relatados"),
      TextCellValue("Falha Encontrada (Final)"),
      TextCellValue("Descrição do Encontro"),
      TextCellValue("Ação Técnica")
    ]);

    // DADOS
    for (var doc in docs) {
      var d = doc.data() as Map<String, dynamic>;
      sheetObject.appendRow([
        TextCellValue((d['numero_da_ocorrencia'] ?? d['id'] ?? '-').toString()),
        TextCellValue((d['semaforo'] ?? '-').toString()),
        TextCellValue((d['endereco'] ?? '-').toString()),
        TextCellValue((d['bairro'] ?? '-').toString()),
        TextCellValue((d['empresa_semaforo'] ?? '-').toString()),
        TextCellValue((d['origem_da_ocorrencia'] ?? '-').toString()),
        TextCellValue((d['status'] ?? '-').toString().toUpperCase()),
        TextCellValue(_formatarDataHoraCompleta(d['data_de_abertura'])),
        TextCellValue(_formatarDataHoraCompleta(d['data_atendimento'])),
        TextCellValue(_formatarDataHoraCompleta(d['data_de_finalizacao'])),
        TextCellValue(_calcularTempoVencido(d)['texto']),
        TextCellValue((d['usuario_abertura'] ?? '-').toString()),
        TextCellValue((d['usuario_finalizacao'] ?? '-').toString()),
        TextCellValue((d['equipe_atrelada'] ?? d['equipe_responsavel'] ?? '-').toString()),
        TextCellValue((d['placa_veiculo'] ?? '-').toString()),
        TextCellValue((d['tipo_da_falha'] ?? '-').toString()),
        TextCellValue((d['detalhes'] ?? '-').toString()),
        TextCellValue((d['falha_aparente_final'] ?? '-').toString()),
        TextCellValue((d['descricao_encontro'] ?? '-').toString()),
        TextCellValue((d['acao_equipe'] ?? '-').toString()),
      ]);
    }

    // USANDO ENCODE PARA NÃO DUPLICAR DOWNLOAD NA WEB
    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(Uint8List.fromList(fileBytes), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', name: 'Relatorio_Ocorrencias.xlsx');
      await Share.shareXFiles([xfile], text: 'Relatório de Ocorrências');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Planilha Excel baixada com sucesso!'),
            backgroundColor: Colors.green,
          )
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Relatório de Ocorrências', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    decoration: BoxDecoration(color: const Color(0xFF3f5066), borderRadius: BorderRadius.circular(10)),
                    child: Wrap(
                      spacing: 15,
                      runSpacing: 15,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        _buildAutocompleteField('Nº Semáforo:', _filtroSemaforoCtrl, _focusSemaforo, _opcoesSemaforos),
                        _buildAutocompleteField('Endereço:', _filtroEnderecoCtrl, _focusEndereco, _opcoesEnderecos),
                        _buildAutocompleteField('Falha:', _filtroFalhaCtrl, _focusFalha, _opcoesFalhas),
                        
                        _buildDropdown('Empresa:', _filtroEmpresa, ['Todas', ..._empresas], (v) => setState(() => _filtroEmpresa = v == 'Todas' ? '' : v!)),
                        _buildDropdown('Status Ocorrência:', _filtroStatus, ['Todos', 'Aberto', 'Em Deslocamento', 'Em Atendimento', 'Finalizado'], (v) => setState(() => _filtroStatus = v == 'Todos' ? '' : v!)),
                        _buildDropdown('Status Prazo:', _filtroPrazo, ['Todos', 'No Prazo', 'Vencido'], (v) => setState(() => _filtroPrazo = v == 'Todos' ? '' : v!)),
                        
                        _buildDateFilter('De (Abertura):', _dataInicioAbertura, (d) => setState(() => _dataInicioAbertura = d)),
                        _buildDateFilter('Até (Fechamento):', _dataFimFechamento, (d) => setState(() => _dataFimFechamento = d)),

                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54),
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
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').orderBy('data_de_abertura', descending: true).snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                          if (!snapshot.hasData) return const Center(child: Text('Nenhum dado.'));

                          // Aplica Filtros
                          var docs = snapshot.data!.docs.where((doc) {
                            var d = doc.data() as Map<String, dynamic>;

                            if (_filtroSemaforoCtrl.text.isNotEmpty && !(d['semaforo'] ?? '').toString().contains(_filtroSemaforoCtrl.text)) return false;
                            if (_filtroEnderecoCtrl.text.isNotEmpty && !(d['endereco'] ?? '').toString().toUpperCase().contains(_filtroEnderecoCtrl.text.toUpperCase())) return false;
                            if (_filtroFalhaCtrl.text.isNotEmpty && !(d['tipo_da_falha'] ?? '').toString().toUpperCase().contains(_filtroFalhaCtrl.text.toUpperCase())) return false;

                            if (_filtroEmpresa.isNotEmpty && (d['empresa_semaforo'] ?? '').toString().toUpperCase() != _filtroEmpresa) return false;
                            if (_filtroStatus.isNotEmpty && (d['status'] ?? '').toString().toLowerCase() != _filtroStatus.toLowerCase()) return false;

                            if (_filtroPrazo.isNotEmpty) {
                              bool isVencido = _calcularTempoVencido(d)['vencido'];
                              if (_filtroPrazo == 'Vencido' && !isVencido) return false;
                              if (_filtroPrazo == 'No Prazo' && isVencido) return false;
                            }

                            if (_dataInicioAbertura != null) {
                              if (d['data_de_abertura'] == null) return false;
                              DateTime dtAbertura = (d['data_de_abertura'] as Timestamp).toDate();
                              if (dtAbertura.isBefore(_dataInicioAbertura!)) return false;
                            }

                            if (_dataFimFechamento != null) {
                              if (d['data_de_finalizacao'] == null) return false;
                              DateTime dtFim = (d['data_de_finalizacao'] as Timestamp).toDate();
                              if (dtFim.isAfter(_dataFimFechamento!.add(const Duration(days: 1)))) return false;
                            }
                            return true;
                          }).toList();

                          if (docs.isEmpty) return const Center(child: Text('Nenhum registro encontrado com estes filtros.'));

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Total: ${docs.length} registros', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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
                                              DataColumn(label: Expanded(child: Center(child: Text('Sem. - Endereço', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Empresa', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Nº Ocorrência', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Status', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Abertura', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Finalização', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Tempo Vencido', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Falha Relatada', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Falha Encontrada', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                              DataColumn(label: Expanded(child: Center(child: Text('Ações', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))))),
                                            ],
                                            rows: docs.map((doc) {
                                              var d = doc.data() as Map<String, dynamic>;
                                              String st = d['status'] ?? 'Aberto';
                                              String stQuebrado = st.toUpperCase().replaceAll(' ', '\n');
                                              var vencidoInfo = _calcularTempoVencido(d);

                                              return DataRow(
                                                cells: [
                                                  DataCell(
                                                    Center(
                                                      child: SizedBox(
                                                        width: 200,
                                                        child: Text('${d['semaforo'] ?? '---'} - ${d['endereco'] ?? '-'}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(Center(child: Text(d['empresa_semaforo'] ?? '-', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
                                                  DataCell(Center(child: Text(d['numero_da_ocorrencia'] ?? d['id'] ?? '-', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold)))),
                                                  DataCell(
                                                    Center(
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(color: _corStatus(st), borderRadius: BorderRadius.circular(4)),
                                                        child: Text(stQuebrado, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(Center(child: Text(_formatarDataHora(d['data_de_abertura']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
                                                  DataCell(Center(child: Text(_formatarDataHora(d['data_de_finalizacao']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
                                                  DataCell(
                                                    Center(
                                                      child: Text(
                                                        vencidoInfo['texto'],
                                                        textAlign: TextAlign.center,
                                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: vencidoInfo['vencido'] ? Colors.red : Colors.green),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Center(
                                                      child: SizedBox(
                                                        width: 150,
                                                        child: Text(d['tipo_da_falha'] ?? '-', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.redAccent), maxLines: 2, overflow: TextOverflow.ellipsis),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Center(
                                                      child: SizedBox(
                                                        width: 150,
                                                        child: Text(d['falha_aparente_final'] ?? '-', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Center(
                                                      child: SizedBox(
                                                        width: 60, 
                                                        child: IconButton(
                                                          icon: const Icon(Icons.visibility, color: Colors.blueGrey, size: 24), 
                                                          tooltip: 'Ver Detalhes e Exportar', 
                                                          onPressed: () => _abrirDetalhes(d),
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