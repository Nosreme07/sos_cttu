import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as excel_pkg; // Para exportação XLSX

class GerenciarRotasPage extends StatefulWidget {
  const GerenciarRotasPage({super.key});

  @override
  State<GerenciarRotasPage> createState() => _GerenciarRotasPageState();
}

class _GerenciarRotasPageState extends State<GerenciarRotasPage> {
  final TextEditingController _buscaGlobalController = TextEditingController();
  String _termoBuscaGlobal = '';

  @override
  void initState() {
    super.initState();
    _buscaGlobalController.addListener(() {
      setState(() {
        _termoBuscaGlobal = _buscaGlobalController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _buscaGlobalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Rotas', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.purple.shade500,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Barra de Pesquisa Global
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _buscaGlobalController,
              decoration: InputDecoration(
                hintText: 'Descobrir rota do semáforo...',
                prefixIcon: const Icon(Icons.search, color: Colors.purple),
                suffixIcon: _termoBuscaGlobal.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _buscaGlobalController.clear())
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: Colors.purple.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.purple, width: 2)),
              ),
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('semaforos').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.purple));
                
                final todosSemaforos = snapshot.data!.docs;

                // ==========================================
                // SE ESTIVER PESQUISANDO: Mostra os Semáforos
                // ==========================================
                if (_termoBuscaGlobal.isNotEmpty) {
                  var semaforosFiltrados = todosSemaforos.where((doc) {
                    var data = doc.data() as Map<String, dynamic>;
                    String rawId = data['id']?.toString() ?? data['numero']?.toString() ?? '0';
                    String numeroSemaforo = rawId.padLeft(3, '0').toLowerCase();
                    String endereco = (data['endereco'] ?? data['cruzamento'] ?? '').toString().toLowerCase();
                    
                    return numeroSemaforo.contains(_termoBuscaGlobal) || endereco.contains(_termoBuscaGlobal);
                  }).toList();

                  if (semaforosFiltrados.isEmpty) {
                    return const Center(child: Text('Nenhum semáforo encontrado com este termo.', style: TextStyle(color: Colors.grey)));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: semaforosFiltrados.length,
                    itemBuilder: (context, index) {
                      var data = semaforosFiltrados[index].data() as Map<String, dynamic>;
                      String rawId = data['id']?.toString() ?? '0';
                      String numeroFormatado = rawId.padLeft(3, '0');
                      String endereco = data['endereco'] ?? data['cruzamento'] ?? 'Sem endereço';
                      String rota = data['rota']?.toString() ?? 'S/R';

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: const Icon(Icons.traffic, color: Colors.blue),
                          ),
                          title: Text('Semáforo: $numeroFormatado', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(endereco, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.purple.shade200)),
                                child: Text('Pertence à Rota $rota', style: TextStyle(color: Colors.purple.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                              )
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          onTap: () {
                            if (rota != 'S/R') {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => DetalheRotaPage(rotaNumero: rota)));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este semáforo não possui rota cadastrada.')));
                            }
                          },
                        ),
                      );
                    },
                  );
                }

                // ==========================================
                // SE NÃO ESTIVER PESQUISANDO: Mostra as Rotas
                // ==========================================
                Set<String> rotasUnicas = {};
                for (var doc in todosSemaforos) {
                  var data = doc.data() as Map<String, dynamic>;
                  if (data['rota'] != null && data['rota'].toString().trim().isNotEmpty) {
                    rotasUnicas.add(data['rota'].toString().trim());
                  }
                }
                
                List<String> rotas = rotasUnicas.toList();
                if (rotas.isEmpty) return const Center(child: Text('Nenhuma rota encontrada nos semáforos.'));

                rotas.sort((a, b) => a.compareTo(b));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: rotas.length,
                  itemBuilder: (context, index) {
                    String rota = rotas[index];
                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.shade100,
                          child: const Icon(Icons.route, color: Colors.purple),
                        ),
                        title: Text('Rota $rota', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        subtitle: const Text('Organizar ordem'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DetalheRotaPage(rotaNumero: rota),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}

class DetalheRotaPage extends StatefulWidget {
  final String rotaNumero;
  const DetalheRotaPage({super.key, required this.rotaNumero});

  @override
  State<DetalheRotaPage> createState() => _DetalheRotaPageState();
}

class _DetalheRotaPageState extends State<DetalheRotaPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _semaforos = [];
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';

  @override
  void initState() {
    super.initState();
    _carregarSemaforosDaRota();
    _buscaController.addListener(() => setState(() => _termoBusca = _buscaController.text.toLowerCase()));
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _carregarSemaforosDaRota() async {
    try {
      var query = await FirebaseFirestore.instance
          .collection('semaforos')
          .where('rota', isEqualTo: widget.rotaNumero)
          .get();

      List<Map<String, dynamic>> lista = query.docs.map((doc) {
        var data = doc.data();
        
        // AJUSTE: ID com 3 dígitos (001, 050, 150)
        String rawId = data['id']?.toString() ?? '0';
        String numeroSemaforo = rawId.padLeft(3, '0');
        
        return {
          'db_id': doc.id,
          'numero': numeroSemaforo,
          'endereco': data['endereco'] ?? data['cruzamento'] ?? 'Sem endereço',
          'ordem': data['ordem_vistoria'] ?? 999,
          'lado': data['lado_vistoria'] ?? 'A', 
        };
      }).toList();

      lista.sort((a, b) => (a['ordem'] as int).compareTo(b['ordem'] as int));

      setState(() {
        _semaforos = lista;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _semaforosExibidos {
    if (_termoBusca.isEmpty) return _semaforos;
    return _semaforos.where((s) {
      final numero = s['numero'].toString().toLowerCase();
      final endereco = s['endereco'].toString().toLowerCase();
      return numero.contains(_termoBusca) || endereco.contains(_termoBusca);
    }).toList();
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (_termoBusca.isNotEmpty) return; 
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _semaforos.removeAt(oldIndex);
      _semaforos.insert(newIndex, item);
    });
  }

  Future<void> _salvarOrganizacao() async {
    setState(() => _isSaving = true);
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (int i = 0; i < _semaforos.length; i++) {
        var item = _semaforos[i];
        var ref = FirebaseFirestore.instance.collection('semaforos').doc(item['db_id']);
        batch.update(ref, {'ordem_vistoria': i + 1, 'lado_vistoria': item['lado']});
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salvo com sucesso!'), backgroundColor: Colors.green));
        setState(() => _isSaving = false); 
      }
    } catch (e) {
      setState(() => _isSaving = false);
    }
  }

  // ==========================================
  // EXPORTAÇÃO PDF (CENTRALIZADO)
  // ==========================================
  Future<void> _exportarPDF() async {
    if (_semaforos.isEmpty) return;
    try {
      final pdf = pw.Document();
      String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          footer: (pw.Context context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Relatório gerado pelo Sistema de Ocorrências semafóricas - SOS - $dataHoraAtual - Página ${context.pageNumber} de ${context.pagesCount}', 
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)
            )
          ),
          build: (pw.Context context) {
            return [
              pw.Header(level: 0, child: pw.Text('Ordem de Vistoria - Rota ${widget.rotaNumero}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                context: context,
                headers: ['Ordem', 'Lado', 'Semáforo', 'Endereço/Cruzamento'],
                data: _semaforos.asMap().entries.map((entry) => [
                  '${entry.key + 1}º', 
                  entry.value['lado'], 
                  entry.value['numero'], 
                  entry.value['endereco']
                ]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.purple700),
                cellAlignment: pw.Alignment.center, 
                cellStyle: const pw.TextStyle(fontSize: 10),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(4),
                }
              ),
            ];
          }
        )
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Rota_${widget.rotaNumero}.pdf');
    } catch (e) {
      debugPrint("Erro PDF: $e");
    }
  }

  // ==========================================
  // EXPORTAÇÃO XLSX (REAL EXCEL) COM CORREÇÃO
  // ==========================================
  Future<void> _exportarExcel() async {
    if (_semaforos.isEmpty) return;
    try {
      var excel = excel_pkg.Excel.createExcel();
      String sheetName = "Rota ${widget.rotaNumero}";
      excel.rename("Sheet1", sheetName);
      var sheet = excel[sheetName];

      sheet.appendRow([
        excel_pkg.TextCellValue('ORDEM'),
        excel_pkg.TextCellValue('LADO'),
        excel_pkg.TextCellValue('SEMAFORO'),
        excel_pkg.TextCellValue('ENDERECO'),
      ]);

      for (int i = 0; i < _semaforos.length; i++) {
        var item = _semaforos[i];
        sheet.appendRow([
          excel_pkg.TextCellValue('${i + 1}º'),
          excel_pkg.TextCellValue(item['lado']?.toString() ?? ''),
          excel_pkg.TextCellValue(item['numero']?.toString() ?? ''),
          excel_pkg.TextCellValue(item['endereco']?.toString() ?? ''),
        ]);
      }

      var bytes = excel.save();
      if (bytes != null) {
        final xFile = XFile.fromData(
          Uint8List.fromList(bytes), 
          name: 'Rota_${widget.rotaNumero}.xlsx', 
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        );
        await Share.shareXFiles([xFile], text: 'Planilha Rota ${widget.rotaNumero}');
      }
    } catch (e) {
      debugPrint("Erro Excel: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Organizar Rota ${widget.rotaNumero}'),
        backgroundColor: Colors.purple.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _isLoading ? null : _exportarPDF),
          IconButton(icon: const Icon(Icons.download), onPressed: _isLoading ? null : _exportarExcel),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _buscaController,
                  decoration: InputDecoration(
                    hintText: 'Pesquisar...',
                    prefixIcon: const Icon(Icons.search, color: Colors.purple),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: Colors.purple.shade200)),
                  ),
                ),
              ),
              Expanded(
                child: _termoBusca.isNotEmpty
                  ? ListView.builder(
                      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 80),
                      itemCount: _semaforosExibidos.length,
                      itemBuilder: (context, index) => _buildSemaforoCard(_semaforosExibidos[index], true),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 80),
                      itemCount: _semaforosExibidos.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) => _buildSemaforoCard(_semaforosExibidos[index], false),
                    ),
              ),
            ],
          ),
      floatingActionButton: _isLoading || _semaforos.isEmpty ? null : FloatingActionButton.extended(
        onPressed: _isSaving ? null : _salvarOrganizacao,
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
        label: Text(_isSaving ? 'Salvando...' : 'Salvar Rota'),
      ),
    );
  }

  Widget _buildSemaforoCard(Map<String, dynamic> item, bool bloqueadoParaArrastar) {
    int indexReal = _semaforos.indexOf(item);
    return Card(
      key: ValueKey(item['db_id']),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple.shade100,
          child: Text('${indexReal + 1}º', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 12)),
        ),
        title: Text('Semáforo: ${item['numero']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(item['endereco'], maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: item['lado'],
                  style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                  items: ['A', 'B'].map((lado) => DropdownMenuItem(value: lado, child: Text('Lado $lado'))).toList(),
                  onChanged: (novoLado) => setState(() => item['lado'] = novoLado!),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.drag_handle, color: bloqueadoParaArrastar ? Colors.grey.shade300 : Colors.grey.shade600),
          ],
        ),
      ),
    );
  }
}