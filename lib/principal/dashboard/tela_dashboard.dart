import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

// Importações para PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../widgets/menu_usuario.dart';

class TelaDashboard extends StatefulWidget {
  const TelaDashboard({super.key});

  @override
  State<TelaDashboard> createState() => _TelaDashboardState();
}

class _TelaDashboardState extends State<TelaDashboard> {
  DateTime? _dataInicio;
  DateTime? _dataFim;

  int _touchedIndexPie = -1;

  // --- NOVOS FILTROS INTELIGENTES ---
  String _filtroTempoAtivo = '24h';
  bool _filtroDiaChuva = false;

  // --- LISTA DE FALHAS CRITICAS ---
  static const List<String> _falhasCriticas = [
    'SEMAFORO APAGADO',
    'APAGADO POR FALTA DE ENERGIA',
    'ESTRUTURA COM FUGA DE TENSAO',
    'SEMAFORO COM FASE APAGADA',
    'SEMAFORO OPERANDO COM GERADOR',
    'SEMAFORO OSCILANDO NAS CORES (ALTERNANDO RAPIDAMENTE)',
    'SEMAFORO PARADO',
    'SEMAFORO PISCANDO',
    'SEMAFORO REINICIANDO',
    'SEMAFORO SERIADO (2 OU MAIS CORES ACESAS AO MESMO TEMPO)',
  ];

