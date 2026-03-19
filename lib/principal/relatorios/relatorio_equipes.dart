import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../widgets/menu_usuario.dart';

class TelaRelatorioEquipes extends StatefulWidget {
  const TelaRelatorioEquipes({super.key});

  @override
  State<TelaRelatorioEquipes> createState() => _TelaRelatorioEquipesState();
}

class _TelaRelatorioEquipesState extends State<TelaRelatorioEquipes> {
  DateTime? _dataInicio;
  DateTime? _dataFim;
  String _filtroEmpresa = '';
  String _filtroTipo = '';
  final TextEditingController _filtroPlaca = TextEditingController();
  final TextEditingController _filtroIntegrante = TextEditingController();
  final TextEditingController _filtroSemaforo = TextEditingController();

  List<String> _empresas = [];
  List<String> _tiposVeiculo = [];
  List<QueryDocumentSnapshot> _todasOcorrencias = [];

  @override
  void initState() {
    super.initState();
    _carregarAuxiliares();
  }

  @override
  void dispose() {
    _filtroPlaca.dispose();
    _filtroIntegrante.dispose();
    _filtroSemaforo.dispose();
    super.dispose();
  }

  Future<void> _carregarAuxiliares() async {
    // Carrega as ocorrências para cruzar com as equipes
    final resOcorrencias = await FirebaseFirestore.instance
        .collection('ocorrencias')
        .get();
    _todasOcorrencias = resOcorrencias.docs;

    // Busca Empresas e Tipos únicos das próprias equipes e veículos
    final resEquipes = await FirebaseFirestore.instance
        .collection('equipes')
        .get();
    final resVeiculos = await FirebaseFirestore.instance
        .collection('veiculos')
        .get();

    Set<String> empSet = {};
    Set<String> tipoSet = {};

    for (var doc in resEquipes.docs) {
      String emp = (doc.data()['empresa'] ?? '').toString().toUpperCase();
      if (emp.isNotEmpty) empSet.add(emp);
    }

    for (var doc in resVeiculos.docs) {
      String tipo = (doc.data()['tipo'] ?? doc.data()['tipo_veiculo'] ?? '')
          .toString()
          .toUpperCase();
      if (tipo.isNotEmpty) tipoSet.add(tipo);
    }

    setState(() {
      _empresas = empSet.toList()..sort();
      _tiposVeiculo = tipoSet.toList()..sort();
    });
  }

  void _limparFiltros() {
    setState(() {
      _dataInicio = null;
      _dataFim = null;
      _filtroEmpresa = '';
      _filtroTipo = '';
      _filtroPlaca.clear();
      _filtroIntegrante.clear();
      _filtroSemaforo.clear();
    });
  }

  String _formatarData(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yy HH:mm').format(t.toDate());
  }

