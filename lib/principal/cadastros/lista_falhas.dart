import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

// Importações novas para Exportação (PDF e CSV)
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

import '../../widgets/menu_usuario.dart'; 

class ListaFalhas extends StatefulWidget {
  const ListaFalhas({super.key});

  @override
  State<ListaFalhas> createState() => _ListaFalhasState();
}

class _ListaFalhasState extends State<ListaFalhas> with SingleTickerProviderStateMixin {
  final List<String> _prioridades = ['Baixa', 'Média', 'Alta'];
  
  late TabController _tabController;
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); 
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _deletarFalha(String docId, String nomeFalha) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Falha'),
        content: Text('Tem certeza que deseja excluir a falha "$nomeFalha"?'),
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
        await FirebaseFirestore.instance.collection('falhas').doc(docId).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falha excluída!'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao excluir.'), backgroundColor: Colors.red));
      }
    }
  }

  void _abrirModalFormulario({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    final falhaController = TextEditingController(text: dadosAtuais?['falha'] ?? '');
    final prazoController = TextEditingController(text: dadosAtuais?['prazo']?.toString() ?? '');
    String? prioridadeSelecionada = dadosAtuais?['prioridade'];
    
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
                          isEditando ? 'Editar Falha' : 'Nova Falha',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: falhaController,
                          decoration: const InputDecoration(labelText: 'Descrição da Falha *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.warning_amber_rounded)),
                          validator: (value) => value == null || value.trim().isEmpty ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: prazoController,
                          decoration: const InputDecoration(labelText: 'Prazo (minutos) *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.timer)),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly], 
                          validator: (value) => value == null || value.trim().isEmpty ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Prioridade *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.flag)),
                          value: prioridadeSelecionada,
                          items: _prioridades.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (val) => setStateModal(() => prioridadeSelecionada = val),
                          validator: (value) => value == null ? 'Selecione uma prioridade' : null,
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
                                final dadosFalha = {
                                  'falha': falhaController.text.trim().toUpperCase(),
                                  'prazo': prazoController.text.trim(), 
                                  'prioridade': prioridadeSelecionada,
                                  'dataAtualizacao': FieldValue.serverTimestamp(),
                                };

                                if (isEditando) {
                                  await FirebaseFirestore.instance.collection('falhas').doc(docId).update(dadosFalha);
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado com sucesso!'), backgroundColor: Colors.green));
                                } else {
                                  dadosFalha['dataCadastro'] = FieldValue.serverTimestamp(); 
                                  await FirebaseFirestore.instance.collection('falhas').add(dadosFalha);
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Criado com sucesso!'), backgroundColor: Colors.green));
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                              } finally {
                                setStateModal(() => estaCarregando = false);
                              }
                            }
                          },
                          child: estaCarregando 
                              ? const CircularProgressIndicator(color: Colors.white) 
                              : Text(isEditando ? 'ATUALIZAR' : 'CADASTRAR', style: const TextStyle(color: Colors.white)),
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

  // --- FUNÇÕES DE EXPORTAÇÃO (AGORA COM RODAPÉ E SEPARAÇÃO) ---
  
  // Função auxiliar para formatar a data e hora (Ex: 24/05/2024 às 14:30)
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

    // Separando as falhas por prioridade
    final altas = docs.where((d) => (d.data() as Map<String, dynamic>)['prioridade'] == 'Alta').toList();
    final medias = docs.where((d) => (d.data() as Map<String, dynamic>)['prioridade'] == 'Média').toList();
    final baixas = docs.where((d) => (d.data() as Map<String, dynamic>)['prioridade'] == 'Baixa').toList();

    pdf.addPage(
      pw.MultiPage( // MultiPage permite criar várias páginas automaticamente se a lista for longa
        pageFormat: PdfPageFormat.a4,
        // Configurando o Rodapé em todas as páginas
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 10.0),
            padding: const pw.EdgeInsets.only(top: 10.0),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
            child: pw.Text(
              'Relatório gerado pelo sistema de ocorrências semafóricas - SOS\nGerado em: $dataHora',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              textAlign: pw.TextAlign.center,
            ),
          );
        },
        build: (pw.Context context) {
          List<pw.Widget> conteudo = [
            pw.Text('Relatório de Falhas Cadastradas', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
          ];

          // Função interna para desenhar a tabela de cada prioridade
          void adicionarGrupo(String titulo, List<QueryDocumentSnapshot> grupoDocs, PdfColor corHeader) {
            if (grupoDocs.isEmpty) return; // Se não tiver falhas dessa prioridade, ignora
            
            conteudo.add(pw.Text('Prioridade: $titulo', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: corHeader)));
            conteudo.add(pw.SizedBox(height: 8));
            conteudo.add(
              pw.TableHelper.fromTextArray(
                context: context,
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: corHeader),
                data: <List<String>>[
                  <String>['Falha', 'Prazo de Atendimento'],
                  ...grupoDocs.map((doc) {
                    var d = doc.data() as Map<String, dynamic>;
                    return [d['falha']?.toString() ?? '', '${d['prazo'] ?? '0'} minutos'];
                  }),
                ],
              )
            );
            conteudo.add(pw.SizedBox(height: 20));
          }

          // Adiciona os grupos na ordem de importância
          adicionarGrupo('Alta', altas, PdfColors.red700);
          adicionarGrupo('Média', medias, PdfColors.orange700);
          adicionarGrupo('Baixa', baixas, PdfColors.green700);

          return conteudo;
        },
      ),
    );

    // Abre a tela padrão do sistema para imprimir ou salvar como PDF
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'relatorio_falhas.pdf');
  }

  Future<void> _exportarCSV(List<QueryDocumentSnapshot> docs) async {
    final dataHora = _formatarDataHora();
    List<List<dynamic>> rows = [];

    // Separando as falhas por prioridade
    final altas = docs.where((d) => (d.data() as Map<String, dynamic>)['prioridade'] == 'Alta').toList();
    final medias = docs.where((d) => (d.data() as Map<String, dynamic>)['prioridade'] == 'Média').toList();
    final baixas = docs.where((d) => (d.data() as Map<String, dynamic>)['prioridade'] == 'Baixa').toList();

    // Função interna para formatar o CSV por grupos
    void adicionarGrupo(String titulo, List<QueryDocumentSnapshot> grupoDocs) {
      if (grupoDocs.isEmpty) return;
      rows.add(['--- PRIORIDADE ${titulo.toUpperCase()} ---']);
      rows.add(['Falha', 'Prazo (minutos)']); // Cabeçalho do grupo
      for (var doc in grupoDocs) {
        var d = doc.data() as Map<String, dynamic>;
        rows.add([d['falha'], d['prazo']]);
      }
      rows.add([]); // Linha em branco para separar os grupos
    }

    // Montando as linhas da planilha
    adicionarGrupo('Alta', altas);
    adicionarGrupo('Média', medias);
    adicionarGrupo('Baixa', baixas);

    // Adicionando o Rodapé no final da planilha
    rows.add([]); // Mais uma linha em branco
    rows.add(['Relatório gerado pelo sistema de ocorrências semafóricas - SOS']);
    rows.add(['Gerado em:', dataHora]);

    // Converte a lista em uma string CSV
    String csv = const ListToCsvConverter().convert(rows);
    
    // Converte a string para bytes e cria o arquivo para compartilhamento
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final xFile = XFile.fromData(bytes, name: 'relatorio_falhas.csv', mimeType: 'text/csv');
    
    // Abre a tela de compartilhamento (WhatsApp, Salvar no Drive, etc)
    await Share.shareXFiles([xFile], text: 'Segue o relatório de falhas agrupado por prioridade do SOS_CTTU.');
  }

  // Modal para mostrar as falhas ao clicar nos cards do Dashboard
  void _mostrarFalhasDaPrioridade(String prioridade, List<QueryDocumentSnapshot> todosDocs) {
    // Filtra apenas as falhas da prioridade clicada
    final filtrados = todosDocs.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      return d['prioridade'] == prioridade;
    }).toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Falhas - Prioridade $prioridade'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: filtrados.isEmpty 
              ? const Center(child: Text('Nenhuma falha encontrada.'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) {
                    var d = filtrados[index].data() as Map<String, dynamic>;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.arrow_right),
                      title: Text(d['falha'] ?? ''),
                      subtitle: Text('${d['prazo']} minutos'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gestão de Falhas', style: TextStyle(color: Colors.white)),
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
            Tab(icon: Icon(Icons.list_alt), text: 'Lista de Falhas'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Relatórios'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0 
        ? FloatingActionButton.extended(
            backgroundColor: const Color(0xFF262C38),
            icon: const Icon(Icons.add_alert, color: Colors.white),
            label: const Text('Nova Falha', style: TextStyle(color: Colors.white)),
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
            stream: FirebaseFirestore.instance.collection('falhas').orderBy('falha').snapshots(),
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
                        child: TextField(
                          controller: _buscaController,
                          decoration: InputDecoration(
                            hintText: 'Buscar falha por nome...',
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

                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: todosOsDocs.isEmpty 
                              ? const Center(child: Text('Nenhuma falha cadastrada.', style: TextStyle(color: Colors.white, fontSize: 18)))
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                                  itemCount: todosOsDocs.length,
                                  itemBuilder: (context, index) {
                                    var doc = todosOsDocs[index];
                                    var data = doc.data() as Map<String, dynamic>;

                                    String nomeFalha = data['falha'] ?? 'Sem Descrição';

                                    if (_termoBusca.isNotEmpty && !nomeFalha.toLowerCase().contains(_termoBusca)) {
                                      return const SizedBox.shrink(); 
                                    }

                                    Color corPrioridade = Colors.green;
                                    if (data['prioridade'] == 'Média') corPrioridade = Colors.orange;
                                    if (data['prioridade'] == 'Alta') corPrioridade = Colors.red;

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12.0),
                                      color: Colors.white.withValues(alpha: 0.95),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                        leading: CircleAvatar(
                                          radius: 18,
                                          backgroundColor: corPrioridade, 
                                          child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                                        ),
                                        title: Text(nomeFalha, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Prioridade: ${data['prioridade'] ?? ''}', style: TextStyle(color: corPrioridade, fontWeight: FontWeight.bold, fontSize: 12)),
                                            Text('Prazo: ${data['prazo'] ?? '0'} min', style: const TextStyle(fontSize: 12)),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _abrirModalFormulario(docId: doc.id, dadosAtuais: data)),
                                            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deletarFalha(doc.id, nomeFalha)),
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
                  // ABA 2: DASHBOARD (3 CARDS + EXPORTAÇÃO)
                  // ==========================================
                  Builder(
                    builder: (context) {
                      int qtdBaixa = todosOsDocs.where((d) => (d.data() as Map<String, dynamic>)['prioridade'] == 'Baixa').length;
                      int qtdMedia = todosOsDocs.where((d) => (d.data() as Map<String, dynamic>)['prioridade'] == 'Média').length;
                      int qtdAlta = todosOsDocs.where((d) => (d.data() as Map<String, dynamic>)['prioridade'] == 'Alta').length;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 190, left: 16, right: 16, bottom: 24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _buildDashboardCard('Baixa', qtdBaixa, Colors.green, () => _mostrarFalhasDaPrioridade('Baixa', todosOsDocs))),
                                    const SizedBox(width: 12),
                                    Expanded(child: _buildDashboardCard('Média', qtdMedia, Colors.orange, () => _mostrarFalhasDaPrioridade('Média', todosOsDocs))),
                                    const SizedBox(width: 12),
                                    Expanded(child: _buildDashboardCard('Alta', qtdAlta, Colors.red, () => _mostrarFalhasDaPrioridade('Alta', todosOsDocs))),
                                  ],
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
                                        onPressed: () => _exportarCSV(todosOsDocs),
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
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 8.0),
          child: Column(
            children: [
              Text(valor.toString(), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: cor)),
              const SizedBox(height: 8),
              Text(titulo, style: const TextStyle(fontSize: 16, color: Colors.blueGrey, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}