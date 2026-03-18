import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../widgets/menu_usuario.dart';

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

  @override
  void initState() {
    super.initState();
    _carregarFiltros();
  }

  Future<void> _carregarFiltros() async {
    final resFalhas = await FirebaseFirestore.instance
        .collection('falhas')
        .get();
    final resOcorrencias = await FirebaseFirestore.instance
        .collection('ocorrencias')
        .get();

    Set<String> empSet = {};
    for (var doc in resOcorrencias.docs) {
      String emp = (doc.data()['empresa_responsavel'] ?? '')
          .toString()
          .toUpperCase();
      if (emp.isNotEmpty) empSet.add(emp);
    }

    setState(() {
      _falhas =
          resFalhas.docs
              .map((d) => (d['tipo_da_falha'] ?? '').toString())
              .toList()
            ..sort();
      _empresas = empSet.toList()..sort();
    });
  }

  void _limparFiltros() {
    setState(() {
      _dataInicio = null;
      _dataFim = null;
      _filtroEmpresa = '';
      _filtroFalha = '';
    });
  }

  String _formatarDataStr(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  String _formatarDataTime(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yy HH:mm').format(t.toDate());
  }

  // --- LÓGICA DE AGRUPAMENTO (RANKING) ---
  List<Map<String, dynamic>> _gerarRanking(List<QueryDocumentSnapshot> docs) {
    // 1. Filtrar
    var filtrados = docs.where((doc) {
      var d = doc.data() as Map<String, dynamic>;

      if (_filtroEmpresa.isNotEmpty &&
          d['empresa_responsavel'] != _filtroEmpresa)
        return false;
      if (_filtroFalha.isNotEmpty && d['tipo_da_falha'] != _filtroFalha)
        return false;

      if (_dataInicio != null || _dataFim != null) {
        if (d['data_de_abertura'] == null) return false;
        DateTime dt = (d['data_de_abertura'] as Timestamp).toDate();
        if (_dataInicio != null && dt.isBefore(_dataInicio!)) return false;
        if (_dataFim != null &&
            dt.isAfter(_dataFim!.add(const Duration(days: 1))))
          return false;
      }
      return true;
    }).toList();

    // 2. Agrupar por Semáforo
    Map<String, Map<String, dynamic>> agrupado = {};
    for (var doc in filtrados) {
      var d = doc.data() as Map<String, dynamic>;
      String sem = (d['semaforo'] ?? 'N/A').toString().trim();

      if (!agrupado.containsKey(sem)) {
        agrupado[sem] = {
          'semaforo': sem,
          'endereco': d['endereco'] ?? '',
          'empresa': d['empresa_responsavel'] ?? 'N/D',
          'total': 0,
        };
      }
      agrupado[sem]!['total'] = (agrupado[sem]!['total'] as int) + 1;
    }

    // 3. Ordenar por Total (Decrescente) e pegar Top 10
    var ranking = agrupado.values.toList();
    ranking.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    return ranking.take(10).toList();
  }

  // --- MODAL: HISTÓRICO DO SEMÁFORO ---
  void _abrirHistorico(
    String semaforo,
    List<QueryDocumentSnapshot> todasOcorrencias,
  ) {
    // Filtra todas as ocorrências desse semáforo
    var historico = todasOcorrencias.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      return (d['semaforo'] ?? '').toString() == semaforo;
    }).toList();

    // Ordena da mais antiga para a mais nova
    historico.sort((a, b) {
      Timestamp? tA = (a.data() as Map)['data_de_abertura'];
      Timestamp? tB = (b.data() as Map)['data_de_abertura'];
      if (tA == null || tB == null) return 0;
      return tA.compareTo(tB);
    });

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Histórico: Semáforo $semaforo',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
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
                      return Card(
                        color: Colors.grey.shade100,
                        child: ListTile(
                          title: Text(
                            'Ocorrência Nº ${d['numero_da_ocorrencia'] ?? historico[index].id}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.blue,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Abertura: ${_formatarDataTime(d['data_de_abertura'])}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              Text(
                                'Falha: ${d['tipo_da_falha'] ?? '-'}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              Text(
                                'Encontrada: ${d['falha_aparente_final'] ?? '-'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          trailing: Text(
                            (d['status'] ?? '').toString().toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          onTap: () {
                            // Navigator.pop(context); // Se quiser fechar a lista antes de abrir detalhes
                            _abrirDetalhesCompletos(d);
                          },
                        ),
                      );
                    },
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

  // --- MODAL: DETALHES COMPLETOS (Aproveitado) ---
  void _abrirDetalhesCompletos(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Detalhes: ${data['numero_da_ocorrencia'] ?? data['id'] ?? 'S/N'}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow(
                  'Semáforo / End.',
                  '${data['semaforo']} - ${data['endereco']}',
                ),
                _buildDetailRow('Empresa', data['empresa_responsavel']),
                _buildDetailRow(
                  'Data Abertura',
                  _formatarDataTime(data['data_de_abertura']),
                ),
                _buildDetailRow('Usuário Abert.', data['usuario']),
                _buildDetailRow('Equipe Resp.', data['equipe_responsavel']),
                _buildDetailRow('Placa', data['placa_veiculo']),
                _buildDetailRow(
                  'Data Finalização',
                  _formatarDataTime(data['data_de_finalizacao']),
                ),
                _buildDetailRow(
                  'Status',
                  data['status']?.toString().toUpperCase(),
                ),
                _buildDetailRow('Falha Relatada', data['tipo_da_falha']),
                _buildDetailRow(
                  'Falha Encontrada',
                  data['falha_aparente_final'],
                ),
                _buildDetailRow('Detalhes/Abertura', data['detalhes']),
                _buildDetailRow('Descrição Equipe', data['descricao_encontro']),
                _buildDetailRow('Ação Técnica', data['acao_equipe']),
                _buildDetailRow('Materiais', data['materiais_utilizados']),
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
          style: const TextStyle(color: Colors.black87, fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF2c3e50),
              ),
            ),
            TextSpan(text: (value ?? '---').toString()),
          ],
        ),
      ),
    );
  }

  // --- GERAR PDF DO RANKING GERAL ---
  Future<void> _exportarPdfRanking(List<Map<String, dynamic>> ranking) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'Relatório de Recorrências (Top 10)',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Gerado em: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          ),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: [
              'Posição',
              'Semáforo',
              'Endereço',
              'Empresa',
              'Total Ocorrências',
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
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.center,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Relatorio_Recorrencias.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Relatório de Recorrências',
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
                        _buildDateFilter(
                          'De (Abertura):',
                          _dataInicio,
                          (d) => setState(() => _dataInicio = d),
                        ),
                        _buildDateFilter(
                          'Até (Abertura):',
                          _dataFim,
                          (d) => setState(() => _dataFim = d),
                        ),

                        _buildDropdown(
                          'Empresa:',
                          _filtroEmpresa,
                          ['Todas', ..._empresas],
                          (v) => setState(
                            () => _filtroEmpresa = v == 'Todas' ? '' : v!,
                          ),
                        ),
                        _buildDropdown(
                          'Falha Relatada:',
                          _filtroFalha,
                          ['Todas', ..._falhas],
                          (v) => setState(
                            () => _filtroFalha = v == 'Todas' ? '' : v!,
                          ),
                        ),

                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
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
                        bottom: 24,
                        left: 16,
                        right: 16,
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('ocorrencias')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                            return const Center(
                              child: Text('Nenhum dado encontrado.'),
                            );

                          // Processar Ranking
                          List<Map<String, dynamic>> ranking = _gerarRanking(
                            snapshot.data!.docs,
                          );

                          if (ranking.isEmpty)
                            return const Center(
                              child: Text(
                                'Nenhum resultado para os filtros atuais.',
                              ),
                            );

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(10),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'TOP 10 MAIS RECORRENTES',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                        fontSize: 16,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.picture_as_pdf,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'PDF',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: () =>
                                          _exportarPdfRanking(ranking),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SingleChildScrollView(
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(
                                        const Color(0xFFeceff1),
                                      ),
                                      dataRowMinHeight: 60,
                                      dataRowMaxHeight: 70,
                                      columns: const [
                                        DataColumn(
                                          label: Text(
                                            'Posição',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Semáforo',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Endereço',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Empresa',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Total Ocorrências',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Histórico',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                      rows: ranking.asMap().entries.map((
                                        entry,
                                      ) {
                                        int idx = entry.key;
                                        var item = entry.value;

                                        // Cores do Pódio
                                        Color corPosicao = Colors.black87;
                                        double fontPosicao = 14;
                                        if (idx == 0) {
                                          corPosicao = const Color(0xFFD4AF37);
                                          fontPosicao = 18;
                                        } // Ouro
                                        else if (idx == 1) {
                                          corPosicao = const Color(0xFFC0C0C0);
                                          fontPosicao = 16;
                                        } // Prata
                                        else if (idx == 2) {
                                          corPosicao = const Color(0xFFCD7F32);
                                          fontPosicao = 16;
                                        } // Bronze

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Text(
                                                '${idx + 1}º',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: fontPosicao,
                                                  color: corPosicao,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                item['semaforo'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 250,
                                                child: Text(
                                                  item['endereco'],
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(Text(item['empresa'])),
                                            DataCell(
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color:
                                                        Colors.green.shade200,
                                                  ),
                                                ),
                                                child: Text(
                                                  '${item['total']}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.list_alt,
                                                  color: Colors.blueGrey,
                                                  size: 28,
                                                ),
                                                tooltip:
                                                    'Ver Histórico Completo',
                                                onPressed: () =>
                                                    _abrirHistorico(
                                                      item['semaforo'],
                                                      snapshot.data!.docs,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
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

  // --- COMPONENTES DOS FILTROS ---
  Widget _buildDateFilter(
    String label,
    DateTime? val,
    Function(DateTime) onPicked,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            DateTime? picked = await showDatePicker(
              context: context,
              initialDate: val ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) onPicked(picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              val == null ? 'dd/mm/aaaa' : DateFormat('dd/MM/yyyy').format(val),
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value.isEmpty ? items.first : value,
              items: items
                  .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
