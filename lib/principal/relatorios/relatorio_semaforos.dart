import 'dart:convert';
import 'dart:typed_data'; // <-- Adicionado para o Excel (Uint8List)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart'; // <-- Adicionado para data e hora no PDF
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

// Classe auxiliar para gerenciar os dezenas de checkboxes
class FiltroCheckbox {
  String label;
  String dbField;
  bool ativo;
  FiltroCheckbox(this.label, this.dbField, this.ativo);
}

class TelaRelatorioSemaforos extends StatefulWidget {
  const TelaRelatorioSemaforos({super.key});

  @override
  State<TelaRelatorioSemaforos> createState() => _TelaRelatorioSemaforosState();
}

class _TelaRelatorioSemaforosState extends State<TelaRelatorioSemaforos> {
  bool _isLoading = true;
  bool _mostrarFiltros = true;
  
  // Paginação
  int _paginaAtual = 0;
  final int _itensPorPagina = 50;

  // Base de dados local para filtro rápido
  List<Map<String, dynamic>> _todosSemaforos = [];

  // Filtros de Texto (Controllers)
  final TextEditingController _fNumero = TextEditingController();
  final TextEditingController _fEndereco = TextEditingController();
  final TextEditingController _fBairro = TextEditingController();
  final TextEditingController _fEmpresa = TextEditingController();
  final TextEditingController _fRota = TextEditingController();
  final TextEditingController _fData = TextEditingController(); 
  final TextEditingController _fControlador = TextEditingController();
  final TextEditingController _fModo = TextEditingController();
  final TextEditingController _fConta = TextEditingController();
  final TextEditingController _fMedidor = TextEditingController();

  // FocusNodes para o Autocomplete
  final FocusNode _focusNumero = FocusNode();
  final FocusNode _focusEndereco = FocusNode();
  final FocusNode _focusBairro = FocusNode();
  final FocusNode _focusEmpresa = FocusNode();
  final FocusNode _focusRota = FocusNode();
  final FocusNode _focusData = FocusNode();
  final FocusNode _focusControlador = FocusNode();
  final FocusNode _focusModo = FocusNode();
  final FocusNode _focusConta = FocusNode();
  final FocusNode _focusMedidor = FocusNode();

  // Opções extraídas do banco para os Autocompletes
  List<String> _opcoesNumero = [];
  List<String> _opcoesEndereco = [];
  List<String> _opcoesBairro = [];
  List<String> _opcoesEmpresa = [];
  List<String> _opcoesRota = [];
  List<String> _opcoesData = [];
  List<String> _opcoesControlador = [];
  List<String> _opcoesModo = [];
  List<String> _opcoesConta = [];
  List<String> _opcoesMedidor = [];

  // Lista de Filtros Booleanos
  final List<FiltroCheckbox> _filtrosBooleanos = [
    FiltroCheckbox('GF Veicular Tipo I', 'grupo_focal_veicular_tipo_i', false),
    FiltroCheckbox('GF Veicular Tipo T', 'grupo_focal_veicular_tipo_t', false),
    FiltroCheckbox('GF Pedestre Simples', 'grupo_focal_pedestre_simples', false),
    FiltroCheckbox('GF Pedestre Cron.', 'grupo_focal_pedestre_com_cronometro', false),
    FiltroCheckbox('GF Ciclista (3 focos)', 'grupo_focal_ciclista_com_tres_focos', false),
    FiltroCheckbox('GF Ciclista (2 focos)', 'grupo_focal_ciclista_com_dois_focos', false),
    FiltroCheckbox('GF Faixa Reversível', 'grupo_focal_faixa_reversivel', false),
    FiltroCheckbox('Veic. Sequencial', 'veicular_com_sequencial', false),
    FiltroCheckbox('Veic. Cronômetro', 'veicular_com_cronometro', false),
    FiltroCheckbox('Botoeira Sonora', 'botoeira_com_dispositivo_sonoro', false),
    FiltroCheckbox('Botoeira Simples', 'botoeira_simples', false),
    FiltroCheckbox('Sirene', 'sirene', false),
    FiltroCheckbox('Nobreak', 'nobreak', false),
    FiltroCheckbox('Possui Medidor', 'medidor', false),
    FiltroCheckbox('Kit Comunicação', 'kit_de_comunicacao', false),
    FiltroCheckbox('Fotossensor', 'fotossensor_equipamento', false),
    FiltroCheckbox('Pórtico Estruturado', 'portico_estruturado', false),
    FiltroCheckbox('Pórtico Simples', 'portico_simples', false),
    FiltroCheckbox('Semipórtico Estrut.', 'semiportico_estruturado', false),
    FiltroCheckbox('Semipórtico Simples', 'semiportico_simples', false),
    FiltroCheckbox('Semipórtico Cônico', 'semiportico_conico', false),
    FiltroCheckbox('Coluna Cônica', 'coluna_conica', false),
    FiltroCheckbox('Coluna Simples', 'coluna_simples', false),
    FiltroCheckbox('Anteparo Tipo I', 'anteparo_tipo_i', false),
    FiltroCheckbox('Luminárias', 'luminarias', false),
  ];

