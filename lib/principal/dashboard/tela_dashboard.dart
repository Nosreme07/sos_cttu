import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart'; // PACOTE DE GRÁFICOS

import '../../widgets/menu_usuario.dart';

class TelaDashboard extends StatefulWidget {
  const TelaDashboard({super.key});

  @override
  State<TelaDashboard> createState() => _TelaDashboardState();
}

class _TelaDashboardState extends State<TelaDashboard> {
  DateTime? _dataInicio;
  DateTime? _dataFim;

  // --- MÉTODOS DE FILTRO DE DATA ---
  Future<void> _selecionarDataInicio(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dataInicio ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dataInicio = picked);
  }

  Future<void> _selecionarDataFim(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataFim ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      // Ajusta para o final do dia (23:59:59)
      setState(
        () => _dataFim = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        ),
      );
    }
  }

  void _limparFiltros() {
    setState(() {
      _dataInicio = null;
      _dataFim = null;
    });
  }

  String _formatarDataStr(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  // --- LÓGICA DE STATUS ---
  String _categorizarStatus(String statusRaw) {
    String st = statusRaw.toLowerCase();
    if (st.contains('aberto') ||
        st.contains('pendente') ||
        st.contains('aguardando'))
      return 'Aberto';
    if (st.contains('deslocamento') || st.contains('atendimento'))
      return 'Em Andamento';
    if (st.contains('conclu') || st.contains('finaliz')) return 'Concluído';
    return 'Outros';
  }

  Color _corDoStatus(String categoria) {
    switch (categoria) {
      case 'Aberto':
        return Colors.redAccent;
      case 'Em Andamento':
        return Colors.orange;
      case 'Concluído':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // =========================================================================
  // CONSTRUÇÃO DA INTERFACE
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Relatórios e Dashboard',
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

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('ocorrencias')
                .orderBy('data_de_abertura', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              if (snapshot.hasError)
                return const Center(
                  child: Text(
                    'Erro ao carregar dados.',
                    style: TextStyle(color: Colors.white),
                  ),
                );

              List<QueryDocumentSnapshot> docs = snapshot.data?.docs ?? [];

              // 1. APLICAR FILTRO DE DATA
              if (_dataInicio != null && _dataFim != null) {
                docs = docs.where((doc) {
                  var d = doc.data() as Map<String, dynamic>;
                  if (d['data_de_abertura'] == null) return false;
                  DateTime dtAbertura = (d['data_de_abertura'] as Timestamp)
                      .toDate();
                  return dtAbertura.isAfter(_dataInicio!) &&
                      dtAbertura.isBefore(_dataFim!);
                }).toList();
              }

              // 2. CÁLCULO DOS KPIs
              int total = docs.length;
              int abertos = 0;
              int emAndamento = 0;
              int concluidos = 0;

              Map<String, int> statusCount = {};
              Map<String, int> falhasCount = {};

              for (var doc in docs) {
                var d = doc.data() as Map<String, dynamic>;
                String catStatus = _categorizarStatus(d['status'] ?? '');

                if (catStatus == 'Aberto')
                  abertos++;
                else if (catStatus == 'Em Andamento')
                  emAndamento++;
                else if (catStatus == 'Concluído')
                  concluidos++;

                statusCount[catStatus] = (statusCount[catStatus] ?? 0) + 1;

                String falha = d['tipo_da_falha'] ?? 'Não informada';
                falhasCount[falha] = (falhasCount[falha] ?? 0) + 1;
              }

              // Top 5 Falhas
              var sortedFalhas = falhasCount.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              var top5Falhas = sortedFalhas.take(5).toList();

              return SingleChildScrollView(
                padding: const EdgeInsets.only(
                  top: 100,
                  left: 16,
                  right: 16,
                  bottom: 40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- BARRA DE FILTROS ---
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3f5066),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text(
                                'Filtrar Período:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white54),
                                ),
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                ),
                                label: Text(
                                  _dataInicio == null
                                      ? 'Data Inicial'
                                      : _formatarDataStr(_dataInicio),
                                ),
                                onPressed: () => _selecionarDataInicio(context),
                              ),
                              const Text(
                                'até',
                                style: TextStyle(color: Colors.white),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white54),
                                ),
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                ),
                                label: Text(
                                  _dataFim == null
                                      ? 'Data Final'
                                      : _formatarDataStr(_dataFim),
                                ),
                                onPressed: () => _selecionarDataFim(context),
                              ),
                              if (_dataInicio != null || _dataFim != null)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                  ),
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Limpar',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  onPressed: _limparFiltros,
                                ),
                            ],
                          ),
                        ),

                        // --- CARDS DE KPIs ---
                        LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = constraints.maxWidth > 800
                                ? 4
                                : (constraints.maxWidth > 400 ? 2 : 1);
                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 2.5,
                              children: [
                                _buildKpiCard(
                                  'Total de Ocorrências',
                                  total.toString(),
                                  Colors.blue,
                                ),
                                _buildKpiCard(
                                  'Pendentes (Aberto)',
                                  abertos.toString(),
                                  Colors.redAccent,
                                ),
                                _buildKpiCard(
                                  'Em Atendimento',
                                  emAndamento.toString(),
                                  Colors.orange,
                                ),
                                _buildKpiCard(
                                  'Concluídas',
                                  concluidos.toString(),
                                  Colors.green,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // --- ÁREA DOS GRÁFICOS ---
                        LayoutBuilder(
                          builder: (context, constraints) {
                            bool isDesktop = constraints.maxWidth > 800;
                            List<Widget> charts = [
                              // GRÁFICO DE ROSCA (STATUS)
                              Expanded(
                                flex: isDesktop ? 1 : 0,
                                child: Container(
                                  height: 350,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Distribuição por Status',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2c3e50),
                                        ),
                                      ),
                                      const Divider(),
                                      Expanded(
                                        child: statusCount.isEmpty
                                            ? const Center(
                                                child: Text('Sem dados'),
                                              )
                                            : PieChart(
                                                PieChartData(
                                                  sectionsSpace: 2,
                                                  centerSpaceRadius: 50,
                                                  sections: statusCount.entries
                                                      .map((e) {
                                                        return PieChartSectionData(
                                                          color: _corDoStatus(
                                                            e.key,
                                                          ),
                                                          value: e.value
                                                              .toDouble(),
                                                          title: '${e.value}',
                                                          radius: 60,
                                                          titleStyle:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        );
                                                      })
                                                      .toList(),
                                                ),
                                              ),
                                      ),
                                      // Legenda
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        alignment: WrapAlignment.center,
                                        children: statusCount.keys
                                            .map(
                                              (k) => Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 12,
                                                    height: 12,
                                                    color: _corDoStatus(k),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    k,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (isDesktop)
                                const SizedBox(width: 24)
                              else
                                const SizedBox(height: 24),

                              // GRÁFICO DE BARRAS (TOP 5 FALHAS)
                              Expanded(
                                flex: isDesktop ? 1 : 0,
                                child: Container(
                                  height: 350,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Top 5 Tipos de Falhas',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2c3e50),
                                        ),
                                      ),
                                      const Divider(),
                                      Expanded(
                                        child: top5Falhas.isEmpty
                                            ? const Center(
                                                child: Text('Sem dados'),
                                              )
                                            : BarChart(
                                                BarChartData(
                                                  alignment: BarChartAlignment
                                                      .spaceAround,
                                                  maxY:
                                                      (top5Falhas.isNotEmpty
                                                          ? top5Falhas
                                                                .first
                                                                .value
                                                                .toDouble()
                                                          : 10) *
                                                      1.2,
                                                  barTouchData: BarTouchData(
                                                    enabled: true,
                                                  ),
                                                  titlesData: FlTitlesData(
                                                    show: true,
                                                    rightTitles:
                                                        const AxisTitles(
                                                          sideTitles:
                                                              SideTitles(
                                                                showTitles:
                                                                    false,
                                                              ),
                                                        ),
                                                    topTitles: const AxisTitles(
                                                      sideTitles: SideTitles(
                                                        showTitles: false,
                                                      ),
                                                    ),
                                                    bottomTitles: AxisTitles(
                                                      sideTitles: SideTitles(
                                                        showTitles: true,
                                                        getTitlesWidget:
                                                            (
                                                              double value,
                                                              TitleMeta meta,
                                                            ) {
                                                              if (value
                                                                      .toInt() >=
                                                                  top5Falhas
                                                                      .length)
                                                                return const SizedBox.shrink();
                                                              String title =
                                                                  top5Falhas[value
                                                                          .toInt()]
                                                                      .key;
                                                              if (title.length >
                                                                  10)
                                                                title =
                                                                    '${title.substring(0, 10)}...';
                                                              return Padding(
                                                                padding:
                                                                    const EdgeInsets.only(
                                                                      top: 8.0,
                                                                    ),
                                                                child: Text(
                                                                  title,
                                                                  style: const TextStyle(
                                                                    color: Colors
                                                                        .black87,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize: 9,
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                      ),
                                                    ),
                                                  ),
                                                  gridData: const FlGridData(
                                                    show: true,
                                                    drawVerticalLine: false,
                                                  ),
                                                  borderData: FlBorderData(
                                                    show: false,
                                                  ),
                                                  barGroups: top5Falhas
                                                      .asMap()
                                                      .entries
                                                      .map((entry) {
                                                        return BarChartGroupData(
                                                          x: entry.key,
                                                          barRods: [
                                                            BarChartRodData(
                                                              toY: entry
                                                                  .value
                                                                  .value
                                                                  .toDouble(),
                                                              color:
                                                                  Colors.blue,
                                                              width: 20,
                                                              borderRadius:
                                                                  const BorderRadius.vertical(
                                                                    top:
                                                                        Radius.circular(
                                                                          4,
                                                                        ),
                                                                  ),
                                                            ),
                                                          ],
                                                        );
                                                      })
                                                      .toList(),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ];

                            return isDesktop
                                ? Row(children: charts)
                                : Column(children: charts);
                          },
                        ),
                        const SizedBox(height: 24),

                        // --- TABELA RESUMO (ÚLTIMAS 10 OCORRÊNCIAS) ---
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 6),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Últimas 10 Ocorrências Registradas',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2c3e50),
                                ),
                              ),
                              const Divider(),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    Colors.grey.shade100,
                                  ),
                                  columns: const [
                                    DataColumn(
                                      label: Text(
                                        'ID',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        'Data Abertura',
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
                                        'Tipo de Falha',
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
                                  ],
                                  rows: docs.take(10).map((doc) {
                                    var d = doc.data() as Map<String, dynamic>;
                                    String catStatus = _categorizarStatus(
                                      d['status'] ?? '',
                                    );
                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          Text(
                                            (d['numero_da_ocorrencia'] ??
                                                    d['id'] ??
                                                    doc.id)
                                                .toString()
                                                .substring(0, 8),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            d['data_de_abertura'] != null
                                                ? DateFormat(
                                                    'dd/MM/yy HH:mm',
                                                  ).format(
                                                    (d['data_de_abertura']
                                                            as Timestamp)
                                                        .toDate(),
                                                  )
                                                : '---',
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${d['semaforo'] ?? ''} - ${d['endereco'] ?? ''}',
                                          ),
                                        ),
                                        DataCell(
                                          Text(d['tipo_da_falha'] ?? '---'),
                                        ),
                                        DataCell(
                                          Text(
                                            d['status'] ?? '---',
                                            style: TextStyle(
                                              color: _corDoStatus(catStatus),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // WIDGET AUXILIAR DO KPI
  Widget _buildKpiCard(String title, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(bottom: BorderSide(color: color, width: 5)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2f3b4c),
            ),
          ),
        ],
      ),
    );
  }
}
