import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; 

// Importações para Exportação (PDF e Excel)
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;

import '../../widgets/menu_usuario.dart'; 

class ListaIntegrantes extends StatefulWidget {
  const ListaIntegrantes({super.key});

  @override
  State<ListaIntegrantes> createState() => _ListaIntegrantesState();
}

class _ListaIntegrantesState extends State<ListaIntegrantes> with SingleTickerProviderStateMixin {
  // Lista fixa de funções
  final List<String> _funcoes = [
    'VISTORIADOR',
    'AUXILIAR DE ELETRICISTA',
    'ELETRICISTA',
    'MOTORISTA DE CAMINHÃO',
    'OPERADOR DA CENTRAL',
    'SUPERVISÃO DA CENTRAL',
    'SUPERVISÃO TÉCNICA',
    'COORDENAÇÃO TÉCNICA'
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
    _carregarEmpresas();
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
      final resInt = await FirebaseFirestore.instance.collection('integrantes').get();

      Set<String> empSet = {};
      
      // Busca do cadastro oficial de empresas (se existir)
      for (var doc in resEmpresas.docs) {
        String emp = (doc.data()['nome'] ?? doc.data()['empresa'] ?? doc.id).toString().toUpperCase();
        if (emp.isNotEmpty) empSet.add(emp);
      }
      
      // Busca também das empresas que já estão nos integrantes (Garante que nenhuma fique de fora)
      for (var doc in resInt.docs) {
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

  // --- Função para Excluir Integrante ---
  Future<void> _deletarIntegrante(String docId, String nome) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Integrante'),
        content: Text('Tem certeza que deseja excluir o integrante $nome?'),
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
        await FirebaseFirestore.instance.collection('integrantes').doc(docId).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Integrante excluído!'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao excluir.'), backgroundColor: Colors.red));
      }
    }
  }

  // --- Função que abre o MODAL para ADICIONAR ou EDITAR ---
  void _abrirModalFormulario({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: dadosAtuais?['nomeCompleto'] ?? '');
    final contatoController = TextEditingController(text: dadosAtuais?['contato'] ?? '');
    
    String empresaAtual = dadosAtuais?['empresa'] ?? '';
    final empresaController = TextEditingController(text: empresaAtual);
    
    // Garante que a empresa atual do integrante apareça na lista de opções (se ele for de uma empresa que foi apagada)
    if (empresaAtual.isNotEmpty && !_empresasOptions.contains(empresaAtual)) {
      _empresasOptions.add(empresaAtual);
    }

    String? funcaoSelecionada = dadosAtuais?['funcao'];
    
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
                          isEditando ? 'Editar Integrante' : 'Novo Integrante',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: nomeController,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            TextInputFormatter.withFunction((oldValue, newValue) {
                              return TextEditingValue(
                                text: newValue.text.toUpperCase(),
                                selection: newValue.selection,
                              );
                            })
                          ],
                          decoration: const InputDecoration(labelText: 'Nome Completo *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                          validator: (value) => value == null || value.trim().isEmpty ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Função *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.work)),
                          value: funcaoSelecionada,
                          isExpanded: true, 
                          items: _funcoes.map((f) => DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (val) => setStateModal(() => funcaoSelecionada = val),
                          validator: (value) => value == null || value.isEmpty ? 'Selecione uma função' : null,
                        ),
                        const SizedBox(height: 12),

                        // NOVO CAMPO DE EMPRESA COM LISTAGEM E AUTOCOMPLETAR
                        DropdownMenu<String>(
                          expandedInsets: EdgeInsets.zero,
                          controller: empresaController,
                          enableFilter: true,
                          enableSearch: true,
                          label: const Text('Empresa *'),
                          leadingIcon: const Icon(Icons.factory),
                          inputDecorationTheme: const InputDecorationTheme(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          dropdownMenuEntries: _empresasOptions.map((e) => DropdownMenuEntry(value: e, label: e)).toList(),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: contatoController,
                          decoration: const InputDecoration(labelText: 'Contato (Telefone/Celular)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        const SizedBox(height: 24),

                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF262C38),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: estaCarregando ? null : () async {
                            // Validação manual da Empresa já que o DropdownMenu não usa o Validator do Form
                            if (empresaController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A Empresa é obrigatória!'), backgroundColor: Colors.red));
                              return;
                            }

                            if (formKey.currentState!.validate()) {
                              setStateModal(() => estaCarregando = true);

                              try {
                                final dadosIntegrante = {
                                  'nomeCompleto': nomeController.text.trim().toUpperCase(),
                                  'funcao': funcaoSelecionada, 
                                  'contato': contatoController.text.trim(),
                                  'empresa': empresaController.text.trim().toUpperCase(),
                                  'dataAtualizacao': FieldValue.serverTimestamp(),
                                };

                                if (isEditando) {
                                  await FirebaseFirestore.instance.collection('integrantes').doc(docId).update(dadosIntegrante);
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado com sucesso!'), backgroundColor: Colors.green));
                                } else {
                                  dadosIntegrante['dataCadastro'] = FieldValue.serverTimestamp(); 
                                  await FirebaseFirestore.instance.collection('integrantes').add(dadosIntegrante);
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Criado com sucesso!'), backgroundColor: Colors.green));
                                }
                                
                                // Recarrega a lista de empresas (caso o usuário tenha digitado uma empresa nova)
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
            pw.Text('Relatório de Integrantes', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
          ];

          for (String funcao in _funcoes) {
            final grupoDocs = docs.where((d) => (d.data() as Map<String, dynamic>)['funcao'] == funcao).toList();
            if (grupoDocs.isEmpty) continue; 
            
            conteudo.add(pw.Text('Função: $funcao', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)));
            conteudo.add(pw.SizedBox(height: 8));
            conteudo.add(
              pw.TableHelper.fromTextArray(
                context: context,
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                data: <List<String>>[
                  <String>['Nome', 'Empresa', 'Contato'],
                  ...grupoDocs.map((doc) {
                    var d = doc.data() as Map<String, dynamic>;
                    return [d['nomeCompleto']?.toString() ?? '', d['empresa']?.toString() ?? '', d['contato']?.toString() ?? ''];
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

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'relatorio_integrantes.pdf');
  }

  // --- EXPORTAÇÃO EXCEL XLSX (Substituindo o antigo CSV) ---
  Future<void> _baixarExcel(List<QueryDocumentSnapshot> docs) async {
    final dataHora = _formatarDataHora();
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Integrantes'];
    excel.setDefaultSheet('Integrantes');

    for (String funcao in _funcoes) {
      final grupoDocs = docs.where((d) => (d.data() as Map<String, dynamic>)['funcao'] == funcao).toList();
      if (grupoDocs.isEmpty) continue;
      
      sheetObject.appendRow(<CellValue>[TextCellValue("--- FUNÇÃO: $funcao ---")]);
      sheetObject.appendRow(<CellValue>[TextCellValue("Nome"), TextCellValue("Empresa"), TextCellValue("Contato")]); 
      
      for (var doc in grupoDocs) {
        var d = doc.data() as Map<String, dynamic>;
        sheetObject.appendRow(<CellValue>[
          TextCellValue((d['nomeCompleto'] ?? '').toString()),
          TextCellValue((d['empresa'] ?? '').toString()),
          TextCellValue((d['contato'] ?? '').toString()),
        ]);
      }
      sheetObject.appendRow(<CellValue>[TextCellValue("")]); 
    }

    sheetObject.appendRow(<CellValue>[TextCellValue("Relatório gerado pelo Sistema de Ocorrências Semafóricas - SOS - $dataHora")]);

    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(
        Uint8List.fromList(fileBytes), 
        name: 'relatorio_integrantes.xlsx', 
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      );
      
      await Share.shareXFiles([xfile], text: 'Segue o relatório de integrantes do SOS_CTTU.');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilha Excel baixada com sucesso!'), backgroundColor: Colors.green));
    }
  }

  void _mostrarIntegrantesDaFuncao(String funcao, List<QueryDocumentSnapshot> todosDocs) {
    final filtrados = todosDocs.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      return d['funcao'] == funcao;
    }).toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Integrantes - $funcao'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: filtrados.isEmpty 
              ? const Center(child: Text('Nenhum integrante encontrado.'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) {
                    var d = filtrados[index].data() as Map<String, dynamic>;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person),
                      title: Text(d['nomeCompleto'] ?? ''),
                      subtitle: Text(d['empresa'] ?? ''),
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

  Color _corParaFuncao(String funcao) {
    switch (funcao) {
      case 'VISTORIADOR': return Colors.teal;
      case 'AUXILIAR DE ELETRICISTA': return Colors.lime.shade700;
      case 'ELETRICISTA': return Colors.orange;
      case 'MOTORISTA DE CAMINHÃO': return Colors.brown;
      case 'OPERADOR DA CENTRAL': return Colors.blue;
      case 'SUPERVISÃO DA CENTRAL': return Colors.indigo;
      case 'SUPERVISÃO TÉCNICA': return Colors.purple;
      case 'COORDENAÇÃO TÉCNICA': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gestão de Integrantes', style: TextStyle(color: Colors.white)),
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
            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
            label: const Text('Novo Integrante', style: TextStyle(color: Colors.white)),
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
            stream: FirebaseFirestore.instance.collection('integrantes').orderBy('nomeCompleto').snapshots(),
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
                                hintText: 'Buscar integrante pelo nome...',
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
                              ? const Center(child: Text('Nenhum integrante cadastrado.', style: TextStyle(color: Colors.white, fontSize: 18)))
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                                  itemCount: todosOsDocs.length,
                                  itemBuilder: (context, index) {
                                    var doc = todosOsDocs[index];
                                    var data = doc.data() as Map<String, dynamic>;

                                    String nome = data['nomeCompleto'] ?? 'Sem Nome';

                                    if (_termoBusca.isNotEmpty && !nome.toLowerCase().contains(_termoBusca)) {
                                      return const SizedBox.shrink(); 
                                    }

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12.0),
                                      color: Colors.white.withValues(alpha: 0.95),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      child: ListTile(
                                        dense: true, 
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                        leading: CircleAvatar(
                                          radius: 20,
                                          backgroundColor: _corParaFuncao(data['funcao'] ?? ''), 
                                          child: Text(
                                            nome.isNotEmpty ? nome[0].toUpperCase() : 'I',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        title: Text(nome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (data['funcao'] != null && data['funcao'].toString().isNotEmpty) 
                                              Text('Função: ${data['funcao']}', style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 12)),
                                            if (data['empresa'] != null && data['empresa'].toString().isNotEmpty) 
                                              Text('Empresa: ${data['empresa']}', style: const TextStyle(fontSize: 12)),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _abrirModalFormulario(docId: doc.id, dadosAtuais: data)),
                                            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deletarIntegrante(doc.id, nome)),
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
                                  itemCount: _funcoes.length,
                                  itemBuilder: (context, index) {
                                    String funcao = _funcoes[index];
                                    int count = todosOsDocs.where((d) => (d.data() as Map<String, dynamic>)['funcao'] == funcao).length;
                                    Color cor = _corParaFuncao(funcao);
                                    
                                    return _buildDashboardCard(funcao, count, cor, () => _mostrarIntegrantesDaFuncao(funcao, todosOsDocs));
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
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold), 
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