  // --- ESTRUTURA PARA OS DETALHES COMPLETOS (Ficha Técnica) ---
  final List<Map<String, dynamic>> _gruposFormulario = [
    {
      'titulo': 'Informações Gerais',
      'icone': Icons.info_outline,
      'campos': [
        {'key': 'numero_formatado', 'label': 'Número do Semáforo'},
        {'key': 'endereco', 'label': 'Endereço'},
        {'key': 'bairro', 'label': 'Bairro'},
        {'key': 'empresa', 'label': 'Empresa Responsável'},
        {'key': 'georeferencia', 'label': 'Georreferência'},
        {'key': 'rota', 'label': 'Rota'},
        {'key': 'tipo_do_controlador', 'label': 'Tipo do Controlador'},
        {'key': 'id_do_controlador', 'label': 'ID do Controlador'},
        {'key': 'subareas', 'label': 'Subáreas'},
      ],
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
      ],
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
      ],
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
      ],
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
      ],
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
      ],
    },
    {
      'titulo': 'Observações e Histórico',
      'icone': Icons.history_edu,
      'campos': [
        {'key': 'data_de_implantacao', 'label': 'Data de Implantação'},
        {'key': 'observacoes', 'label': 'Observações (Geral)'},
        {'key': 'observacoes_2', 'label': 'Observações 2 (Adicionais)'},
        {'key': 'historico', 'label': 'Histórico (Intervenções/Eventos)'},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _fNumero.dispose();
    _fEndereco.dispose();
    _fBairro.dispose();
    _fEmpresa.dispose();
    _fRota.dispose();
    _fData.dispose();
    _fControlador.dispose();
    _fModo.dispose();
    _fConta.dispose();
    _fMedidor.dispose();
    
    _focusNumero.dispose();
    _focusEndereco.dispose();
    _focusBairro.dispose();
    _focusEmpresa.dispose();
    _focusRota.dispose();
    _focusData.dispose();
    _focusControlador.dispose();
    _focusModo.dispose();
    _focusConta.dispose();
    _focusMedidor.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('semaforos').get();
      List<Map<String, dynamic>> listaLocal = [];

      Set<String> setNumero = {};
      Set<String> setEndereco = {};
      Set<String> setBairro = {};
      Set<String> setEmpresa = {};
      Set<String> setRota = {};
      Set<String> setData = {};
      Set<String> setControlador = {};
      Set<String> setModo = {};
      Set<String> setConta = {};
      Set<String> setMedidor = {};

      for (var doc in snapshot.docs) {
        var d = doc.data();
        
        // Formatar número para 3 dígitos com zero à esquerda
        String rawNum = (d['id'] ?? d['numero'] ?? '').toString().trim();
        int? numVal = int.tryParse(rawNum);
        String numeroFormatado = numVal != null ? numVal.toString().padLeft(3, '0') : rawNum.padLeft(3, '0');
        d['numero_formatado'] = numeroFormatado;
        
        listaLocal.add(d);

        if (numeroFormatado.isNotEmpty) setNumero.add(numeroFormatado);
        if ((d['endereco'] ?? '').toString().isNotEmpty) setEndereco.add(d['endereco'].toString().toUpperCase());
        if ((d['bairro'] ?? '').toString().isNotEmpty) setBairro.add(d['bairro'].toString().toUpperCase());
        if ((d['empresa'] ?? '').toString().isNotEmpty) setEmpresa.add(d['empresa'].toString().toUpperCase());
        if ((d['rota'] ?? '').toString().isNotEmpty) setRota.add(d['rota'].toString().toUpperCase());
        if ((d['data_de_implantacao'] ?? '').toString().isNotEmpty) setData.add(d['data_de_implantacao'].toString().toUpperCase());
        if ((d['tipo_do_controlador'] ?? '').toString().isNotEmpty) setControlador.add(d['tipo_do_controlador'].toString().toUpperCase());
        if ((d['modo_de_funcionamento'] ?? '').toString().isNotEmpty) setModo.add(d['modo_de_funcionamento'].toString().toUpperCase());
        if ((d['conta_contrato'] ?? '').toString().isNotEmpty) setConta.add(d['conta_contrato'].toString().toUpperCase());
        if ((d['numero_do_medidor'] ?? '').toString().isNotEmpty) setMedidor.add(d['numero_do_medidor'].toString().toUpperCase());
      }

      if (mounted) {
        setState(() {
          _todosSemaforos = listaLocal;
          _opcoesNumero = setNumero.toList()..sort();
          _opcoesEndereco = setEndereco.toList()..sort();
          _opcoesBairro = setBairro.toList()..sort();
          _opcoesEmpresa = setEmpresa.toList()..sort();
          _opcoesRota = setRota.toList()..sort();
          _opcoesData = setData.toList()..sort();
          _opcoesControlador = setControlador.toList()..sort();
          _opcoesModo = setModo.toList()..sort();
          _opcoesConta = setConta.toList()..sort();
          _opcoesMedidor = setMedidor.toList()..sort();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar semáforos: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _limparFiltros() {
    setState(() {
      _fNumero.clear();
      _fEndereco.clear();
      _fBairro.clear();
      _fEmpresa.clear();
      _fRota.clear();
      _fData.clear();
      _fControlador.clear();
      _fModo.clear();
      _fConta.clear();
      _fMedidor.clear();
      for (var f in _filtrosBooleanos) {
        f.ativo = false;
      }
      _paginaAtual = 0; // Volta para a página 1
    });
  }

  // --- LÓGICA DE FILTRAGEM ---
  bool _passouNoFiltro(Map<String, dynamic> item) {
    bool matchString(String? valDb, String term) {
      if (term.isEmpty) return true;
      return (valDb ?? '').toLowerCase().contains(term.toLowerCase());
    }

    if (!matchString(item['numero_formatado']?.toString(), _fNumero.text)) return false;
    if (!matchString(item['endereco']?.toString(), _fEndereco.text)) return false;
    if (!matchString(item['bairro']?.toString(), _fBairro.text)) return false;
    if (!matchString(item['empresa']?.toString(), _fEmpresa.text)) return false;
    if (!matchString(item['rota']?.toString(), _fRota.text)) return false;
    if (!matchString(item['data_de_implantacao']?.toString(), _fData.text)) return false;
    if (!matchString(item['tipo_do_controlador']?.toString(), _fControlador.text)) return false;
    if (!matchString(item['modo_de_funcionamento']?.toString(), _fModo.text)) return false;
    if (!matchString(item['conta_contrato']?.toString(), _fConta.text)) return false;
    if (!matchString(item['numero_do_medidor']?.toString(), _fMedidor.text)) return false;

    // Filtros Booleanos
    for (var filtro in _filtrosBooleanos) {
      if (filtro.ativo) {
        var valor = item[filtro.dbField];
        bool isSim = false;
        if (valor == true ||
            valor == 'Sim' ||
            valor == 'SIM' ||
            valor == 's' ||
            valor == 'true' ||
            valor == '1') {
          isSim = true;
        } else if (valor is num && valor > 0) {
          isSim = true;
        } else if (valor is String &&
            num.tryParse(valor) != null &&
            num.parse(valor) > 0) {
          isSim = true;
        }
        if (!isSim) return false;
      }
    }

    return true;
  }

  // --- EXPORTAÇÃO EXCEL GLOBAL ---
  Future<void> _baixarExcelGlobal(List<Map<String, dynamic>> docs) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Semáforos'];
    excel.setDefaultSheet('Semáforos');

    sheetObject.appendRow([TextCellValue("Relatório de Acervo de Semáforos")]);
    sheetObject.appendRow([TextCellValue("")]);

    List<TextCellValue> headers = [];
    for (var grupo in _gruposFormulario) {
      for (var campo in (grupo['campos'] as List)) {
        headers.add(TextCellValue(campo['label'].toString().replaceAll(' *', '')));
      }
    }
    sheetObject.appendRow(headers);

    for (var doc in docs) {
      List<TextCellValue> row = [];
      for (var grupo in _gruposFormulario) {
        for (var campo in (grupo['campos'] as List)) {
          var val = doc[campo['key']];
          
          if (val == true || val == 'Sim' || val == 'SIM' || val == 's' || val == 'true' || val == '1' || (val is num && val > 0) || (val is String && num.tryParse(val) != null && num.parse(val) > 0)) {
            val = (val is num || (val is String && num.tryParse(val) != null)) ? val.toString() : 'Sim';
          } else if (val == false || val == 'Não' || val == 'NÃO' || val == 'n' || val == 'false' || val == '0') {
             val = '-';
          }
          
          row.add(TextCellValue((val ?? '-').toString()));
        }
      }
      sheetObject.appendRow(row);
    }

    CellStyle centerStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);
    for (int r = 2; r < sheetObject.maxRows; r++) { 
      for (int c = 0; c < sheetObject.maxRows; c++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        cell.cellStyle = centerStyle;
      }
    }

    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(
        Uint8List.fromList(fileBytes),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: 'Acervo_Semaforos.xlsx'
      );
      await Share.shareXFiles([xfile], text: 'Acervo de Semáforos Filtrados');
    }
  }

  // --- MODAL DE DETALHES COMPLETOS (O "Olhinho") ---
  void _abrirModalDetalhesCompletos(Map<String, dynamic> data, String idFormatado) {
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
                'Ficha Técnica Completa: $idFormatado',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2f3b4c),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: _gruposFormulario.map<Widget>((grupo) {
                      var campos = grupo['campos'] as List;
                      bool temDado = campos.any(
                        (c) => (data[c['key']] ?? '').toString().isNotEmpty,
                      );
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
                                Icon(
                                  grupo['icone'],
                                  color: const Color(0xFF2f3b4c),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  grupo['titulo'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF2f3b4c),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(thickness: 1),
                            const SizedBox(height: 8),
                            ...campos.map<Widget>((campo) {
                              String valor = (data[campo['key']] ?? '').toString();
                              
                              if (valor == 'true' || valor == '1') valor = 'Sim';
                              if (valor == 'false' || valor == '0') valor = 'Não';
                              
                              if (valor.isEmpty) return const SizedBox.shrink();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${campo['label'].toString().replaceAll(' *', '')}:',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        valor,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
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
                  backgroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Voltar',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- EXPORTAÇÃO PDF ---
  Future<void> _exportarPdfAcervo(List<Map<String, dynamic>> dadosVisiveis, List<FiltroCheckbox> colunasExtras) async {
    final pdf = pw.Document();

    List<String> headers = [
      'Semáforo',
      'Endereço',
      'Bairro',
      'Empresa',
      ...colunasExtras.map((e) => e.label),
    ];

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
                    'Relatório gerado pelo Sistema de Ocorrências semafóricas - SOS em ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}',
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
        build: (context) => [
          pw.Text('Relatório de Acervo de Semáforos', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Text('Total de Registros filtrados: ${dadosVisiveis.length}'),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: dadosVisiveis.map((d) {
              List<String> row = [
                d['numero_formatado'].toString(),
                (d['endereco'] ?? '-').toString(),
                (d['bairro'] ?? '-').toString(),
                (d['empresa'] ?? '-').toString(),
              ];
              for (var col in colunasExtras) {
                var v = d[col.dbField];
                bool isSim = (v == true || v == 'Sim' || v == 'SIM' || v == 's' || v == 'true' || v == '1' || (v is num && v > 0) || (v is String && num.tryParse(v) != null && num.parse(v) > 0));
                row.add(isSim ? (v is num || (v is String && num.tryParse(v) != null) ? v.toString() : 'Sim') : '-');
              }
              return row;
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 7),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Relatorio_Semaforos.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> docsFiltrados = _todosSemaforos.where(_passouNoFiltro).toList();
    
    docsFiltrados.sort((a, b) => (a['numero_formatado'] ?? '').compareTo(b['numero_formatado'] ?? ''));

    int totalPaginas = (docsFiltrados.length / _itensPorPagina).ceil();
    if (_paginaAtual >= totalPaginas && totalPaginas > 0) {
      _paginaAtual = totalPaginas - 1; 
    }
    
    List<Map<String, dynamic>> dadosPagina = docsFiltrados
        .skip(_paginaAtual * _itensPorPagina)
        .take(_itensPorPagina)
        .toList();

    List<FiltroCheckbox> colunasExtras = _filtrosBooleanos.where((f) => f.ativo).toList();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Acervo de Semáforos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [MenuUsuario()],
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

          Column(
            children: [
              const SizedBox(height: 100),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFf5f5f5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _mostrarFiltros = !_mostrarFiltros;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3f5066),
                              borderRadius: _mostrarFiltros
                                  ? const BorderRadius.vertical(top: Radius.circular(9))
                                  : BorderRadius.circular(9),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Filtros de Busca Avançados',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Icon(_mostrarFiltros ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                        if (_mostrarFiltros) ...[
                          Container(
                            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch, 
                                children: [
                                  const Text('DADOS GERAIS E TÉCNICOS', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                                  const Divider(),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _buildAutocompleteField('Nº Semáforo', _fNumero, _focusNumero, _opcoesNumero),
                                      _buildAutocompleteField('Endereço', _fEndereco, _focusEndereco, _opcoesEndereco),
                                      _buildAutocompleteField('Bairro', _fBairro, _focusBairro, _opcoesBairro),
                                      _buildAutocompleteField('Empresa', _fEmpresa, _focusEmpresa, _opcoesEmpresa),
                                      _buildAutocompleteField('Rota', _fRota, _focusRota, _opcoesRota),
                                      _buildAutocompleteField('Ano/Data Implantação', _fData, _focusData, _opcoesData),
                                      _buildAutocompleteField('Controlador', _fControlador, _focusControlador, _opcoesControlador),
                                      _buildAutocompleteField('Modo de Func.', _fModo, _focusModo, _opcoesModo),
                                      _buildAutocompleteField('Conta Contrato', _fConta, _focusConta, _opcoesConta),
                                      _buildAutocompleteField('Nº Medidor', _fMedidor, _focusMedidor, _opcoesMedidor),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  const Text('COMPONENTES (Marque para filtrar apenas os que possuem)', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                                  const Divider(),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _filtrosBooleanos.map((f) => SizedBox(
                                      width: 200,
                                      child: CheckboxListTile(
                                        title: Text(f.label, style: const TextStyle(fontSize: 12, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        value: f.ativo,
                                        activeColor: Colors.blue,
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        controlAffinity: ListTileControlAffinity.leading,
                                        onChanged: (v) {
                                          setState(() {
                                            f.ativo = v!;
                                            _paginaAtual = 0; 
                                          });
                                        },
                                      ),
                                    )).toList(),
                                  ),
                                  const SizedBox(height: 16),
                                  Align(
                                    alignment: Alignment.center,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.redAccent,
                                        side: const BorderSide(color: Colors.redAccent),
                                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 30),
                                      ),
                                      onPressed: _limparFiltros,
                                      child: const Text('Limpar Todos os Filtros', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                      child: _isLoading 
                        ? const Center(child: CircularProgressIndicator())
                        : docsFiltrados.isEmpty
                          ? const Center(child: Text('Nenhum resultado para os filtros atuais.'))
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                  ),
                                  child: Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      Text(
                                        'Resultados: ${docsFiltrados.length} encontrados',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                                      ),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green.shade600,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                            icon: const Icon(Icons.download, color: Colors.white, size: 16),
                                            label: const Text(
                                              'Baixar Planilha (XLSX)',
                                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                            onPressed: () => _baixarExcelGlobal(docsFiltrados),
                                          ),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.redAccent,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                            icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 16),
                                            label: const Text(
                                              'Baixar PDF (Com Colunas Visíveis)',
                                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                            onPressed: () => _exportarPdfAcervo(docsFiltrados, colunasExtras),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Center(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.vertical,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: DataTable(
                                          headingRowColor: WidgetStateProperty.all(const Color(0xFF2c3e50)),
                                          headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          dataRowMinHeight: 40,
                                          dataRowMaxHeight: 50,
                                          columns: [
                                            const DataColumn(label: Text('Semáforo')),
                                            const DataColumn(label: Text('Endereço')),
                                            const DataColumn(label: Text('Bairro')),
                                            const DataColumn(label: Text('Empresa')),
                                            ...colunasExtras.map((col) => DataColumn(label: Text(col.label))),
                                            const DataColumn(label: Text('Ações')),
                                          ],
                                          rows: dadosPagina.map((d) {
                                            List<DataCell> celulas = [
                                              DataCell(Text(d['numero_formatado'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                                              DataCell(SizedBox(width: 200, child: Text(d['endereco'] ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis))),
                                              DataCell(Text(d['bairro'] ?? '-')),
                                              DataCell(Text(d['empresa'] ?? '-')),
                                            ];

                                            for (var col in colunasExtras) {
                                              var v = d[col.dbField];
                                              bool isSim = (v == true || v == 'Sim' || v == 'SIM' || v == 's' || v == 'true' || v == '1' || (v is num && v > 0) || (v is String && num.tryParse(v) != null && num.parse(v) > 0));
                                              String txt = '-';
                                              if (isSim) {
                                                txt = (v is num || (v is String && num.tryParse(v) != null)) ? v.toString() : 'Sim';
                                              }
                                              celulas.add(DataCell(Text(txt, style: TextStyle(color: isSim ? Colors.green : Colors.grey, fontWeight: isSim ? FontWeight.bold : FontWeight.normal))));
                                            }

                                            celulas.add(
                                              DataCell(
                                                Center(
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      IconButton(
                                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                                        constraints: const BoxConstraints(),
                                                        icon: const Icon(Icons.visibility, color: Colors.blueGrey, size: 20),
                                                        tooltip: 'Ficha Completa',
                                                        onPressed: () => _abrirModalDetalhesCompletos(d, d['numero_formatado'].toString()),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );

                                            return DataRow(cells: celulas);
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (totalPaginas > 1)
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      border: Border(top: BorderSide(color: Colors.grey.shade300)),
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10))
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.chevron_left),
                                          onPressed: _paginaAtual > 0 ? () => setState(() => _paginaAtual--) : null,
                                        ),
                                        Text(
                                          'Página ${_paginaAtual + 1} de $totalPaginas',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_right),
                                          onPressed: _paginaAtual < totalPaginas - 1 ? () => setState(() => _paginaAtual++) : null,
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutocompleteField(String label, TextEditingController controller, FocusNode focus, List<String> options) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, 
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            height: 38,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
            child: RawAutocomplete<String>(
              textEditingController: controller,
              focusNode: focus,
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                return options.where((String option) => option.contains(textEditingValue.text.toUpperCase()));
              },
              onSelected: (String selection) {
                controller.text = selection;
                setState(() {
                  _paginaAtual = 0; 
                });
              },
              fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                return TextField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  onChanged: (v) {
                    setState(() {
                      _paginaAtual = 0; 
                    });
                  },
                  inputFormatters: [UpperCaseTextFormatter()],
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center, 
                  decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12), isDense: true),
                );
              },
              optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4.0,
                    borderRadius: BorderRadius.circular(4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200, maxWidth: 180),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final String option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                              child: Text(option, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}