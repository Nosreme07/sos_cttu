import 'dart:typed_data';
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

class TelaRelatorioRecorrencias extends StatefulWidget {
  const TelaRelatorioRecorrencias({super.key});

  @override
  State<TelaRelatorioRecorrencias> createState() =>
      _TelaRelatorioRecorrenciasState();
}

class _TelaRelatorioRecorrenciasState extends State<TelaRelatorioRecorrencias> {
  DateTime? _dataInicio;
  DateTime? _dataFim;
  String _filtroEmpresa = '';
  String _filtroFalha = '';

  List<String> _empresas = [];
  List<String> _falhas = [];

  bool _isLoading = true;
  List<QueryDocumentSnapshot> _todasOcorrenciasCache = [];
  List<Map<String, dynamic>> _rankingGerado = [];

  @override
  void initState() {
    super.initState();
    _inicializarDados();
  }

  Future<void> _inicializarDados() async {
    setState(() => _isLoading = true);

    try {
      final resFalhas =
          await FirebaseFirestore.instance.collection('falhas').get();
      final resEmpresas =
          await FirebaseFirestore.instance.collection('empresas').get();
      final resOcorrencias = await FirebaseFirestore.instance
          .collection('Gerenciamento_ocorrencias')
          .get();

      _todasOcorrenciasCache = resOcorrencias.docs;

      Set<String> empSet = {};
      for (var doc in resEmpresas.docs) {
        String emp = (doc.data()['nome'] ?? doc.data()['empresa'] ?? doc.id)
            .toString()
            .toUpperCase();
        if (emp.isNotEmpty) empSet.add(emp);
      }

      List<String> falhasTemp = resFalhas.docs
          .map((d) =>
              (d['tipo_da_falha'] ?? d['falha'] ?? '').toString().toUpperCase())
          .toSet()
          .toList();
      falhasTemp.sort();

      List<String> empresasTemp = empSet.toList();
      empresasTemp.sort();

      if (mounted) {
        setState(() {
          _falhas = falhasTemp;
          _empresas = empresasTemp;
        });

        await _gerarRankingAsync();
      }
    } catch (e) {
      debugPrint("Erro ao inicializar dados: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _gerarRankingAsync() async {
    setState(() => _isLoading = true);

    await Future.delayed(const Duration(milliseconds: 100));

    var filtrados = _todasOcorrenciasCache.where((doc) {
      var d = doc.data() as Map<String, dynamic>;

      if (_filtroEmpresa.isNotEmpty &&
          (d['empresa_semaforo'] ?? d['empresa_responsavel'] ?? '')
                  .toString()
                  .toUpperCase() !=
              _filtroEmpresa) return false;
      if (_filtroFalha.isNotEmpty &&
          (d['tipo_da_falha'] ?? '').toString().toUpperCase() != _filtroFalha)
        return false;

      if (_dataInicio != null || _dataFim != null) {
        if (d['data_de_abertura'] == null) return false;
        DateTime dt = (d['data_de_abertura'] as Timestamp).toDate();
        if (_dataInicio != null && dt.isBefore(_dataInicio!)) return false;
        if (_dataFim != null &&
            dt.isAfter(_dataFim!.add(const Duration(days: 1)))) return false;
      }
      return true;
    }).toList();

    Map<String, Map<String, dynamic>> agrupado = {};
    for (var doc in filtrados) {
      var d = doc.data() as Map<String, dynamic>;
      String sem = (d['semaforo'] ?? 'N/A').toString().trim();

      if (!agrupado.containsKey(sem)) {
        agrupado[sem] = {
          'semaforo': sem,
          'endereco': d['endereco'] ?? '',
          'empresa': d['empresa_semaforo'] ?? d['empresa_responsavel'] ?? 'N/D',
          'total': 0,
        };
      }
      agrupado[sem]!['total'] = (agrupado[sem]!['total'] as int) + 1;
    }

    var ranking = agrupado.values.toList();
    ranking.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

    if (mounted) {
      setState(() {
        _rankingGerado = ranking.take(10).toList();
        _isLoading = false;
      });
    }
  }

  void _limparFiltros() {
    setState(() {
      _dataInicio = null;
      _dataFim = null;
      _filtroEmpresa = '';
      _filtroFalha = '';
    });
    _gerarRankingAsync();
  }

  String _formatarDataHoraCompleta(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(t.toDate());
  }

  Color _corStatus(String status) {
    String st = status.toLowerCase();
    if (st.contains('aberto') || st.contains('pendente'))
      return Colors.redAccent;
    if (st.contains('deslocamento')) return Colors.orange;
    if (st.contains('atendimento')) return Colors.blue;
    if (st.contains('conclu') || st.contains('finaliz')) return Colors.green;
    return Colors.grey;
  }

  void _abrirHistorico(
      String semaforo, List<QueryDocumentSnapshot> todasOcorrencias) {
    var historico = todasOcorrencias.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      return (d['semaforo'] ?? '').toString() == semaforo;
    }).toList();

    historico.sort((a, b) {
      Timestamp? tA = (a.data() as Map)['data_de_abertura'];
      Timestamp? tB = (b.data() as Map)['data_de_abertura'];
      if (tA == null || tB == null) return 0;
      return tB.compareTo(tA);
    });

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Histórico Completo: Semáforo $semaforo',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: historico.isEmpty
                ? const Center(child: Text('Nenhuma informação encontrada.'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: historico.length,
                    itemBuilder: (context, index) {
                      var d = historico[index].data() as Map<String, dynamic>;
                      String st = d['status'] ?? 'Aberto';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade300)),
                        child: ListTile(
                          title: Text(
                            'Ocorrência Nº ${d['numero_da_ocorrencia'] ?? historico[index].id}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.blueGrey),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                  'Abertura: ${_formatarDataHoraCompleta(d['data_de_abertura'])}',
                                  style: const TextStyle(fontSize: 11)),
                              Text('Falha: ${d['tipo_da_falha'] ?? '-'}',
                                  style: const TextStyle(fontSize: 11)),
                              Text(
                                  'Encontrada: ${d['falha_aparente_final'] ?? '-'}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87)),
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: _corStatus(st),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(st.toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                          onTap: () {
                            _abrirDetalhesCompletos(d);
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              label: const Text('Baixar PDF deste Histórico',
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onPressed: () =>
                  _exportarPdfHistoricoSemaforo(semaforo, historico),
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

  void _abrirDetalhesCompletos(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Detalhes: ${data['numero_da_ocorrencia'] ?? data['id'] ?? 'S/N'}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Semáforo / End.',
                    '${data['semaforo']} - ${data['endereco']}'),
                _buildDetailRow(
                    'Empresa', data['empresa_semaforo'] ?? data['empresa_responsavel']),
                _buildDetailRow('Origem', data['origem_da_ocorrencia']),
                const Divider(),
                _buildDetailRow('Data Abertura',
                    _formatarDataHoraCompleta(data['data_de_abertura'])),
                _buildDetailRow('Data Atendimento',
                    _formatarDataHoraCompleta(data['data_atendimento'])),
                _buildDetailRow('Data Finalização',
                    _formatarDataHoraCompleta(data['data_de_finalizacao'])),
                const Divider(),
                _buildDetailRow('Usuário Abertura',
                    data['usuario_abertura'] ?? data['usuario']),
                _buildDetailRow('Equipe Resp.',
                    data['equipe_atrelada'] ?? data['equipe_responsavel']),
                _buildDetailRow('Placa', data['placa_veiculo']),
                const Divider(),
                _buildDetailRow(
                    'Status', data['status']?.toString().toUpperCase()),
                _buildDetailRow('Falha Relatada', data['tipo_da_falha']),
                _buildDetailRow('Detalhes/Abertura', data['detalhes']),
                _buildDetailRow('Falha Encontrada', data['falha_aparente_final']),
                _buildDetailRow(
                    'Descrição Equipe', data['descricao_encontro']),
                _buildDetailRow('Ação Técnica', data['acao_equipe']),
              ],
            ),
          ),
          actions: [
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
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF2c3e50)),
            ),
            TextSpan(text: (value ?? '---').toString()),
          ],
        ),
      ),
    );
  }

  Future<void> _exportarPdfRanking(List<Map<String, dynamic>> ranking) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
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
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Página ${context.pageNumber} de ${context.pagesCount}',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          );
        },
        build: (context) => [
          pw.Text('Relatório de Recorrências (Top 10)',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: [
              'Posição',
              'Semáforo',
              'Endereço',
              'Empresa',
              'Total Ocorrências'
            ],
            data: ranking.asMap().entries.map((entry) {
              int pos = entry.key + 1;
              var d = entry.value;
              return [
                '${pos}º',
                d['semaforo'],
                d['endereco'],
                d['empresa'],
                d['total'].toString(),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.center,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Relatorio_Recorrencias.pdf');
  }

  Future<void> _exportarPdfHistoricoSemaforo(
      String semaforo, List<QueryDocumentSnapshot> historicoDocs) async {
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
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Página ${context.pageNumber} de ${context.pagesCount}',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          );
        },
        build: (context) => [
          pw.Text('Histórico de Ocorrências - Semáforo $semaforo',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Text('Total de Ocorrências: ${historicoDocs.length}'),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: [
              'Nº Ocorrência',
              'Abertura',
              'Finalização',
              'Status',
              'Equipe',
              'Falha Relatada',
              'Falha Encontrada'
            ],
            data: historicoDocs.map((doc) {
              var d = doc.data() as Map<String, dynamic>;
              return [
                (d['numero_da_ocorrencia'] ?? doc.id).toString(),
                _formatarDataHoraCompleta(d['data_de_abertura']),
                _formatarDataHoraCompleta(d['data_de_finalizacao']),
                (d['status'] ?? '-').toString().toUpperCase(),
                (d['equipe_atrelada'] ?? d['equipe_responsavel'] ?? '-')
                    .toString(),
                (d['tipo_da_falha'] ?? '-').toString(),
                (d['falha_aparente_final'] ?? '-').toString(),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.center,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Historico_Semaforo_$semaforo.pdf');
  }

  void _baixarExcel(List<Map<String, dynamic>> ranking) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Top 10'];
    excel.setDefaultSheet('Top 10');

    sheetObject
        .appendRow([TextCellValue("Relatório de Recorrências - Top 10")]);
    sheetObject.appendRow([TextCellValue("Filtros Aplicados:")]);
    sheetObject.appendRow([
      TextCellValue("Empresa:"),
      TextCellValue(_filtroEmpresa.isEmpty ? 'Todas' : _filtroEmpresa)
    ]);
    sheetObject.appendRow([
      TextCellValue("Falha:"),
      TextCellValue(_filtroFalha.isEmpty ? 'Todas' : _filtroFalha)
    ]);

    String dtIni = _dataInicio != null
        ? DateFormat('dd/MM/yyyy').format(_dataInicio!)
        : '-';
    String dtFim =
        _dataFim != null ? DateFormat('dd/MM/yyyy').format(_dataFim!) : '-';
    sheetObject.appendRow([
      TextCellValue("Período:"),
      TextCellValue("$dtIni até $dtFim")
    ]);

    sheetObject.appendRow([TextCellValue("")]);

    sheetObject.appendRow([
      TextCellValue("Posição"),
      TextCellValue("Semáforo"),
      TextCellValue("Endereço"),
      TextCellValue("Empresa"),
      TextCellValue("Total Ocorrências")
    ]);

    int pos = 1;
    for (var d in ranking) {
      sheetObject.appendRow([
        TextCellValue("${pos}º"),
        TextCellValue(d['semaforo'].toString()),
        TextCellValue(d['endereco'].toString()),
        TextCellValue(d['empresa'].toString()),
        TextCellValue(d['total'].toString()),
      ]);
      pos++;
    }

    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(
          Uint8List.fromList(fileBytes),
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: 'Relatorio_Recorrencias.xlsx');
      await Share.shareXFiles([xfile], text: 'Relatório de Recorrências Top 10');

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Planilha baixada com sucesso!'),
            backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Relatório de Recorrências',
          style:
              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                        _buildDropdown(
                            'Empresa:',
                            _filtroEmpresa,
                            ['Todas', ..._empresas], (v) {
                          setState(
                              () => _filtroEmpresa = v == 'Todas' ? '' : v!);
                          _gerarRankingAsync();
                        }),
                        _buildDropdown(
                            'Falha Relatada:',
                            _filtroFalha,
                            ['Todas', ..._falhas], (v) {
                          setState(
                              () => _filtroFalha = v == 'Todas' ? '' : v!);
                          _gerarRankingAsync();
                        }),
                        _buildDateFilter('De (Abertura):', _dataInicio, (d) {
                          setState(() => _dataInicio = d);
                          _gerarRankingAsync();
                        }),
                        _buildDateFilter('Até (Abertura):', _dataFim, (d) {
                          setState(() => _dataFim = d);
                          _gerarRankingAsync();
                        }),

                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 16),
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
                      margin: const EdgeInsets.only(
                          bottom: 24, left: 16, right: 16),
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _rankingGerado.isEmpty
                              ? const Center(
                                  child: Text(
                                      'Nenhum resultado para os filtros atuais.'))
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(10)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'TOP 10 MAIS RECORRENTES',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blueGrey,
                                                fontSize: 16),
                                          ),
                                          Row(
                                            children: [
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.green.shade600,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 12,
                                                        vertical: 8)),
                                                icon: const Icon(Icons.download,
                                                    color: Colors.white,
                                                    size: 16),
                                                label: const Text(
                                                    'Baixar Planilha (XLSX)',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                onPressed: () =>
                                                    _baixarExcel(_rankingGerado),
                                              ),
                                              const SizedBox(width: 10),
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.redAccent,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 12,
                                                        vertical: 8)),
                                                icon: const Icon(
                                                    Icons.picture_as_pdf,
                                                    color: Colors.white,
                                                    size: 16),
                                                label: const Text(
                                                    'Baixar PDF Global',
                                                    style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                onPressed: () =>
                                                    _exportarPdfRanking(
                                                        _rankingGerado),
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
                                                constraints: BoxConstraints(
                                                    minWidth:
                                                        constraints.maxWidth),
                                                child: DataTable(
                                                  headingRowColor:
                                                      WidgetStateProperty.all(
                                                          const Color(
                                                              0xFFeceff1)),
                                                  dataRowMinHeight: 60,
                                                  dataRowMaxHeight: 70,
                                                  columns: const [
                                                    DataColumn(
                                                        label: Expanded(
                                                            child: Center(
                                                                child: Text(
                                                                    'Posição',
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.bold))))),
                                                    DataColumn(
                                                        label: Expanded(
                                                            child: Center(
                                                                child: Text(
                                                                    'Semáforo',
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.bold))))),
                                                    DataColumn(
                                                        label: Expanded(
                                                            child: Center(
                                                                child: Text(
                                                                    'Endereço',
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.bold))))),
                                                    DataColumn(
                                                        label: Expanded(
                                                            child: Center(
                                                                child: Text(
                                                                    'Empresa',
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.bold))))),
                                                    DataColumn(
                                                        label: Expanded(
                                                            child: Center(
                                                                child: Text(
                                                                    'Total Ocorrências',
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.bold))))),
                                                    DataColumn(
                                                        label: Expanded(
                                                            child: Center(
                                                                child: Text(
                                                                    'Histórico',
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    style: TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.bold))))),
                                                  ],
                                                  rows: List.generate(
                                                      _rankingGerado.length,
                                                      (idx) {
                                                    var item =
                                                        _rankingGerado[idx];

                                                    Color corPosicao =
                                                        Colors.black87;
                                                    double fontPosicao = 14;
                                                    if (idx == 0) {
                                                      corPosicao = const Color(
                                                          0xFFD4AF37); // Ouro
                                                      fontPosicao = 18;
                                                    } else if (idx == 1) {
                                                      corPosicao = const Color(
                                                          0xFFC0C0C0); // Prata
                                                      fontPosicao = 16;
                                                    } else if (idx == 2) {
                                                      corPosicao = const Color(
                                                          0xFFCD7F32); // Bronze
                                                      fontPosicao = 16;
                                                    }

                                                    return DataRow(
                                                      cells: [
                                                        DataCell(Center(
                                                            child: Text(
                                                                '${idx + 1}º',
                                                                style: TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        fontPosicao,
                                                                    color:
                                                                        corPosicao)))),
                                                        DataCell(Center(
                                                            child: Text(
                                                                item['semaforo']
                                                                    .toString(),
                                                                style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: Colors
                                                                        .blueGrey)))),
                                                        DataCell(
                                                          Center(
                                                            child: SizedBox(
                                                              width: 300,
                                                              child: Text(
                                                                  item['endereco']
                                                                      .toString(),
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center,
                                                                  maxLines: 2,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis),
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(Center(
                                                            child: Text(
                                                                item['empresa']
                                                                    .toString(),
                                                                textAlign:
                                                                    TextAlign
                                                                        .center))),
                                                        DataCell(
                                                          Center(
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          6),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .red
                                                                    .shade50,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4),
                                                                border: Border.all(
                                                                    color: Colors
                                                                        .red
                                                                        .shade200),
                                                              ),
                                                              child: Text(
                                                                  '${item['total']}',
                                                                  style: TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontSize:
                                                                          16,
                                                                      color: Colors
                                                                          .red
                                                                          .shade800)),
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          Center(
                                                            child: IconButton(
                                                              icon: const Icon(
                                                                  Icons
                                                                      .list_alt,
                                                                  color: Colors
                                                                      .blueGrey,
                                                                  size: 28),
                                                              tooltip:
                                                                  'Ver Histórico Completo',
                                                              onPressed: () =>
                                                                  _abrirHistorico(
                                                                      item['semaforo']
                                                                          .toString(),
                                                                      _todasOcorrenciasCache),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  }),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
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

  // CORREÇÃO: void Function(DateTime) no lugar de Function(DateTime)
  Widget _buildDateFilter(
      String label, DateTime? val, void Function(DateTime) onPicked) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          InkWell(
            onTap: () async {
              DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: val ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now());
              if (picked != null) onPicked(picked);
            },
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Text(
                  val == null
                      ? 'dd/mm/aaaa'
                      : DateFormat('dd/MM/yyyy').format(val),
                  style: const TextStyle(color: Colors.black87)),
            ),
          ),
        ],
      ),
    );
  }

  // CORREÇÃO: void Function(String?) no lugar de Function(String?)
  Widget _buildDropdown(String label, String value, List<String> items,
      void Function(String?) onChanged) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(4)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value.isEmpty ? items.first : value,
                items: items
                    .map((i) => DropdownMenuItem(
                        value: i,
                        child: Text(i, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}