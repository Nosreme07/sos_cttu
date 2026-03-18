import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../widgets/menu_usuario.dart';

class TelaRelatorioOcorrencias extends StatefulWidget {
  const TelaRelatorioOcorrencias({super.key});

  @override
  State<TelaRelatorioOcorrencias> createState() =>
      _TelaRelatorioOcorrenciasState();
}

class _TelaRelatorioOcorrenciasState extends State<TelaRelatorioOcorrencias> {
  // Filtros
  DateTime? _dataInicio;
  DateTime? _dataFim;
  String _filtroEmpresa = '';
  String _filtroFalha = '';
  String _filtroStatus = '';
  String _filtroPrazo = '';

  List<String> _empresas = [];
  List<String> _falhas = [];

  @override
  void initState() {
    super.initState();
    _carregarFiltros();
  }

  Future<void> _carregarFiltros() async {
    // Busca as listas únicas para preencher os Dropdowns
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
      _filtroStatus = '';
      _filtroPrazo = '';
    });
  }

  String _formatarData(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yy HH:mm').format(t.toDate());
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

  // --- MODAL DE DETALHES ---
  void _abrirDetalhes(Map<String, dynamic> data) {
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
                  _formatarData(data['data_de_abertura']),
                ),
                _buildDetailRow('Usuário Abert.', data['usuario']),
                _buildDetailRow('Equipe Resp.', data['equipe_responsavel']),
                _buildDetailRow('Placa', data['placa_veiculo']),
                _buildDetailRow(
                  'Data Finalização',
                  _formatarData(data['data_de_finalizacao']),
                ),
                _buildDetailRow('Falha Relatada', data['tipo_da_falha']),
                _buildDetailRow(
                  'Falha Encontrada',
                  data['falha_aparente_final'],
                ),
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
          style: const TextStyle(color: Colors.black87, fontSize: 13),
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

  // --- EXPORTAÇÃO PDF ---
  Future<void> _exportarPdfGlobal(List<QueryDocumentSnapshot> docs) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text(
            'Relatório Global de Ocorrências',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Gerado em: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          ),
          pw.Text('Total de Registros filtrados: ${docs.length}'),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: [
              'Nº',
              'Semáforo',
              'Falha',
              'Empresa',
              'Status',
              'Abertura',
              'Finalização',
            ],
            data: docs.map((doc) {
              var d = doc.data() as Map<String, dynamic>;
              return [
                d['numero_da_ocorrencia'] ?? d['id'] ?? '-',
                d['semaforo'] ?? '-',
                d['tipo_da_falha'] ?? '-',
                d['empresa_responsavel'] ?? '-',
                (d['status'] ?? '-').toString().toUpperCase(),
                _formatarData(d['data_de_abertura']),
                _formatarData(d['data_de_finalizacao']),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Relatorio_Ocorrencias.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Relatório de Ocorrências',
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
                          'Falha:',
                          _filtroFalha,
                          ['Todas', ..._falhas],
                          (v) => setState(
                            () => _filtroFalha = v == 'Todas' ? '' : v!,
                          ),
                        ),
                        _buildDropdown(
                          'Status:',
                          _filtroStatus,
                          [
                            'Todos',
                            'Aberto',
                            'Em Deslocamento',
                            'Em Atendimento',
                            'Concluído',
                          ],
                          (v) => setState(
                            () => _filtroStatus = v == 'Todos' ? '' : v!,
                          ),
                        ),

                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                          ),
                          icon: const Icon(
                            Icons.picture_as_pdf,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Exportar PDF',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            // A exportação será chamada pelo StreamBuilder via chave global se necessário,
                            // mas por simplicidade, o usuário pode filtrar na tela e exportamos os dados visíveis.
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Aperte PDF após os dados carregarem na tabela!',
                                ),
                              ),
                            );
                          },
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
                            .orderBy('data_de_abertura', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          if (!snapshot.hasData)
                            return const Center(child: Text('Nenhum dado.'));

                          // Aplica Filtros
                          var docs = snapshot.data!.docs.where((doc) {
                            var d = doc.data() as Map<String, dynamic>;

                            if (_filtroEmpresa.isNotEmpty &&
                                d['empresa_responsavel'] != _filtroEmpresa)
                              return false;
                            if (_filtroFalha.isNotEmpty &&
                                d['tipo_da_falha'] != _filtroFalha)
                              return false;
                            if (_filtroStatus.isNotEmpty &&
                                (d['status'] ?? '').toString().toLowerCase() !=
                                    _filtroStatus.toLowerCase())
                              return false;

                            if (_dataInicio != null || _dataFim != null) {
                              if (d['data_de_abertura'] == null) return false;
                              DateTime dt = (d['data_de_abertura'] as Timestamp)
                                  .toDate();
                              if (_dataInicio != null &&
                                  dt.isBefore(_dataInicio!))
                                return false;
                              if (_dataFim != null &&
                                  dt.isAfter(
                                    _dataFim!.add(const Duration(days: 1)),
                                  ))
                                return false;
                            }
                            return true;
                          }).toList();

                          if (docs.isEmpty)
                            return const Center(
                              child: Text(
                                'Nenhum registro encontrado com estes filtros.',
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
                                    Text(
                                      'Total: ${docs.length} registros',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
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
                                        'Baixar PDF destes Resultados',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                      onPressed: () => _exportarPdfGlobal(docs),
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
                                      columns: const [
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
                                            'Abertura',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Finalização',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Status',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Ações',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                      rows: docs.map((doc) {
                                        var d =
                                            doc.data() as Map<String, dynamic>;
                                        String st = d['status'] ?? 'Aberto';

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Text(
                                                d['semaforo'] ?? '---',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 200,
                                                child: Text(
                                                  d['endereco'] ?? '-',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                d['empresa_responsavel'] ?? '-',
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                _formatarData(
                                                  d['data_de_abertura'],
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                _formatarData(
                                                  d['data_de_finalizacao'],
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _corStatus(st),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  st.toUpperCase(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.visibility,
                                                  color: Colors.blueGrey,
                                                ),
                                                onPressed: () =>
                                                    _abrirDetalhes(d),
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

  // Helper para construir os filtros de data e dropdown rapidamente
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
