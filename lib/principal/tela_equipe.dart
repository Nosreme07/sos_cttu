import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../widgets/menu_usuario.dart';

class TelaEquipes extends StatefulWidget {
  const TelaEquipes({super.key});

  @override
  State<TelaEquipes> createState() => _TelaEquipesState();
}

class _TelaEquipesState extends State<TelaEquipes> {
  final TextEditingController _buscaPlacaController = TextEditingController();
  final TextEditingController _buscaIntegranteController = TextEditingController();
  String _filtroStatus = 'ativo'; 
  
  String _termoPlaca = '';
  String _termoIntegrante = '';

  @override
  void dispose() {
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
  Future<Map<String, List<String>>> _buscarRecursosLivres(String? equipeAtualId) async {
    // 1. Descobrir quem já está ocupado em equipes ATIVAS
    final equipesAtivas = await FirebaseFirestore.instance.collection('equipes').where('status', isEqualTo: 'ativo').get();
    
    Set<String> placasOcupadas = {};
    Set<String> integrantesOcupados = {};

    for (var doc in equipesAtivas.docs) {
      // Se estivermos editando uma equipe, ignoramos ela mesma para que seus recursos apareçam como livres para ela!
      if (doc.id == equipeAtualId) continue; 

      var data = doc.data();
      if (data['placa'] != null) {
        placasOcupadas.add(data['placa'].toString().toUpperCase());
      }
      if (data['integrantes_str'] != null && data['integrantes_str'].toString().isNotEmpty) {
        List<String> ints = data['integrantes_str'].toString().split(',');
        for (var i in ints) {
          integrantesOcupados.add(i.trim().toUpperCase());
        }
      }
    }

    // 2. Buscar TODOS os veículos e filtrar os que estão livres
    final veiculos = await FirebaseFirestore.instance.collection('veiculos').get();
    List<String> placasLivres = [];
    for (var doc in veiculos.docs) {
      String placa = (doc.data()['placa'] ?? '').toString().toUpperCase();
      if (placa.isNotEmpty && !placasOcupadas.contains(placa)) {
        placasLivres.add(placa);
      }
    }

    // 3. Buscar TODOS os integrantes e filtrar os que estão livres
    final integrantes = await FirebaseFirestore.instance.collection('integrantes').get();
    List<String> integrantesLivres = [];
    for (var doc in integrantes.docs) {
      String nome = (doc.data()['nomeCompleto'] ?? '').toString().toUpperCase();
      if (nome.isNotEmpty && !integrantesOcupados.contains(nome)) {
        integrantesLivres.add(nome);
      }
    }

    // Ordena em ordem alfabética para ficar bonito no Dropdown
    placasLivres.sort();
    integrantesLivres.sort();

    return {
      'veiculos': placasLivres,
      'integrantes': integrantesLivres,
    };
  }


  // =========================================================================
  // MODAL INTELIGENTE: FORMAR NOVA EQUIPE
  // =========================================================================
  void _abrirModalNovaEquipe({String? docId, Map<String, dynamic>? dadosAtuais}) async {
    // Exibe um mini carregamento enquanto pensa
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.green))
    );

    // Busca quem está livre!
    Map<String, List<String>> recursosLivres;
    try {
      recursosLivres = await _buscarRecursosLivres(docId);
    } catch (e) {
      Navigator.pop(context); // Fecha o loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao buscar recursos.'), backgroundColor: Colors.red));
      return;
    }
    
    if(!mounted) return;
    Navigator.pop(context); // Fecha o loading

    final formKey = GlobalKey<FormState>();
    bool estaCarregando = false;
    
    final kmInicialController = TextEditingController(text: dadosAtuais?['km_inicial']?.toString() ?? '');
    final observacoesController = TextEditingController(text: dadosAtuais?['observacoes'] ?? '');
    
    // Variáveis de Seleção
    String? placaSelecionada = dadosAtuais?['placa'];
    if (placaSelecionada != null && !recursosLivres['veiculos']!.contains(placaSelecionada)) {
      recursosLivres['veiculos']!.add(placaSelecionada!); // Garante que a placa atual apareça no dropdown se for edição
    }

    List<String> equipeSelecionada = [];
    if (dadosAtuais != null && dadosAtuais['integrantes_str'] != null && dadosAtuais['integrantes_str'].toString().isNotEmpty) {
      equipeSelecionada = dadosAtuais['integrantes_str'].toString().split(',').map((e) => e.trim()).toList();
    }
    
    String? integranteSendoEscolhido;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {

            // Filtra o dropdown de integrantes para não mostrar quem já foi adicionado nos Chips
            List<String> opcoesIntegrantes = recursosLivres['integrantes']!
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
                      Text(docId == null ? 'Nova Equipe / Despacho' : 'Editando Equipe', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2f3b4c))),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
                            // 1. ESCOLHER VEÍCULO (Puxa do Banco)
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: 'Viatura (Apenas Livres) *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car)),
                              value: recursosLivres['veiculos']!.contains(placaSelecionada) ? placaSelecionada : null,
                              items: recursosLivres['veiculos']!.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                              onChanged: (val) => setStateModal(() => placaSelecionada = val),
                              validator: (val) => val == null ? 'Selecione uma viatura' : null,
                            ),
                            const SizedBox(height: 16),
                            
                            // 2. MONTAR A EQUIPE DE INTEGRANTES
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blueGrey.shade200)
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Montar Equipe', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          decoration: const InputDecoration(labelText: 'Adicionar Integrante Livre', border: OutlineInputBorder(), isDense: true),
                                          value: null, // Sempre volta pra nulo ao selecionar
                                          items: opcoesIntegrantes.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setStateModal(() {
                                                equipeSelecionada.add(val);
                                                integranteSendoEscolhido = null; // Reseta
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  // CHIPS (Etiquetas) dos integrantes adicionados
                                  if (equipeSelecionada.isEmpty)
                                    const Text('Nenhum integrante adicionado.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.redAccent, fontSize: 12)),
                                  
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: equipeSelecionada.map((membro) {
                                      return Chip(
                                        label: Text(membro, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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

                            // 3. KM E OBSERVAÇÕES
                            TextFormField(
                              controller: kmInicialController,
                              decoration: const InputDecoration(labelText: 'KM Inicial', border: OutlineInputBorder(), prefixIcon: Icon(Icons.speed)),
                              keyboardType: TextInputType.number,
                              validator: (val) => val == null || val.isEmpty ? 'Obrigatório' : null,
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: observacoesController,
                              decoration: const InputDecoration(labelText: 'Observações (Opcional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.note)),
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27ae60), padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: estaCarregando ? null : () async {
                      if (equipeSelecionada.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A equipe precisa ter pelo menos 1 integrante!'), backgroundColor: Colors.red));
                        return;
                      }

                      if (formKey.currentState!.validate()) {
                        setStateModal(() => estaCarregando = true);
                        try {
                          String integrantesStr = equipeSelecionada.join(', ');

                          if (docId != null) {
                            // Atualiza
                            await FirebaseFirestore.instance.collection('equipes').doc(docId).update({
                              'placa': placaSelecionada,
                              'integrantes_str': integrantesStr,
                              'km_inicial': kmInicialController.text.trim(),
                              'observacoes': observacoesController.text.trim(),
                            });
                          } else {
                            // Cria novo
                            await FirebaseFirestore.instance.collection('equipes').add({
                              'placa': placaSelecionada,
                              'integrantes_str': integrantesStr,
                              'km_inicial': kmInicialController.text.trim(),
                              'observacoes': observacoesController.text.trim(),
                              'status': 'ativo',
                              'data_inicio': FieldValue.serverTimestamp(),
                            });
                          }

                          if (mounted) Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(docId == null ? 'Equipe Despachada!' : 'Equipe Atualizada!'), backgroundColor: Colors.green));
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao salvar'), backgroundColor: Colors.red));
                        } finally {
                          setStateModal(() => estaCarregando = false);
                        }
                      }
                    },
                    child: estaCarregando 
                        ? const CircularProgressIndicator(color: Colors.white) 
                        : Text(docId == null ? 'Salvar Despacho' : 'Atualizar Equipe', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  // --- Função Finalizar Equipe ---
  Future<void> _finalizarEquipe(String docId, Map<String, dynamic> dadosAtuais) async {
    final kmFinalController = TextEditingController();

    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar Equipe', style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Deseja realmente encerrar os trabalhos desta equipe? A viatura e os integrantes ficarão livres para novos despachos.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: kmFinalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'KM Final do Veículo *', border: OutlineInputBorder()),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (kmFinalController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o KM Final!'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Finalizar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirmar) {
      int kmInicial = int.tryParse(dadosAtuais['km_inicial']?.toString() ?? '0') ?? 0;
      int kmFinal = int.tryParse(kmFinalController.text) ?? kmInicial;
      int kmRodado = kmFinal - kmInicial;

      await FirebaseFirestore.instance.collection('equipes').doc(docId).update({
        'status': 'finalizado',
        'data_fim': FieldValue.serverTimestamp(),
        'km_final': kmFinal.toString(),
        'km_rodado': kmRodado.toString(),
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Equipe Finalizada! Os recursos estão livres.'), backgroundColor: Colors.grey));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Equipes Formadas', style: TextStyle(color: Colors.white)),
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

              // --- CABEÇALHO DA TELA & BOTÃO NOVA EQUIPE ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Visão Geral', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ecc71), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Formar Nova Equipe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        onPressed: () => _abrirModalNovaEquipe(),
                      )
                    ],
                  ),
                ),
              ),

              // --- BARRA DE FILTROS ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(8)),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        SizedBox(
                          width: 150,
                          child: TextField(
                            controller: _buscaPlacaController,
                            decoration: const InputDecoration(labelText: 'Placa', border: OutlineInputBorder(), isDense: true),
                            onChanged: (v) => setState(() => _termoPlaca = v.toLowerCase()),
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: TextField(
                            controller: _buscaIntegranteController,
                            decoration: const InputDecoration(labelText: 'Integrante', border: OutlineInputBorder(), isDense: true),
                            onChanged: (v) => setState(() => _termoIntegrante = v.toLowerCase()),
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
                            value: _filtroStatus,
                            items: const [
                              DropdownMenuItem(value: 'todos', child: Text('TODOS')),
                              DropdownMenuItem(value: 'ativo', child: Text('ATIVO')),
                              DropdownMenuItem(value: 'finalizado', child: Text('FINALIZADO')),
                            ],
                            onChanged: (v) => setState(() => _filtroStatus = v!),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- GRID DE EQUIPES ---
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('equipes').orderBy('data_inicio', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
                    if (snapshot.hasError) return const Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.white)));
                    
                    final docs = snapshot.data?.docs ?? [];
                    
                    // Aplicação dos Filtros
                    final filtrados = docs.where((doc) {
                      var d = doc.data() as Map<String, dynamic>;
                      String placa = (d['placa'] ?? '').toString().toLowerCase();
                      String ints = (d['integrantes_str'] ?? '').toString().toLowerCase();
                      String status = d['status'] ?? 'ativo';

                      if (_filtroStatus != 'todos' && status != _filtroStatus) return false;
                      if (_termoPlaca.isNotEmpty && !placa.contains(_termoPlaca)) return false;
                      if (_termoIntegrante.isNotEmpty && !ints.contains(_termoIntegrante)) return false;
                      return true;
                    }).toList();

                    if (filtrados.isEmpty) {
                      return const Center(child: Text('Nenhuma equipe encontrada.', style: TextStyle(color: Colors.white, fontSize: 16, fontStyle: FontStyle.italic)));
                    }

                    // Constroi o GRID
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: GridView.builder(
                          padding: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 380, // Largura máxima do card
                            mainAxisExtent: 340, // Altura do Card
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: filtrados.length,
                          itemBuilder: (context, index) {
                            var doc = filtrados[index];
                            var data = doc.data() as Map<String, dynamic>;
                            
                            bool isAtivo = data['status'] == 'ativo';
                            Color corStatus = isAtivo ? const Color(0xFF2ecc71) : const Color(0xFF7f8c8d);
                            String txtStatus = isAtivo ? 'ATIVO' : 'FINALIZADO';
                            
                            String dtInicio = _formatarData(data['data_inicio']);
                            String dtFim = isAtivo ? '' : _formatarData(data['data_fim']);

                            return Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 6,
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // HEADER AZUL
                                  Container(
                                    color: const Color(0xFF448aff),
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                    child: Column(
                                      children: [
                                        Text('🚗 ${data['placa'] ?? 'S/ PLACA'}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                          decoration: BoxDecoration(color: corStatus, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 1)),
                                          child: Text(txtStatus, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                        )
                                      ],
                                    ),
                                  ),
                                  
                                  // BODY
                                  Expanded(
                                    child: Container(
                                      color: Colors.white,
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // DATAS
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Início: $dtInicio', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                              if (!isAtivo) Text('Fim: $dtFim', style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const Divider(),
                                          // KMs
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('KM Ini: ${data['km_inicial'] ?? '0'}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                              Text('KM Fim: ${data['km_final'] ?? '---'}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                              Text('Rodado: ${data['km_rodado'] ?? '---'}', style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          
                                          // INTEGRANTES
                                          const Text('👤 Integrantes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF444444))),
                                          Text(data['integrantes_str'] ?? '-', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                          const SizedBox(height: 12),

                                          // TAREFAS
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                                            child: const Text('Tarefas atribuídas aparecerão aqui no próximo módulo.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.blueGrey)),
                                          )
                                        ],
                                      ),
                                    ),
                                  ),

                                  // FOOTER ACTIONS
                                  Container(
                                    color: Colors.grey.shade100,
                                    padding: const EdgeInsets.all(8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: isAtivo ? [
                                        TextButton(
                                          onPressed: () => _abrirModalNovaEquipe(docId: doc.id, dadosAtuais: data), 
                                          child: const Text('Editar', style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold))
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFeb4c4c)),
                                          onPressed: () => _finalizarEquipe(doc.id, data),
                                          child: const Text('Finalizar Equipe', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                        )
                                      ] : [
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF34495e)),
                                          icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 16),
                                          label: const Text('Exportar PDF', style: TextStyle(color: Colors.white, fontSize: 12)),
                                          onPressed: () {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geração de PDF da equipe será ativada em breve.')));
                                          },
                                        )
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                      ),
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