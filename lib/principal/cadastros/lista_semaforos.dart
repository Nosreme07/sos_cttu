import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

// Importações para Exportação (PDF e CSV)
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

import '../../widgets/menu_usuario.dart'; 

class ListaSemaforos extends StatefulWidget {
  const ListaSemaforos({super.key});

  @override
  State<ListaSemaforos> createState() => _ListaSemaforosState();
}

class _ListaSemaforosState extends State<ListaSemaforos> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';
  
  Timer? _debounce; 

  // --- ESTRUTURA INTELIGENTE DO FORMULÁRIO E DETALHES ---
  final List<Map<String, dynamic>> _gruposFormulario = [
    {
      'titulo': 'Informações Gerais',
      'icone': Icons.info_outline,
      'campos': [
        {'key': 'id', 'label': 'Número do Semáforo *'},
        {'key': 'endereco', 'label': 'Endereço *'},
        {'key': 'bairro', 'label': 'Bairro'},
        {'key': 'empresa', 'label': 'Empresa Responsável'},
        {'key': 'georeferencia', 'label': 'Georreferência'},
        {'key': 'rota', 'label': 'Rota'},
        {'key': 'tipo_do_controlador', 'label': 'Tipo do Controlador'},
        {'key': 'id_do_controlador', 'label': 'ID do Controlador'},
        {'key': 'subareas', 'label': 'Subáreas'},
      ]
    },
    {
      'titulo': 'Grupos Focais',
      'icone': Icons.traffic,
      'campos': [
        {'key': 'grupo_focal_veicular_tipo_i', 'label': 'GF Veicular Tipo I (Padrão)'},
        {'key': 'grupo_focal_veicular_tipo_t', 'label': 'GF Veicular Tipo T (Seta)'},
        {'key': 'grupo_focal_pedestre_simples', 'label': 'GF Pedestre Simples'},
        {'key': 'grupo_focal_pedestre_com_cronometro', 'label': 'GF Pedestre com Cronômetro'},
        {'key': 'grupo_focal_faixa_reversivel', 'label': 'GF Faixa Reversível'},
        {'key': 'grupo_focal_ciclista_com_tres_focos', 'label': 'GF Ciclista com Três Focos'},
        {'key': 'grupo_focal_ciclista_com_dois_focos', 'label': 'GF Ciclista com Dois Focos'},
        {'key': 'anteparo_tipo_i', 'label': 'Anteparo Tipo I'},
      ]
    },
    {
      'titulo': 'Veicular e Botoeiras',
      'icone': Icons.touch_app,
      'campos': [
        {'key': 'veicular_com_sequencial', 'label': 'Veicular com Sequencial'},
        {'key': 'veicular_com_cronometro', 'label': 'Veicular com Cronômetro'},
        {'key': 'sirene', 'label': 'Sirene'},
        {'key': 'horario_de_funcionamente_das_sirenes', 'label': 'Horário de Funcionamento da Sirene'},
        {'key': 'botoeira_com_dispositivo_sonoro', 'label': 'Botoeira com Dispositivo Sonoro'},
        {'key': 'botoeira_simples', 'label': 'Botoeira Simples'},
      ]
    },
    {
      'titulo': 'Energia e Comunicação',
      'icone': Icons.electric_bolt,
      'campos': [
        {'key': 'nobreak', 'label': 'Nobreak'},
        {'key': 'kit_bateria', 'label': 'Kit Bateria'},
        {'key': 'numero_do_nobreak', 'label': 'Número do Nobreak'},
        {'key': 'medidor', 'label': 'Medidor (Existente)'},
        {'key': 'numero_do_medidor', 'label': 'Número do Medidor'},
        {'key': 'kit_de_comunicacao', 'label': 'Kit de Comunicação (Existente)'},
        {'key': 'modo_de_funcionamento', 'label': 'Modo de Funcionamento'},
      ]
    },
    {
      'titulo': 'Estrutura Física',
      'icone': Icons.construction,
      'campos': [
        {'key': 'semiportico_conico', 'label': 'Semi-Pórtico Cônico'},
        {'key': 'semiportico_simples', 'label': 'Semi-Pórtico Simples'},
        {'key': 'semiportico_estruturado', 'label': 'Semi-Pórtico Estruturado'},
        {'key': 'portico_simples', 'label': 'Pórtico Simples'},
        {'key': 'portico_estruturado', 'label': 'Pórtico Estruturado'},
        {'key': 'coluna_conica', 'label': 'Coluna Cônica'},
        {'key': 'coluna_simples', 'label': 'Coluna Simples'},
        {'key': 'placa_adesiva_para_botoeira', 'label': 'Placa Adesiva para Botoeira'},
        {'key': 'conjunto_entrada_de_energia_padrao_celpe_instalado', 'label': 'Entrada de Energia CELPE Instalado'},
        {'key': 'conjunto_aterramento_para_colunas', 'label': 'Conjunto Aterramento para Colunas'},
      ]
    },
    {
      'titulo': 'Cabos, Identificação e Documentação',
      'icone': Icons.cable,
      'campos': [
        {'key': 'cabo_2x1mm', 'label': 'Cabo 2x1mm'},
        {'key': 'cabo_3x1mm', 'label': 'Cabo 3x1mm'},
        {'key': 'cabo_4x1mm', 'label': 'Cabo 4x1mm'},
        {'key': 'cabo_7x1mm', 'label': 'Cabo 7x1mm'},
        {'key': 'luminarias', 'label': 'Luminárias'},
        {'key': 'placa_de_identificacao_de_semaforo', 'label': 'Placa de Identificação'},
        {'key': 'fotossensor_equipamento', 'label': 'Fotossensor no Semáforo'},
        {'key': 'conta_contrato', 'label': 'Conta Contrato'},
        {'key': 'link_da_programacao', 'label': 'Link da Programação'},
      ]
    },
    {
      'titulo': 'Observações e Histórico',
      'icone': Icons.history_edu,
      'campos': [
        {'key': 'data_de_implantacao', 'label': 'Data de Implantação'},
        {'key': 'observacoes', 'label': 'Observações (Geral)'},
        {'key': 'observacoes_2', 'label': 'Observações 2 (Adicionais)'},
        {'key': 'historico', 'label': 'Histórico (Intervenções/Eventos)'},
      ]
    }
  ];

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
    _debounce?.cancel(); 
    _tabController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  String _formatarId(String idStr) {
    if (idStr.isEmpty || idStr.contains('NUMERO')) return '000';
    String numeros = idStr.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeros.isEmpty) return idStr; 
    return numeros.padLeft(3, '0');
  }

  Future<void> _deletarSemaforo(String docId, String numeroFormatado) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Semáforo'),
        content: Text('Tem certeza que deseja excluir o semáforo $numeroFormatado?'),
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
        await FirebaseFirestore.instance.collection('semaforos').doc(docId).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Semáforo excluído!'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao excluir.'), backgroundColor: Colors.red));
      }
    }
  }

  void _abrirModalDetalhes(String docId, Map<String, dynamic> data) {
    String numeroFormatado = _formatarId(data['id'] ?? '');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85, 
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Detalhes do Semáforo: $numeroFormatado',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2f3b4c)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: _gruposFormulario.map((grupo) {
                      bool temDado = grupo['campos'].any((c) => (data[c['key']] ?? '').toString().isNotEmpty);
                      if (!temDado) return const SizedBox.shrink();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(grupo['icone'], color: const Color(0xFF2f3b4c), size: 20),
                                const SizedBox(width: 8),
                                Text(grupo['titulo'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2f3b4c))),
                              ],
                            ),
                            const Divider(thickness: 1),
                            const SizedBox(height: 8),
                            ...grupo['campos'].map((campo) {
                              String valor = (data[campo['key']] ?? '').toString();
                              if (valor.isEmpty) return const SizedBox.shrink();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2, 
                                      child: Text('${campo['label'].replaceAll(' *', '')}:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))
                                    ),
                                    Expanded(
                                      flex: 3, 
                                      child: Text(valor, style: const TextStyle(fontSize: 14, color: Colors.black54))
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    icon: const Icon(Icons.edit, color: Colors.white, size: 18),
                    label: const Text('Editar', style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      Navigator.pop(context); 
                      _abrirModalFormulario(docId: docId, dadosAtuais: data); 
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                    label: const Text('PDF', style: TextStyle(color: Colors.white)),
                    onPressed: () => _exportarPdfIndividual(data, numeroFormatado),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.table_chart, color: Colors.white, size: 18),
                    label: const Text('Planilha', style: TextStyle(color: Colors.white)),
                    onPressed: () => _exportarCsvIndividual(data, numeroFormatado),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.black54),
                    icon: const Icon(Icons.delete, color: Colors.white, size: 18),
                    label: const Text('Excluir', style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      Navigator.pop(context); 
                      _deletarSemaforo(docId, numeroFormatado);
                    },
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  void _abrirModalFormulario({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    bool estaCarregando = false;
    bool isEditando = docId != null;

    final Map<String, TextEditingController> controllers = {};
    for (var grupo in _gruposFormulario) {
      for (var campo in grupo['campos']) {
        String key = campo['key'];
        controllers[key] = TextEditingController(text: dadosAtuais?[key] ?? '');
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: EdgeInsets.only(top: 60, bottom: MediaQuery.of(context).viewInsets.bottom), 
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: formKey,
                  child: Column( 
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isEditando ? 'Editar Semáforo' : 'Cadastrar Novo Semáforo',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2f3b4c)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: _gruposFormulario.map((grupo) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(grupo['icone'], color: const Color(0xFF2f3b4c)),
                                        const SizedBox(width: 8),
                                        Text(grupo['titulo'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2f3b4c))),
                                      ],
                                    ),
                                    const Divider(thickness: 1),
                                    const SizedBox(height: 8),
                                    ...grupo['campos'].map((campo) {
                                      String key = campo['key'];
                                      bool isMultilinha = key == 'endereco' || key.contains('observacoes') || key == 'historico';
                                      
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: TextFormField(
                                          controller: controllers[key],
                                          maxLines: isMultilinha ? 3 : 1,
                                          decoration: InputDecoration(
                                            labelText: campo['label'],
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                            fillColor: Colors.white,
                                            filled: true,
                                          ),
                                          validator: (key == 'id' || key == 'endereco') 
                                              ? (value) => value == null || value.trim().isEmpty ? 'Campo obrigatório' : null 
                                              : null,
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF61c764), 
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: estaCarregando ? null : () async {
                          if (formKey.currentState!.validate()) {
                            setStateModal(() => estaCarregando = true);
                            try {
                              Map<String, dynamic> dadosParaSalvar = {};
                              controllers.forEach((key, controller) {
                                dadosParaSalvar[key] = controller.text.trim().toUpperCase();
                              });
                              dadosParaSalvar['dataAtualizacao'] = FieldValue.serverTimestamp();

                              if (isEditando) {
                                await FirebaseFirestore.instance.collection('semaforos').doc(docId).update(dadosParaSalvar);
                                if (mounted) Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado com sucesso!'), backgroundColor: Colors.green));
                              } else {
                                dadosParaSalvar['dataCadastro'] = FieldValue.serverTimestamp(); 
                                await FirebaseFirestore.instance.collection('semaforos').add(dadosParaSalvar);
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
                            : const Text('Salvar Alterações', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatarDataHora() {
    final now = DateTime.now();
    final dia = now.day.toString().padLeft(2, '0');
    final mes = now.month.toString().padLeft(2, '0');
    final ano = now.year.toString();
    final hora = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$ano às $hora:$min';
  }

  Future<void> _exportarPdfIndividual(Map<String, dynamic> data, String numeroFormatado) async {
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
            child: pw.Text(
              'Relatório gerado pelo sistema de ocorrências semafóricas - SOS\nGerado em: $dataHora',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              textAlign: pw.TextAlign.center,
            ),
          );
        },
        build: (pw.Context context) {
          List<pw.Widget> conteudo = [
            pw.Text('Ficha Técnica do Semáforo $numeroFormatado', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
          ];

          for (var grupo in _gruposFormulario) {
            bool temDado = grupo['campos'].any((c) => (data[c['key']] ?? '').toString().isNotEmpty);
            if (!temDado) continue;

            conteudo.add(pw.Text(grupo['titulo'], style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)));
            conteudo.add(pw.SizedBox(height: 8));

            List<List<String>> tabelaGrupo = [];
            for (var campo in grupo['campos']) {
              String valor = (data[campo['key']] ?? '').toString();
              if (valor.isNotEmpty) {
                tabelaGrupo.add([campo['label'].toString().replaceAll(' *', ''), valor]);
              }
            }

            conteudo.add(
              pw.TableHelper.fromTextArray(
                context: context,
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey600),
                data: <List<String>>[
                  <String>['Campo', 'Informação'],
                  ...tabelaGrupo,
                ],
              )
            );
            conteudo.add(pw.SizedBox(height: 20));
          }

          return conteudo;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'semaforo_$numeroFormatado.pdf');
  }

  Future<void> _exportarCsvIndividual(Map<String, dynamic> data, String numeroFormatado) async {
    final dataHora = _formatarDataHora();
    List<List<dynamic>> rows = [];

    rows.add(['FICHA TÉCNICA - SEMÁFORO $numeroFormatado']);
    rows.add([]);

    for (var grupo in _gruposFormulario) {
      bool temDado = grupo['campos'].any((c) => (data[c['key']] ?? '').toString().isNotEmpty);
      if (!temDado) continue;

      rows.add(['--- ${grupo['titulo'].toString().toUpperCase()} ---']);
      rows.add(['Campo', 'Informação']);
      for (var campo in grupo['campos']) {
        String valor = (data[campo['key']] ?? '').toString();
        if (valor.isNotEmpty) {
          rows.add([campo['label'].toString().replaceAll(' *', ''), valor]);
        }
      }
      rows.add([]);
    }

    rows.add(['Relatório gerado pelo sistema de ocorrências semafóricas - SOS']);
    rows.add(['Gerado em:', dataHora]);

    String csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final xFile = XFile.fromData(bytes, name: 'semaforo_$numeroFormatado.csv', mimeType: 'text/csv');
    
    await Share.shareXFiles([xFile], text: 'Segue a ficha técnica do semáforo $numeroFormatado.');
  }

  // --- FUNÇÕES DE EXPORTAÇÃO GLOBAL ---
  Future<void> _exportarCsvGlobal(List<QueryDocumentSnapshot> docs) async {
    List<List<dynamic>> rows = [];

    List<String> cabecalho = [];
    List<String> chaves = [];
    for (var grupo in _gruposFormulario) {
      for (var campo in grupo['campos']) {
        cabecalho.add(campo['label'].toString().replaceAll(' *', ''));
        chaves.add(campo['key']);
      }
    }
    rows.add(cabecalho);

    for (var doc in docs) {
      var d = doc.data() as Map<String, dynamic>;
      List<dynamic> linha = [];
      for (String chave in chaves) {
        linha.add(d[chave] ?? '');
      }
      rows.add(linha);
    }

    String csv = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final xFile = XFile.fromData(bytes, name: 'acervo_completo_semaforos.csv', mimeType: 'text/csv');
    await Share.shareXFiles([xFile], text: 'Acervo completo de semáforos.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Acervo Semafórico', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [
          MenuUsuario(),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.green,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Lista'),
            Tab(icon: Icon(Icons.file_download), text: 'Exportação'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0 
        ? FloatingActionButton.extended(
            backgroundColor: const Color(0xFF61c764), 
            icon: const Icon(Icons.traffic, color: Colors.white),
            label: const Text('Novo Semáforo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            stream: FirebaseFirestore.instance.collection('semaforos').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
              if (snapshot.hasError) return const Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.white)));
              
              final docsDesordenados = snapshot.data?.docs.toList() ?? [];
              
              // --- ORDENAÇÃO NUMÉRICA ---
              docsDesordenados.sort((a, b) {
                String idA = (a.data() as Map<String, dynamic>)['id']?.toString() ?? '';
                String idB = (b.data() as Map<String, dynamic>)['id']?.toString() ?? '';
                
                int numA = int.tryParse(idA.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                int numB = int.tryParse(idB.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                
                return numA.compareTo(numB);
              });
              
              final todosOsDocs = docsDesordenados;

              return TabBarView(
                controller: _tabController,
                children: [
                  
                  // ==========================================
                  // ABA 1: LISTA PRINCIPAL
                  // ==========================================
                  Column(
                    children: [
                      const SizedBox(height: 220), 
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: TextField(
                              controller: _buscaController,
                              decoration: InputDecoration(
                                hintText: 'Buscar por Número ou Endereço...',
                                prefixIcon: const Icon(Icons.search),
                                fillColor: Colors.white.withValues(alpha: 0.95),
                                filled: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                              ),
                              onChanged: (valor) {
                                if (_debounce?.isActive ?? false) _debounce!.cancel();
                                _debounce = Timer(const Duration(milliseconds: 400), () {
                                  setState(() { _termoBusca = valor.toLowerCase(); });
                                });
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
                              ? const Center(child: Text('Nenhum semáforo cadastrado.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18)))
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16, top: 8),
                                  itemCount: todosOsDocs.length,
                                  itemBuilder: (context, index) {
                                    var doc = todosOsDocs[index];
                                    var data = doc.data() as Map<String, dynamic>;

                                    String idOriginal = data['id'] ?? '';
                                    String idFormatado = _formatarId(idOriginal);
                                    String endereco = data['endereco'] ?? '';
                                    String bairro = data['bairro'] ?? '';
                                    String empresa = data['empresa'] ?? '';

                                    // BUSCA APENAS POR NÚMERO OU ENDEREÇO
                                    if (_termoBusca.isNotEmpty && 
                                        !idOriginal.toLowerCase().contains(_termoBusca) &&
                                        !idFormatado.toLowerCase().contains(_termoBusca) &&
                                        !endereco.toLowerCase().contains(_termoBusca)) {
                                      return const SizedBox.shrink(); 
                                    }

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12.0),
                                      color: Colors.white.withValues(alpha: 0.95),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      child: ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        leading: const CircleAvatar(
                                          radius: 20,
                                          backgroundColor: Colors.amber, 
                                          child: Icon(Icons.traffic, color: Colors.black87, size: 22),
                                        ),
                                        title: Text('$idFormatado - $endereco', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4.0),
                                          child: Text('Bairro: $bairro\nEmpresa: $empresa', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                        ),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.visibility, color: Color(0xFF2f3b4c), size: 28),
                                          tooltip: 'Ver Detalhes',
                                          onPressed: () => _abrirModalDetalhes(doc.id, data),
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
                  // ABA 2: EXPORTAÇÃO
                  // ==========================================
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 220, left: 16, right: 16, bottom: 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Exportar Base Completa', 
                              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), 
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color.fromARGB(255, 4, 14, 5),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.table_chart, color: Colors.white, size: 24),
                              label: const Text('Exportar Planilha de Todo o Acervo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              onPressed: () => _exportarCsvGlobal(todosOsDocs),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )

                ],
              );
            }
          ),
        ],
      ),
    );
  }
}