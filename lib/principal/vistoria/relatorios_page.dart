import 'dart:io';
import 'dart:convert'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// IMPORTAÇÃO DO MENU (LOGOUT E PERFIL)
import '../../widgets/menu_usuario.dart';

class RelatoriosPage extends StatefulWidget {
  const RelatoriosPage({super.key});

  @override
  State<RelatoriosPage> createState() => _RelatoriosPageState();
}

class _RelatoriosPageState extends State<RelatoriosPage> with SingleTickerProviderStateMixin {
  final User? user = FirebaseAuth.instance.currentUser;
  late TabController _tabController;

  // ==== ESTADOS DA ABA CONSULTA ====
  DateTime? _deConsulta;
  DateTime? _ateConsulta;
  String _rotaConsulta = 'Todas';
  final TextEditingController _semaforoController = TextEditingController();
  bool _filtrosAplicadosConsulta = false;

  // ==== ESTADOS DA ABA EXPORTAÇÃO ====
  DateTime? _deExport;
  DateTime? _ateExport;
  String _rotaExport = 'Selecione';

  // ==== ESTADOS DA ABA PENDÊNCIAS ====
  DateTime _mesPendencia = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _rotaPendencia = 'Todas';

  final Map<String, String> _cacheNomes = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _semaforoController.dispose();
    super.dispose();
  }

  Future<String> _getNomeVistoriador(String uid) async {
    if (_cacheNomes.containsKey(uid)) return _cacheNomes[uid]!;
    try {
      var doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        String nome = doc.data()!['nome'] ?? doc.data()!['nome_completo'] ?? 'Vistoriador';
        _cacheNomes[uid] = nome;
        return nome;
      }
    } catch (e) {
      // Ignora erro
    }
    return 'Desconhecido';
  }

  Future<void> _selecionarData(BuildContext context, {bool isDe = true, required String tipoAba}) async {
    DateTime initial = DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: isDe ? 'SELECIONE A DATA INICIAL' : 'SELECIONE A DATA FINAL',
    );

    if (picked != null) {
      setState(() {
        if (tipoAba == 'Consulta') {
          if (isDe) _deConsulta = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
          else _ateConsulta = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
          _filtrosAplicadosConsulta = false;
        } else if (tipoAba == 'Exportacao') {
          if (isDe) _deExport = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
          else _ateExport = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
  }

  Future<void> _selecionarMesAnoDialog(BuildContext context) async {
    int mesSelecionado = _mesPendencia.month;
    int anoSelecionado = _mesPendencia.year;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Selecione o Mês e Ano', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  DropdownButton<int>(
                    value: mesSelecionado,
                    items: List.generate(12, (index) => DropdownMenuItem(value: index + 1, child: Text((index + 1).toString().padLeft(2, '0')))),
                    onChanged: (val) => setStateDialog(() => mesSelecionado = val!),
                  ),
                  const Text('/', style: TextStyle(fontSize: 20)),
                  DropdownButton<int>(
                    value: anoSelecionado,
                    items: List.generate(10, (index) => DropdownMenuItem(value: 2024 + index, child: Text((2024 + index).toString()))),
                    onChanged: (val) => setStateDialog(() => anoSelecionado = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                  onPressed: () {
                    setState(() {
                      _mesPendencia = DateTime(anoSelecionado, mesSelecionado, 1);
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Confirmar'),
                )
              ],
            );
          }
        );
      }
    );
  }

  void _limparFiltrosConsulta() {
    setState(() {
      _deConsulta = null;
      _ateConsulta = null;
      _rotaConsulta = 'Todas';
      _semaforoController.clear();
      _filtrosAplicadosConsulta = false;
    });
  }

  Widget _buildBotaoData(String label, DateTime? data, VoidCallback onTap, {String formato = 'dd/MM/yy'}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 18, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data == null ? '$label: Selecione' : '$label: ${DateFormat(formato).format(data)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: data == null ? Colors.grey : Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirFotoTelaCheia(String url) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black87,
          insetPadding: const EdgeInsets.all(0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(url, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
              ),
              Positioned(
                top: 20, right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  // ==== RODAPÉ FIXO DO PDF ====
  pw.Widget _buildRodapePDF(pw.Context context, String dataHora) {
    return pw.Container(
      alignment: pw.Alignment.bottomCenter,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.SizedBox(width: 50), // Espaçador para manter o texto do meio centralizado
              pw.Expanded(
                child: pw.Text('Relatório gerado pelo aplicativo Vistoria CTTU ($dataHora)', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ),
              pw.SizedBox(width: 50, child: pw.Text('Pág. ${context.pageNumber} / ${context.pagesCount}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
            ]
          )
        ]
      )
    );
  }

  Future<void> _exportarPDFIndividual(Map<String, dynamic> vistoria, String nomeVistoriador) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Baixando fotos e gerando PDF...'), backgroundColor: Colors.teal));
    try {
      bool temFalha = vistoria['teve_anormalidade'] == true;
      List<dynamic> urlsFotos = vistoria['fotos'] ?? [];
      List<pw.ImageProvider> imagensPdf = [];

      for (String url in urlsFotos) {
        try {
          final imageBytes = await networkImage(url);
          imagensPdf.add(imageBytes);
        } catch (e) {
          debugPrint('Erro ao baixar imagem pro pdf: $e');
        }
      }

      String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

      await Printing.layoutPdf(
        name: 'Ficha_Semaforo_${vistoria['semaforo_id']}.pdf',
        onLayout: (PdfPageFormat format) async {
          final pdf = pw.Document();
          
          pdf.addPage(
            pw.MultiPage(
              pageFormat: format, // <- FORMATO DINÂMICO
              margin: const pw.EdgeInsets.only(left: 32, right: 32, top: 32, bottom: 20),
              footer: (pw.Context context) => _buildRodapePDF(context, dataHoraAtual),
              build: (pw.Context context) {
                return [
                  pw.Row(
                    children: [
                      pw.Container(width: 30, height: 30, decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: temFalha ? PdfColors.red : PdfColors.green)),
                      pw.SizedBox(width: 12),
                      pw.Text('Semáforo Nº ${vistoria['semaforo_id']}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                    ]
                  ),
                  pw.Divider(thickness: 2, height: 32),
                  pw.Text('Vistoriador: $nomeVistoriador', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Endereço: ${vistoria['semaforo_endereco']}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('Início: ${vistoria['data_hora_inicio']}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('Fim: ${vistoria['data_hora_fim']}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('Coordenadas GPS: ${vistoria['gps_coordenadas']}', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 16),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12), width: double.infinity, decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(8)),
                    child: pw.Text(vistoria['resumo_checklist'] ?? 'Checklist verificado.', style: pw.TextStyle(color: PdfColors.blue800, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12), width: double.infinity,
                    decoration: pw.BoxDecoration(color: temFalha ? PdfColors.red50 : PdfColors.green50, border: pw.Border.all(color: temFalha ? PdfColors.red : PdfColors.green), borderRadius: pw.BorderRadius.circular(8)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(temFalha ? 'FALHA REGISTRADA:' : 'STATUS:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: temFalha ? PdfColors.red : PdfColors.green)),
                        pw.Text(vistoria['falha_registrada'] ?? 'Nenhuma', style: const pw.TextStyle(fontSize: 14)),
                        pw.SizedBox(height: 8),
                        pw.Text('Detalhes:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: temFalha ? PdfColors.red : PdfColors.green)),
                        pw.Text(vistoria['detalhes_ocorrencia'] ?? 'Sem detalhes', style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  if (imagensPdf.isNotEmpty) ...[
                    pw.SizedBox(height: 24),
                    pw.Text('Fotos da Ocorrência:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                    pw.SizedBox(height: 12),
                    pw.Wrap(
                      spacing: 12, runSpacing: 12,
                      children: imagensPdf.map((img) => pw.Container(width: 150, height: 150, decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey), borderRadius: pw.BorderRadius.circular(8), image: pw.DecorationImage(image: img, fit: pw.BoxFit.cover)))).toList(),
                    )
                  ]
                ];
              }
            )
          );
          return pdf.save();
        }
      );
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar PDF da ficha!'), backgroundColor: Colors.red));
    }
  }

  Future<void> _exportarPDFGlobal(List<Map<String, dynamic>> vistorias, String rotaNumero) async {
    if (vistorias.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando PDF Global...'), backgroundColor: Colors.teal));
    try {
      String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

      await Printing.layoutPdf(
        name: 'Relatorio_Rota$rotaNumero.pdf',
        onLayout: (PdfPageFormat format) async {
          final pdf = pw.Document();
          
          pdf.addPage(
            pw.MultiPage(
              pageFormat: format, // <- FORMATO DINÂMICO
              margin: const pw.EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 20),
              footer: (pw.Context context) => _buildRodapePDF(context, dataHoraAtual),
              build: (pw.Context context) {
                return [
                  pw.Header(level: 0, child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Relatório de Vistorias', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('Rota: $rotaNumero', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    ]
                  )),
                  pw.SizedBox(height: 16),
                  pw.TableHelper.fromTextArray(
                    context: context,
                    headers: ['Semáforo', 'Vistoriador', 'Endereço', 'Início', 'Fim', 'Status', 'Falha', 'Detalhes', 'Fotos (Links)'],
                    data: vistorias.map((v) {
                      return [ 
                        v['semaforo_id']?.toString() ?? '', v['nome_vistoriador']?.toString() ?? '', v['semaforo_endereco']?.toString() ?? '', 
                        v['data_hora_inicio']?.toString() ?? '', v['data_hora_fim']?.toString() ?? '', v['teve_anormalidade'] == true ? 'COM FALHA' : 'OK', 
                        v['falha_registrada'] ?? '-', v['detalhes_ocorrencia']?.toString().replaceAll('\n', ' ') ?? '-', (v['fotos'] ?? []).join('\n\n')
                      ];
                    }).toList(),
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
                    cellAlignment: pw.Alignment.centerLeft, cellStyle: const pw.TextStyle(fontSize: 7),
                    columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1.2), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1), 4: const pw.FlexColumnWidth(1), 5: const pw.FlexColumnWidth(1), 6: const pw.FlexColumnWidth(1.2), 7: const pw.FlexColumnWidth(1.5), 8: const pw.FlexColumnWidth(2) }
                  ),
                ];
              }
            )
          );
          return pdf.save();
        }
      );
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar PDF!'), backgroundColor: Colors.red));
    }
  }

  Future<void> _exportarExcelGlobal(List<Map<String, dynamic>> vistorias) async {
    if (vistorias.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando Excel...'), backgroundColor: Colors.green));
    try {
      String csv = '\uFEFF'; 
      csv += 'SEMAFORO;VISTORIADOR;ENDERECO;INICIO;FIM;COORDENADAS;STATUS;FALHA;DETALHES;FOTOS\n';
      for (var v in vistorias) {
        String status = v['teve_anormalidade'] == true ? 'COM FALHA' : 'OK';
        csv += '${v['semaforo_id']};${v['nome_vistoriador'] ?? ''};${v['semaforo_endereco']};${v['data_hora_inicio']};${v['data_hora_fim']};${v['gps_coordenadas']};$status;${v['falha_registrada']};${v['detalhes_ocorrencia']?.toString().replaceAll('\n', ' ')};${(v['fotos'] ?? []).join(', ')}\n';
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/Relatorio_Vistorias.xls';
      final file = File(path);
      await file.writeAsBytes(utf8.encode(csv));
      await Share.shareXFiles([XFile(path)], text: 'Planilha de Vistorias.');
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar Excel!'), backgroundColor: Colors.red));
    }
  }

  Future<void> _realizarExportacao(String tipoExportacao, Map<String, String> mapaRotas) async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('vistorias').where('criado_em', isGreaterThanOrEqualTo: _deExport).where('criado_em', isLessThanOrEqualTo: _ateExport).orderBy('criado_em', descending: true).get();
    List<Map<String, dynamic>> vistoriasFiltradas = [];
    String rotaSelecionadaLimpa = _rotaExport.replaceFirst(RegExp(r'^0+'), '');

    for (var doc in snapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      String rotaDesteSemaforo = mapaRotas[data['semaforo_id'].toString()] ?? '';
      if (_rotaExport == 'Todas' || rotaDesteSemaforo == rotaSelecionadaLimpa) {
        data['nome_vistoriador'] = await _getNomeVistoriador(data['vistoriador_uid'] ?? '');
        vistoriasFiltradas.add(data);
      }
    }
    if (vistoriasFiltradas.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma vistoria encontrada para este filtro!'), backgroundColor: Colors.orange));
      return;
    }
    if (tipoExportacao == 'PDF') await _exportarPDFGlobal(vistoriasFiltradas, _rotaExport);
    else await _exportarExcelGlobal(vistoriasFiltradas);
  }

  Future<void> _exportarPendenciasPDF(Map<String, List<Map<String, dynamic>>> pendentesPorRota, Map<String, Map<String, dynamic>> statsPorRota, String mesFiltro) async {
    if (pendentesPorRota.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando PDF de Semáforos não vistoriados...'), backgroundColor: Colors.red));
    try {
      String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());

      await Printing.layoutPdf(
        name: 'Omissões_$mesFiltro.pdf',
        onLayout: (PdfPageFormat format) async {
          final pdf = pw.Document();
          
          pdf.addPage(
            pw.MultiPage(
              pageFormat: format, // <- FORMATO DINÂMICO
              margin: const pw.EdgeInsets.only(left: 32, right: 32, top: 32, bottom: 20),
              footer: (pw.Context context) => _buildRodapePDF(context, dataHoraAtual),
              build: (pw.Context context) {
                return [
                  pw.Header(level: 0, child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Relatório de Semáforos Não Vistoriados', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                      pw.SizedBox(height: 4),
                      pw.Text('Mês de referência: $mesFiltro', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                    ]
                  )),
                  pw.SizedBox(height: 16),
                  pw.TableHelper.fromTextArray(
                    context: context,
                    headers: ['Rota', 'Qtd. Não Vistoriados', 'Semáforos (IDs)'],
                    data: pendentesPorRota.keys.map((rota) {
                      return [ 'Rota $rota', statsPorRota[rota]!['omitidos'].toString(), pendentesPorRota[rota]!.map((e) => e['id'].toString()).join(', ') ];
                    }).toList(),
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
                    cellAlignment: pw.Alignment.centerLeft,
                    columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1.5), 2: const pw.FlexColumnWidth(3) }
                  ),
                ];
              }
            )
          );
          return pdf.save();
        }
      );
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar PDF de Pendências!'), backgroundColor: Colors.red));
    }
  }

  Future<void> _exportarPendenciasExcel(Map<String, List<Map<String, dynamic>>> pendentesPorRota, Map<String, Map<String, dynamic>> statsPorRota, String mesFiltro) async {
    if (pendentesPorRota.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando Planilha de Semáforos Não Vistoriados...'), backgroundColor: Colors.green));
    try {
      String csv = '\uFEFF'; 
      csv += 'Mês do Filtro:;$mesFiltro\n\n';
      csv += 'ROTA;QTD NAO VISTORIADOS;SEMAFOROS PENDENTES\n';
      for (var rota in pendentesPorRota.keys) {
        csv += 'Rota $rota;${statsPorRota[rota]!['omitidos']};${pendentesPorRota[rota]!.map((e) => e['id'].toString()).join(', ')}\n';
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Omissões_${mesFiltro.replaceAll('/', '-')}.xls');
      await file.writeAsBytes(utf8.encode(csv));
      await Share.shareXFiles([XFile(file.path)], text: 'Lista de semáforos não vistoriados - $mesFiltro.');
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao exportar Pendências!'), backgroundColor: Colors.red));
    }
  }

  void _mostrarDetalhesVistoriaAnterior(Map<String, dynamic> vistoria, String rotaExibicao, String nomeVistoriador) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        bool temFalha = vistoria['teve_anormalidade'] == true;
        List<dynamic> fotos = vistoria['fotos'] ?? [];
        return DraggableScrollableSheet(
          initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(temFalha ? Icons.warning_amber_rounded : Icons.check_circle, color: temFalha ? Colors.red : Colors.green, size: 36),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Semáforo Nº ${vistoria['semaforo_id']}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800))),
                      ],
                    ),
                    const Divider(thickness: 2, height: 32),
                    _buildInfoRow('Vistoriador', nomeVistoriador),
                    _buildInfoRow('Endereço', vistoria['semaforo_endereco']),
                    _buildInfoRow('Início', vistoria['data_hora_inicio']),
                    _buildInfoRow('Fim', vistoria['data_hora_fim']),
                    _buildInfoRow('Coordenadas GPS', vistoria['gps_coordenadas']),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.playlist_add_check, color: Colors.blue, size: 28),
                          const SizedBox(width: 12),
                          Expanded(child: Text(vistoria['resumo_checklist'] ?? 'Checklist verificado.', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12), width: double.infinity, decoration: BoxDecoration(color: temFalha ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: temFalha ? Colors.red : Colors.green)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(temFalha ? 'FALHA REGISTRADA:' : 'STATUS:', style: TextStyle(fontWeight: FontWeight.bold, color: temFalha ? Colors.red : Colors.green)),
                          Text(vistoria['falha_registrada'] ?? 'Nenhuma', style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('Detalhes:', style: TextStyle(fontWeight: FontWeight.bold, color: temFalha ? Colors.red : Colors.green)),
                          Text(vistoria['detalhes_ocorrencia'] ?? 'Sem detalhes', style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                    if (fotos.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const Text('Fotos da Ocorrência:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12, runSpacing: 12, 
                        children: fotos.map((url) => GestureDetector(
                          onTap: () => _abrirFotoTelaCheia(url), // ABRIR FOTO EM TELA CHEIA
                          child: Container(
                            width: 100, height: 100, 
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey), image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover))
                          ),
                        )).toList()
                      )
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white), icon: const Icon(Icons.picture_as_pdf), label: const Text('Exportar PDF Desta Vistoria', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => _exportarPDFIndividual(vistoria, nomeVistoriador),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade300, foregroundColor: Colors.black87), onPressed: () => Navigator.pop(context), child: const Text('Fechar Ficha', style: TextStyle(fontWeight: FontWeight.bold))))
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(text: TextSpan(style: const TextStyle(color: Colors.black87, fontSize: 15), children: [
        TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)), TextSpan(text: value ?? '-'),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    Query queryConsulta = FirebaseFirestore.instance.collection('vistorias').orderBy('criado_em', descending: true);
    if (_deConsulta != null && _ateConsulta != null) queryConsulta = queryConsulta.where('criado_em', isGreaterThanOrEqualTo: _deConsulta, isLessThanOrEqualTo: _ateConsulta);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios e Exportações', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade500,
        foregroundColor: Colors.white,
        actions: const [MenuUsuario()], // MENU ADICIONADO AQUI
        bottom: TabBar(
          controller: _tabController, labelColor: Colors.white, unselectedLabelColor: Colors.white60, indicatorColor: Colors.white,
          tabs: const [ Tab(icon: Icon(Icons.list_alt), text: 'Consulta'), Tab(icon: Icon(Icons.download), text: 'Exportação'), Tab(icon: Icon(Icons.warning_amber_rounded), text: 'Pendências') ],
        ),
      ),
      
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('rotas').orderBy('numero').snapshots(),
        builder: (context, snapshotRotas) {
          if (!snapshotRotas.hasData) return const Center(child: CircularProgressIndicator());
          List<String> listaRotasOptions = ['Todas'];
          listaRotasOptions.addAll(snapshotRotas.data!.docs.map((r) => r['numero'].toString()));

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('semaforos').snapshots(),
            builder: (context, snapshotSemaforos) {
              if (!snapshotSemaforos.hasData) return const Center(child: CircularProgressIndicator());

              Map<String, String> mapaRotasSemaforos = {};
              List<Map<String, dynamic>> todosSemaforosData = [];
              for (var doc in snapshotSemaforos.data!.docs) {
                var data = doc.data() as Map<String, dynamic>;
                mapaRotasSemaforos[data['id'].toString()] = (data['rota'] ?? '').toString().replaceFirst(RegExp(r'^0+'), ''); 
                todosSemaforosData.add(data);
              }

              return TabBarView(
                controller: _tabController,
                children: [
                  
                  // ================= ABA 1: CONSULTA =================
                  Column(
                    children: [
                      Container(
                        color: Colors.blue.shade50, padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(children: [ _buildBotaoData('De', _deConsulta, () => _selecionarData(context, isDe: true, tipoAba: 'Consulta')), const SizedBox(width: 8), _buildBotaoData('Até', _ateConsulta, () => _selecionarData(context, isDe: false, tipoAba: 'Consulta')) ]),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: InputDecorator(
                                    decoration: InputDecoration(labelText: 'Rota', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true, value: listaRotasOptions.contains(_rotaConsulta) ? _rotaConsulta : 'Todas',
                                        items: listaRotasOptions.map((r) => DropdownMenuItem(value: r, child: Text(r == 'Todas' ? 'Todas Rotas' : 'Rota $r'))).toList(),
                                        onChanged: (val) => setState(() { _rotaConsulta = val!; _filtrosAplicadosConsulta = false; }),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 1,
                                  child: TextField(
                                    controller: _semaforoController, onChanged: (val) => setState(() => _filtrosAplicadosConsulta = false),
                                    decoration: InputDecoration(labelText: 'Nº Semáforo', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                                onPressed: () {
                                  if (_deConsulta == null || _ateConsulta == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha a data De e Até!'), backgroundColor: Colors.orange)); return; }
                                  setState(() => _filtrosAplicadosConsulta = true);
                                },
                                child: const Text('Aplicar Filtros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                            ),
                            if (_deConsulta != null || _ateConsulta != null || _rotaConsulta != 'Todas' || _semaforoController.text.isNotEmpty) ...[
                              TextButton.icon(style: TextButton.styleFrom(foregroundColor: Colors.red), icon: const Icon(Icons.clear), label: const Text('Limpar Filtros', style: TextStyle(fontWeight: FontWeight.bold)), onPressed: _limparFiltrosConsulta)
                            ]
                          ],
                        ),
                      ),
                      
                      Expanded(
                        child: !_filtrosAplicadosConsulta 
                          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.manage_search, size: 80, color: Colors.grey.shade400), const SizedBox(height: 16), const Text('Preencha os filtros acima e clique em Aplicar.', style: TextStyle(color: Colors.grey, fontSize: 16)) ]))
                          : StreamBuilder<QuerySnapshot>(
                              stream: queryConsulta.snapshots(),
                              builder: (context, snapshotVistorias) {
                                if (snapshotVistorias.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                                var vistorias = snapshotVistorias.data!.docs;
                                String textoPesquisa = _semaforoController.text.trim().toLowerCase();
                                if (textoPesquisa.isNotEmpty) vistorias = vistorias.where((doc) => (doc['semaforo_id'] ?? '').toString().toLowerCase().contains(textoPesquisa)).toList();
                                if (_rotaConsulta != 'Todas') {
                                  String rotaLimpa = _rotaConsulta.replaceFirst(RegExp(r'^0+'), '');
                                  vistorias = vistorias.where((doc) => (mapaRotasSemaforos[doc['semaforo_id'].toString()] ?? '') == rotaLimpa).toList();
                                }
                                if (vistorias.isEmpty) return const Center(child: Text('Nenhuma vistoria encontrada para estes filtros.', style: TextStyle(color: Colors.grey, fontSize: 16)));

                                return ListView.builder(
                                  padding: const EdgeInsets.all(12), itemCount: vistorias.length,
                                  itemBuilder: (context, index) {
                                    var vistoria = vistorias[index].data() as Map<String, dynamic>;
                                    String idSemaforo = vistoria['semaforo_id']?.toString() ?? 'S/N';
                                    String uidVistoriador = vistoria['vistoriador_uid'] ?? '';
                                    bool temFalha = vistoria['teve_anormalidade'] == true;
                                    String rotaExibicao = mapaRotasSemaforos[idSemaforo] ?? 'Sem Rota';
                                    Color corFundo = temFalha ? Colors.red.shade50 : Colors.green.shade50;
                                    Color corIcone = temFalha ? Colors.red.shade700 : Colors.green.shade700;

                                    return FutureBuilder<String>(
                                      future: _getNomeVistoriador(uidVistoriador),
                                      builder: (context, snapshotNome) {
                                        String nome = snapshotNome.data ?? 'Carregando...';
                                        return Card(
                                          color: corFundo, elevation: 1, margin: const EdgeInsets.only(bottom: 8),
                                          child: ListTile(
                                            leading: CircleAvatar(backgroundColor: corIcone, child: Text(idSemaforo, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                            title: Text('Semáforo $idSemaforo (Rota $rotaExibicao)', style: TextStyle(fontWeight: FontWeight.bold, color: corIcone)),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(vistoria['semaforo_endereco'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                                                Text('Data: ${vistoria['data_hora_inicio'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                                Text('Vistoriador: $nome', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                              ],
                                            ),
                                            trailing: Icon(temFalha ? Icons.warning_amber_rounded : Icons.check_circle, color: corIcone),
                                            onTap: () => _mostrarDetalhesVistoriaAnterior(vistoria, rotaExibicao, nome),
                                          ),
                                        );
                                      }
                                    );
                                  },
                                );
                              }
                            ),
                      )
                    ],
                  ),

                  // ================= ABA 2: EXPORTAÇÃO =================
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Filtros para Exportação', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey), textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        Row(children: [ _buildBotaoData('De', _deExport, () => _selecionarData(context, isDe: true, tipoAba: 'Exportacao')), const SizedBox(width: 8), _buildBotaoData('Até', _ateExport, () => _selecionarData(context, isDe: false, tipoAba: 'Exportacao')) ]),
                        const SizedBox(height: 16),
                        InputDecorator(
                          decoration: InputDecoration(labelText: 'Escolha a Rota', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true, value: listaRotasOptions.contains(_rotaExport) ? _rotaExport : 'Selecione',
                              items: [ const DropdownMenuItem(value: 'Selecione', child: Text('Selecione uma rota...')), ...listaRotasOptions.map((r) => DropdownMenuItem(value: r, child: Text(r == 'Todas' ? 'Todas as Rotas' : 'Rota $r'))) ],
                              onChanged: (val) => setState(() => _rotaExport = val!),
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        Builder(
                          builder: (context) {
                            bool liberado = _deExport != null && _ateExport != null && _rotaExport != 'Selecione';
                            return Column(
                              children: [
                                SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: const Icon(Icons.picture_as_pdf, size: 28), label: const Text('Exportar PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), onPressed: liberado ? () => _realizarExportacao('PDF', mapaRotasSemaforos) : null)),
                                const SizedBox(height: 16),
                                SizedBox(width: double.infinity, height: 60, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: const Icon(Icons.grid_on, size: 28), label: const Text('Exportar Excel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), onPressed: liberado ? () => _realizarExportacao('EXCEL', mapaRotasSemaforos) : null)),
                                if (!liberado) ...[ const SizedBox(height: 16), const Text('Preencha as datas e selecione a rota para liberar a exportação.', textAlign: TextAlign.center, style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic)) ]
                              ],
                            );
                          }
                        )
                      ],
                    ),
                  ),

                  // ================= ABA 3: PENDÊNCIAS =================
                  Column(
                    children: [
                      Container(
                        color: Colors.red.shade50, padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Semáforos não vistoriados no Mês', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                            const SizedBox(height: 4),
                            const Text('Verifique os semáforos que ficaram o mês inteiro sem vistoria.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildBotaoData('Mês', _mesPendencia, () => _selecionarMesAnoDialog(context), formato: 'MM/yyyy'),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: InputDecorator(
                                    decoration: InputDecoration(labelText: 'Rota', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true, value: listaRotasOptions.contains(_rotaPendencia) ? _rotaPendencia : 'Todas',
                                        items: listaRotasOptions.map((r) => DropdownMenuItem(value: r, child: Text(r == 'Todas' ? 'Todas Rotas' : 'Rota $r'))).toList(),
                                        onChanged: (val) => setState(() { _rotaPendencia = val!; }),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('vistorias')
                            .where('criado_em', isGreaterThanOrEqualTo: DateTime(_mesPendencia.year, _mesPendencia.month, 1))
                            .where('criado_em', isLessThanOrEqualTo: DateTime(_mesPendencia.year, _mesPendencia.month + 1, 0, 23, 59, 59))
                            .snapshots(),
                          builder: (context, snapshotVistoriasDoMes) {
                            if (snapshotVistoriasDoMes.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                            Set<String> idsVistoriadosNoMes = snapshotVistoriasDoMes.data!.docs.map((doc) => doc['semaforo_id'].toString()).toSet();
                            String rotaFiltro = _rotaPendencia.replaceFirst(RegExp(r'^0+'), '');

                            Map<String, List<Map<String, dynamic>>> semaforosAgrupados = {};
                            for (var sem in todosSemaforosData) {
                              String rotaSem = (sem['rota'] ?? '').toString().replaceFirst(RegExp(r'^0+'), '');
                              if (_rotaPendencia == 'Todas' || rotaSem == rotaFiltro) {
                                if (!semaforosAgrupados.containsKey(rotaSem)) semaforosAgrupados[rotaSem] = [];
                                semaforosAgrupados[rotaSem]!.add(sem);
                              }
                            }

                            Map<String, List<Map<String, dynamic>>> pendentesPorRota = {};
                            Map<String, Map<String, dynamic>> statsPorRota = {};
                            int totalPendentes = 0;

                            for (var rota in semaforosAgrupados.keys) {
                              var semaforosDaRota = semaforosAgrupados[rota]!;
                              int totalRota = semaforosDaRota.length;
                              
                              List<Map<String, dynamic>> omitidos = semaforosDaRota.where((s) => !idsVistoriadosNoMes.contains(s['id'].toString())).toList();
                              
                              if (omitidos.isNotEmpty) {
                                pendentesPorRota[rota] = omitidos;
                                totalPendentes += omitidos.length;
                              }

                              int qtdOmitidos = omitidos.length;
                              int qtdVistoriados = totalRota - qtdOmitidos;

                              statsPorRota[rota] = {
                                'total': totalRota,
                                'vistoriados': qtdVistoriados,
                                'omitidos': qtdOmitidos,
                                'perc_vistoriados': totalRota == 0 ? 0.0 : (qtdVistoriados / totalRota) * 100,
                                'perc_omitidos': totalRota == 0 ? 0.0 : (qtdOmitidos / totalRota) * 100,
                              };
                            }

                            var rotasOrdenadas = pendentesPorRota.keys.toList()..sort((a,b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
                            String mesFormatado = DateFormat('MM/yyyy').format(_mesPendencia);

                            return Column(
                              children: [
                                Container(
                                  width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.grey.shade200,
                                  child: Text('Total Geral de Semáforos não vistoriados no Mês: $totalPendentes', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                                ),
                                Expanded(
                                  child: rotasOrdenadas.isEmpty
                                    ? const Center(child: Text('Todos semáforos vistoriados no mês! Meta 100% cumprida.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)))
                                    : ListView.builder(
                                        padding: const EdgeInsets.all(12),
                                        itemCount: rotasOrdenadas.length,
                                        itemBuilder: (context, index) {
                                          String rotaListada = rotasOrdenadas[index];
                                          var semaforosDessaRota = pendentesPorRota[rotaListada]!;
                                          var stats = statsPorRota[rotaListada]!;
                                          
                                          String idsPendentes = semaforosDessaRota.map((s) => s['id']).join(', ');

                                          return Card(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            child: Padding(
                                              padding: const EdgeInsets.all(16.0),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  CircleAvatar(
                                                    radius: 26,
                                                    backgroundColor: Colors.red.shade100, 
                                                    child: Text(rotaListada, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 18))
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Text('Vistoriados: ${stats['vistoriados']} (${stats['perc_vistoriados'].toStringAsFixed(1)}%)', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                                                            Text('Pendentes: ${stats['omitidos']} (${stats['perc_omitidos'].toStringAsFixed(1)}%)', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                                                          ],
                                                        ),
                                                        const Divider(height: 16),
                                                        const Text('Semáforos Não Vistoriados:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                                                        const SizedBox(height: 4),
                                                        Text(idsPendentes, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                ),
                                if (rotasOrdenadas.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
                                            icon: const Icon(Icons.picture_as_pdf),
                                            label: const Text('PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                                            onPressed: () => _exportarPendenciasPDF(pendentesPorRota, statsPorRota, mesFormatado),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
                                            icon: const Icon(Icons.grid_on),
                                            label: const Text('Excel', style: TextStyle(fontWeight: FontWeight.bold)),
                                            onPressed: () => _exportarPendenciasExcel(pendentesPorRota, statsPorRota, mesFormatado),
                                          ),
                                        )
                                      ],
                                    ),
                                  )
                              ],
                            );
                          }
                        ),
                      )
                    ],
                  ),

                ],
              );
            }
          );
        }
      ),
    );
  }
}