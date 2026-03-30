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
  String _filtroTempoAtivo = '24h'; // Opções: '24h', 'hoje', 'personalizado'
  bool _filtroDiaChuva = false;

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
        // FORÇA O FORMATO 24 HORAS
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
      pickedTime.minute
    );
  }

  // --- MÉTODOS DE FILTRO DE DATA ---
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

  // --- MODAL DIA DE CHUVA ---
  void _abrirModalDiaChuva() {
    DateTime? tempInicio = _dataInicio ?? DateTime.now().subtract(const Duration(hours: 12));
    DateTime? tempFim = _dataFim ?? DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text('🌧️ Filtro: Dia de Chuva', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2c3e50))),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Defina o período da chuva para filtrar apenas ocorrências geradas pelo clima.', style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text('Início: ${_formatarDataStr(tempInicio)}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text('Fim: ${_formatarDataStr(tempFim)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        DateTime? dt = await _escolherDataHora(tempFim);
                        if (dt != null) setModalState(() => tempFim = dt);
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () {
                  setState(() => _filtroDiaChuva = false);
                  Navigator.pop(context);
                }, child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: () {
                    setState(() {
                      _dataInicio = tempInicio;
                      _dataFim = tempFim;
                      _filtroDiaChuva = true;
                      _filtroTempoAtivo = 'personalizado';
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Aplicar Filtro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _limparFiltros() {
    setState(() {
      _dataInicio = null;
      _dataFim = null;
      _filtroTempoAtivo = '24h'; // Volta para o padrão
      _filtroDiaChuva = false;
    });
  }

  String _formatarDataStr(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  String _formatarDataHora(dynamic t) {
    if (t == null) return '---';
    if (t is Timestamp) return DateFormat('dd/MM/yy HH:mm\'h\'').format(t.toDate());
    if (t is DateTime) return DateFormat('dd/MM/yy HH:mm\'h\'').format(t);
    return t.toString(); 
  }

  // --- LÓGICA DE STATUS ---
  String _categorizarStatus(String statusRaw) {
    String st = statusRaw.toLowerCase();
    if (st.contains('aberto') || st.contains('pendente') || st.contains('aguardando')) {
      return 'Aberto';
    }
    if (st.contains('deslocamento') || st.contains('atendimento')) {
      return 'Em Andamento';
    }
    if (st.contains('conclu') || st.contains('finaliz')) {
      return 'Concluído';
    }
    return 'Outros';
  }

  Color _corDoStatus(String categoria) {
    switch (categoria) {
      case 'Aberto': return Colors.redAccent;
      case 'Em Andamento': return Colors.orange;
      case 'Concluído': return Colors.green;
      default: return Colors.grey;
    }
  }

  // --- GERADOR DE PDF ---
  Future<void> _gerarPdfDashboard(
    int total, int abertos, int emAndamento, int concluidos,
    List<QueryDocumentSnapshot> docs,
    Map<String, List<Map<String, dynamic>>> agrupadosDiaChuva
  ) async {
    
    // Mostra o Loading para não parecer que travou
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.blue))
    );

    await Future.delayed(const Duration(milliseconds: 150));

    try {
      final pdf = pw.Document();
      final dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

      String periodoTexto = 'Últimas 24h';
      if (_filtroTempoAtivo == 'hoje') periodoTexto = 'Hoje (Desde às 00:00)';
      if (_filtroTempoAtivo == 'personalizado') {
        periodoTexto = '${_formatarDataStr(_dataInicio)} até ${_formatarDataStr(_dataFim)}';
      }
      if (_filtroDiaChuva) periodoTexto += ' [FILTRO: DIA DE CHUVA]';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape, 
          margin: const pw.EdgeInsets.all(30),
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                'Relatório gerado pelo Sistema de Ocorrências Semafóricas - SOS - $dataHoraAtual - Página ${context.pageNumber} de ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            );
          },
          build: (pw.Context context) {
            return [
              pw.Text('Relatório Gerencial e Dashboard', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
              pw.SizedBox(height: 15),

              // ROW DOS KPIs
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildPdfKpi('Total do Período', total.toString(), PdfColors.blue),
                  _buildPdfKpi('Pendentes (Abertas)', abertos.toString(), PdfColors.red),
                  _buildPdfKpi('Em Atendimento', emAndamento.toString(), PdfColors.orange),
                  _buildPdfKpi('Concluídas', concluidos.toString(), PdfColors.green),
                ]
              ),
              pw.SizedBox(height: 30),

              // LISTAGEM DE DADOS (Chuva vs Normal)
              if (_filtroDiaChuva) ...[
                pw.Text('Detalhamento do Dia de Chuva (Ocorrências Climáticas)', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
                pw.Divider(color: PdfColors.grey400),
                pw.SizedBox(height: 10),
                
                if (agrupadosDiaChuva.isEmpty)
                  pw.Text('Nenhuma ocorrência climática registrada no período.', style: const pw.TextStyle(color: PdfColors.grey))
                else
                  ...agrupadosDiaChuva.entries.map((grupo) {
                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 12),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.grey200,
                              borderRadius: pw.BorderRadius.only(topLeft: pw.Radius.circular(6), topRight: pw.Radius.circular(6))
                            ),
                            child: pw.Text('${grupo.key} (${grupo.value.length})', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                          ),
                          ...grupo.value.map((oc) {
                            String statusBase = oc['status'] ?? 'ABERTO';
                            String stCat = _categorizarStatus(statusBase);
                            
                            PdfColor corSt = PdfColors.grey;
                            if (stCat == 'Aberto') corSt = PdfColors.redAccent;
                            if (stCat == 'Em Andamento') corSt = PdfColors.orange;
                            if (stCat == 'Concluído') corSt = PdfColors.green;

                            return pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))
                              ),
                              child: pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Expanded(
                                    child: pw.Column(
                                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                                      children: [
                                        pw.Text('${oc['numero_da_ocorrencia'] ?? 'S/N'} - ${oc['semaforo']} - ${oc['endereco']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                                      ]
                                    )
                                  ),
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: pw.BoxDecoration(color: corSt, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                                    child: pw.Text(statusBase.toUpperCase(), style: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                                  )
                                ]
                              )
                            );
                          }).toList(),
                        ]
                      )
                    );
                  }).toList()
              ] else ...[
                pw.Text('Últimas Ocorrências do Período Selecionado', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
                pw.Divider(color: PdfColors.grey400),
                pw.SizedBox(height: 10),
                
                if (docs.isEmpty)
                   pw.Text('Nenhuma ocorrência encontrada para o período.', style: const pw.TextStyle(color: PdfColors.grey))
                else
                  pw.Table.fromTextArray(
                    headers: ['Nº Ocorrência', 'Semáforo c/ Endereço', 'Falha', 'Data Abertura', 'Data Fechamento', 'Status'],
                    // Limite para evitar congelamento do Browser
                    data: docs.take(50).map((doc) {
                      var d = doc.data() as Map<String, dynamic>;
                      String numOc = (d['numero_da_ocorrencia'] ?? d['id'] ?? doc.id).toString();
                      if (numOc.length > 8) numOc = numOc.substring(0, 8);
                      return [
                        numOc,
                        '${d['semaforo']} - ${d['endereco']}',
                        (d['tipo_da_falha'] ?? '-').toString(),
                        _formatarDataHora(d['data_de_abertura']),
                        _formatarDataHora(d['data_de_finalizacao']),
                        (d['status'] ?? 'ABERTO').toString().toUpperCase()
                      ];
                    }).toList(),
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                    cellAlignment: pw.Alignment.centerLeft,
                    cellStyle: const pw.TextStyle(fontSize: 9),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1),
                      1: const pw.FlexColumnWidth(3),
                      2: const pw.FlexColumnWidth(2),
                      3: const pw.FlexColumnWidth(1.5),
                      4: const pw.FlexColumnWidth(1.5),
                      5: const pw.FlexColumnWidth(1.5),
                    }
                  ),
              ]
            ];
          },
        ),
      );

      if (mounted) Navigator.pop(context);
      await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Dashboard_Relatorio.pdf');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: Colors.red));
    }
  }

  // WIDGET HELPER PARA OS KPIs DO PDF
  pw.Widget _buildPdfKpi(String titulo, String valor, PdfColor corBase) {
    return pw.Container(
      width: 170, 
      padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border(bottom: pw.BorderSide(color: corBase, width: 4)),
        // REMOVIDO o borderRadius que causava o erro na biblioteca de PDF
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(titulo, style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(valor, style: pw.TextStyle(fontSize: 28, color: PdfColors.blueGrey900, fontWeight: pw.FontWeight.bold)),
        ]
      )
    );
  }

  // =========================================================================
  // CONSTRUÇÃO DA INTERFACE
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Relatórios e Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            stream: FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').orderBy('data_de_abertura', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              if (snapshot.hasError) {
                return const Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.white)));
              }

              List<QueryDocumentSnapshot> docs = snapshot.data?.docs ?? [];

              // --- 1. APLICAR FILTROS INTELIGENTES (TEMPO E CHUVA) ---
              DateTime now = DateTime.now();
              DateTime? filterStart;
              DateTime? filterEnd;

              if (_filtroTempoAtivo == '24h') {
                filterStart = now.subtract(const Duration(hours: 24));
                filterEnd = now;
              } else if (_filtroTempoAtivo == 'hoje') {
                filterStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
                filterEnd = now;
              } else if (_filtroTempoAtivo == 'personalizado') {
                filterStart = _dataInicio;
                filterEnd = _dataFim;
              }

              const List<String> falhasChuva = [
                'SEMÁFORO APAGADO',
                'APAGADO POR FALTA DE ENERGIA',
                'ESTRUTURA COM FUGA DE TENSÃO',
                'SEMÁFORO COM FASE APAGADA',
                'SEMÁFORO OPERANDO COM GERADOR',
                'SEMÁFORO OSCILANDO NAS CORES (ALTERNANDO RAPIDAMENTE)',
                'SEMÁFORO PARADO',
                'SEMÁFORO PISCANDO',
                'SEMÁFORO REINICIANDO',
                'SEMÁFORO SERIADO (2 OU MAIS CORES ACESAS AO MESMO TEMPO)'
              ];

              docs = docs.where((doc) {
                var d = doc.data() as Map<String, dynamic>;
                
                // Filtro de Tempo
                if (filterStart != null || filterEnd != null) {
                  if (d['data_de_abertura'] == null) return false;
                  DateTime dtAbertura = (d['data_de_abertura'] as Timestamp).toDate();
                  
                  if (filterStart != null && dtAbertura.isBefore(filterStart)) return false;
                  if (filterEnd != null && dtAbertura.isAfter(filterEnd)) return false;
                }

                // Filtro Dia de Chuva
                if (_filtroDiaChuva) {
                  String falha = (d['tipo_da_falha'] ?? '').toString().toUpperCase().trim();
                  if (!falhasChuva.contains(falha)) return false;
                }

                return true;
              }).toList();

              // --- 2. CÁLCULO DOS KPIs E AGRUPAMENTO ---
              int total = docs.length;
              int abertos = 0;
              int emAndamento = 0;
              int concluidos = 0;

              Map<String, int> statusCount = {};
              Map<String, int> falhasCount = {};
              
              // Mapa para agrupar as ocorrências no modo Dia de Chuva
              Map<String, List<Map<String, dynamic>>> agrupadosChuva = {};

              for (var doc in docs) {
                var d = doc.data() as Map<String, dynamic>;
                String catStatus = _categorizarStatus(d['status'] ?? '');

                if (catStatus == 'Aberto') abertos++;
                else if (catStatus == 'Em Andamento') emAndamento++;
                else if (catStatus == 'Concluído') concluidos++;

                statusCount[catStatus] = (statusCount[catStatus] ?? 0) + 1;

                String falha = d['tipo_da_falha'] ?? 'Não informada';
                if (falha.trim().isNotEmpty && falha != 'Não informada') {
                  falhasCount[falha] = (falhasCount[falha] ?? 0) + 1;
                }
                
                if (_filtroDiaChuva) {
                  if (!agrupadosChuva.containsKey(falha)) agrupadosChuva[falha] = [];
                  agrupadosChuva[falha]!.add(d);
                }
              }

              // Top 5 Falhas
              var sortedFalhas = falhasCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              var top5Falhas = sortedFalhas.take(5).toList();

              return SingleChildScrollView(
                padding: const EdgeInsets.only(top: 100, left: 16, right: 16, bottom: 40),
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
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                          ),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('Filtro Rápido:', style: TextStyle(color: Color(0xFF2c3e50), fontWeight: FontWeight.bold, fontSize: 14)),
                              
                              ChoiceChip(
                                label: const Text('Últimas 24h'),
                                selected: _filtroTempoAtivo == '24h',
                                selectedColor: Colors.blueAccent,
                                labelStyle: TextStyle(color: _filtroTempoAtivo == '24h' ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                                onSelected: (v) => setState(() { _filtroTempoAtivo = '24h'; _dataInicio = null; _dataFim = null; _filtroDiaChuva = false; }),
                              ),
                              ChoiceChip(
                                label: const Text('Hoje'),
                                selected: _filtroTempoAtivo == 'hoje',
                                selectedColor: Colors.blueAccent,
                                labelStyle: TextStyle(color: _filtroTempoAtivo == 'hoje' ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                                onSelected: (v) => setState(() { _filtroTempoAtivo = 'hoje'; _dataInicio = null; _dataFim = null; _filtroDiaChuva = false; }),
                              ),
                              
                              const SizedBox(width: 8),
                              const Text('ou Período Exato:', style: TextStyle(color: Color(0xFF2c3e50), fontWeight: FontWeight.bold, fontSize: 14)),

                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2c3e50), side: const BorderSide(color: Colors.blueGrey)),
                                icon: const Icon(Icons.calendar_month, size: 16),
                                label: Text(_dataInicio == null ? 'Data/Hora Inicial' : _formatarDataStr(_dataInicio)),
                                onPressed: () => _selecionarDataInicio(context),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2c3e50), side: const BorderSide(color: Colors.blueGrey)),
                                icon: const Icon(Icons.calendar_month, size: 16),
                                label: Text(_dataFim == null ? 'Data/Hora Final' : _formatarDataStr(_dataFim)),
                                onPressed: () => _selecionarDataFim(context),
                              ),

                              const SizedBox(width: 16),
                              FilterChip(
                                label: const Text('🌧️ Dia de Chuva'),
                                selected: _filtroDiaChuva,
                                selectedColor: Colors.blueGrey.shade700,
                                labelStyle: TextStyle(color: _filtroDiaChuva ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                                onSelected: (v) {
                                  if (v) {
                                    _abrirModalDiaChuva();
                                  } else {
                                    setState(() => _filtroDiaChuva = false);
                                  }
                                },
                              ),

                              if (_filtroTempoAtivo != '24h' || _dataInicio != null || _dataFim != null || _filtroDiaChuva)
                                ActionChip(
                                  backgroundColor: Colors.redAccent,
                                  label: const Text('Limpar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  avatar: const Icon(Icons.clear, color: Colors.white, size: 16),
                                  onPressed: _limparFiltros,
                                ),
                                
                              const Spacer(),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFc0392b),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                                label: const Text('Exportar PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                onPressed: () => _gerarPdfDashboard(total, abertos, emAndamento, concluidos, docs, agrupadosChuva),
                              )
                            ],
                          ),
                        ),

                        // --- CARDS DE KPIs COM ÍCONES ---
                        LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 400 ? 2 : 1);
                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 2.5,
                              children: [
                                _buildKpiCard('Total do Período', total.toString(), Colors.blue, Icons.assignment),
                                _buildKpiCard('Pendentes (Abertas)', abertos.toString(), Colors.redAccent, Icons.warning_amber_rounded),
                                _buildKpiCard('Em Atendimento', emAndamento.toString(), Colors.orange, Icons.engineering),
                                _buildKpiCard('Concluídas', concluidos.toString(), Colors.green, Icons.check_circle_outline),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // --- ÁREA DOS GRÁFICOS INTERATIVOS ---
                        LayoutBuilder(
                          builder: (context, constraints) {
                            bool isDesktop = constraints.maxWidth > 800;
                            List<Widget> charts = [
                              
                              // GRÁFICO DE ROSCA (STATUS) COM PROTEÇÃO CONTRA FLICKER
                              Expanded(
                                flex: isDesktop ? 1 : 0,
                                child: Container(
                                  height: 380,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                                  ),
                                  child: Column(
                                    children: [
                                      const Text('Distribuição por Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2c3e50))),
                                      const Divider(),
                                      Expanded(
                                        child: statusCount.isEmpty
                                            ? const Center(child: Text('Sem dados no período', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
                                            : StatefulBuilder(
                                                builder: (context, setStateChart) {
                                                  return PieChart(
                                                    PieChartData(
                                                      pieTouchData: PieTouchData(
                                                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                                          setStateChart(() {
                                                            if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                                                              _touchedIndexPie = -1;
                                                              return;
                                                            }
                                                            _touchedIndexPie = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                                          });
                                                        },
                                                      ),
                                                      sectionsSpace: 3,
                                                      centerSpaceRadius: 60,
                                                      sections: statusCount.entries.toList().asMap().entries.map((entry) {
                                                        final isTouched = entry.key == _touchedIndexPie;
                                                        final fontSize = isTouched ? 20.0 : 14.0;
                                                        final radius = isTouched ? 70.0 : 60.0;
                                                        return PieChartSectionData(
                                                          color: _corDoStatus(entry.value.key),
                                                          value: entry.value.value.toDouble(),
                                                          title: '${entry.value.value}',
                                                          radius: radius,
                                                          titleStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: Colors.white),
                                                        );
                                                      }).toList(),
                                                    ),
                                                  );
                                                }
                                              ),
                                      ),
                                      // Legenda Inteligente
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        alignment: WrapAlignment.center,
                                        children: statusCount.keys.map((k) => Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(width: 12, height: 12, decoration: BoxDecoration(color: _corDoStatus(k), shape: BoxShape.circle)),
                                            const SizedBox(width: 4),
                                            Text(k, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                          ],
                                        )).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              if (isDesktop) const SizedBox(width: 24) else const SizedBox(height: 24),

                              // GRÁFICO DE BARRAS (TOP 5 FALHAS) COM NOMES COMPLETOS
                              Expanded(
                                flex: isDesktop ? 1 : 0,
                                child: Container(
                                  height: 380, // Aumentado para caber o texto
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                                  ),
                                  child: Column(
                                    children: [
                                      const Text('Top 5 Tipos de Falhas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2c3e50))),
                                      const Divider(),
                                      const SizedBox(height: 10),
                                      Expanded(
                                        child: top5Falhas.isEmpty
                                            ? const Center(child: Text('Sem dados no período', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
                                            : BarChart(
                                                BarChartData(
                                                  alignment: BarChartAlignment.spaceAround,
                                                  maxY: (top5Falhas.isNotEmpty ? top5Falhas.first.value.toDouble() : 10) * 1.3, 
                                                  barTouchData: BarTouchData(
                                                    enabled: true,
                                                    touchTooltipData: BarTouchTooltipData(
                                                      getTooltipColor: (group) => const Color(0xFF2c3e50),
                                                      tooltipPadding: const EdgeInsets.all(8),
                                                      tooltipMargin: 8,
                                                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                                        return BarTooltipItem(
                                                          '${top5Falhas[group.x.toInt()].key}\n',
                                                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                                          children: [
                                                            TextSpan(
                                                              text: '${rod.toY.toInt()} Ocorrências',
                                                              style: const TextStyle(color: Colors.yellowAccent, fontSize: 11, fontWeight: FontWeight.normal),
                                                            ),
                                                          ],
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  titlesData: FlTitlesData(
                                                    show: true,
                                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                                    leftTitles: AxisTitles(
                                                      sideTitles: SideTitles(
                                                        showTitles: true,
                                                        reservedSize: 40,
                                                        getTitlesWidget: (value, meta) {
                                                          if(value % 1 != 0) return const SizedBox.shrink(); // Apenas inteiros
                                                          return Text(value.toInt().toString(), style: const TextStyle(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold));
                                                        }
                                                      )
                                                    ),
                                                    bottomTitles: AxisTitles(
                                                      sideTitles: SideTitles(
                                                        showTitles: true,
                                                        reservedSize: 80, // Área aumentada para caber o texto completo
                                                        getTitlesWidget: (double value, TitleMeta meta) {
                                                          if (value.toInt() >= top5Falhas.length) return const SizedBox.shrink();
                                                          String title = top5Falhas[value.toInt()].key;
                                                          return Container(
                                                            width: 80,
                                                            padding: const EdgeInsets.only(top: 8.0),
                                                            child: Text(
                                                              title, 
                                                              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 8),
                                                              textAlign: TextAlign.center,
                                                              maxLines: 4,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                  gridData: FlGridData(
                                                    show: true,
                                                    drawVerticalLine: false,
                                                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade300, strokeWidth: 1, dashArray: [4, 4]),
                                                  ),
                                                  borderData: FlBorderData(show: false),
                                                  barGroups: top5Falhas.asMap().entries.map((entry) {
                                                    return BarChartGroupData(
                                                      x: entry.key,
                                                      barRods: [
                                                        BarChartRodData(
                                                          toY: entry.value.value.toDouble(),
                                                          gradient: const LinearGradient(
                                                            colors: [Colors.lightBlueAccent, Colors.blue],
                                                            begin: Alignment.bottomCenter,
                                                            end: Alignment.topCenter,
                                                          ),
                                                          width: 22,
                                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                                        ),
                                                      ],
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ];

                            return isDesktop ? Row(children: charts) : Column(children: charts);
                          },
                        ),
                        const SizedBox(height: 24),

                        // --- LISTAGEM INFERIOR (TABELA NORMAL OU AGRUPADA POR CHUVA) ---
                        if (_filtroDiaChuva) ...[
                          // VISÃO DIA DE CHUVA (Agrupada por Falha)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)]),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Detalhamento do Dia de Chuva (Ocorrências Climáticas)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2c3e50))),
                                const Divider(),
                                if (agrupadosChuva.isEmpty)
                                  const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Nenhuma ocorrência gerada pelo clima neste período.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))))
                                else
                                  ...agrupadosChuva.entries.map((grupo) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(border: Border.all(color: Colors.blueGrey.shade200), borderRadius: BorderRadius.circular(8)),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                                            child: Text('${grupo.key} (${grupo.value.length})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                                          ),
                                          ...grupo.value.map((oc) {
                                            String st = oc['status'] ?? 'Aberto';
                                            return ListTile(
                                              dense: true,
                                              leading: const Icon(Icons.traffic, color: Colors.blueGrey, size: 20),
                                              title: Text('${oc['semaforo'] ?? '---'} - ${oc['endereco'] ?? '---'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                              subtitle: Text('Nº ${oc['numero_da_ocorrencia'] ?? 'S/N'}', style: const TextStyle(color: Colors.blue)),
                                              trailing: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(color: _corDoStatus(_categorizarStatus(st)), borderRadius: BorderRadius.circular(4)),
                                                child: Text(st.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                              ),
                                            );
                                          })
                                        ],
                                      ),
                                    );
                                  })
                              ],
                            ),
                          )
                        ] else ...[
                          // VISÃO NORMAL (Tabela de Ocorrências com colunas exigidas)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Últimas Ocorrências do Período Selecionado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2c3e50))),
                                const Divider(),
                                
                                if (docs.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(20.0),
                                    child: Center(child: Text('Nenhuma ocorrência encontrada para o período/filtro selecionado.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))),
                                  )
                                else
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(const Color(0xFFf5f6f8)),
                                      headingTextStyle: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 13),
                                      columns: const [
                                        DataColumn(label: Text('Nº Ocorrência')),
                                        DataColumn(label: Text('Semáforo com endereço')),
                                        DataColumn(label: Text('Falha')),
                                        DataColumn(label: Text('Data Abertura')),
                                        DataColumn(label: Text('Data Fechamento')),
                                        DataColumn(label: Text('Status')),
                                      ],
                                      rows: docs.take(20).map((doc) {
                                        var d = doc.data() as Map<String, dynamic>;
                                        String st = d['status'] ?? 'Aberto';
                                        
                                        return DataRow(
                                          cells: [
                                            DataCell(Text((d['numero_da_ocorrencia'] ?? d['id'] ?? doc.id).toString().substring(0, 8), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                                            DataCell(SizedBox(width: 250, child: Text('${d['semaforo'] ?? '---'} - ${d['endereco'] ?? '---'}', maxLines: 2, overflow: TextOverflow.ellipsis))),
                                            DataCell(SizedBox(width: 150, child: Text(d['tipo_da_falha'] ?? '---', style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis))),
                                            DataCell(Text(_formatarDataHora(d['data_de_abertura']))),
                                            DataCell(Text(_formatarDataHora(d['data_de_finalizacao']))),
                                            DataCell(
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _corDoStatus(_categorizarStatus(st)),
                                                  borderRadius: BorderRadius.circular(4)
                                                ),
                                                child: Text(st.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                              )
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ]
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

  // WIDGET AUXILIAR DO KPI APRIMORADO COM ÍCONES E DESIGN IDÊNTICO À FOTO
  Widget _buildKpiCard(String title, String value, Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(bottom: BorderSide(color: color, width: 5)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -10,
            child: Icon(icon, size: 80, color: color.withValues(alpha: 0.15)),
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
                    Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF2f3b4c))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}