  // --- MOTOR DE CRUZAMENTO: QUAIS OCORRÊNCIAS ESTA EQUIPE ATENDEU? ---
  List<Map<String, dynamic>> _obterOcorrenciasDaEquipe(
    Map<String, dynamic> eqData,
  ) {
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
      String equipeResp =
          (oc['equipe_responsavel'] ?? oc['equipe_atrelada'] ?? '')
              .toString()
              .toUpperCase();
      String placaResp = (oc['placa_veiculo'] ?? '').toString().toUpperCase();

      bool bateuNome = nomeLider.isNotEmpty && equipeResp.contains(nomeLider);
      bool bateuPlaca =
          placa.isNotEmpty &&
          (placaResp == placa || equipeResp.contains(placa));

      if (bateuNome || bateuPlaca) {
        // Verifica se a ocorrência foi atendida durante o turno da equipe
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

  // --- MODAL DE DETALHES ---
  void _abrirDetalhes(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> ocorrencias,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Detalhes do Despacho (Equipe)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDetailRow(
                    'Veículo',
                    '${data['placa'] ?? '-'} (${data['tipo'] ?? data['tipo_veiculo'] ?? '-'})',
                  ),
                  _buildDetailRow('Empresa', data['empresa']),
                  _buildDetailRow(
                    'Data Início',
                    _formatarData(data['data_inicio']),
                  ),
                  _buildDetailRow('Data Fim', _formatarData(data['data_fim'])),
                  _buildDetailRow(
                    'Status',
                    data['status']?.toString().toUpperCase(),
                  ),
                  _buildDetailRow(
                    'KM',
                    'Ini: ${data['km_inicial'] ?? 0} | Fim: ${data['km_final'] ?? '-'} | Rodado: ${data['km_rodado'] ?? 0}',
                  ),
                  const Divider(),
                  const Text(
                    '👤 INTEGRANTES:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Text(
                    data['integrantes_str'] ?? '-',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '📝 OBSERVAÇÕES:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Text(
                    data['observacoes'] ?? 'Nenhuma observação',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),

                  const Divider(height: 30, thickness: 2, color: Colors.blue),
                  const Text(
                    '🚦 OCORRÊNCIAS ATENDIDAS NESTE TURNO',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (ocorrencias.isEmpty)
                    const Text(
                      'Nenhuma ocorrência vinculada.',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ...ocorrencias.map(
                    (oc) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        border: Border(
                          left: BorderSide(
                            color: _corStatus(oc['status'] ?? ''),
                            width: 4,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Semáforo: ${oc['semaforo']} - ${oc['tipo_da_falha']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            oc['endereco'] ?? '',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black54,
                            ),
                          ),
                          Text(
                            'Status: ${(oc['status'] ?? '').toString().toUpperCase()}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _corStatus(oc['status'] ?? ''),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
      padding: const EdgeInsets.only(bottom: 6.0),
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

  Color _corStatus(String status) {
    String st = status.toLowerCase();
    if (st == 'ativo') return Colors.green;
    if (st == 'finalizado') return Colors.blueGrey;
    if (st.contains('aberto')) return Colors.redAccent;
    if (st.contains('atendimento')) return Colors.blue;
    if (st.contains('conclu')) return Colors.green;
    return Colors.grey;
  }

  // --- EXPORTAÇÃO PDF ---
  Future<void> _exportarPdfGlobal(List<QueryDocumentSnapshot> docs) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text(
            'Relatório Global de Equipes em Campo',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Gerado em: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          ),
          pw.Text('Total de Registros filtrados: ${docs.length}'),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: [
              'Início',
              'Fim',
              'Status',
              'Placa',
              'Empresa',
              'Líder',
              'KM Rodado',
            ],
            data: docs.map((doc) {
              var d = doc.data() as Map<String, dynamic>;
              String lider = (d['integrantes_str'] ?? '')
                  .toString()
                  .split(',')
                  .first
                  .trim();
              return [
                _formatarData(d['data_inicio']),
                _formatarData(d['data_fim']),
                (d['status'] ?? '-').toString().toUpperCase(),
                d['placa'] ?? '-',
                d['empresa'] ?? 'Externa',
                lider,
                '${d['km_rodado'] ?? 0} km',
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
      name: 'Relatorio_Equipes.pdf',
    );
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
                        _buildDateFilter(
                          'De (Início):',
                          _dataInicio,
                          (d) => setState(() => _dataInicio = d),
                        ),
                        _buildDateFilter(
                          'Até (Início):',
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
                          'Tipo Veículo:',
                          _filtroTipo,
                          ['Todos', ..._tiposVeiculo],
                          (v) => setState(
                            () => _filtroTipo = v == 'Todos' ? '' : v!,
                          ),
                        ),

                        _buildTextField('Placa:', _filtroPlaca),
                        _buildTextField('Integrante:', _filtroIntegrante),
                        _buildTextField('Semáforo Atendido:', _filtroSemaforo),

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
                            .collection('equipes')
                            .orderBy('data_inicio', descending: true)
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
                                d['empresa'] != _filtroEmpresa)
                              return false;
                            if (_filtroTipo.isNotEmpty &&
                                (d['tipo'] ?? d['tipo_veiculo'] ?? '') !=
                                    _filtroTipo)
                              return false;

                            if (_filtroPlaca.text.isNotEmpty &&
                                !(d['placa'] ?? '')
                                    .toString()
                                    .toLowerCase()
                                    .contains(_filtroPlaca.text.toLowerCase()))
                              return false;
                            if (_filtroIntegrante.text.isNotEmpty &&
                                !(d['integrantes_str'] ?? '')
                                    .toString()
                                    .toLowerCase()
                                    .contains(
                                      _filtroIntegrante.text.toLowerCase(),
                                    ))
                              return false;

                            if (_dataInicio != null || _dataFim != null) {
                              if (d['data_inicio'] == null) return false;
                              DateTime dt = (d['data_inicio'] as Timestamp)
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

                          // Filtro complexo: Se filtrou por "Semáforo Atendido"
                          if (_filtroSemaforo.text.isNotEmpty) {
                            docs = docs.where((doc) {
                              var d = doc.data() as Map<String, dynamic>;
                              var ocorrencias = _obterOcorrenciasDaEquipe(d);
                              // Verifica se alguma das ocorrências atendidas tem o número do semáforo buscado
                              return ocorrencias.any(
                                (oc) => (oc['semaforo'] ?? '')
                                    .toString()
                                    .contains(_filtroSemaforo.text),
                              );
                            }).toList();
                          }

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
                                            'Início',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Fim',
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
                                            'Placa',
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
                                            'Integrantes',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'Atendimentos',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Text(
                                            'KM',
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
                                        String st = d['status'] ?? 'ativo';

                                        var ocorrenciasDestaEquipe =
                                            _obterOcorrenciasDaEquipe(d);
                                        List<String> sems =
                                            ocorrenciasDestaEquipe
                                                .map(
                                                  (o) =>
                                                      o['semaforo'].toString(),
                                                )
                                                .toSet()
                                                .toList(); // Remove duplicados

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Text(
                                                _formatarData(d['data_inicio']),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                _formatarData(d['data_fim']),
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
                                              Text(
                                                d['placa'] ?? '---',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(d['empresa'] ?? 'Externa'),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 150,
                                                child: Text(
                                                  d['integrantes_str'] ?? '',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                sems.isEmpty
                                                    ? '-'
                                                    : sems.join(', '),
                                                style: const TextStyle(
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text('${d['km_rodado'] ?? 0} km'),
                                            ),
                                            DataCell(
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.visibility,
                                                  color: Colors.blueGrey,
                                                ),
                                                tooltip:
                                                    'Ver Detalhes do Turno',
                                                onPressed: () => _abrirDetalhes(
                                                  d,
                                                  ocorrenciasDestaEquipe,
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

  // Helpers de Interface
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
    var column = Column(
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
    return column;
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          width: 150,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            onChanged: (v) => setState(() {}), // Atualiza on-the-fly
          ),
        ),
      ],
    );
  }
}
