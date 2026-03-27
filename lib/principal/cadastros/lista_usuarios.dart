import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

// Importações para Exportação (PDF e Excel)
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;

import '../../widgets/menu_usuario.dart'; 

class ListaUsuarios extends StatefulWidget {
  const ListaUsuarios({super.key});

  @override
  State<ListaUsuarios> createState() => _ListaUsuariosState();
}

class _ListaUsuariosState extends State<ListaUsuarios> with SingleTickerProviderStateMixin {
  // Lista de perfis para o Dropdown (se adicionar aqui, vai pro form e pro dashboard automaticamente!)
  final List<String> _perfis = [
    'Callcenter', 
    'Vistoriador', 
    'Equipe técnica',
    'Operador central', 
    'Administrador', 
    'Desenvolvedor'
  ];

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

  // --- Função para Excluir Usuário ---
  Future<void> _deletarUsuario(String docId, String nome) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Usuário'),
        content: Text('Tem certeza que deseja excluir o usuário $nome?'),
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
        await FirebaseFirestore.instance.collection('usuarios').doc(docId).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuário excluído!'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao excluir.'), backgroundColor: Colors.red));
      }
    }
  }

  // --- Função que abre o MODAL para ADICIONAR ou EDITAR ---
  void _abrirModalFormulario({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: dadosAtuais?['nomeCompleto'] ?? '');
    final usuarioController = TextEditingController(text: dadosAtuais?['username'] ?? '');
    final emailController = TextEditingController(text: dadosAtuais?['email'] ?? '');
    final senhaController = TextEditingController(); 
    String? perfilSelecionado = dadosAtuais?['perfil'];
    
    bool ocultarSenha = true;
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
                          isEditando ? 'Editar Usuário' : 'Novo Usuário',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: nomeController,
                          decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                          validator: (value) => value!.isEmpty ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: usuarioController,
                          decoration: const InputDecoration(labelText: 'Usuário (nome.sobrenome)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge)),
                          enabled: !isEditando,
                          validator: (value) {
                            if (value!.isEmpty) return 'Obrigatório';
                            if (!value.contains('.')) return 'Formato inválido';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: emailController,
                          decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                          enabled: !isEditando, 
                          validator: (value) => !value!.contains('@') ? 'E-mail inválido' : null,
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Perfil de Acesso', border: OutlineInputBorder(), prefixIcon: Icon(Icons.admin_panel_settings)),
                          value: perfilSelecionado,
                          items: _perfis.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (val) => setStateModal(() => perfilSelecionado = val),
                          validator: (value) => value == null ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: senhaController,
                          obscureText: ocultarSenha,
                          decoration: InputDecoration(
                            labelText: isEditando ? 'Nova Senha (deixe em branco para não alterar)' : 'Senha',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(ocultarSenha ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setStateModal(() => ocultarSenha = !ocultarSenha),
                            ),
                          ),
                          validator: (value) {
                            if (!isEditando && value!.isEmpty) return 'Obrigatório';
                            if (value!.isNotEmpty && !RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{7,}$').hasMatch(value)) {
                              return 'Mínimo 7 caracteres, c/ letra e número';
                            }
                            return null;
                          },
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
                                if (isEditando) {
                                  await FirebaseFirestore.instance.collection('usuarios').doc(docId).update({
                                    'nomeCompleto': nomeController.text.trim().toUpperCase(),
                                    'perfil': perfilSelecionado,
                                  });
                                  if (mounted) Navigator.pop(context); 
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado com sucesso!'), backgroundColor: Colors.green));
                                } else {
                                  UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                                    email: emailController.text.trim(),
                                    password: senhaController.text,
                                  );

                                  await FirebaseFirestore.instance.collection('usuarios').doc(cred.user!.uid).set({
                                    'nomeCompleto': nomeController.text.trim().toUpperCase(),
                                    'username': usuarioController.text.trim().toLowerCase(),
                                    'email': emailController.text.trim().toLowerCase(),
                                    'perfil': perfilSelecionado,
                                    'dataCadastro': FieldValue.serverTimestamp(),
                                    'ativo': true,
                                  });

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
            pw.Text('Relatório de Usuários Cadastrados', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
          ];

          for (String perfil in _perfis) {
            final grupoDocs = docs.where((d) => (d.data() as Map<String, dynamic>)['perfil'] == perfil).toList();
            if (grupoDocs.isEmpty) continue; 
            
            conteudo.add(pw.Text('Perfil: $perfil', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)));
            conteudo.add(pw.SizedBox(height: 8));
            conteudo.add(
              pw.TableHelper.fromTextArray(
                context: context,
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                data: <List<String>>[
                  <String>['Nome', 'Usuário', 'E-mail'],
                  ...grupoDocs.map((doc) {
                    var d = doc.data() as Map<String, dynamic>;
                    return [d['nomeCompleto']?.toString() ?? '', d['username']?.toString() ?? '', d['email']?.toString() ?? ''];
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

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'relatorio_usuarios.pdf');
  }

  // --- EXPORTAÇÃO EXCEL XLSX (Substituindo o CSV) ---
  Future<void> _baixarExcel(List<QueryDocumentSnapshot> docs) async {
    final dataHora = _formatarDataHora();
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Usuários'];
    excel.setDefaultSheet('Usuários');

    for (String perfil in _perfis) {
      final grupoDocs = docs.where((d) => (d.data() as Map<String, dynamic>)['perfil'] == perfil).toList();
      if (grupoDocs.isEmpty) continue;
      
      sheetObject.appendRow(<CellValue>[TextCellValue("--- PERFIL: ${perfil.toUpperCase()} ---")]);
      sheetObject.appendRow(<CellValue>[TextCellValue("Nome"), TextCellValue("Usuário"), TextCellValue("E-mail")]); 
      
      for (var doc in grupoDocs) {
        var d = doc.data() as Map<String, dynamic>;
        sheetObject.appendRow(<CellValue>[
          TextCellValue((d['nomeCompleto'] ?? '').toString()),
          TextCellValue((d['username'] ?? '').toString()),
          TextCellValue((d['email'] ?? '').toString()),
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
        name: 'relatorio_usuarios.xlsx'
      );
      
      await Share.shareXFiles([xfile], text: 'Segue o relatório de usuários do SOS.');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilha Excel baixada com sucesso!'), backgroundColor: Colors.green));
    }
  }

  // Mostra usuários ao clicar nos cards do Dashboard
  void _mostrarUsuariosDoPerfil(String perfil, List<QueryDocumentSnapshot> todosDocs) {
    final filtrados = todosDocs.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      return d['perfil'] == perfil;
    }).toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Usuários - $perfil'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: filtrados.isEmpty 
              ? const Center(child: Text('Nenum usuário encontrado.'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) {
                    var d = filtrados[index].data() as Map<String, dynamic>;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person),
                      title: Text(d['nomeCompleto'] ?? ''),
                      subtitle: Text(d['username'] ?? ''),
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

  // --- Função para gerar cor baseada no nome do perfil ---
  Color _corParaPerfil(String perfil) {
    switch (perfil) {
      case 'Administrador': return Colors.deepPurple;
      case 'Operador central': return Colors.blue;
      case 'Equipe técnica': return Colors.orange;
      case 'Vistoriador': return Colors.teal;
      case 'Callcenter': return Colors.pink;
      case 'Desenvolvedor': return Colors.blueGrey;
      default: return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gestão de Usuários', style: TextStyle(color: Colors.white)),
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
            icon: const Icon(Icons.person_add, color: Colors.white),
            label: const Text('Novo Usuário', style: TextStyle(color: Colors.white)),
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
            stream: FirebaseFirestore.instance.collection('usuarios').orderBy('nomeCompleto').snapshots(),
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
                                hintText: 'Buscar usuário pelo nome...',
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
                              ? const Center(child: Text('Nenhum usuário cadastrado.', style: TextStyle(color: Colors.white, fontSize: 18)))
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                                  itemCount: todosOsDocs.length,
                                  itemBuilder: (context, index) {
                                    var doc = todosOsDocs[index];
                                    var data = doc.data() as Map<String, dynamic>;

                                    String nomeUsuario = data['nomeCompleto'] ?? 'Sem Nome';

                                    if (_termoBusca.isNotEmpty && !nomeUsuario.toLowerCase().contains(_termoBusca)) {
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
                                          backgroundColor: _corParaPerfil(data['perfil'] ?? ''), // Pinta a bolinha com a cor do perfil
                                          child: Text(
                                            nomeUsuario.isNotEmpty ? nomeUsuario[0].toUpperCase() : '?',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        title: Text(nomeUsuario, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('User: ${data['username'] ?? ''}', style: const TextStyle(fontSize: 12)),
                                            Text('Perfil: ${data['perfil'] ?? ''}', style: const TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _abrirModalFormulario(docId: doc.id, dadosAtuais: data)),
                                            IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deletarUsuario(doc.id, nomeUsuario)),
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
                                // Grid dinâmico que lê todos os perfis da lista
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(), // Impede scroll interno, deixa a tela rolar inteira
                                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 180, // Largura máxima de cada card (ele cria várias colunas sozinho)
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    childAspectRatio: 1.0, // Formato quadradinho
                                  ),
                                  itemCount: _perfis.length,
                                  itemBuilder: (context, index) {
                                    String perfil = _perfis[index];
                                    int count = todosOsDocs.where((d) => (d.data() as Map<String, dynamic>)['perfil'] == perfil).length;
                                    Color cor = _corParaPerfil(perfil);
                                    
                                    return _buildDashboardCard(perfil, count, cor, () => _mostrarUsuariosDoPerfil(perfil, todosOsDocs));
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

  // --- Centraliza o conteúdo dentro dos cards do Dashboard ---
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
            mainAxisAlignment: MainAxisAlignment.center, // Alinha ao centro vertical
            crossAxisAlignment: CrossAxisAlignment.center, // Alinha ao centro horizontal
            children: [
              Text(valor.toString(), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: cor)),
              const SizedBox(height: 8),
              Text(
                titulo, 
                style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.bold), 
                textAlign: TextAlign.center,
                maxLines: 2, // Garante que perfis com nomes longos caibam na tela
              ),
            ],
          ),
        ),
      ),
    );
  }
}