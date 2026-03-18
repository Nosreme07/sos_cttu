import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../widgets/menu_usuario.dart';

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
  // Filtros de Texto
  final TextEditingController _fEndereco = TextEditingController();
  final TextEditingController _fNumero = TextEditingController();
  final TextEditingController _fBairro = TextEditingController();
  final TextEditingController _fRota = TextEditingController();
  final TextEditingController _fEmpresa = TextEditingController();
  final TextEditingController _fData =
      TextEditingController(); // Ano implantação
  final TextEditingController _fControlador = TextEditingController();
  final TextEditingController _fModo = TextEditingController();
  final TextEditingController _fConta = TextEditingController();
  final TextEditingController _fMedidor = TextEditingController();

  // Lista de Filtros Booleanos (Os checkboxes do seu HTML)
  List<FiltroCheckbox> _filtrosBooleanos = [
    FiltroCheckbox('GF Veicular Tipo I', 'grupo_focal_veicular_tipo_i', false),
    FiltroCheckbox('GF Veicular Tipo T', 'grupo_focal_veicular_tipo_t', false),
    FiltroCheckbox(
      'GF Pedestre Simples',
      'grupo_focal_pedestre_simples',
      false,
    ),
    FiltroCheckbox(
      'GF Pedestre Cron.',
      'grupo_focal_pedestre_com_cronometro',
      false,
    ),
    FiltroCheckbox(
      'GF Ciclista (3 focos)',
      'grupo_focal_ciclista_com_tres_focos',
      false,
    ),
    FiltroCheckbox(
      'GF Ciclista (2 focos)',
      'grupo_focal_ciclista_com_dois_focos',
      false,
    ),
    FiltroCheckbox(
      'GF Faixa Reversível',
      'grupo_focal_faixa_reversivel',
      false,
    ),
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

  @override
  void dispose() {
    _fEndereco.dispose();
    _fNumero.dispose();
    _fBairro.dispose();
    _fRota.dispose();
    _fEmpresa.dispose();
    _fData.dispose();
    _fControlador.dispose();
    _fModo.dispose();
    _fConta.dispose();
    _fMedidor.dispose();
    super.dispose();
  }

  void _limparFiltros() {
    setState(() {
      _fEndereco.clear();
      _fNumero.clear();
      _fBairro.clear();
      _fRota.clear();
      _fEmpresa.clear();
      _fData.clear();
      _fControlador.clear();
      _fModo.clear();
      _fConta.clear();
      _fMedidor.clear();
      for (var f in _filtrosBooleanos) {
        f.ativo = false;
      }
    });
  }

  // --- LÓGICA DE FILTRAGEM ---
  bool _passouNoFiltro(Map<String, dynamic> item) {
    bool matchString(String? valDb, String term) {
      if (term.isEmpty) return true;
      return (valDb ?? '').toLowerCase().contains(term.toLowerCase());
    }

    if (!matchString(item['endereco'], _fEndereco.text)) return false;
    if (!matchString((item['numero'] ?? item['id'])?.toString(), _fNumero.text))
      return false;
    if (!matchString(item['bairro'], _fBairro.text)) return false;
    if (!matchString(item['rota'], _fRota.text)) return false;
    if (!matchString(item['empresa'], _fEmpresa.text)) return false;
    if (!matchString(item['tipo_do_controlador'], _fControlador.text))
      return false;
    if (!matchString(item['modo_de_funcionamento'], _fModo.text)) return false;
    if (!matchString(item['conta_contrato'], _fConta.text)) return false;
    if (!matchString(item['numero_do_medidor'], _fMedidor.text)) return false;
    if (!matchString(item['data_de_implantacao'], _fData.text)) return false;

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

  // --- MODAL DE DETALHES ---
  void _abrirDetalhes(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Detalhes: Semáforo ${data['id'] ?? data['numero'] ?? 'S/N'}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Endereço', data['endereco']),
                _buildDetailRow('Bairro', data['bairro']),
                _buildDetailRow('Empresa', data['empresa']),
                _buildDetailRow('Rota', data['rota']),
                _buildDetailRow('Controlador', data['tipo_do_controlador']),
                _buildDetailRow('Modo Func.', data['modo_de_funcionamento']),
                _buildDetailRow('Conta Contrato', data['conta_contrato']),
                _buildDetailRow('Nº Medidor', data['numero_do_medidor']),
                _buildDetailRow(
                  'Data Implantação',
                  data['data_de_implantacao'],
                ),
                const Divider(),
                const Text(
                  'Componentes Ativos:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                ..._filtrosBooleanos.map((f) {
                  var v = data[f.dbField];
                  bool isSim =
                      (v == true ||
                      v == 'Sim' ||
                      v == 'SIM' ||
                      v == 's' ||
                      v == 'true' ||
                      v == '1' ||
                      (v is num && v > 0) ||
                      (v is String &&
                          num.tryParse(v) != null &&
                          num.parse(v) > 0));
                  if (!isSim) return const SizedBox.shrink();
                  String displayVal =
                      v is num || (v is String && num.tryParse(v) != null)
                      ? '($v)'
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      '✅ ${f.label} $displayVal',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF2c3e50),
              ),
            ),
            TextSpan(text: (value ?? '---').toString()),
          ],
        ),
      ),
    );
  }

  // --- EXPORTAÇÃO PDF ---
  Future<void> _exportarPdfAcervo(
    List<Map<String, dynamic>> dadosVisiveis,
    List<FiltroCheckbox> colunasExtras,
  ) async {
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
        build: (context) => [
          pw.Text(
            'Relatório de Acervo de Semáforos',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Total de Registros filtrados: ${dadosVisiveis.length}'),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: dadosVisiveis.map((d) {
              List<String> row = [
                (d['id'] ?? d['numero'] ?? '-').toString(),
                (d['endereco'] ?? '-').toString(),
                (d['bairro'] ?? '-').toString(),
                (d['empresa'] ?? '-').toString(),
              ];
              // Preenche as colunas extras que estão ativas no filtro
              for (var col in colunasExtras) {
                var v = d[col.dbField];
                bool isSim =
                    (v == true ||
                    v == 'Sim' ||
                    v == 'SIM' ||
                    v == 's' ||
                    v == 'true' ||
                    v == '1' ||
                    (v is num && v > 0) ||
                    (v is String &&
                        num.tryParse(v) != null &&
                        num.parse(v) > 0));
                row.add(
                  isSim
                      ? (v is num || (v is String && num.tryParse(v) != null)
                            ? v.toString()
                            : 'Sim')
                      : '-',
                );
              }
              return row;
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
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

              // --- PAINEL DE FILTROS ---
              Expanded(
                flex: 2,
                child: Padding(
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
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Color(0xFF3f5066),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(9),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Painel de Filtros Avançados',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(
                                          color: Colors.white54,
                                        ),
                                      ),
                                      onPressed: _limparFiltros,
                                      child: const Text('Limpar Tudo'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'DADOS GERAIS E TÉCNICOS',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Divider(),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      _buildTextField('Nº Semáforo', _fNumero),
                                      _buildTextField('Endereço', _fEndereco),
                                      _buildTextField('Bairro', _fBairro),
                                      _buildTextField('Empresa', _fEmpresa),
                                      _buildTextField('Rota', _fRota),
                                      _buildTextField('Ano/Data', _fData),
                                      _buildTextField(
                                        'Controlador',
                                        _fControlador,
                                      ),
                                      _buildTextField('Modo', _fModo),
                                      _buildTextField('Conta', _fConta),
                                      _buildTextField('Nº Medidor', _fMedidor),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  const Text(
                                    'COMPONENTES (Marque para filtrar apenas os que possuem)',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Divider(),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _filtrosBooleanos
                                        .map(
                                          (f) => SizedBox(
                                            width: 200,
                                            child: CheckboxListTile(
                                              title: Text(
                                                f.label,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black87,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              value: f.ativo,
                                              activeColor: Colors.blue,
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              controlAffinity:
                                                  ListTileControlAffinity
                                                      .leading,
                                              onChanged: (v) =>
                                                  setState(() => f.ativo = v!),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // --- TABELA DE RESULTADOS ---
              Expanded(
                flex: 3,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      margin: const EdgeInsets.only(
                        bottom: 24,
                        left: 16,
                        right: 16,
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('semaforos')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                            return const Center(
                              child: Text('Nenhum dado encontrado no acervo.'),
                            );

                          // Aplica Filtros
                          var docsFiltrados = snapshot.data!.docs
                              .map((d) => d.data() as Map<String, dynamic>)
                              .where(_passouNoFiltro)
                              .toList();

                          if (docsFiltrados.isEmpty)
                            return const Center(
                              child: Text(
                                'Nenhum resultado para os filtros atuais.',
                              ),
                            );

                          // Descobre quais checkboxes estão ativos para criar colunas extras
                          List<FiltroCheckbox> colunasExtras = _filtrosBooleanos
                              .where((f) => f.ativo)
                              .toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(10),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Resultados: ${docsFiltrados.length} encontrados',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.picture_as_pdf,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Baixar PDF (Com Colunas Visíveis)',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: () => _exportarPdfAcervo(
                                        docsFiltrados,
                                        colunasExtras,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SingleChildScrollView(
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(
                                        const Color(0xFF2c3e50),
                                      ),
                                      headingTextStyle: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      dataRowMinHeight: 40,
                                      dataRowMaxHeight: 50,
                                      columns: [
                                        const DataColumn(
                                          label: Text('Semáforo'),
                                        ),
                                        const DataColumn(
                                          label: Text('Endereço'),
                                        ),
                                        const DataColumn(label: Text('Bairro')),
                                        const DataColumn(
                                          label: Text('Empresa'),
                                        ),
                                        ...colunasExtras.map(
                                          (col) => DataColumn(
                                            label: Text(col.label),
                                          ),
                                        ),
                                        const DataColumn(label: Text('Ações')),
                                      ],
                                      rows: docsFiltrados.take(200).map((d) {
                                        List<DataCell> celulas = [
                                          DataCell(
                                            Text(
                                              (d['id'] ?? d['numero'] ?? '---')
                                                  .toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            SizedBox(
                                              width: 200,
                                              child: Text(
                                                d['endereco'] ?? '-',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          DataCell(Text(d['bairro'] ?? '-')),
                                          DataCell(Text(d['empresa'] ?? '-')),
                                        ];

                                        // Adiciona as colunas dinâmicas (checkboxes que o usuário ativou)
                                        for (var col in colunasExtras) {
                                          var v = d[col.dbField];
                                          bool isSim =
                                              (v == true ||
                                              v == 'Sim' ||
                                              v == 'SIM' ||
                                              v == 's' ||
                                              v == 'true' ||
                                              v == '1' ||
                                              (v is num && v > 0) ||
                                              (v is String &&
                                                  num.tryParse(v) != null &&
                                                  num.parse(v) > 0));

                                          String txt = '-';
                                          if (isSim) {
                                            txt =
                                                (v is num ||
                                                    (v is String &&
                                                        num.tryParse(v) !=
                                                            null))
                                                ? v.toString()
                                                : 'Sim';
                                          }
                                          celulas.add(
                                            DataCell(
                                              Text(
                                                txt,
                                                style: TextStyle(
                                                  color: isSim
                                                      ? Colors.green
                                                      : Colors.grey,
                                                  fontWeight: isSim
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        celulas.add(
                                          DataCell(
                                            IconButton(
                                              icon: const Icon(
                                                Icons.visibility,
                                                color: Colors.blueGrey,
                                              ),
                                              tooltip: 'Ficha Completa',
                                              onPressed: () =>
                                                  _abrirDetalhes(d),
                                            ),
                                          ),
                                        );

                                        return DataRow(cells: celulas);
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                              if (docsFiltrados.length > 200)
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  color: Colors.amber.shade100,
                                  child: const Text(
                                    '⚠️ Exibindo os primeiros 200 resultados para evitar travamentos. Use os filtros acima para refinar sua busca.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
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

  // Helper de Interface
  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 180,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            onChanged: (v) => setState(() {}), // Atualiza on-the-fly
          ),
        ),
      ],
    );
  }
}
