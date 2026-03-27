import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:brasil_fields/brasil_fields.dart'; // Para a máscara da Placa

// Importações para Exportação (PDF e Excel)
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;

import '../../widgets/menu_usuario.dart';

class ListaVeiculos extends StatefulWidget {
  const ListaVeiculos({super.key});

  @override
  State<ListaVeiculos> createState() => _ListaVeiculosState();
}

class _ListaVeiculosState extends State<ListaVeiculos> with SingleTickerProviderStateMixin {
  // Lista de tipos de veículos
  final List<String> _tiposVeiculo = [
    'Moto',
    'Carro Passeio',
    'Carro com Cesto',
    'Pick-up',
    'Caminhão Munck',
  ];

  late TabController _tabController;
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';

  // Lista de empresas carregadas do banco para o Autocompletar
  List<String> _empresasOptions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); 
    });
    _carregarEmpresas(); // Carrega as empresas ao abrir a tela
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  // --- CARREGA TODAS AS EMPRESAS DO BANCO DE DADOS ---
  Future<void> _carregarEmpresas() async {
    try {
      final resEmpresas = await FirebaseFirestore.instance.collection('empresas').get();
      final resVeiculos = await FirebaseFirestore.instance.collection('veiculos').get();

      Set<String> empSet = {};
      
      // Busca do cadastro oficial de empresas (se existir)
      for (var doc in resEmpresas.docs) {
        String emp = (doc.data()['nome'] ?? doc.data()['empresa'] ?? doc.id).toString().toUpperCase();
        if (emp.isNotEmpty) empSet.add(emp);
      }
      
      // Busca também das empresas que já estão nos veículos (Garante que nenhuma fique de fora)
      for (var doc in resVeiculos.docs) {
        String emp = (doc.data()['empresa'] ?? '').toString().toUpperCase();
        if (emp.isNotEmpty) empSet.add(emp);
      }

      if (mounted) {
        setState(() {
          _empresasOptions = empSet.toList()..sort();
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar empresas: $e');
    }
  }

  // --- Função para Excluir Veículo ---
  Future<void> _deletarVeiculo(String docId, String placa) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Veículo'),
        content: Text('Tem certeza que deseja excluir o veículo placa $placa?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirmar) {
      try {
        await FirebaseFirestore.instance.collection('veiculos').doc(docId).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veículo excluído!'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao excluir.'), backgroundColor: Colors.red));
      }
    }
  }

  // --- Função que abre o MODAL para ADICIONAR ou EDITAR ---
  void _abrirModalFormulario({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    final marcaController = TextEditingController(text: dadosAtuais?['marca'] ?? '');
    final modeloController = TextEditingController(text: dadosAtuais?['modelo'] ?? '');
    final placaController = TextEditingController(text: dadosAtuais?['placa'] ?? '');
    String? tipoSelecionado = dadosAtuais?['tipo'];

    String empresaAtual = dadosAtuais?['empresa'] ?? '';
    final empresaController = TextEditingController(text: empresaAtual);

    // Garante que a empresa atual do veículo apareça na lista de opções (se ele for de uma empresa que foi apagada)
    if (empresaAtual.isNotEmpty && !_empresasOptions.contains(empresaAtual)) {
      _empresasOptions.add(empresaAtual);
    }

    bool estaCarregando = false;
    bool isEditando = docId != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          isEditando ? 'Editar Veículo' : 'Novo Veículo',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: placaController,
                          decoration: const InputDecoration(labelText: 'Placa *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.pin)),
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [PlacaVeiculoInputFormatter()],
                          validator: (value) => value == null || value.trim().isEmpty ? 'A placa é obrigatória' : null,
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Tipo de Veículo *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car)),
                          value: tipoSelecionado,
                          items: _tiposVeiculo.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (val) => setStateModal(() => tipoSelecionado = val),
                          validator: (value) => value == null ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: marcaController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'Marca', border: OutlineInputBorder(), prefixIcon: Icon(Icons.branding_watermark)),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: modeloController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.car_repair)),
                        ),
                        const SizedBox(height: 12),

                        // NOVO CAMPO DE EMPRESA COM LISTAGEM E AUTOCOMPLETAR
                        DropdownMenu<String>(
                          expandedInsets: EdgeInsets.zero,
                          controller: empresaController,
                          enableFilter: true,
                          enableSearch: true,
                          label: const Text('Empresa'),
                          leadingIcon: const Icon(Icons.factory),
                          inputDecorationTheme: const InputDecorationTheme(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          dropdownMenuEntries: _empresasOptions.map((e) => DropdownMenuEntry(value: e, label: e)).toList(),
                        ),
                        const SizedBox(height: 24),

                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF262C38),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: estaCarregando ? null : () async {
                            if (formKey.currentState!.validate()) {
                              setStateModal(() => estaCarregando = true);
                              try {
                                final dadosVeiculo = {
                                  'placa': placaController.text.trim().toUpperCase(),
                                  'tipo': tipoSelecionado,
                                  'marca': marcaController.text.trim().toUpperCase(),
                                  'modelo': modeloController.text.trim().toUpperCase(),
                                  'empresa': empresaController.text.trim().toUpperCase(),
                                  'dataAtualizacao': FieldValue.serverTimestamp(),
                                };

                                if (isEditando) {
                                  await FirebaseFirestore.instance.collection('veiculos').doc(docId).update(dadosVeiculo);
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado com sucesso!'), backgroundColor: Colors.green));
                                } else {
                                  dadosVeiculo['dataCadastro'] = FieldValue.serverTimestamp();
                                  await FirebaseFirestore.instance.collection('veiculos').add(dadosVeiculo);
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Criado com sucesso!'), backgroundColor: Colors.green));
                                }

                                // Recarrega as empresas caso o usuário tenha digitado uma nova
                                _carregarEmpresas();

                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                              } finally {
                                setStateModal(() => estaCarregando = false);
                              }
                            }
                          },
                          child: estaCarregando 
                              ? const CircularProgressIndicator(color: Colors.white) 
                              : Text(isEditando ? 'ATUALIZAR' : 'CADASTRAR', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- FUNÇÕES DE EXPORTAÇÃO ---
  String _formatarDataHora() {
    final now = DateTime.now();
    final dia = now.day.toString().padLeft(2, '0');
    final mes = now.month.toString().padLeft(2, '0');
    final ano = now.year.toString();
    final hora = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$ano às $hora:$min';
  }

  Future<void> _exportarPDF(List<QueryDocumentSnapshot> docs) async {
    final pdf = pw.Document();
    final dataHora = _formatarDataHora();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 10.0),
            padding: const pw.EdgeInsets.only(top: 10.0),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Relatório gerado pelo Sistema de Ocorrências Semafóricas - SOS - $dataHora',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
                pw.Text(
                  'Página ${context.pageNumber} de ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          List<pw.Widget> conteudo = [
            pw.Text('Relatório de Veículos Cadastrados', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
          ];

          for (String tipo in _tiposVeiculo) {
            final grupoDocs = docs.where((d) => (d.data() as Map<String, dynamic>)['tipo'] == tipo).toList();
            if (grupoDocs.isEmpty) continue; 
            
            conteudo.add(pw.Text('Tipo: $tipo', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)));
            conteudo.add(pw.SizedBox(height: 8));
            conteudo.add(
              pw.TableHelper.fromTextArray(
                context: context,
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                data: <List<String>>[
                  <String>['Placa', 'Marca/Modelo', 'Empresa'],
                  ...grupoDocs.map((doc) {
                    var d = doc.data() as Map<String, dynamic>;
                    String carro = '${d['marca'] ?? ''} ${d['modelo'] ?? ''}'.trim();
                    return [d['placa']?.toString() ?? '', carro, d['empresa']?.toString() ?? ''];
                  }),
                ],
              )
            );
            conteudo.add(pw.SizedBox(height: 20));
          }

          return conteudo;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'relatorio_veiculos.pdf');
  }

  // --- EXPORTAÇÃO EXCEL XLSX (Substituindo o CSV) ---
  Future<void> _baixarExcel(List<QueryDocumentSnapshot> docs) async {
    final dataHora = _formatarDataHora();
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Veículos'];
    excel.setDefaultSheet('Veículos');

    for (String tipo in _tiposVeiculo) {
      final grupoDocs = docs.where((d) => (d.data() as Map<String, dynamic>)['tipo'] == tipo).toList();
      if (grupoDocs.isEmpty) continue;
      
      sheetObject.appendRow(<CellValue>[TextCellValue("--- TIPO: ${tipo.toUpperCase()} ---")]);
      sheetObject.appendRow(<CellValue>[TextCellValue("Placa"), TextCellValue("Marca"), TextCellValue("Modelo"), TextCellValue("Empresa")]); 
      
      for (var doc in grupoDocs) {
        var d = doc.data() as Map<String, dynamic>;
        sheetObject.appendRow(<CellValue>[
          TextCellValue((d['placa'] ?? '').toString()),
          TextCellValue((d['marca'] ?? '').toString()),
          TextCellValue((d['modelo'] ?? '').toString()),
          TextCellValue((d['empresa'] ?? '').toString()),
        ]);
      }
      sheetObject.appendRow(<CellValue>[TextCellValue("")]); 
    }

    sheetObject.appendRow(<CellValue>[TextCellValue("Relatório gerado pelo Sistema de Ocorrências Semafóricas - SOS - $dataHora")]);

    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(
        Uint8List.fromList(fileBytes),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: 'relatorio_veiculos.xlsx'
      );
      
      await Share.shareXFiles([xfile], text: 'Segue o relatório de veículos do SOS.');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilha Excel baixada com sucesso!'), backgroundColor: Colors.green));
    }
  }

  // Mostra veículos ao clicar nos cards do Dashboard
  void _mostrarVeiculosDoTipo(String tipo, List<QueryDocumentSnapshot> todosDocs) {
    final filtrados = todosDocs.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      return d['tipo'] == tipo;
    }).toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Veículos - $tipo'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: filtrados.isEmpty 
              ? const Center(child: Text('Nenhum veículo encontrado.'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) {
                    var d = filtrados[index].data() as Map<String, dynamic>;
                    String carro = '${d['marca'] ?? ''} ${d['modelo'] ?? ''}'.trim();
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.local_shipping),
                      title: Text(d['placa'] ?? ''),
                      subtitle: Text(carro.isEmpty ? 'Sem detalhes' : carro),
                    );
                  },
                ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
          ],
        );
      }
    );
  }

  Color _corParaTipo(String tipo) {
    switch (tipo) {
      case 'Moto': return Colors.redAccent;
      case 'Carro Passeio': return Colors.blue;
      case 'Carro com Cesto': return Colors.orange;
      case 'Pick-up': return Colors.teal;
      case 'Caminhão Munck': return Colors.deepPurple;
      default: return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gestão de Veículos', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [ MenuUsuario() ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blueAccent,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Lista'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Relatórios'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0 
        ? FloatingActionButton.extended(
            backgroundColor: const Color(0xFF262C38),
            icon: const Icon(Icons.add_circle, color: Colors.white),
            label: const Text('Novo Veículo', style: TextStyle(color: Colors.white)),
            onPressed: () => _abrirModalFormulario(),
          )
        : null,
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
            stream: FirebaseFirestore.instance.collection('veiculos').orderBy('placa').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
              if (snapshot.hasError) return const Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.white)));
              
              final todosOsDocs = snapshot.data?.docs ?? [];

              return TabBarView(
                controller: _tabController,
                children: [
                  
                  // ==========================================
                  // ABA 1: LISTA COM CAMPO DE BUSCA
                  // ==========================================
                  Column(
                    children: [
                      const SizedBox(height: 190), 
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: TextField(
                              controller: _buscaController,
                              decoration: InputDecoration(
                                hintText: 'Buscar pela placa ou marca...',
                                prefixIcon: const Icon(Icons.search),
                                fillColor: Colors.white.withValues(alpha: 0.95),
                                filled: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                              ),
                              onChanged: (valor) {
                                setState(() { _termoBusca = valor.toLowerCase(); });
                              },
                            ),
                          ),
                        ),
                      ),

                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: todosOsDocs.isEmpty 
                              ? const Center(child: Text('Nenhum veículo cadastrado.', style: TextStyle(color: Colors.white, fontSize: 18)))
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                                  itemCount: todosOsDocs.length,
                                  itemBuilder: (context, index) {
                                    var doc = todosOsDocs[index];
                                    var data = doc.data() as Map<String, dynamic>;

                                    String placa = data['placa'] ?? '';
                                    String marcaModelo = '${data['marca'] ?? ''} ${data['modelo'] ?? ''}'.trim();
                                    
                                    // Busca tanto pela placa quanto pela marca/modelo
                                    if (_termoBusca.isNotEmpty && 
                                        !placa.toLowerCase().contains(_termoBusca) &&
                                        !marcaModelo.toLowerCase().contains(_termoBusca)) {
                                      return const SizedBox.shrink(); 
                                    }

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12.0),
                                      color: Colors.white.withValues(alpha: 0.95),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        leading: CircleAvatar(
                                          radius: 20,
                                          backgroundColor: _corParaTipo(data['tipo'] ?? ''),
                                          child: const Icon(Icons.local_shipping, color: Colors.white, size: 20),
                                        ),
                                        title: Text(placa, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(marcaModelo.isEmpty ? (data['tipo'] ?? 'Veículo') : marcaModelo, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                                            Text('Tipo: ${data['tipo'] ?? ''}', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                                            if (data['empresa'] != null && data['empresa'].toString().isNotEmpty) 
                                              Text('Empresa: ${data['empresa']}', style: const TextStyle(fontSize: 12)),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _abrirModalFormulario(docId: doc.id, dadosAtuais: data)),
                                            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deletarVeiculo(doc.id, placa)),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ==========================================
                  // ABA 2: DASHBOARD DINÂMICO
                  // ==========================================
                  Builder(
                    builder: (context) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 190, left: 16, right: 16, bottom: 24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(), 
                                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 180, 
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 1.0, 
                                  ),
                                  itemCount: _tiposVeiculo.length,
                                  itemBuilder: (context, index) {
                                    String tipo = _tiposVeiculo[index];
                                    int count = todosOsDocs.where((d) => (d.data() as Map<String, dynamic>)['tipo'] == tipo).length;
                                    Color cor = _corParaTipo(tipo);
                                    
                                    return _buildDashboardCard(tipo, count, cor, () => _mostrarVeiculosDoTipo(tipo, todosOsDocs));
                                  },
                                ),
                                const SizedBox(height: 48),

                                const Text(
                                  'Exportar Dados',
                                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 16),
                                
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                                        label: const Text('Gerar PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        onPressed: () => _exportarPDF(todosOsDocs),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        icon: const Icon(Icons.table_chart, color: Colors.white),
                                        label: const Text('Exportar Planilha', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        onPressed: () => _baixarExcel(todosOsDocs),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  ),

                ],
              );
            }
          ),
        ],
      ),
    );
  }

  // --- Centraliza o conteúdo dos cards do Dashboard ---
  Widget _buildDashboardCard(String titulo, int valor, Color cor, VoidCallback onTap) {
    return Card(
      color: Colors.white.withValues(alpha: 0.95),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap, 
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // Centraliza verticalmente
            crossAxisAlignment: CrossAxisAlignment.center, // Centraliza horizontalmente
            children: [
              Text(valor.toString(), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: cor)),
              const SizedBox(height: 8),
              Text(
                titulo, 
                style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.bold), 
                textAlign: TextAlign.center,
                maxLines: 2, 
              ),
            ],
          ),
        ),
      ),
    );
  }
}