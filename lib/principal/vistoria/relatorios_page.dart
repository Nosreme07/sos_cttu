import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border; 

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

  // Controle de Perfil
  bool _carregandoPerfil = true;

  // ==== ESTADOS DA ABA CONSULTA ====
  DateTime? _deConsulta;
  DateTime? _ateConsulta;
  final TextEditingController _semaforoController = TextEditingController();
  bool _buscandoSemaforo = false;
  List<Map<String, dynamic>> _resultadoSemaforo = [];

  // ==== ESTADOS DA ABA EXPORTAÇÃO ====
  DateTime? _dataExport; 
  String _rotaExport = 'Selecione';

  // ==== ESTADOS DA ABA PENDÊNCIAS ====
  DateTime _mesPendencia = DateTime(DateTime.now().year, DateTime.now().month, 1);
  Map<String, int> _totalSemaforosPorRota = {}; // Para mostrar o total cadastrado

  final Map<String, String> _cacheNomes = {};
  
  // Cache de Rotas e Semáforos
  final List<String> _todasAsRotas = ['Todas']; 
  List<Map<String, String>> _opcoesSemaforos = []; 
  Map<String, String> _mapaRotas = {}; 
  
  bool _exportando = false;
  bool _calculandoPendencias = false;
  Map<String, List<Map<String, dynamic>>> _resultadoPendencias = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _carregarDadosBase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _semaforoController.dispose();
    super.dispose();
  }

  // ==== FUNÇÃO PARA FORMATAR O ID DO SEMÁFORO COM ZERO À ESQUERDA ====
  String _formatarId(String idStr) {
    if (idStr.isEmpty) return '000';
    String numeros = idStr.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeros.isEmpty) return idStr;
    return numeros.padLeft(3, '0');
  }

  Future<void> _carregarDadosBase() async {
    try {
      var snapSemaforos = await FirebaseFirestore.instance.collection('semaforos').get();
      Set<String> rotasUnicas = {};
      Map<String, String> mapaLocal = {};
      List<Map<String, String>> semaforosLocal = []; 
      
      for (var doc in snapSemaforos.docs) {
        var data = doc.data();
        String idOriginal = data['id'].toString();
        String idFormatado = _formatarId(idOriginal);
        String endereco = (data['endereco'] ?? '').toString();
        String rota = (data['rota'] ?? '').toString().replaceFirst(RegExp(r'^0+'), '');
        
        if (idOriginal.isNotEmpty) {
          if (rota.isNotEmpty) {
            mapaLocal[idOriginal] = rota;
            rotasUnicas.add(rota);
          }
          semaforosLocal.add({
            'id': idOriginal, 
            'label': '$idFormatado - $endereco' 
          }); 
        }
      }

      List<String> listaOrdenada = rotasUnicas.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      semaforosLocal.sort((a, b) => (int.tryParse(a['label']!.split(' - ')[0]) ?? 0).compareTo(int.tryParse(b['label']!.split(' - ')[0]) ?? 0));
      
      if (mounted) {
        setState(() {
          _mapaRotas = mapaLocal;
          _todasAsRotas.addAll(listaOrdenada);
          _opcoesSemaforos = semaforosLocal;
          _carregandoPerfil = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar base: $e");
      if (mounted) {
        setState(() => _carregandoPerfil = false);
      }
    }
  }

  Future<String> _getNomeVistoriador(String uid) async {
    if (_cacheNomes.containsKey(uid)) return _cacheNomes[uid]!;
    try {
      var doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        String nome = doc.data()!['nomeCompleto'] ?? doc.data()!['nome_completo'] ?? doc.data()!['nome'] ?? 'Vistoriador';
        _cacheNomes[uid] = nome.toUpperCase();
        return nome.toUpperCase();
      }
    } catch (e) {
      // Ignora erro
    }
    return 'DESCONHECIDO';
  }

  Future<void> _selecionarData(BuildContext context, {required bool isDe, required String tipoAba}) async {
    DateTime initial = DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: tipoAba == 'Exportacao' ? 'SELECIONE A DATA DA ROTA' : (isDe ? 'SELECIONE A DATA INICIAL' : 'SELECIONE A DATA FINAL'),
    );

    if (picked != null) {
      setState(() {
        if (tipoAba == 'Consulta') {
          if (isDe) {
            _deConsulta = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
          } else {
            _ateConsulta = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
          }
        } else if (tipoAba == 'Exportacao') {
          _dataExport = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        }
      });
    }
  }

  void _limparFiltrosConsulta() {
    setState(() {
      _deConsulta = null;
      _ateConsulta = null;
      _semaforoController.clear();
      _resultadoSemaforo.clear();
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

  // ==== RODAPÉ FIXO DO PDF COM TEXTO SOLICITADO ====
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
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Text('Relatório gerado pelo Sistema de Ocorrências Semafóricas - SOS ($dataHora)', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ),
              pw.SizedBox(width: 20, child: pw.Text('Pág. ${context.pageNumber} / ${context.pagesCount}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
            ]
          )
        ]
      )
    );
  }

  // ============================================================
  // ABA 1: CONSULTA SEMÁFORO
  // ============================================================
  Future<void> _buscarVistoriasSemaforo({String? idSemaforo}) async {
    String idOriginalBusca = '';

    if (idSemaforo != null) {
      idOriginalBusca = idSemaforo;
    } else {
      String textoPesquisa = _semaforoController.text.trim();
      var match = _opcoesSemaforos.where((s) => s['label'] == textoPesquisa).toList();
      if (match.isNotEmpty) {
        idOriginalBusca = match.first['id']!;
      } else {
        String trechoNumero = textoPesquisa.split(' - ')[0].trim();
        var fallbackMatch = _opcoesSemaforos.where((s) => _formatarId(s['id']!) == _formatarId(trechoNumero)).toList();
        if (fallbackMatch.isNotEmpty) {
          idOriginalBusca = fallbackMatch.first['id']!;
        } else {
          idOriginalBusca = trechoNumero; 
        }
      }
    }
    
    if (idOriginalBusca.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um semáforo!'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _buscandoSemaforo = true);

    try {
      Query query = FirebaseFirestore.instance.collection('vistoria').where('semaforo_id', isEqualTo: idOriginalBusca);
      
      var snapshot = await query.get();
      List<Map<String, dynamic>> filtrados = [];

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        
        if (_deConsulta != null || _ateConsulta != null) {
          if (data['criado_em'] == null) continue;
          DateTime dt = (data['criado_em'] as Timestamp).toDate();
          if (_deConsulta != null && dt.isBefore(_deConsulta!)) continue;
          if (_ateConsulta != null && dt.isAfter(_ateConsulta!)) continue;
        }

        data['nome_vistoriador'] = await _getNomeVistoriador(data['vistoriador_uid'] ?? '');
        filtrados.add(data);
      }

      filtrados.sort((a, b) {
        Timestamp tA = a['criado_em'] ?? Timestamp(0, 0);
        Timestamp tB = b['criado_em'] ?? Timestamp(0, 0);
        return tB.compareTo(tA); 
      });

      if (mounted) {
        setState(() {
          _resultadoSemaforo = filtrados;
          _buscandoSemaforo = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _buscandoSemaforo = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _gerarFichaPDFSemaforo(Map<String, dynamic> vistoria) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Baixando fotos e gerando PDF...'), backgroundColor: Colors.teal));
    try {
      bool temFalha = vistoria['teve_anormalidade'] == true;
      List<dynamic> urlsFotos = vistoria['fotos'] ?? [];
      List<pw.ImageProvider> imagensPdf = [];

      for (String base64Str in urlsFotos) {
        try {
          if (base64Str.startsWith('http')) {
            final imageBytes = await networkImage(base64Str);
            imagensPdf.add(imageBytes);
          } else {
            final imageBytes = base64Decode(base64Str);
            imagensPdf.add(pw.MemoryImage(imageBytes));
          }
        } catch (e) {
          debugPrint('Erro ao decodificar imagem pro pdf: $e');
        }
      }

      String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
      final pdf = pw.Document();
      
      String idFormatado = _formatarId(vistoria['semaforo_id']?.toString() ?? '');

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.only(left: 32, right: 32, top: 32, bottom: 20),
          footer: (pw.Context context) => _buildRodapePDF(context, dataHoraAtual),
          build: (pw.Context context) {
            return [
              pw.Row(
                children: [
                  pw.Container(width: 30, height: 30, decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: temFalha ? PdfColors.red : PdfColors.green)),
                  pw.SizedBox(width: 12),
                  pw.Text('Semáforo Nº $idFormatado', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                ]
              ),
              pw.Divider(thickness: 2, height: 32),
              pw.Text('Vistoriador: ${vistoria['nome_vistoriador'] ?? ''}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('Endereço: ${vistoria['semaforo_endereco']}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Início: ${vistoria['data_hora_inicio']}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Fim: ${vistoria['data_hora_fim']}', style: const pw.TextStyle(fontSize: 12)),
              pw.Text('Coordenadas GPS: ${vistoria['gps_coordenadas']}', style: const pw.TextStyle(fontSize: 12)),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(12), width: double.infinity, decoration: const pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.all(pw.Radius.circular(8))),
                child: pw.Text(vistoria['resumo_checklist'] ?? 'Checklist verificado.', style: pw.TextStyle(color: PdfColors.blue800, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(12), width: double.infinity,
                decoration: pw.BoxDecoration(color: temFalha ? PdfColors.red50 : PdfColors.green50, border: pw.Border.all(color: temFalha ? PdfColors.red : PdfColors.green), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
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
                  children: imagensPdf.map((img) => pw.Container(width: 150, height: 150, decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)), image: pw.DecorationImage(image: img, fit: pw.BoxFit.cover)))).toList(),
                )
              ],
            ];
          }
        )
      );

      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Ficha_Semaforo_$idFormatado.pdf');
      
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar PDF da ficha!'), backgroundColor: Colors.red));
    }
  }

  Widget _buildAbaSemaforo() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16), color: Colors.blue.shade50,
          child: Column(
            children: [
              DropdownMenu<String>(
                expandedInsets: EdgeInsets.zero,
                controller: _semaforoController,
                enableFilter: true,
                enableSearch: true,
                hintText: 'Digite o Nº ou Endereço...',
                label: const Text('Pesquisar Semáforo', style: TextStyle(fontWeight: FontWeight.bold)),
                leadingIcon: const Icon(Icons.traffic),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                dropdownMenuEntries: _opcoesSemaforos.map((s) {
                  return DropdownMenuEntry<String>(value: s['id']!, label: s['label']!);
                }).toList(),
                onSelected: (val) {
                  if (val != null) {
                    _semaforoController.text = _opcoesSemaforos.firstWhere((element) => element['id'] == val)['label']!;
                    _buscarVistoriasSemaforo(idSemaforo: val); 
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(children: [
                _buildBotaoData('Data De', _deConsulta, () => _selecionarData(context, isDe: true, tipoAba: 'Consulta')),
                const SizedBox(width: 8),
                _buildBotaoData('Data Até', _ateConsulta, () => _selecionarData(context, isDe: false, tipoAba: 'Consulta')),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity, height: 45,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                  icon: _buscandoSemaforo ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.search),
                  label: const Text('Atualizar Filtro de Data', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _buscandoSemaforo ? null : () => _buscarVistoriasSemaforo(),
                ),
              ),
              if (_deConsulta != null || _ateConsulta != null || _resultadoSemaforo.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _limparFiltrosConsulta, child: const Text('Limpar Pesquisa', style: TextStyle(color: Colors.red))),
                )
            ],
          ),
        ),
        Expanded(
          child: _resultadoSemaforo.isEmpty
            ? Center(child: Text('Nenhum resultado. Pesquise um semáforo acima.', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _resultadoSemaforo.length,
                itemBuilder: (context, index) {
                  var item = _resultadoSemaforo[index];
                  bool temFalha = item['teve_anormalidade'] == true;
                  String idFormatado = _formatarId(item['semaforo_id']?.toString() ?? '');
                  String rotaDoSem = _mapaRotas[item['semaforo_id']?.toString()] ?? 'S/R';
                  
                  return Card(
                    elevation: 2, margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(side: BorderSide(color: temFalha ? Colors.red.shade200 : Colors.green.shade200, width: 2), borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Semáforo $idFormatado', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              Icon(temFalha ? Icons.warning : Icons.check_circle, color: temFalha ? Colors.red : Colors.green),
                            ],
                          ),
                          Text('Rota: $rotaDoSem', style: const TextStyle(color: Colors.blueGrey)),
                          const Divider(),
                          Text('Vistoriador: ${item['nome_vistoriador']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          Text('Data da Vistoria: ${item['data_hora_inicio']}'),
                          const SizedBox(height: 8),
                          if (temFalha) ...[
                            Text('Falha: ${item['falha_registrada']}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                            Text('Detalhes: ${item['detalhes_ocorrencia']}'),
                          ] else ...[
                            const Text('Status: Sem defeitos constatados', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          ],
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.picture_as_pdf, size: 16), label: const Text('Ver Ficha PDF'),
                              onPressed: () => _gerarFichaPDFSemaforo(item),
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
        )
      ],
    );
  }

  // ============================================================
  // ABA 2: ROTAS (EXPORTAÇÃO E EXCEL NATIVO)
  // ============================================================
  Future<void> _realizarExportacao(String tipo) async {
    if (_dataExport == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione a data da rota!'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _exportando = true);

    try {
      DateTime startOfDay = DateTime(_dataExport!.year, _dataExport!.month, _dataExport!.day, 0, 0, 0);
      DateTime endOfDay = DateTime(_dataExport!.year, _dataExport!.month, _dataExport!.day, 23, 59, 59);

      var snapSemaforos = await FirebaseFirestore.instance.collection('semaforos').get();
      
      List<Map<String, dynamic>> todosSemaforosRota = [];
      String rotaSelecionadaLimpa = _rotaExport.replaceFirst(RegExp(r'^0+'), '');

      for (var doc in snapSemaforos.docs) {
        var data = doc.data();
        String rotaDesteSem = (data['rota'] ?? '').toString().replaceFirst(RegExp(r'^0+'), '');
        
        if (_rotaExport == 'Todas' || rotaDesteSem == rotaSelecionadaLimpa) {
          todosSemaforosRota.add({
            'id': data['id'].toString(),
            'rota': rotaDesteSem.isEmpty ? 'S/R' : rotaDesteSem,
          });
        }
      }

      todosSemaforosRota.sort((a, b) => (int.tryParse(a['id']) ?? 0).compareTo(int.tryParse(b['id']) ?? 0));

      if (todosSemaforosRota.isEmpty) {
        setState(() => _exportando = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum semáforo encontrado para esta rota!'), backgroundColor: Colors.orange));
        return;
      }

      QuerySnapshot snapVistorias = await FirebaseFirestore.instance.collection('vistoria')
          .where('criado_em', isGreaterThanOrEqualTo: startOfDay)
          .where('criado_em', isLessThanOrEqualTo: endOfDay)
          .orderBy('criado_em', descending: true)
          .get();

      Map<String, Map<String, dynamic>> vistoriasMap = {};
      for (var doc in snapVistorias.docs) {
        var data = doc.data() as Map<String, dynamic>;
        String idSem = data['semaforo_id'].toString();
        
        if (!vistoriasMap.containsKey(idSem)) {
          data['nome_vistoriador'] = await _getNomeVistoriador(data['vistoriador_uid'] ?? '');
          vistoriasMap[idSem] = data;
        }
      }

      List<Map<String, dynamic>> dadosFinais = [];
      for (var semaforo in todosSemaforosRota) {
        String idSem = semaforo['id'];
        var vistoria = vistoriasMap[idSem];

        if (vistoria != null) {
          bool temFalha = vistoria['teve_anormalidade'] == true;
          String status = temFalha ? (vistoria['falha_registrada'] ?? 'DEFEITO') : 'SEM FALHA APARENTE';
          
          dadosFinais.add({
            'rota': semaforo['rota'],
            'semaforo_id': idSem,
            'vistoriado': 'SIM',
            'nome_vistoriador': vistoria['nome_vistoriador'],
            'data_hora': vistoria['data_hora_fim'] ?? vistoria['data_hora_inicio'] ?? '-',
            'status': status,
          });
        } else {
          dadosFinais.add({
            'rota': semaforo['rota'],
            'semaforo_id': idSem,
            'vistoriado': 'NÃO',
            'nome_vistoriador': '-',
            'data_hora': '-',
            'status': 'NÃO VISTORIADO',
          });
        }
      }

      int vistoriados = dadosFinais.where((v) => v['vistoriado'] == 'SIM').length;
      int naoVistoriados = dadosFinais.where((v) => v['vistoriado'] == 'NÃO').length;
      int total = dadosFinais.length;
      double percentual = total > 0 ? (vistoriados / total) * 100 : 0;

      if (tipo == 'PDF') {
        await _exportarRotasPDF(dadosFinais, vistoriados, naoVistoriados, percentual);
      } else {
        await _exportarRotasExcel(dadosFinais, vistoriados, naoVistoriados, percentual);
      }

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _exportarRotasPDF(List<Map<String, dynamic>> dados, int vistoriados, int naoVistoriados, double percentual) async {
    final pdf = pw.Document();
    String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        footer: (pw.Context ctx) => _buildRodapePDF(ctx, dataHoraAtual),
        build: (pw.Context context) {
          return [
            pw.Text('RELATÓRIO DE VISTORIAS DE ROTAS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('Filtro: Rota $_rotaExport | Data: ${DateFormat('dd/MM/yyyy').format(_dataExport!)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            pw.SizedBox(height: 8),
            
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: PdfColors.grey300)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Vistoriados: $vistoriados', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                  pw.Text('Não Vistoriados: $naoVistoriados', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                  pw.Text('Conclusão: ${percentual.toStringAsFixed(1)}%', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                ]
              )
            ),
            pw.SizedBox(height: 12),

            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['Semáforo', 'Vistoriado', 'Nome do Vistoriador', 'Data/Hora da Vistoria', 'Status'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              data: dados.map((v) {
                return [
                  _formatarId(v['semaforo_id']?.toString() ?? ''),
                  v['vistoriado'],
                  v['nome_vistoriador'],
                  v['data_hora'],
                  v['status'],
                ];
              }).toList()
            )
          ];
        }
      )
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Exportacao_Rotas.pdf');
  }

  Future<void> _exportarRotasExcel(List<Map<String, dynamic>> dados, int vistoriados, int naoVistoriados, double percentual) async {
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Relatorio'];
      excel.setDefaultSheet('Relatorio');

      sheetObject.appendRow([TextCellValue('RELATÓRIO DE ROTAS')]);
      sheetObject.appendRow([TextCellValue('ROTA:'), TextCellValue(_rotaExport)]);
      sheetObject.appendRow([TextCellValue('DATA:'), TextCellValue(DateFormat('dd/MM/yyyy').format(_dataExport!))]);
      sheetObject.appendRow([TextCellValue('VISTORIADOS:'), IntCellValue(vistoriados)]);
      sheetObject.appendRow([TextCellValue('NAO VISTORIADOS:'), IntCellValue(naoVistoriados)]);
      sheetObject.appendRow([TextCellValue('CONCLUSAO:'), TextCellValue('${percentual.toStringAsFixed(1)}%')]);
      sheetObject.appendRow([TextCellValue('')]);

      sheetObject.appendRow([
        TextCellValue('SEMAFORO'),
        TextCellValue('VISTORIADO'),
        TextCellValue('NOME DO VISTORIADOR'),
        TextCellValue('DATA/HORA'),
        TextCellValue('STATUS')
      ]);

      for (var v in dados) {
        String idFormatado = _formatarId(v['semaforo_id']?.toString() ?? '');
        sheetObject.appendRow([
          TextCellValue(idFormatado),
          TextCellValue(v['vistoriado']?.toString() ?? ''),
          TextCellValue(v['nome_vistoriador']?.toString() ?? ''),
          TextCellValue(v['data_hora']?.toString() ?? ''),
          TextCellValue(v['status']?.toString() ?? '')
        ]);
      }

      if (excel.tables.keys.contains('Sheet1')) {
        excel.delete('Sheet1');
      }

      var fileBytes = excel.encode();
      if (fileBytes != null) {
        final xFile = XFile.fromData(
          Uint8List.fromList(fileBytes),
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: 'Relatorio_Rotas.xlsx'
        );
        await Share.shareXFiles([xFile], text: 'Planilha de Rotas gerada pelo SOS.');
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar Excel: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _buildAbaRotas() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.route, size: 60, color: Colors.blueGrey),
          const SizedBox(height: 16),
          const Text('Exportação de Rotas', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 32),
          
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Selecione a Rota', border: OutlineInputBorder(), prefixIcon: Icon(Icons.map)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _todasAsRotas.contains(_rotaExport) ? _rotaExport : 'Todas',
                items: _todasAsRotas.map((r) => DropdownMenuItem(value: r, child: Text(r == 'Todas' ? 'Todas as Rotas' : 'Rota $r'))).toList(),
                onChanged: (v) => setState(() => _rotaExport = v!),
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          const Text('Dia da Vistoria:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            _buildBotaoData('Data', _dataExport, () => _selecionarData(context, isDe: true, tipoAba: 'Exportacao')),
          ]),
          const SizedBox(height: 40),

          SizedBox(
            height: 55,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: _exportando ? const SizedBox.shrink() : const Icon(Icons.picture_as_pdf),
              label: _exportando ? const CircularProgressIndicator(color: Colors.white) : const Text('EXPORTAR PDF', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: _exportando ? null : () => _realizarExportacao('PDF'),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 55,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: _exportando ? const SizedBox.shrink() : const Icon(Icons.grid_on),
              label: _exportando ? const CircularProgressIndicator(color: Colors.white) : const Text('EXPORTAR PLANILHA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: _exportando ? null : () => _realizarExportacao('EXCEL'),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ABA 3: PENDÊNCIAS DE ROTAS
  // ============================================================
  Future<void> _calcularPendencias() async {
    setState(() => _calculandoPendencias = true);

    try {
      DateTime start = DateTime(_mesPendencia.year, _mesPendencia.month, 1);
      DateTime end = DateTime(_mesPendencia.year, _mesPendencia.month + 1, 0, 23, 59, 59);

      var snapSemaforos = await FirebaseFirestore.instance.collection('semaforos').get();
      Map<String, Map<String, List<String>>> semaforosMaster = {}; 
      
      for(var doc in snapSemaforos.docs) {
        var data = doc.data();
        String id = data['id'].toString();
        String rota = (data['rota'] ?? '').toString().replaceFirst(RegExp(r'^0+'), '');
        String grupo = (data['lado_vistoria'] ?? data['grupo'] ?? 'A').toString().toUpperCase();

        if(rota.isEmpty || id.isEmpty) continue;

        if(!semaforosMaster.containsKey(rota)) semaforosMaster[rota] = {'A': [], 'B': []};
        if(!semaforosMaster[rota]!.containsKey(grupo)) semaforosMaster[rota]![grupo] = [];
        semaforosMaster[rota]![grupo]!.add(id);
      }

      var snapTurnos = await FirebaseFirestore.instance.collection('turnos')
          .where('data_inicio', isGreaterThanOrEqualTo: start)
          .where('data_inicio', isLessThanOrEqualTo: end)
          .get();

      Map<String, Set<String>> rotasRodadasNoDia = {}; 
      for(var doc in snapTurnos.docs) {
        var data = doc.data();
        if(data['data_inicio'] == null) continue;
        DateTime d = (data['data_inicio'] as Timestamp).toDate();
        String diaStr = DateFormat('yyyy-MM-dd').format(d);
        String rota = (data['rota_numero'] ?? '').toString().replaceFirst(RegExp(r'^0+'), '');
        
        if(rota.isNotEmpty) {
          if(!rotasRodadasNoDia.containsKey(diaStr)) rotasRodadasNoDia[diaStr] = {};
          rotasRodadasNoDia[diaStr]!.add(rota);
        }
      }

      var snapVistorias = await FirebaseFirestore.instance.collection('vistoria')
          .where('criado_em', isGreaterThanOrEqualTo: start)
          .where('criado_em', isLessThanOrEqualTo: end)
          .get();

      Map<String, Map<String, Set<String>>> vistoriasPorDiaERota = {}; 
      for(var doc in snapVistorias.docs) {
        var data = doc.data();
        if(data['criado_em'] == null) continue;
        DateTime d = (data['criado_em'] as Timestamp).toDate();
        String diaStr = DateFormat('yyyy-MM-dd').format(d);
        String idSem = data['semaforo_id'].toString();
        String rota = _mapaRotas[idSem] ?? '';

        if(rota.isNotEmpty) {
          if(!vistoriasPorDiaERota.containsKey(diaStr)) vistoriasPorDiaERota[diaStr] = {};
          if(!vistoriasPorDiaERota[diaStr]!.containsKey(rota)) vistoriasPorDiaERota[diaStr]![rota] = {};
          vistoriasPorDiaERota[diaStr]![rota]!.add(idSem);
        }
      }

      Map<String, List<Map<String, dynamic>>> resultadoFinal = {};
      DateTime baseDate = DateTime(2024, 1, 1);

      rotasRodadasNoDia.forEach((diaStr, rotasDesteDia) {
        DateTime diaDt = DateTime.parse(diaStr);
        int diasPassados = diaDt.difference(baseDate).inDays;
        String grupoDaMeta = (diasPassados % 2 == 0) ? 'A' : 'B';

        for(String rota in rotasDesteDia) {
          List<String> metaDoDiaParaRota = semaforosMaster[rota]?[grupoDaMeta] ?? [];
          Set<String> vistoriadosReal = vistoriasPorDiaERota[diaStr]?[rota] ?? {};

          List<String> deixadosParaTras = metaDoDiaParaRota.where((id) => !vistoriadosReal.contains(id)).toList();

          if (deixadosParaTras.isNotEmpty) {
            if(!resultadoFinal.containsKey(rota)) resultadoFinal[rota] = [];
            resultadoFinal[rota]!.add({
              'dia_dt': diaDt,
              'dia_str': DateFormat('dd/MM/yyyy').format(diaDt),
              'qtd': deixadosParaTras.length,
              'ids': deixadosParaTras.map((id) => _formatarId(id)).join(' - ')
            });
          }
        }
      });

      resultadoFinal.forEach((key, list) {
        list.sort((a, b) => (b['dia_dt'] as DateTime).compareTo(a['dia_dt'] as DateTime));
      });

      Map<String, int> totalCadastradoLocal = {};
      semaforosMaster.forEach((rota, grupos) {
        totalCadastradoLocal[rota] = (grupos['A']?.length ?? 0) + (grupos['B']?.length ?? 0);
      });

      if (mounted) {
        setState(() {
          _resultadoPendencias = resultadoFinal;
          _totalSemaforosPorRota = totalCadastradoLocal;
          _calculandoPendencias = false;
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() => _calculandoPendencias = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _escolherMesPendencia() async {
    int mes = _mesPendencia.month;
    int ano = _mesPendencia.year;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Filtrar Mês/Ano'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              DropdownButton<int>(
                value: mes,
                items: List.generate(12, (i) => DropdownMenuItem(value: i+1, child: Text((i+1).toString().padLeft(2, '0')))),
                onChanged: (v) => setStateDialog(() => mes = v!),
              ),
              const Text('/'),
              DropdownButton<int>(
                value: ano,
                items: List.generate(10, (i) => DropdownMenuItem(value: 2024+i, child: Text((2024+i).toString()))),
                onChanged: (v) => setStateDialog(() => ano = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                setState(() => _mesPendencia = DateTime(ano, mes, 1));
                Navigator.pop(ctx);
                _calcularPendencias();
              },
              child: const Text('Aplicar')
            )
          ],
        )
      )
    );
  }

  Future<void> _exportarPendenciasPDF() async {
    setState(() => _exportando = true);
    try {
      final pdf = pw.Document();
      String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
      String mesFormatado = DateFormat('MM/yyyy').format(_mesPendencia);
      
      List<List<String>> tableData = [];
      List<String> rotasComPendencia = _resultadoPendencias.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      
      for (String rota in rotasComPendencia) {
        int totalRota = _totalSemaforosPorRota[rota] ?? 0;
        for (var dia in _resultadoPendencias[rota]!) {
          tableData.add([
            'Rota $rota',
            totalRota.toString(),
            dia['dia_str'],
            dia['qtd'].toString(),
            dia['ids']
          ]);
        }
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          footer: (pw.Context ctx) => _buildRodapePDF(ctx, dataHoraAtual),
          build: (pw.Context context) {
            return [
              pw.Text('RELATÓRIO DE PENDÊNCIAS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('Mês de Referência: $mesFormatado', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                context: context,
                headers: ['Rota', 'Total Rota', 'Data', 'Qtd Pendentes', 'Semáforos (IDs)'],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.red800),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                data: tableData,
                columnWidths: {
                  0: const pw.FixedColumnWidth(50),
                  1: const pw.FixedColumnWidth(60),
                  2: const pw.FixedColumnWidth(60),
                  3: const pw.FixedColumnWidth(80),
                  4: const pw.FlexColumnWidth(),
                }
              )
            ];
          }
        )
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Pendencias_$mesFormatado.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _exportarPendenciasExcel() async {
    setState(() => _exportando = true);
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Pendencias'];
      excel.setDefaultSheet('Pendencias');
      String mesFormatado = DateFormat('MM/yyyy').format(_mesPendencia);

      sheetObject.appendRow([TextCellValue('RELATÓRIO DE PENDÊNCIAS')]);
      sheetObject.appendRow([TextCellValue('MÊS:'), TextCellValue(mesFormatado)]);
      sheetObject.appendRow([TextCellValue('')]);

      sheetObject.appendRow([
        TextCellValue('ROTA'),
        TextCellValue('TOTAL CADASTRADO'),
        TextCellValue('DATA'),
        TextCellValue('QTD PENDENTES'),
        TextCellValue('SEMAFOROS PENDENTES')
      ]);

      List<String> rotasComPendencia = _resultadoPendencias.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      
      for (String rota in rotasComPendencia) {
        int totalRota = _totalSemaforosPorRota[rota] ?? 0;
        for (var dia in _resultadoPendencias[rota]!) {
          sheetObject.appendRow([
            TextCellValue(rota),
            IntCellValue(totalRota),
            TextCellValue(dia['dia_str']),
            IntCellValue(dia['qtd']),
            TextCellValue(dia['ids'])
          ]);
        }
      }

      if (excel.tables.keys.contains('Sheet1')) {
        excel.delete('Sheet1');
      }

      var fileBytes = excel.encode();
      if (fileBytes != null) {
        String nomeArquivo = 'Pendencias_${mesFormatado.replaceAll('/', '-')}.xlsx';
        final xFile = XFile.fromData(
          Uint8List.fromList(fileBytes),
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: nomeArquivo
        );
        await Share.shareXFiles([xFile], text: 'Planilha de Pendências gerada pelo SOS.');
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar Excel: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Widget _buildAbaPendencias() {
    List<String> rotasComPendencia = _resultadoPendencias.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    return Column(
      children: [
        Container(
          color: Colors.red.shade50, padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('Controle de Pendências', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                      icon: const Icon(Icons.calendar_month),
                      label: Text(DateFormat('MM/yyyy').format(_mesPendencia), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _escolherMesPendencia,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
                      icon: _calculandoPendencias ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.search),
                      label: const Text('Calcular'),
                      onPressed: _calculandoPendencias ? null : _calcularPendencias,
                    ),
                  )
                ],
              )
            ],
          ),
        ),
        
        if (rotasComPendencia.isNotEmpty && !_calculandoPendencias)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
                    icon: _exportando ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(color:Colors.white,strokeWidth:2)) : const Icon(Icons.picture_as_pdf),
                    label: const Text('PDF'),
                    onPressed: _exportando ? null : _exportarPendenciasPDF,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                    icon: _exportando ? const SizedBox.shrink() : const Icon(Icons.grid_on),
                    label: const Text('PLANILHA'),
                    onPressed: _exportando ? null : _exportarPendenciasExcel,
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: _calculandoPendencias 
            ? const Center(child: Text('Cruzando dados de metas e vistorias... aguarde.'))
            : rotasComPendencia.isEmpty
              ? const Center(child: Text('Nenhuma pendência encontrada para este mês.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: rotasComPendencia.length,
                  itemBuilder: (context, index) {
                    String rota = rotasComPendencia[index];
                    List<Map<String, dynamic>> dias = _resultadoPendencias[rota]!;
                    
                    int totalRota = _totalSemaforosPorRota[rota] ?? 0;
                    int totalPendenteMes = dias.fold(0, (acc, item) => acc + (item['qtd'] as int));

                    return Card(
                      elevation: 2, margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.red.shade200), borderRadius: BorderRadius.circular(8)),
                      child: ExpansionTile(
                        leading: CircleAvatar(backgroundColor: Colors.red.shade100, child: Text(rota, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold))),
                        title: Text('Rota $rota', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Total cadastrado: $totalRota | Faltaram $totalPendenteMes no mês', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                        children: dias.map((dia) {
                          return Container(
                            color: Colors.grey.shade50,
                            child: ListTile(
                              title: Text('Dia ${dia['dia_str']} - ${dia['qtd']} pendente(s)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text(dia['ids'], style: const TextStyle(color: Colors.blueGrey)),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregandoPerfil) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios Gerenciais', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: const [MenuUsuario()],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.traffic), text: 'Semáforo'),
            Tab(icon: Icon(Icons.route), text: 'Rotas'),
            Tab(icon: Icon(Icons.warning_amber), text: 'Pendências'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAbaSemaforo(),
          _buildAbaRotas(),
          _buildAbaPendencias(),
        ],
      ),
    );
  }
}