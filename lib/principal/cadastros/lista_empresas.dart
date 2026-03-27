import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; 
import 'package:brasil_fields/brasil_fields.dart'; 

// Importações para Exportação (PDF e Excel)
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;

import '../../widgets/menu_usuario.dart';

class ListaEmpresas extends StatefulWidget {
  const ListaEmpresas({super.key});

  @override
  State<ListaEmpresas> createState() => _ListaEmpresasState();
}

class _ListaEmpresasState extends State<ListaEmpresas> {
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  // --- Função para Excluir Empresa ---
  Future<void> _deletarEmpresa(String docId, String nome) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Empresa'),
        content: Text('Tem certeza que deseja excluir a empresa $nome?'),
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
        await FirebaseFirestore.instance.collection('empresas').doc(docId).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Empresa excluída!'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao excluir.'), backgroundColor: Colors.red));
      }
    }
  }

  // --- Função que abre o MODAL para ADICIONAR ou EDITAR ---
  void _abrirModalFormulario({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: dadosAtuais?['nome'] ?? '');
    final cnpjController = TextEditingController(text: dadosAtuais?['cnpj'] ?? '');
    final enderecoController = TextEditingController(text: dadosAtuais?['endereco'] ?? '');
    final contatoController = TextEditingController(text: dadosAtuais?['contato'] ?? '');

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
                          isEditando ? 'Editar Empresa' : 'Nova Empresa',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: nomeController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'Nome da Empresa *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business)),
                          validator: (value) => value == null || value.trim().isEmpty ? 'O nome da empresa é obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: cnpjController,
                          decoration: const InputDecoration(labelText: 'CNPJ', border: OutlineInputBorder(), prefixIcon: Icon(Icons.assignment_ind)),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, CnpjInputFormatter()],
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: enderecoController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(labelText: 'Endereço', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on)),
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: contatoController,
                          decoration: const InputDecoration(labelText: 'Contato (Telefone/Celular)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.contact_phone)),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, TelefoneInputFormatter()],
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
                                final dadosEmpresa = {
                                  'nome': nomeController.text.trim().toUpperCase(),
                                  'cnpj': cnpjController.text.trim(),
                                  'endereco': enderecoController.text.trim(),
                                  'contato': contatoController.text.trim(),
                                  'dataAtualizacao': FieldValue.serverTimestamp(),
                                };

                                if (isEditando) {
                                  await FirebaseFirestore.instance.collection('empresas').doc(docId).update(dadosEmpresa);
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado com sucesso!'), backgroundColor: Colors.green));
                                } else {
                                  dadosEmpresa['dataCadastro'] = FieldValue.serverTimestamp();
                                  await FirebaseFirestore.instance.collection('empresas').add(dadosEmpresa);
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
        pageFormat: PdfPageFormat.a4.landscape, 
        footer: (pw.Context context) {
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Relatório gerado pelo Sistema de Ocorrências Semafóricas - SOS - $dataHora',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Página ${context.pageNumber} de ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.Text('Relatório de Empresas Cadastradas', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              data: <List<String>>[
                <String>['Nome da Empresa', 'CNPJ', 'Contato', 'Endereço'],
                ...docs.map((doc) {
                  var d = doc.data() as Map<String, dynamic>;
                  return [d['nome']?.toString() ?? '', d['cnpj']?.toString() ?? '', d['contato']?.toString() ?? '', d['endereco']?.toString() ?? ''];
                }),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'relatorio_empresas.pdf');
  }

  Future<void> _baixarExcel(List<QueryDocumentSnapshot> docs) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Empresas'];
    excel.setDefaultSheet('Empresas');

    sheetObject.appendRow(<CellValue>[TextCellValue("Relatório de Empresas Cadastradas")]);
    sheetObject.appendRow(<CellValue>[TextCellValue("Gerado em: ${_formatarDataHora()}")]);
    sheetObject.appendRow(<CellValue>[TextCellValue("")]); 

    sheetObject.appendRow(<CellValue>[
      TextCellValue("Nome da Empresa"),
      TextCellValue("CNPJ"),
      TextCellValue("Contato"),
      TextCellValue("Endereço"),
    ]);

    for (var doc in docs) {
      var d = doc.data() as Map<String, dynamic>;
      sheetObject.appendRow(<CellValue>[
        TextCellValue(d['nome']?.toString() ?? ''),
        TextCellValue(d['cnpj']?.toString() ?? ''),
        TextCellValue(d['contato']?.toString() ?? ''),
        TextCellValue(d['endereco']?.toString() ?? ''),
      ]);
    }

    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(
        Uint8List.fromList(fileBytes),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: 'relatorio_empresas.xlsx'
      );
      await Share.shareXFiles([xfile], text: 'Relatório de Empresas');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilha Excel baixada com sucesso!'), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gestão de Empresas', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [ MenuUsuario() ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF262C38),
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text('Nova Empresa', style: TextStyle(color: Colors.white)),
        onPressed: () => _abrirModalFormulario(),
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
            stream: FirebaseFirestore.instance.collection('empresas').orderBy('nome').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
              if (snapshot.hasError) return const Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.white)));
              
              final todosOsDocs = snapshot.data?.docs ?? [];

              return Column(
                children: [
                  const SizedBox(height: 100), 
                  
                  // BARRA DE PESQUISA
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: TextField(
                          controller: _buscaController,
                          decoration: InputDecoration(
                            hintText: 'Buscar empresa pelo nome...',
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

                  // BOTÕES DE EXPORTAÇÃO
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                                label: const Text('Gerar PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                onPressed: () => _exportarPDF(todosOsDocs),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.table_chart, color: Colors.white, size: 18),
                                label: const Text('Exportar Planilha', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                onPressed: () => _baixarExcel(todosOsDocs),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // LISTA DE EMPRESAS
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: todosOsDocs.isEmpty 
                          ? const Center(child: Text('Nenhuma empresa cadastrada.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18)))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16, top: 8),
                              itemCount: todosOsDocs.length,
                              itemBuilder: (context, index) {
                                var doc = todosOsDocs[index];
                                var data = doc.data() as Map<String, dynamic>;

                                String nomeEmpresa = data['nome'] ?? 'Sem Nome';

                                if (_termoBusca.isNotEmpty && !nomeEmpresa.toLowerCase().contains(_termoBusca)) {
                                  return const SizedBox.shrink(); 
                                }

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12.0),
                                  color: Colors.white.withValues(alpha: 0.95),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: const CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Color(0xFF262C38),
                                      child: Icon(Icons.factory, color: Colors.white, size: 20),
                                    ),
                                    title: Text(nomeEmpresa, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (data['cnpj'] != null && data['cnpj'].toString().isNotEmpty)
                                          Text('CNPJ: ${data['cnpj']}', style: const TextStyle(fontSize: 12)),
                                        if (data['contato'] != null && data['contato'].toString().isNotEmpty)
                                          Text('Contato: ${data['contato']}', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                          onPressed: () => _abrirModalFormulario(docId: doc.id, dadosAtuais: data),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                          onPressed: () => _deletarEmpresa(doc.id, nomeEmpresa),
                                        ),
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
              );
            }
          ),
        ],
      ),
    );
  }
}