  // --- FUNÇÃO UNIVERSAL DE ESCOLHER DATA E HORA (COM FORMATO 24H) ---
  Future<DateTime?> _escolherDataHora(DateTime? dataInicial) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: dataInicial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2c3e50)),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate == null) return null;
    if (!mounted) return null;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(dataInicial ?? DateTime.now()),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<void> _selecionarDataInicio(BuildContext context) async {
    DateTime? dt = await _escolherDataHora(_dataInicio);
    if (dt != null) {
      setState(() {
        _dataInicio = dt;
        _filtroTempoAtivo = 'personalizado';
      });
    }
  }

  Future<void> _selecionarDataFim(BuildContext context) async {
    DateTime? dt = await _escolherDataHora(_dataFim);
    if (dt != null) {
      setState(() {
        _dataFim = dt;
        _filtroTempoAtivo = 'personalizado';
      });
    }
  }

  // --- MODAL OCORRENCIAS CRITICAS EM ABERTO ---
  void _abrirModalCriticasEmAberto() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ocorrências Críticas em Aberto',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade800,
                              ),
                            ),
                            const Text(
                              'Semáforos com falhas críticas: Aberto • Em Deslocamento • Em Atendimento',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Conteúdo com StreamBuilder
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('Gerenciamento_ocorrencias')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF2c3e50),
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Erro ao carregar dados.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }

                        List<QueryDocumentSnapshot> todos =
                            snapshot.data?.docs ?? [];

                        // Filtrar: status pendente + falha crítica
                        List<Map<String, dynamic>> criticas = [];
                        for (var doc in todos) {
                          var d = doc.data() as Map<String, dynamic>;

                          String statusRaw =
                              (d['status'] ?? '').toString().toLowerCase();
                          bool statusPendente =
                              statusRaw.contains('aberto') ||
                                  statusRaw.contains('deslocamento') ||
                                  statusRaw.contains('atendimento');
                          if (!statusPendente) continue;

                          String falha = (d['tipo_da_falha'] ?? '')
                              .toString()
                              .toUpperCase()
                              .trim();
                          String falhaNorm = _removerAcentos(falha);
                          bool ehCritica = _falhasCriticas.any(
                            (f) => _removerAcentos(f) == falhaNorm,
                          );
                          if (!ehCritica) continue;

                          criticas.add({...d, '__doc_id': doc.id});
                        }

                        // Ordenar: Aberto > Deslocamento > Atendimento, depois por data recente
                        criticas.sort((a, b) {
                          int wA = _getStatusWeight(a['status'] ?? '');
                          int wB = _getStatusWeight(b['status'] ?? '');
                          if (wA != wB) return wA.compareTo(wB);
                          DateTime dtA = a['data_de_abertura'] != null
                              ? (a['data_de_abertura'] as Timestamp).toDate()
                              : DateTime.fromMillisecondsSinceEpoch(0);
                          DateTime dtB = b['data_de_abertura'] != null
                              ? (b['data_de_abertura'] as Timestamp).toDate()
                              : DateTime.fromMillisecondsSinceEpoch(0);
                          return dtB.compareTo(dtA);
                        });

                        // Agrupar por tipo de falha
                        Map<String, List<Map<String, dynamic>>> agrupados = {};
                        for (var oc in criticas) {
                          String falha =
                              oc['tipo_da_falha'] ?? 'Não informada';
                          agrupados.putIfAbsent(falha, () => []).add(oc);
                        }

                        if (criticas.isEmpty) {
                          return Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 56,
                                        color: Colors.green.shade300,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Nenhuma ocorrência crítica em aberto!',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Todos os semáforos com falhas críticas\nestão finalizados.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2c3e50),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text(
                                    'Fechar',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Contador total
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.red.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.traffic,
                                    size: 16,
                                    color: Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${criticas.length} semáforo(s) com ocorrência crítica em aberto',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Lista agrupada
                            Expanded(
                              child: ListView(
                                children: agrupados.entries.map((grupo) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // Cabeçalho do grupo
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade700,
                                            borderRadius:
                                                const BorderRadius.vertical(
                                              top: Radius.circular(8),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.error_outline,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  grupo.key,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.25),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '${grupo.value.length}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Itens do grupo
                                        ...grupo.value.map((oc) {
                                          String st =
                                              oc['status'] ?? 'Aberto';
                                          String stDisplay =
                                              st.toUpperCase();
                                          if (stDisplay == 'EM ATENDIMENTO') {
                                            stDisplay = 'EM\nATENDIMENTO';
                                          }
                                          if (stDisplay == 'EM DESLOCAMENTO') {
                                            stDisplay = 'EM\nDESLOCAMENTO';
                                          }

                                          return Container(
                                            decoration: BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: Colors.red.shade50,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                            child: ListTile(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 6,
                                              ),
                                              leading: Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: _corStatusReal(st)
                                                      .withValues(alpha: 0.1),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.traffic,
                                                  size: 20,
                                                  color: _corStatusReal(st),
                                                ),
                                              ),
                                              title: Text(
                                                '${oc['semaforo'] ?? '---'} — ${oc['endereco'] ?? '---'}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              subtitle: Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Wrap(
                                                  spacing: 16,
                                                  runSpacing: 2,
                                                  children: [
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          Icons
                                                              .lock_open_rounded,
                                                          size: 11,
                                                          color: Colors.black45,
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        Text(
                                                          'Abertura: ${_formatarDataHora(oc['data_de_abertura'])}',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                Colors.black54,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (oc['numero_da_ocorrencia'] !=
                                                        null)
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons.tag,
                                                            size: 11,
                                                            color:
                                                                Colors.black45,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            'Nº ${oc['numero_da_ocorrencia']}',
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 11,
                                                              color: Colors
                                                                  .black54,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              trailing: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _corStatusReal(st),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  stDisplay,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),

                            // ── BOTÕES DO RODAPÉ ──────────────────────────
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          const Color(0xFFc0392b),
                                      side: const BorderSide(
                                          color: Color(0xFFc0392b)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: const Icon(Icons.picture_as_pdf,
                                        size: 18),
                                    label: const Text(
                                      'Exportar PDF',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () =>
                                        _gerarPdfCriticasEmAberto(criticas),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF2c3e50),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text(
                                      'Fechar',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- MODAL OCORRENCIAS CRITICAS (FILTRO DE PERÍODO) ---
  void _abrirModalDiaChuva() {
    DateTime? tempInicio =
        _dataInicio ?? DateTime.now().subtract(const Duration(hours: 12));
    DateTime? tempFim = _dataFim ?? DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Text(
                'Filtro: Ocorrencias Criticas',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2c3e50),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Defina o periodo para filtrar apenas ocorrencias criticas.',
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        'Inicio: ${_formatarDataStr(tempInicio)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        DateTime? dt = await _escolherDataHora(tempInicio);
                        if (dt != null) setModalState(() => tempInicio = dt);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        'Fim: ${_formatarDataStr(tempFim)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        DateTime? dt = await _escolherDataHora(tempFim);
                        if (dt != null) setModalState(() => tempFim = dt);
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() => _filtroDiaChuva = false);
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                  onPressed: () {
                    setState(() {
                      _dataInicio = tempInicio;
                      _dataFim = tempFim;
                      _filtroDiaChuva = true;
                      _filtroTempoAtivo = 'personalizado';
                    });
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Aplicar Filtro',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _limparFiltros() {
    setState(() {
      _dataInicio = null;
      _dataFim = null;
      _filtroTempoAtivo = '24h';
      _filtroDiaChuva = false;
    });
  }

  String _formatarDataStr(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  String _formatarDataHora(dynamic t) {
    if (t == null) return '---';
    if (t is Timestamp) {
      return DateFormat("dd/MM/yy HH:mm'h'").format(t.toDate());
    }
    if (t is DateTime) {
      return DateFormat("dd/MM/yy HH:mm'h'").format(t);
    }
    return t.toString();
  }

  // --- LOGICA DE ORDENACAO E CORES DO STATUS ---
  int _getStatusWeight(String statusRaw) {
    String st = statusRaw.toLowerCase();
    if (st.contains('aberto')) return 1;
    if (st.contains('deslocamento')) return 2;
    if (st.contains('atendimento')) return 3;
    if (st.contains('conclu') || st.contains('finaliz')) return 4;
    return 5;
  }

  Color _corStatusReal(String statusRaw) {
    String st = statusRaw.toLowerCase();
    if (st.contains('aberto')) return Colors.redAccent;
    if (st.contains('deslocamento')) return Colors.orange;
    if (st.contains('atendimento')) return Colors.green;
    if (st.contains('conclu') || st.contains('finaliz')) return Colors.blueGrey;
    return Colors.grey;
  }

  PdfColor _corStatusPdf(String statusRaw) {
    String st = statusRaw.toLowerCase();
    if (st.contains('aberto')) return PdfColors.redAccent;
    if (st.contains('deslocamento')) return PdfColors.orange;
    if (st.contains('atendimento')) return PdfColors.green;
    if (st.contains('conclu') || st.contains('finaliz')) {
      return PdfColors.blueGrey;
    }
    return PdfColors.grey;
  }

  String _categorizarStatusParaKpi(String statusRaw) {
    String st = statusRaw.toLowerCase();
    if (st.contains('aberto') ||
        st.contains('deslocamento') ||
        st.contains('atendimento')) {
      return 'Pendente';
    }
    if (st.contains('conclu') || st.contains('finaliz')) return 'Concluido';
    return 'Outros';
  }

  // --- GERADOR DE PDF: OCORRÊNCIAS CRÍTICAS EM ABERTO (MODAL) ---
  Future<void> _gerarPdfCriticasEmAberto(
    List<Map<String, dynamic>> criticas,
  ) async {
    Navigator.pop(context); // Fecha o modal antes de abrir o viewer de PDF

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.blue)),
    );

    await Future.delayed(const Duration(milliseconds: 150));

    try {
      final pdf = pw.Document();
      final dataHoraAtual =
          DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

      // Agrupar por tipo de falha
      Map<String, List<Map<String, dynamic>>> agrupados = {};
      for (var oc in criticas) {
        String falha = oc['tipo_da_falha'] ?? 'Não informada';
        agrupados.putIfAbsent(falha, () => []).add(oc);
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          footer: (pw.Context context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'SOS - Ocorrencias Criticas em Aberto - $dataHoraAtual',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    'Pagina ${context.pageNumber} de ${context.pagesCount}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            );
          },
          build: (pw.Context context) {
            return [
              // Cabeçalho principal
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.red700,
                  borderRadius:
                      pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Ocorrencias Criticas em Aberto',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius:
                            pw.BorderRadius.all(pw.Radius.circular(12)),
                      ),
                      child: pw.Text(
                        '${criticas.length} semaforo(s)',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.red700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Status incluidos: Aberto  •  Em Deslocamento  •  Em Atendimento',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 20),

              // Grupos de falhas
              if (agrupados.isEmpty)
                pw.Text(
                  'Nenhuma ocorrencia critica em aberto.',
                  style: const pw.TextStyle(color: PdfColors.grey),
                )
              else
                ...agrupados.entries.map((grupo) {
                  return pw.Wrap(
                    children: [
                      pw.Container(
                        margin: const pw.EdgeInsets.only(bottom: 16),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.red200),
                          borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(6)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: [
                            // Cabeçalho do grupo
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: const pw.BoxDecoration(
                                color: PdfColors.red700,
                                borderRadius: pw.BorderRadius.only(
                                  topLeft: pw.Radius.circular(6),
                                  topRight: pw.Radius.circular(6),
                                ),
                              ),
                              child: pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Expanded(
                                    child: pw.Text(
                                      grupo.key,
                                      style: pw.TextStyle(
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColors.white,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  pw.Text(
                                    '${grupo.value.length} ocorrencia(s)',
                                    style: const pw.TextStyle(
                                      color: PdfColors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Tabela de ocorrências do grupo
                            pw.TableHelper.fromTextArray(
                              headers: [
                                'N Ocorrencia',
                                'Semaforo / Endereco',
                                'Data de Abertura',
                                'Status',
                              ],
                              data: grupo.value.map((oc) {
                                return [
                                  (oc['numero_da_ocorrencia'] ?? '---')
                                      .toString(),
                                  '${oc['semaforo'] ?? '---'} - ${oc['endereco'] ?? '---'}',
                                  _formatarDataHora(oc['data_de_abertura']),
                                  (oc['status'] ?? 'ABERTO')
                                      .toString()
                                      .toUpperCase(),
                                ];
                              }).toList(),
                              headerStyle: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                                fontSize: 9,
                              ),
                              headerDecoration: const pw.BoxDecoration(
                                color: PdfColors.blueGrey800,
                              ),
                              cellAlignment: pw.Alignment.centerLeft,
                              headerAlignment: pw.Alignment.center,
                              cellStyle: const pw.TextStyle(fontSize: 8),
                              columnWidths: {
                                0: const pw.FlexColumnWidth(1.2),
                                1: const pw.FlexColumnWidth(3.0),
                                2: const pw.FlexColumnWidth(1.4),
                                3: const pw.FlexColumnWidth(1.4),
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
            ];
          },
        ),
      );

      if (mounted) Navigator.pop(context);
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Ocorrencias_Criticas_Aberto.pdf',
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- GERADOR DE PDF CENTRALIZADO (DASHBOARD) ---
  Future<void> _gerarPdfDashboard(
    int total,
    int pendentes,
    int concluidos,
    List<QueryDocumentSnapshot> docs,
    Map<String, List<Map<String, dynamic>>> agrupadosDiaChuva,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.blue)),
    );

    await Future.delayed(const Duration(milliseconds: 150));

    try {
      final pdf = pw.Document();
      final dataHoraAtual =
          DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

      String periodoTexto = 'Ultimas 24h';
      if (_filtroTempoAtivo == 'hoje') {
        periodoTexto = 'Hoje (Desde as 00:00)';
      }
      if (_filtroTempoAtivo == 'personalizado') {
        periodoTexto =
            '${_formatarDataStr(_dataInicio)} ate ${_formatarDataStr(_dataFim)}';
      }
      if (_filtroDiaChuva) periodoTexto += ' [FILTRO: Ocorrencias Criticas]';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          footer: (pw.Context context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Relatorio gerado pelo Sistema de Ocorrencias Semaforicas - SOS - $dataHoraAtual',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    'Pagina ${context.pageNumber} de ${context.pagesCount}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            );
          },
          build: (pw.Context context) {
            return [
              pw.Text(
                'Relatorio Gerencial e Dashboard',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.Text(
                'Periodo Analisado: $periodoTexto',
                style: const pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 15),

              // ROW DOS KPIs
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildPdfKpi(
                    'Total do Periodo',
                    total.toString(),
                    PdfColors.blue,
                  ),
                  _buildPdfKpi(
                    'Pendentes',
                    pendentes.toString(),
                    PdfColors.orange,
                  ),
                  _buildPdfKpi(
                    'Concluidas',
                    concluidos.toString(),
                    PdfColors.green,
                  ),
                ],
              ),
              pw.SizedBox(height: 30),

              if (_filtroDiaChuva) ...[
                pw.Text(
                  'Detalhamento de Ocorrencias Criticas',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                ),
                pw.Divider(color: PdfColors.grey400),
                pw.SizedBox(height: 10),
                if (agrupadosDiaChuva.isEmpty)
                  pw.Text(
                    'Nenhuma ocorrencia critica registrada no periodo.',
                    style: const pw.TextStyle(color: PdfColors.grey),
                  )
                else
                  ...agrupadosDiaChuva.entries.map((grupo) {
                    return pw.Wrap(
                      children: [
                        pw.Container(
                          margin: const pw.EdgeInsets.only(bottom: 12),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey300),
                            borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(6),
                            ),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: const pw.BoxDecoration(
                                  color: PdfColors.grey200,
                                  borderRadius: pw.BorderRadius.only(
                                    topLeft: pw.Radius.circular(6),
                                    topRight: pw.Radius.circular(6),
                                  ),
                                ),
                                child: pw.Text(
                                  '${grupo.key} (${grupo.value.length})',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.blueGrey800,
                                  ),
                                ),
                              ),
                              ...grupo.value.map((oc) {
                                String statusBase = oc['status'] ?? 'ABERTO';
                                PdfColor corSt = _corStatusPdf(statusBase);
                                String stDisplay = statusBase.toUpperCase();

                                return pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: const pw.BoxDecoration(
                                    border: pw.Border(
                                      bottom: pw.BorderSide(
                                        color: PdfColors.grey200,
                                      ),
                                    ),
                                  ),
                                  child: pw.Row(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.center,
                                    mainAxisAlignment:
                                        pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Expanded(
                                        child: pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            pw.Text(
                                              '${oc['semaforo']} - ${oc['endereco']}',
                                              style: pw.TextStyle(
                                                fontWeight: pw.FontWeight.bold,
                                                fontSize: 10,
                                              ),
                                            ),
                                            pw.SizedBox(height: 4),
                                            pw.Text(
                                              'Abertura: ${_formatarDataHora(oc['data_de_abertura'])}   |   Fechamento: ${_formatarDataHora(oc['data_de_finalizacao'])}',
                                              style: const pw.TextStyle(
                                                fontSize: 9,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      pw.Container(
                                        padding: const pw.EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: pw.BoxDecoration(
                                          color: corSt,
                                          borderRadius:
                                              const pw.BorderRadius.all(
                                            pw.Radius.circular(4),
                                          ),
                                        ),
                                        child: pw.Text(
                                          stDisplay,
                                          style: pw.TextStyle(
                                            color: PdfColors.white,
                                            fontSize: 8,
                                            fontWeight: pw.FontWeight.bold,
                                          ),
                                          textAlign: pw.TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
              ] else ...[
                pw.Text(
                  'Ultimas Ocorrencias do Periodo Selecionado',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                ),
                pw.Divider(color: PdfColors.grey400),
                pw.SizedBox(height: 10),
                if (docs.isEmpty)
                  pw.Text(
                    'Nenhuma ocorrencia encontrada para o periodo.',
                    style: const pw.TextStyle(color: PdfColors.grey),
                  )
                else
                  pw.TableHelper.fromTextArray(
                    headers: [
                      'N Ocorrencia',
                      'Semaforo c/ Endereco',
                      'Falha Relatada',
                      'Falha Encontrada',
                      'Abertura',
                      'Fechamento',
                      'Status',
                    ],
                    data: docs.take(50).map((doc) {
                      var d = doc.data() as Map<String, dynamic>;
                      String numOc =
                          (d['numero_da_ocorrencia'] ?? d['id'] ?? doc.id)
                              .toString();
                      if (numOc.length > 8) numOc = numOc.substring(0, 8);

                      String stDisplay =
                          (d['status'] ?? 'ABERTO').toString().toUpperCase();
                      if (stDisplay == 'EM ATENDIMENTO') {
                        stDisplay = 'EM\nATENDIMENTO';
                      }
                      if (stDisplay == 'EM DESLOCAMENTO') {
                        stDisplay = 'EM\nDESLOCAMENTO';
                      }

                      return [
                        numOc,
                        '${d['semaforo']} - ${d['endereco']}',
                        (d['tipo_da_falha'] ?? '-').toString(),
                        (d['falha_aparente_final'] ?? '-').toString(),
                        _formatarDataHora(d['data_de_abertura']),
                        _formatarDataHora(d['data_de_finalizacao']),
                        stDisplay,
                      ];
                    }).toList(),
                    headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      fontSize: 9,
                    ),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.blueGrey800,
                    ),
                    cellAlignment: pw.Alignment.center,
                    headerAlignment: pw.Alignment.center,
                    cellStyle: const pw.TextStyle(fontSize: 8),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2.5),
                      2: const pw.FlexColumnWidth(1.5),
                      3: const pw.FlexColumnWidth(1.5),
                      4: const pw.FlexColumnWidth(1),
                      5: const pw.FlexColumnWidth(1),
                      6: const pw.FlexColumnWidth(1.2),
                    },
                  ),
              ],
            ];
          },
        ),
      );

      if (mounted) Navigator.pop(context);
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Dashboard_Relatorio.pdf',
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  pw.Widget _buildPdfKpi(String titulo, String valor, PdfColor corBase) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(
          bottom: pw.BorderSide(color: corBase, width: 4),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            titulo,
            style: pw.TextStyle(
              fontSize: 12,
              color: PdfColors.blueGrey,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: 32,
              color: PdfColors.blueGrey900,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // CONSTRUCAO DA INTERFACE
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Relatorios e Dashboard',
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
                .collection('Gerenciamento_ocorrencias')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Erro ao carregar dados.',
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }

              List<QueryDocumentSnapshot> docs = snapshot.data?.docs ?? [];

              // --- 1. APLICAR FILTROS INTELIGENTES ---
              DateTime now = DateTime.now();
              DateTime? filterStart;
              DateTime? filterEnd;

              if (_filtroTempoAtivo == '24h') {
                filterStart = now.subtract(const Duration(hours: 24));
                filterEnd = now;
              } else if (_filtroTempoAtivo == 'hoje') {
                filterStart =
                    DateTime(now.year, now.month, now.day, 0, 0, 0);
                filterEnd = now;
              } else if (_filtroTempoAtivo == 'personalizado') {
                filterStart = _dataInicio;
                filterEnd = _dataFim;
              }

              docs = docs.where((doc) {
                var d = doc.data() as Map<String, dynamic>;

                // Filtro de Tempo
                if (filterStart != null || filterEnd != null) {
                  if (d['data_de_abertura'] == null) return false;
                  DateTime dtAbertura =
                      (d['data_de_abertura'] as Timestamp).toDate();

                  if (filterStart != null &&
                      dtAbertura.isBefore(filterStart)) {
                    return false;
                  }
                  if (filterEnd != null && dtAbertura.isAfter(filterEnd)) {
                    return false;
                  }
                }

                // Filtro Ocorrencias Criticas
                if (_filtroDiaChuva) {
                  String falha = (d['tipo_da_falha'] ?? '')
                      .toString()
                      .toUpperCase()
                      .trim();
                  String falhaNorm = _removerAcentos(falha);
                  bool found = _falhasCriticas.any(
                    (f) => _removerAcentos(f) == falhaNorm,
                  );
                  if (!found) return false;
                }

                return true;
              }).toList();

              // --- ORDENACAO GLOBAL POR STATUS E DATA RECENTE ---
              docs.sort((a, b) {
                var dA = a.data() as Map<String, dynamic>;
                var dB = b.data() as Map<String, dynamic>;
                int wA = _getStatusWeight(dA['status'] ?? '');
                int wB = _getStatusWeight(dB['status'] ?? '');
                if (wA != wB) return wA.compareTo(wB);

                DateTime dtA = dA['data_de_abertura'] != null
                    ? (dA['data_de_abertura'] as Timestamp).toDate()
                    : DateTime.fromMillisecondsSinceEpoch(0);
                DateTime dtB = dB['data_de_abertura'] != null
                    ? (dB['data_de_abertura'] as Timestamp).toDate()
                    : DateTime.fromMillisecondsSinceEpoch(0);
                return dtB.compareTo(dtA);
              });

              // --- 2. CALCULO DOS KPIs E AGRUPAMENTO ---
              int total = docs.length;
              int pendentes = 0;
              int concluidos = 0;

              Map<String, int> statusPieCount = {};
              Map<String, int> falhasCount = {};
              Map<String, List<Map<String, dynamic>>> agrupadosChuva = {};

              for (var doc in docs) {
                var d = doc.data() as Map<String, dynamic>;

                String catKPI = _categorizarStatusParaKpi(d['status'] ?? '');
                if (catKPI == 'Pendente') {
                  pendentes++;
                } else if (catKPI == 'Concluido') {
                  concluidos++;
                }

                String stReal =
                    (d['status'] ?? 'ABERTO').toString().toUpperCase();
                statusPieCount[stReal] = (statusPieCount[stReal] ?? 0) + 1;

                String falha = d['tipo_da_falha'] ?? 'Nao informada';
                if (falha.trim().isNotEmpty && falha != 'Nao informada') {
                  falhasCount[falha] = (falhasCount[falha] ?? 0) + 1;
                }

                if (_filtroDiaChuva) {
                  if (!agrupadosChuva.containsKey(falha)) {
                    agrupadosChuva[falha] = [];
                  }
                  agrupadosChuva[falha]!.add(d);
                }
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
                        // --- BARRA DE FILTROS INTELIGENTES ---
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text(
                                    'Filtro Rapido:',
                                    style: TextStyle(
                                      color: Color(0xFF2c3e50),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Ultimas 24h'),
                                    selected: _filtroTempoAtivo == '24h',
                                    selectedColor: Colors.blueAccent,
                                    labelStyle: TextStyle(
                                      color: _filtroTempoAtivo == '24h'
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    onSelected: (v) => setState(() {
                                      _filtroTempoAtivo = '24h';
                                      _dataInicio = null;
                                      _dataFim = null;
                                      _filtroDiaChuva = false;
                                    }),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Hoje'),
                                    selected: _filtroTempoAtivo == 'hoje',
                                    selectedColor: Colors.blueAccent,
                                    labelStyle: TextStyle(
                                      color: _filtroTempoAtivo == 'hoje'
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    onSelected: (v) => setState(() {
                                      _filtroTempoAtivo = 'hoje';
                                      _dataInicio = null;
                                      _dataFim = null;
                                      _filtroDiaChuva = false;
                                    }),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'ou Periodo Exato:',
                                    style: TextStyle(
                                      color: Color(0xFF2c3e50),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF2c3e50),
                                      side: const BorderSide(
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.calendar_month,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _dataInicio == null
                                          ? 'Data/Hora Inicial'
                                          : _formatarDataStr(_dataInicio),
                                    ),
                                    onPressed: () =>
                                        _selecionarDataInicio(context),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF2c3e50),
                                      side: const BorderSide(
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.calendar_month,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _dataFim == null
                                          ? 'Data/Hora Final'
                                          : _formatarDataStr(_dataFim),
                                    ),
                                    onPressed: () =>
                                        _selecionarDataFim(context),
                                  ),
                                  const SizedBox(width: 16),
                                  FilterChip(
                                    label: const Text(
                                      'Ocorrencias Criticas',
                                    ),
                                    avatar: const Icon(
                                      Icons.thunderstorm_outlined,
                                      size: 16,
                                    ),
                                    selected: _filtroDiaChuva,
                                    selectedColor: Colors.blueGrey.shade700,
                                    labelStyle: TextStyle(
                                      color: _filtroDiaChuva
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    onSelected: (v) {
                                      if (v) {
                                        _abrirModalDiaChuva();
                                      } else {
                                        setState(
                                          () => _filtroDiaChuva = false,
                                        );
                                      }
                                    },
                                  ),
                                  if (_filtroTempoAtivo != '24h' ||
                                      _dataInicio != null ||
                                      _dataFim != null ||
                                      _filtroDiaChuva)
                                    ActionChip(
                                      backgroundColor: Colors.redAccent,
                                      label: const Text(
                                        'Limpar',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      avatar: const Icon(
                                        Icons.clear,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      onPressed: _limparFiltros,
                                    ),
                                ],
                              ),

                              // --- BOTÕES DA DIREITA ---
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  // BOTÃO: OCORRÊNCIAS CRÍTICAS EM ABERTO
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade700,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      elevation: 3,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Ocorrências Críticas em Aberto',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: _abrirModalCriticasEmAberto,
                                  ),

                                  // BOTÃO PDF DASHBOARD
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFc0392b),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.picture_as_pdf,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Exportar PDF',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: () => _gerarPdfDashboard(
                                      total,
                                      pendentes,
                                      concluidos,
                                      docs,
                                      agrupadosChuva,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // --- CARDS DE KPIs ---
                        LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount =
                                constraints.maxWidth > 800
                                    ? 3
                                    : (constraints.maxWidth > 400 ? 2 : 1);
                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 3.5,
                              children: [
                                _buildKpiCard(
                                  'Total do Periodo',
                                  total.toString(),
                                  Colors.blue,
                                  Icons.assignment,
                                ),
                                _buildKpiCard(
                                  'Pendentes',
                                  pendentes.toString(),
                                  Colors.orange,
                                  Icons.warning_amber_rounded,
                                ),
                                _buildKpiCard(
                                  'Concluidas',
                                  concluidos.toString(),
                                  Colors.green,
                                  Icons.check_circle_outline,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // --- AREA DOS GRAFICOS INTERATIVOS ---
                        LayoutBuilder(
                          builder: (context, constraints) {
                            bool isDesktop = constraints.maxWidth > 800;

                            Widget pieChart = Container(
                              height: 380,
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
                                    'Distribuicao por Status',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2c3e50),
                                    ),
                                  ),
                                  const Divider(),
                                  Expanded(
                                    child: statusPieCount.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'Sem dados no periodo',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          )
                                        : StatefulBuilder(
                                            builder: (context, setStateChart) {
                                              return PieChart(
                                                PieChartData(
                                                  pieTouchData: PieTouchData(
                                                    touchCallback: (
                                                      FlTouchEvent event,
                                                      pieTouchResponse,
                                                    ) {
                                                      setStateChart(() {
                                                        if (!event
                                                                .isInterestedForInteractions ||
                                                            pieTouchResponse ==
                                                                null ||
                                                            pieTouchResponse
                                                                    .touchedSection ==
                                                                null) {
                                                          _touchedIndexPie =
                                                              -1;
                                                          return;
                                                        }
                                                        _touchedIndexPie =
                                                            pieTouchResponse
                                                                .touchedSection!
                                                                .touchedSectionIndex;
                                                      });
                                                    },
                                                  ),
                                                  sectionsSpace: 3,
                                                  centerSpaceRadius: 60,
                                                  sections: statusPieCount
                                                      .entries
                                                      .toList()
                                                      .asMap()
                                                      .entries
                                                      .map((entry) {
                                                    final isTouched =
                                                        entry.key ==
                                                            _touchedIndexPie;
                                                    final fontSize =
                                                        isTouched
                                                            ? 20.0
                                                            : 14.0;
                                                    final radius =
                                                        isTouched
                                                            ? 70.0
                                                            : 60.0;
                                                    return PieChartSectionData(
                                                      color: _corStatusReal(
                                                        entry.value.key,
                                                      ),
                                                      value: entry.value.value
                                                          .toDouble(),
                                                      title:
                                                          '${entry.value.value}',
                                                      radius: radius,
                                                      titleStyle: TextStyle(
                                                        fontSize: fontSize,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: statusPieCount.keys
                                        .map(
                                          (k) => Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: _corStatusReal(k),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                k,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blueGrey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                            );

                            Widget barChart = Container(
                              height: 380,
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
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: top5Falhas.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'Sem dados no periodo',
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          )
                                        : BarChart(
                                            BarChartData(
                                              alignment:
                                                  BarChartAlignment.spaceAround,
                                              maxY: (top5Falhas.isNotEmpty
                                                      ? top5Falhas
                                                          .first.value
                                                          .toDouble()
                                                      : 10) *
                                                  1.3,
                                              barTouchData: BarTouchData(
                                                enabled: true,
                                                touchTooltipData:
                                                    BarTouchTooltipData(
                                                  getTooltipColor: (group) =>
                                                      const Color(0xFF2c3e50),
                                                  tooltipPadding:
                                                      const EdgeInsets.all(8),
                                                  tooltipMargin: 8,
                                                  getTooltipItem: (
                                                    group,
                                                    groupIndex,
                                                    rod,
                                                    rodIndex,
                                                  ) {
                                                    return BarTooltipItem(
                                                      '${top5Falhas[group.x.toInt()].key}\n',
                                                      const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                      children: [
                                                        TextSpan(
                                                          text:
                                                              '${rod.toY.toInt()} Ocorrencias',
                                                          style:
                                                              const TextStyle(
                                                            color: Colors
                                                                .yellowAccent,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ),
                                              titlesData: FlTitlesData(
                                                show: true,
                                                rightTitles: const AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: false,
                                                  ),
                                                ),
                                                topTitles: const AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: false,
                                                  ),
                                                ),
                                                leftTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    reservedSize: 40,
                                                    getTitlesWidget:
                                                        (value, meta) {
                                                      if (value % 1 != 0) {
                                                        return const SizedBox
                                                            .shrink();
                                                      }
                                                      return Text(
                                                        value
                                                            .toInt()
                                                            .toString(),
                                                        style: const TextStyle(
                                                          color: Colors.blueGrey,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                bottomTitles: AxisTitles(
                                                  sideTitles: SideTitles(
                                                    showTitles: true,
                                                    reservedSize: 90,
                                                    getTitlesWidget: (
                                                      double value,
                                                      TitleMeta meta,
                                                    ) {
                                                      if (value.toInt() >=
                                                          top5Falhas.length) {
                                                        return const SizedBox
                                                            .shrink();
                                                      }
                                                      String title =
                                                          top5Falhas[value
                                                                  .toInt()]
                                                              .key;
                                                      return SideTitleWidget(
                                                        axisSide: meta.axisSide,
                                                        space: 8,
                                                        child: SizedBox(
                                                          width: 90,
                                                          child: Text(
                                                            title,
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .black87,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 8,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                            maxLines: 4,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                              gridData: FlGridData(
                                                show: true,
                                                drawVerticalLine: false,
                                                getDrawingHorizontalLine:
                                                    (value) => FlLine(
                                                  color: Colors.grey.shade300,
                                                  strokeWidth: 1,
                                                  dashArray: [4, 4],
                                                ),
                                              ),
                                              borderData:
                                                  FlBorderData(show: false),
                                              barGroups: top5Falhas
                                                  .asMap()
                                                  .entries
                                                  .map((entry) {
                                                return BarChartGroupData(
                                                  x: entry.key,
                                                  barRods: [
                                                    BarChartRodData(
                                                      toY: entry.value.value
                                                          .toDouble(),
                                                      gradient:
                                                          const LinearGradient(
                                                        colors: [
                                                          Colors.lightBlueAccent,
                                                          Colors.blue,
                                                        ],
                                                        begin: Alignment
                                                            .bottomCenter,
                                                        end: Alignment
                                                            .topCenter,
                                                      ),
                                                      width: 22,
                                                      borderRadius:
                                                          const BorderRadius
                                                              .vertical(
                                                        top: Radius.circular(6),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            );

                            if (isDesktop) {
                              return Row(
                                children: [
                                  Expanded(child: pieChart),
                                  const SizedBox(width: 24),
                                  Expanded(child: barChart),
                                ],
                              );
                            } else {
                              return Column(
                                children: [
                                  pieChart,
                                  const SizedBox(height: 24),
                                  barChart,
                                ],
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 24),

                        // --- LISTAGEM INFERIOR ---
                        if (_filtroDiaChuva) ...[
                          Container(
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Detalhamento de Ocorrencias Criticas',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2c3e50),
                                  ),
                                ),
                                const Divider(),
                                if (agrupadosChuva.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Center(
                                      child: Text(
                                        'Nenhuma ocorrencia critica registrada neste periodo.',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ...agrupadosChuva.entries.map((grupo) {
                                    return Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.blueGrey.shade200,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blueGrey.shade50,
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                top: Radius.circular(8),
                                              ),
                                            ),
                                            child: Text(
                                              '${grupo.key} (${grupo.value.length})',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blueGrey,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          ...grupo.value.map((oc) {
                                            String st =
                                                oc['status'] ?? 'Aberto';
                                            String stDisplay =
                                                st.toUpperCase();
                                            if (stDisplay ==
                                                'EM ATENDIMENTO') {
                                              stDisplay = 'EM\nATENDIMENTO';
                                            }
                                            if (stDisplay ==
                                                'EM DESLOCAMENTO') {
                                              stDisplay = 'EM\nDESLOCAMENTO';
                                            }

                                            return ListTile(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                              title: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.traffic,
                                                    size: 16,
                                                    color: Colors.blueGrey,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      '${oc['semaforo'] ?? '---'} - ${oc['endereco'] ?? '---'}',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    spacing: 16,
                                                    runSpacing: 4,
                                                    children: [
                                                      Text(
                                                        'Abertura: ${_formatarDataHora(oc['data_de_abertura'])}',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Fechamento: ${_formatarDataHora(oc['data_de_finalizacao'])}',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              trailing: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _corStatusReal(st),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  stDisplay,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ] else ...[
                          Container(
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Ultimas Ocorrencias do Periodo Selecionado',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2c3e50),
                                  ),
                                ),
                                const Divider(),
                                if (docs.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(20.0),
                                    child: Center(
                                      child: Text(
                                        'Nenhuma ocorrencia encontrada para o periodo/filtro selecionado.',
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(
                                        const Color(0xFFf5f6f8),
                                      ),
                                      headingTextStyle: const TextStyle(
                                        color: Colors.blueGrey,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      dataRowMinHeight: 60,
                                      dataRowMaxHeight: 80,
                                      columns: const [
                                        DataColumn(
                                          label: Expanded(
                                            child: Center(
                                              child: Text(
                                                'N Ocorrencia',
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Expanded(
                                            child: Center(
                                              child: Text(
                                                'Semaforo com Endereco',
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Expanded(
                                            child: Center(
                                              child: Text(
                                                'Falha Relatada',
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Expanded(
                                            child: Center(
                                              child: Text(
                                                'Falha Encontrada',
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Expanded(
                                            child: Center(
                                              child: Text(
                                                'Datas (Abertura / Fechamento)',
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: Expanded(
                                            child: Center(
                                              child: Text(
                                                'Status',
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      rows: docs.take(20).map((doc) {
                                        var d = doc.data()
                                            as Map<String, dynamic>;
                                        String st = d['status'] ?? 'Aberto';

                                        String numOc = (d[
                                                    'numero_da_ocorrencia'] ??
                                                d['id'] ??
                                                doc.id)
                                            .toString();
                                        String numOcShort = numOc.length > 8
                                            ? numOc.substring(0, 8)
                                            : numOc;

                                        String stDisplay = st.toUpperCase();
                                        if (stDisplay == 'EM ATENDIMENTO') {
                                          stDisplay = 'EM\nATENDIMENTO';
                                        }
                                        if (stDisplay == 'EM DESLOCAMENTO') {
                                          stDisplay = 'EM\nDESLOCAMENTO';
                                        }

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Center(
                                                child: Text(
                                                  numOcShort,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blueGrey,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Center(
                                                child: SizedBox(
                                                  width: 200,
                                                  child: Text(
                                                    '${d['semaforo'] ?? '---'} - ${d['endereco'] ?? '---'}',
                                                    textAlign: TextAlign.center,
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Center(
                                                child: SizedBox(
                                                  width: 130,
                                                  child: Text(
                                                    d['tipo_da_falha'] ?? '---',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: Colors
                                                          .orange.shade800,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 11,
                                                    ),
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Center(
                                                child: SizedBox(
                                                  width: 130,
                                                  child: Text(
                                                    d['falha_aparente_final'] ??
                                                        '---',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.blueGrey,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Center(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      'Ab: ${_formatarDataHora(d['data_de_abertura'])}',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                    Container(
                                                      height: 1,
                                                      width: 80,
                                                      color:
                                                          Colors.grey.shade300,
                                                      margin: const EdgeInsets
                                                          .symmetric(
                                                        vertical: 4,
                                                      ),
                                                    ),
                                                    Text(
                                                      'Fc: ${_formatarDataHora(d['data_de_finalizacao'])}',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Center(
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: _corStatusReal(st),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      4,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    stDisplay,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
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

  // Utilitario para remover acentos na comparacao de falhas
  String _removerAcentos(String texto) {
    const comAcento =
        'àáâãäåèéêëìíîïòóôõöùúûüýÿçñÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÝÇÑ';
    const semAcento =
        'aaaaaaeeeeiiiioooooouuuuyyçnAAAAAAEEEEIIIIOOOOOUUUUYCN';
    String resultado = texto;
    for (int i = 0; i < comAcento.length; i++) {
      resultado = resultado.replaceAll(comAcento[i], semAcento[i]);
    }
    return resultado;
  }

  Widget _buildKpiCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(bottom: BorderSide(color: color, width: 5)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -10,
            child: Icon(
              icon,
              size: 80,
              color: color.withValues(alpha: 0.15),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
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
          ),
        ],
      ),
    );
  }
}