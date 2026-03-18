import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../widgets/menu_usuario.dart';

class TelaEquipes extends StatefulWidget {
  const TelaEquipes({super.key});

  @override
  State<TelaEquipes> createState() => _TelaEquipesState();
}

class _TelaEquipesState extends State<TelaEquipes>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _buscaPlacaController = TextEditingController();
  final TextEditingController _buscaIntegranteController =
      TextEditingController();

  String _termoPlaca = '';
  String _termoIntegrante = '';

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
    _buscaPlacaController.dispose();
    _buscaIntegranteController.dispose();
    super.dispose();
  }

  String _formatarData(Timestamp? timestamp) {
    if (timestamp == null) return '---';
    DateTime dt = timestamp.toDate();
    return DateFormat('dd/MM/yy HH:mm').format(dt);
  }

  // =========================================================================
  // "CÉREBRO" DO DESPACHO: Cruza os dados para saber quem está livre
  // =========================================================================
  Future<Map<String, dynamic>> _buscarRecursosLivres(
    String? equipeAtualId,
  ) async {
    final equipesAtivas = await FirebaseFirestore.instance
        .collection('equipes')
        .where('status', isEqualTo: 'ativo')
        .get();

    Set<String> placasOcupadas = {};
    Set<String> integrantesOcupados = {};

    for (var doc in equipesAtivas.docs) {
      if (doc.id == equipeAtualId) continue;

      var data = doc.data();
      if (data['placa'] != null) {
        placasOcupadas.add(data['placa'].toString().toUpperCase());
      }
      if (data['integrantes_str'] != null &&
          data['integrantes_str'].toString().isNotEmpty) {
        List<String> ints = data['integrantes_str'].toString().split(',');
        for (var i in ints) {
          integrantesOcupados.add(i.trim().toUpperCase());
        }
      }
    }

    final veiculos = await FirebaseFirestore.instance
        .collection('veiculos')
        .get();
    Map<String, Map<String, dynamic>> veiculosLivresData =
        {}; // Guarda todos os dados do veículo
    for (var doc in veiculos.docs) {
      String placa = (doc.data()['placa'] ?? '').toString().toUpperCase();
      if (placa.isNotEmpty && !placasOcupadas.contains(placa)) {
        veiculosLivresData[placa] = doc.data();
      }
    }

    final integrantes = await FirebaseFirestore.instance
        .collection('integrantes')
        .get();
    List<String> integrantesLivres = [];
    for (var doc in integrantes.docs) {
      String nome = (doc.data()['nomeCompleto'] ?? '').toString().toUpperCase();
      if (nome.isNotEmpty && !integrantesOcupados.contains(nome)) {
        integrantesLivres.add(nome);
      }
    }

    integrantesLivres.sort();

    return {
      'veiculosData': veiculosLivresData,
      'integrantes': integrantesLivres,
    };
  }

  // =========================================================================
  // MODAL INTELIGENTE: FORMAR NOVA EQUIPE
  // =========================================================================
  void _abrirModalNovaEquipe({
    String? docId,
    Map<String, dynamic>? dadosAtuais,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    Map<String, dynamic> recursosLivres;
    try {
      recursosLivres = await _buscarRecursosLivres(docId);
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao buscar recursos.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);

    final formKey = GlobalKey<FormState>();
    bool estaCarregando = false;

    final kmInicialController = TextEditingController(
      text: dadosAtuais?['km_inicial']?.toString() ?? '',
    );
    final observacoesController = TextEditingController(
      text: dadosAtuais?['observacoes'] ?? '',
    );

    Map<String, Map<String, dynamic>> veiculosLivresData =
        recursosLivres['veiculosData'];
    List<String> veiculosPlacas = veiculosLivresData.keys.toList()..sort();

    String? placaSelecionada = dadosAtuais?['placa'];
    if (placaSelecionada != null &&
        !veiculosPlacas.contains(placaSelecionada)) {
      veiculosPlacas.add(placaSelecionada!);
      // Salva os dados antigos provisoriamente caso o usuário não altere
      veiculosLivresData[placaSelecionada!] = {
        'tipo': dadosAtuais?['tipo'],
        'empresa': dadosAtuais?['empresa'],
      };
    }

    List<String> equipeSelecionada = [];
    if (dadosAtuais != null &&
        dadosAtuais['integrantes_str'] != null &&
        dadosAtuais['integrantes_str'].toString().isNotEmpty) {
      equipeSelecionada = dadosAtuais['integrantes_str']
          .toString()
          .split(',')
          .map((e) => e.trim())
          .toList();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            List<String> opcoesIntegrantes =
                (recursosLivres['integrantes'] as List<String>)
                    .where((nome) => !equipeSelecionada.contains(nome))
                    .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.90,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        docId == null
                            ? 'Nova Equipe / Despacho'
                            : 'Editando Equipe',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2f3b4c),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(thickness: 1),
                  const SizedBox(height: 10),

                  Expanded(
                    child: SingleChildScrollView(
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Viatura (Apenas Livres) *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.directions_car),
                              ),
                              value: veiculosPlacas.contains(placaSelecionada)
                                  ? placaSelecionada
                                  : null,
                              items: veiculosPlacas
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(
                                        p,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setStateModal(() => placaSelecionada = val),
                              validator: (val) =>
                                  val == null ? 'Selecione uma viatura' : null,
                            ),
                            const SizedBox(height: 16),

                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.blueGrey.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Montar Equipe',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Adicionar Integrante Livre',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          value: null,
                                          items: opcoesIntegrantes
                                              .map(
                                                (i) => DropdownMenuItem(
                                                  value: i,
                                                  child: Text(i),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setStateModal(() {
                                                equipeSelecionada.add(val);
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  if (equipeSelecionada.isEmpty)
                                    const Text(
                                      'Nenhum integrante adicionado.',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                      ),
                                    ),

                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: equipeSelecionada.map((membro) {
                                      return Chip(
                                        label: Text(
                                          membro,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        backgroundColor: Colors.white,
                                        deleteIconColor: Colors.red,
                                        onDeleted: () {
                                          setStateModal(() {
                                            equipeSelecionada.remove(membro);
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: kmInicialController,
                              decoration: const InputDecoration(
                                labelText: 'KM Inicial',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.speed),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (val) => val == null || val.isEmpty
                                  ? 'Obrigatório'
                                  : null,
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: observacoesController,
                              decoration: const InputDecoration(
                                labelText: 'Observações (Opcional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.note),
                              ),
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27ae60),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: estaCarregando
                        ? null
                        : () async {
                            if (equipeSelecionada.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'A equipe precisa ter pelo menos 1 integrante!',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            if (formKey.currentState!.validate()) {
                              setStateModal(() => estaCarregando = true);
                              try {
                                String integrantesStr = equipeSelecionada.join(
                                  ', ',
                                );

                                // Lógica Inteligente para capturar o Tipo e Empresa do Veículo Selecionado
                                Map<String, dynamic>? dadosDoVeiculo =
                                    veiculosLivresData[placaSelecionada];
                                String tipoVeiculo =
                                    dadosDoVeiculo?['tipo'] ??
                                    dadosAtuais?['tipo'] ??
                                    '';
                                String empresaVeiculo =
                                    dadosDoVeiculo?['empresa'] ??
                                    dadosAtuais?['empresa'] ??
                                    '';

                                Map<String, dynamic> dadosParaSalvar = {
                                  'placa': placaSelecionada,
                                  'tipo': tipoVeiculo,
                                  'empresa': empresaVeiculo,
                                  'integrantes_str': integrantesStr,
                                  'km_inicial': kmInicialController.text.trim(),
                                  'observacoes': observacoesController.text
                                      .trim(),
                                };

                                if (docId != null) {
                                  await FirebaseFirestore.instance
                                      .collection('equipes')
                                      .doc(docId)
                                      .update(dadosParaSalvar);
                                } else {
                                  dadosParaSalvar['status'] = 'ativo';
                                  dadosParaSalvar['data_inicio'] =
                                      FieldValue.serverTimestamp();
                                  await FirebaseFirestore.instance
                                      .collection('equipes')
                                      .add(dadosParaSalvar);
                                }

                                if (mounted) Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      docId == null
                                          ? 'Equipe Despachada!'
                                          : 'Equipe Atualizada!',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Erro ao salvar'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              } finally {
                                setStateModal(() => estaCarregando = false);
                              }
                            }
                          },
                    child: estaCarregando
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            docId == null
                                ? 'Salvar Despacho'
                                : 'Atualizar Equipe',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Função Finalizar Equipe ---
  Future<void> _finalizarEquipe(
    String docId,
    Map<String, dynamic> dadosAtuais,
  ) async {
    final kmFinalController = TextEditingController();

    bool confirmar =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(
              'Finalizar Equipe',
              style: TextStyle(color: Colors.red),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Deseja realmente encerrar os trabalhos desta equipe? A viatura e os integrantes ficarão livres para novos despachos.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: kmFinalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'KM Final do Veículo *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  if (kmFinalController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Informe o KM Final!'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text(
                  'Finalizar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmar) {
      int kmInicial =
          int.tryParse(dadosAtuais['km_inicial']?.toString() ?? '0') ?? 0;
      int kmFinal = int.tryParse(kmFinalController.text) ?? kmInicial;
      int kmRodado = kmFinal - kmInicial;

      await FirebaseFirestore.instance.collection('equipes').doc(docId).update({
        'status': 'finalizado',
        'data_fim': FieldValue.serverTimestamp(),
        'km_final': kmFinal.toString(),
        'km_rodado': kmRodado.toString(),
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Equipe Finalizada! Os recursos estão livres.'),
            backgroundColor: Colors.grey,
          ),
        );
    }
  }

  // --- COMPONENTE: GRID DE EQUIPES OTIMIZADO ---
  Widget _buildGrid(List<QueryDocumentSnapshot> lista, bool isAtivo) {
    if (lista.isEmpty) {
      return Center(
        child: Text(
          isAtivo
              ? 'Nenhuma equipe ATIVA no momento.'
              : 'Nenhuma equipe FINALIZADA encontrada.',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: GridView.builder(
          padding: const EdgeInsets.only(
            bottom: 80,
            left: 16,
            right: 16,
            top: 16,
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 380,
            mainAxisExtent: 270, // <-- REDUZIDO PARA DEIXAR O CARD MENOR
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: lista.length,
          itemBuilder: (context, index) {
            var doc = lista[index];
            var data = doc.data() as Map<String, dynamic>;

            Color corStatus = isAtivo
                ? const Color(0xFF2ecc71)
                : const Color(0xFF7f8c8d);
            String txtStatus = isAtivo ? 'ATIVO' : 'FINALIZADO';

            String dtInicio = _formatarData(data['data_inicio']);
            String dtFim = isAtivo ? '' : _formatarData(data['data_fim']);

            // Tratamento do Cabeçalho
            String placa = data['placa'] ?? 'S/ PLACA';
            String tipo = data['tipo'] ?? data['tipo_veiculo'] ?? '';
            String empresa = data['empresa'] ?? '';

            String headerTextoCarro = tipo.isNotEmpty
                ? '$placa ($tipo)'
                : placa;

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 6,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // CABEÇALHO AZUL (Super Completo)
                  Container(
                    color: const Color(0xFF448aff),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 8,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '🚗 $headerTextoCarro',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (empresa.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              empresa,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: corStatus,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            txtStatus,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // CORPO BRANCO
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // DATAS
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Início: $dtInicio',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black87,
                                ),
                              ),
                              if (!isAtivo)
                                Text(
                                  'Fim: $dtFim',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          const Divider(height: 12),
                          // KMs
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'KM Ini: ${data['km_inicial'] ?? '0'}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                'KM Fim: ${data['km_final'] ?? '---'}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                'Rodado: ${data['km_rodado'] ?? '---'}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // INTEGRANTES
                          const Text(
                            '👤 Integrantes:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Color(0xFF444444),
                            ),
                          ),
                          Text(
                            data['integrantes_str'] ?? '-',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),

                          // TAREFAS (Placeholder Compacto)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Tarefas atribuídas aparecerão aqui no próximo módulo.',
                              style: TextStyle(
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // FOOTER ACTIONS
                  Container(
                    color: Colors.grey.shade100,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: isAtivo
                          ? [
                              TextButton(
                                onPressed: () => _abrirModalNovaEquipe(
                                  docId: doc.id,
                                  dadosAtuais: data,
                                ),
                                child: const Text(
                                  'Editar',
                                  style: TextStyle(
                                    color: Colors.blueGrey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFeb4c4c),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                onPressed: () => _finalizarEquipe(doc.id, data),
                                child: const Text(
                                  'Finalizar Equipe',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ]
                          : [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF34495e),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.picture_as_pdf,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                label: const Text(
                                  'Exportar PDF',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Geração de PDF da equipe será ativada em breve.',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Equipes Formadas',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [MenuUsuario()],
        // ADIÇÃO DAS ABAS
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.green,
          tabs: const [
            Tab(icon: Icon(Icons.directions_car), text: 'Ativas'),
            Tab(icon: Icon(Icons.check_circle), text: 'Finalizadas'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF2ecc71),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Nova Equipe',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: () => _abrirModalNovaEquipe(),
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

          Column(
            children: [
              // AUMENTO DO ESPAÇO NO TOPO PARA NÃO ESCONDER A BARRA DE PESQUISA (De 150 para 190)
              const SizedBox(height: 190),

              // --- BARRA DE FILTROS LIMPA (Sem o Status) ---
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _buscaPlacaController,
                            decoration: const InputDecoration(
                              labelText: 'Filtrar por Placa',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                setState(() => _termoPlaca = v.toLowerCase()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _buscaIntegranteController,
                            decoration: const InputDecoration(
                              labelText: 'Filtrar por Integrante',
                              prefixIcon: Icon(Icons.person_search),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => setState(
                              () => _termoIntegrante = v.toLowerCase(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- CORPO DAS ABAS (TAB BAR VIEW) ---
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('equipes')
                      .orderBy('data_inicio', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting)
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    if (snapshot.hasError)
                      return const Center(
                        child: Text(
                          'Erro ao carregar dados.',
                          style: TextStyle(color: Colors.white),
                        ),
                      );

                    final docs = snapshot.data?.docs ?? [];

                    // Aplicação dos Filtros de Texto (Placa e Integrante)
                    final filtrados = docs.where((doc) {
                      var d = doc.data() as Map<String, dynamic>;
                      String placa = (d['placa'] ?? '')
                          .toString()
                          .toLowerCase();
                      String ints = (d['integrantes_str'] ?? '')
                          .toString()
                          .toLowerCase();

                      if (_termoPlaca.isNotEmpty &&
                          !placa.contains(_termoPlaca))
                        return false;
                      if (_termoIntegrante.isNotEmpty &&
                          !ints.contains(_termoIntegrante))
                        return false;
                      return true;
                    }).toList();

                    // Separa em Ativas e Finalizadas
                    final equipesAtivas = filtrados
                        .where(
                          (d) =>
                              (d.data() as Map<String, dynamic>)['status'] ==
                              'ativo',
                        )
                        .toList();
                    final equipesFinalizadas = filtrados
                        .where(
                          (d) =>
                              (d.data() as Map<String, dynamic>)['status'] ==
                              'finalizado',
                        )
                        .toList();

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildGrid(equipesAtivas, true),
                        _buildGrid(equipesFinalizadas, false),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
