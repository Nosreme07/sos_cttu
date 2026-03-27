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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class ListaMateriais extends StatefulWidget {
  const ListaMateriais({super.key});

  @override
  State<ListaMateriais> createState() => _ListaMateriaisState();
}

class _ListaMateriaisState extends State<ListaMateriais> {
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';

  // Lista fixa de unidades para o Dropdown
  final List<String> _unidades = ['Unidade', 'Metro', 'Quilo', 'Caixa'];

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  // --- Função para Excluir Material ---
  Future<void> _deletarMaterial(String docId, String nomeMaterial) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Material'),
        content: Text('Tem certeza que deseja excluir o material "$nomeMaterial"?'),
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
        await FirebaseFirestore.instance.collection('materiais').doc(docId).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Material excluído!'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao excluir.'), backgroundColor: Colors.red));
      }
    }
  }

  // --- Função que abre o MODAL para ADICIONAR ou EDITAR ---
  void _abrirModalFormulario({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: dadosAtuais?['nome'] ?? '');
    
    String unidadeSalva = dadosAtuais?['unidade']?.toString().toUpperCase() ?? 'UNIDADE';
    String unidadeInicial = 'Unidade';
    if (unidadeSalva == 'M' || unidadeSalva == 'METRO') unidadeInicial = 'Metro';
    if (unidadeSalva == 'KG' || unidadeSalva == 'QUILO') unidadeInicial = 'Quilo';
    if (unidadeSalva == 'CX' || unidadeSalva == 'CAIXA') unidadeInicial = 'Caixa';

    String? unidadeSelecionada = unidadeInicial;
    
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
                          isEditando ? 'Editar Material' : 'Novo Material',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: nomeController,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                          decoration: const InputDecoration(labelText: 'Descrição do Material *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.build)),
                          validator: (value) => value == null || value.trim().isEmpty ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Unidade de Medida *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.straighten)),
                          value: unidadeSelecionada,
                          items: _unidades.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                          onChanged: (val) => setStateModal(() => unidadeSelecionada = val),
                          validator: (value) => value == null ? 'Selecione a unidade' : null,
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
                                final dadosMaterial = {
                                  'nome': nomeController.text.trim().toUpperCase(),
                                  'unidade': unidadeSelecionada, 
                                  'dataAtualizacao': FieldValue.serverTimestamp(),
                                };

                                if (isEditando) {
                                  await FirebaseFirestore.instance.collection('materiais').doc(docId).update(dadosMaterial);
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado com sucesso!'), backgroundColor: Colors.green));
                                } else {
                                  dadosMaterial['dataCadastro'] = FieldValue.serverTimestamp(); 
                                  await FirebaseFirestore.instance.collection('materiais').add(dadosMaterial);
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
          return [
            pw.Text('Relatório de Materiais Cadastrados', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              data: <List<String>>[
                <String>['Descrição do Material', 'Unidade de Medida'],
                ...docs.map((doc) {
                  var d = doc.data() as Map<String, dynamic>;
                  return [d['nome']?.toString() ?? '', d['unidade']?.toString() ?? ''];
                }),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'relatorio_materiais.pdf');
  }

  Future<void> _baixarExcel(List<QueryDocumentSnapshot> docs) async {
    final dataHora = _formatarDataHora();
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Materiais'];
    excel.setDefaultSheet('Materiais');

    sheetObject.appendRow(<CellValue>[TextCellValue("Relatório de Materiais Cadastrados")]);
    sheetObject.appendRow(<CellValue>[TextCellValue("Gerado em: $dataHora")]);
    sheetObject.appendRow(<CellValue>[TextCellValue("")]);

    sheetObject.appendRow(<CellValue>[
      TextCellValue("Descrição do Material"),
      TextCellValue("Unidade de Medida")
    ]);

    for (var doc in docs) {
      var d = doc.data() as Map<String, dynamic>;
      sheetObject.appendRow(<CellValue>[
        TextCellValue((d['nome'] ?? '').toString()),
        TextCellValue((d['unidade'] ?? '').toString()),
      ]);
    }

    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(
        Uint8List.fromList(fileBytes),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: 'relatorio_materiais.xlsx'
      );
      
      await Share.shareXFiles([xfile], text: 'Segue o relatório de materiais do SOS.');
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilha Excel baixada com sucesso!'), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Gestão de Materiais', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [ MenuUsuario() ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF262C38),
        icon: const Icon(Icons.add_box, color: Colors.white),
        label: const Text('Novo Material', style: TextStyle(color: Colors.white)),
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
            stream: FirebaseFirestore.instance.collection('materiais').orderBy('nome').snapshots(),
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
                            hintText: 'Buscar material...',
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

                  // LISTA DE MATERIAIS
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: todosOsDocs.isEmpty 
                          ? const Center(child: Text('Nenhum material cadastrado.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18)))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16, top: 8),
                              itemCount: todosOsDocs.length,
                              itemBuilder: (context, index) {
                                var doc = todosOsDocs[index];
                                var data = doc.data() as Map<String, dynamic>;

                                String nomeMaterial = data['nome'] ?? 'Sem Nome';

                                if (_termoBusca.isNotEmpty && !nomeMaterial.toLowerCase().contains(_termoBusca)) {
                                  return const SizedBox.shrink(); 
                                }

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12.0),
                                  color: Colors.white.withValues(alpha: 0.95),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    leading: const CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Color(0xFF262C38), 
                                      child: Icon(Icons.inventory, color: Colors.white, size: 20),
                                    ),
                                    title: Text(nomeMaterial, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Text('Unidade: ${data['unidade'] ?? 'Unidade'}', style: const TextStyle(fontSize: 12)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => _abrirModalFormulario(docId: doc.id, dadosAtuais: data)),
                                        IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deletarMaterial(doc.id, nomeMaterial)),
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