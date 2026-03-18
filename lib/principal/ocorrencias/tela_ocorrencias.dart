import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../widgets/menu_usuario.dart';

class ListaOcorrencias extends StatefulWidget {
  const ListaOcorrencias({super.key});

  @override
  State<ListaOcorrencias> createState() => _ListaOcorrenciasState();
}

class _ListaOcorrenciasState extends State<ListaOcorrencias> {
  // Filtros
  bool _verFinalizadas24h = false;
  final TextEditingController _filtroSemaforo = TextEditingController();
  final TextEditingController _filtroEndereco = TextEditingController();
  final TextEditingController _filtroEmpresa = TextEditingController();
  final TextEditingController _filtroFalha = TextEditingController();
  final TextEditingController _filtroEquipe = TextEditingController();
  final TextEditingController _filtroStatus = TextEditingController();
  final TextEditingController _filtroNumero = TextEditingController();

  // Listas Auxiliares (Para os Dropdowns)
  List<Map<String, dynamic>> _semaforosAux = [];
  List<Map<String, dynamic>> _falhasAux = [];
  List<String> _estoqueAux = [];

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _carregarDadosAuxiliares();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _filtroSemaforo.dispose();
    _filtroEndereco.dispose();
    _filtroEmpresa.dispose();
    _filtroFalha.dispose();
    _filtroEquipe.dispose();
    _filtroStatus.dispose();
    _filtroNumero.dispose();
    super.dispose();
  }

  // --- CARREGAR DADOS PARA OS DROPDOWNS (Semáforos, Falhas, Materiais) ---
  Future<void> _carregarDadosAuxiliares() async {
    try {
      final s = await FirebaseFirestore.instance.collection('semaforos').get();
      final f = await FirebaseFirestore.instance.collection('falhas').get();
      final e = await FirebaseFirestore.instance.collection('estoque').get();

      setState(() {
        _semaforosAux = s.docs
            .map(
              (d) => {
                'id': d['id'] ?? '',
                'endereco': d['endereco'] ?? '',
                'bairro': d['bairro'] ?? '',
              },
            )
            .toList();
        _falhasAux = f.docs
            .map(
              (d) => {
                'falha': d['tipo_da_falha'] ?? '',
                'prioridade': d['prioridade_da_falha'] ?? 'MÉDIA',
              },
            )
            .toList();
        _estoqueAux = e.docs
            .map((d) => (d['descricao'] ?? '').toString())
            .toList();
      });
    } catch (e) {
      debugPrint("Erro ao carregar auxiliares: $e");
    }
  }

  void _onFiltroChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() {}));
  }

  void _limparFiltros() {
    setState(() {
      _filtroSemaforo.clear();
      _filtroEndereco.clear();
      _filtroEmpresa.clear();
      _filtroFalha.clear();
      _filtroEquipe.clear();
      _filtroStatus.clear();
      _filtroNumero.clear();
    });
  }

  String _formatarDataHora(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yy\nHH:mm\'h\'').format(t.toDate());
  }

  // =======================================================================
  // AÇÕES DAS OCORRÊNCIAS (MODAIS)
  // =======================================================================

  // 1. CADASTRAR OU EDITAR OCORRÊNCIA
  void _abrirModalCadastro({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    String semaforoSel = dadosAtuais?['semaforo'] ?? '';
    String falhaSel = dadosAtuais?['tipo_da_falha'] ?? '';
    String origemSel = dadosAtuais?['origem_da_ocorrencia'] ?? 'Ronda';
    final detalhesCtrl = TextEditingController(
      text: dadosAtuais?['detalhes'] ?? '',
    );

    // Para o Dropdown de Semáforos ficar amigável:
    List<String> opcoesSemaforos = _semaforosAux
        .map((s) => "${s['id']} - ${s['endereco']}")
        .toList();
    if (semaforoSel.isNotEmpty &&
        !opcoesSemaforos.any((e) => e.startsWith(semaforoSel))) {
      opcoesSemaforos.add(semaforoSel);
    }
    String? semaforoDropdownValue = semaforoSel.isEmpty
        ? null
        : opcoesSemaforos.firstWhere(
            (e) => e.startsWith(semaforoSel),
            orElse: () => semaforoSel,
          );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => Padding(
          padding: EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  docId == null ? 'Nova Ocorrência' : 'Editar Ocorrência',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2c3e50),
                  ),
                ),
                const Divider(),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Semáforo *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  isExpanded: true,
                  value: semaforoDropdownValue,
                  items: opcoesSemaforos
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => semaforoSel = val?.split(' - ')[0] ?? '',
                  validator: (v) => v == null ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Tipo da Falha *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  value: falhaSel.isEmpty ? null : falhaSel,
                  items: _falhasAux
                      .map(
                        (f) => DropdownMenuItem(
                          value: f['falha'] as String,
                          child: Text(f['falha']),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => falhaSel = val ?? '',
                  validator: (v) => v == null ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Origem *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  value: origemSel,
                  items: ['Ronda', 'Call Center', 'Nobreak', 'População']
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (val) => origemSel = val ?? '',
                  validator: (v) => v == null ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: detalhesCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Detalhes da Ocorrência',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5cb85c),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      Map<String, dynamic> payload = {
                        'semaforo': semaforoSel,
                        'tipo_da_falha': falhaSel,
                        'origem_da_ocorrencia': origemSel,
                        'detalhes': detalhesCtrl.text.toUpperCase(),
                        'data_atualizacao': FieldValue.serverTimestamp(),
                      };
                      if (docId == null) {
                        payload['status'] = 'Aberto';
                        payload['data_de_abertura'] =
                            FieldValue.serverTimestamp();
                        // Preenchendo dados automáticos do semáforo
                        var semInfo = _semaforosAux.firstWhere(
                          (s) => s['id'] == semaforoSel,
                          orElse: () => {},
                        );
                        payload['endereco'] = semInfo['endereco'] ?? '';
                        payload['bairro'] = semInfo['bairro'] ?? '';
                        await FirebaseFirestore.instance
                            .collection('ocorrencias')
                            .add(payload);
                      } else {
                        await FirebaseFirestore.instance
                            .collection('ocorrencias')
                            .doc(docId)
                            .update(payload);
                      }
                      if (mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text(
                    'Salvar Ocorrência',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 2. ATRIBUIR EQUIPE
  void _abrirModalAtribuir(String docId) async {
    final equipesSnapshot = await FirebaseFirestore.instance
        .collection('equipes')
        .where('status', isEqualTo: 'ativo')
        .get();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Atribuir Equipe',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 10),
              if (equipesSnapshot.docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nenhuma equipe ATIVA encontrada no momento.'),
                )
              else
                ...equipesSnapshot.docs.map((eq) {
                  var data = eq.data();
                  String placa = data['placa'] ?? 'S/ PLACA';
                  String empresa = data['empresa'] ?? 'EXTERNA';
                  String ints = data['integrantes_str'] ?? '';
                  String nomeLider = ints.split(',').first.trim().toUpperCase();
                  if (nomeLider.isEmpty) nomeLider = "EQUIPE $placa";

                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const Icon(
                        Icons.directions_car,
                        color: Colors.blueGrey,
                      ),
                      title: Text(
                        '$placa - $empresa',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        ints,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                      ),
                      onTap: () async {
                        await FirebaseFirestore.instance
                            .collection('ocorrencias')
                            .doc(docId)
                            .update({
                              'equipe_atrelada': nomeLider,
                              'equipe_responsavel': nomeLider,
                              'placa_veiculo': placa,
                              'status': 'Em deslocamento',
                            });
                        if (mounted) Navigator.pop(context);
                      },
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  // 3. REGISTRAR CHEGADA
  void _registrarChegada(String docId) async {
    bool? conf = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Registrar Chegada',
          style: TextStyle(color: Colors.orange),
        ),
        content: const Text(
          'Confirmar que a equipe chegou ao local e iniciará o atendimento?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Confirmar',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (conf == true) {
      await FirebaseFirestore.instance
          .collection('ocorrencias')
          .doc(docId)
          .update({
            'status': 'Em atendimento',
            'data_atendimento': FieldValue.serverTimestamp(),
          });
    }
  }

  // 4. FINALIZAR OCORRÊNCIA
  void _abrirModalFinalizar(String docId, Map<String, dynamic> dados) {
    bool defeitoConstatado = true;
    String falha = dados['tipo_da_falha'] ?? '';
    final descricaoCtrl = TextEditingController();
    final acaoCtrl = TextEditingController();
    List<Map<String, dynamic>> materiaisUsados = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => Padding(
          padding: EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Finalizar Ocorrência',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.all(10),
                  color: Colors.blue.shade50,
                  child: Text(
                    'Falha Original: ${dados['tipo_da_falha'] ?? '---'}\nDetalhes: ${dados['detalhes'] ?? '---'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SwitchListTile(
                  title: const Text(
                    'Foi constatado defeito?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  value: defeitoConstatado,
                  activeColor: Colors.green,
                  onChanged: (v) => setStateModal(() => defeitoConstatado = v),
                ),
                if (defeitoConstatado) ...[
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Falha Encontrada *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    value: falha.isEmpty ? null : falha,
                    items: _falhasAux
                        .map(
                          (f) => DropdownMenuItem(
                            value: f['falha'] as String,
                            child: Text(f['falha']),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => falha = val ?? '',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: descricaoCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Como encontrou o semáforo? *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: acaoCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Ação Técnica da Equipe *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    if (defeitoConstatado &&
                        (falha.isEmpty || descricaoCtrl.text.isEmpty)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Preencha a falha e descrição!'),
                        ),
                      );
                      return;
                    }
                    if (acaoCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Descreva a ação realizada!'),
                        ),
                      );
                      return;
                    }

                    await FirebaseFirestore.instance
                        .collection('ocorrencias')
                        .doc(docId)
                        .update({
                          'status': 'Finalizado',
                          'data_de_finalizacao': FieldValue.serverTimestamp(),
                          'falha_aparente_final': defeitoConstatado
                              ? falha
                              : 'DEFEITO NÃO CONSTATADO',
                          'descricao_encontro': defeitoConstatado
                              ? descricaoCtrl.text.toUpperCase()
                              : 'DEFEITO NÃO CONSTATADO',
                          'acao_equipe': acaoCtrl.text.toUpperCase(),
                          'usuario_finalizacao':
                              'Técnico App', // Em módulo futuro puxaremos do login
                        });
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text(
                    'Concluir Atendimento',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 5. GERAR PDF (RELATÓRIO FINAL)
  Future<void> _gerarPdfRelatorio(Map<String, dynamic> dados) async {
    final pdf = pw.Document();
    String numOcc = dados['numero_da_ocorrencia'] ?? dados['id'] ?? 'N/A';

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'RELATÓRIO DE OCORRÊNCIA FINALIZADA',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green800,
              ),
            ),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'Ocorrência Nº: $numOcc',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Semáforo: ${dados['semaforo']} - ${dados['endereco']}'),
            pw.Text('Bairro: ${dados['bairro']}'),
            pw.Text(
              'Prioridade: ${_falhasAux.firstWhere((f) => f['falha'] == dados['tipo_da_falha'], orElse: () => {'prioridade': '---'})['prioridade']}',
            ),
            pw.SizedBox(height: 15),
            pw.Text(
              'DADOS DA ABERTURA',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue,
              ),
            ),
            pw.Text('Falha Registrada: ${dados['tipo_da_falha']}'),
            pw.Text('Origem: ${dados['origem_da_ocorrencia']}'),
            pw.Text('Detalhes: ${dados['detalhes']}'),
            pw.SizedBox(height: 15),
            pw.Text(
              'DADOS DO ATENDIMENTO',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.orange,
              ),
            ),
            pw.Text('Equipe Responsável: ${dados['equipe_responsavel']}'),
            pw.Text('Veículo: ${dados['placa_veiculo'] ?? '---'}'),
            pw.Text('Ação Técnica: ${dados['acao_equipe'] ?? '---'}'),
            pw.Text('Como Encontrou: ${dados['descricao_encontro'] ?? '---'}'),
            pw.Text('Falha Final: ${dados['falha_aparente_final'] ?? '---'}'),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Ocorrencia_$numOcc.pdf',
    );
  }

  // =======================================================================
  // CONSTRUÇÃO DA INTERFACE DA TABELA
  // =======================================================================

  Color _corStatus(String status) {
    String st = status.toLowerCase();
    if (st == 'aberto') return Colors.redAccent;
    if (st == 'em deslocamento') return Colors.orange;
    if (st == 'em atendimento') return Colors.blue;
    if (st.contains('conclu') || st.contains('finaliz')) return Colors.green;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Lista de Ocorrências',
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

              // BARRA DE AÇÕES E FILTROS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5cb85c),
                              padding: const EdgeInsets.all(16),
                            ),
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              'Nova Ocorrência',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () => _abrirModalCadastro(),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _verFinalizadas24h
                                  ? Colors.orange
                                  : Colors.blue,
                              padding: const EdgeInsets.all(16),
                            ),
                            icon: Icon(
                              _verFinalizadas24h
                                  ? Icons.pending_actions
                                  : Icons.history,
                              color: Colors.white,
                            ),
                            label: Text(
                              _verFinalizadas24h
                                  ? 'Voltar para Pendentes'
                                  : 'Finalizadas (24h)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () => setState(
                              () => _verFinalizadas24h = !_verFinalizadas24h,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Campos de Filtro
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildFilterField('Semáforo', _filtroSemaforo),
                            _buildFilterField('Endereço', _filtroEndereco),
                            _buildFilterField('Empresa', _filtroEmpresa),
                            _buildFilterField('Falha', _filtroFalha),
                            _buildFilterField('Equipe', _filtroEquipe),
                            _buildFilterField('Status', _filtroStatus),
                            ActionChip(
                              backgroundColor: Colors.grey.shade600,
                              label: const Text(
                                'Limpar Filtros',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: _limparFiltros,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // TABELA DE OCORRÊNCIAS
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      margin: const EdgeInsets.only(
                        bottom: 24,
                        left: 16,
                        right: 16,
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('ocorrencias')
                            .orderBy('data_de_abertura', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                            return const Center(
                              child: Text('Nenhuma ocorrência encontrada.'),
                            );

                          // Aplicando Filtros
                          final docsFiltrados = snapshot.data!.docs.where((
                            doc,
                          ) {
                            var d = doc.data() as Map<String, dynamic>;
                            String st = (d['status'] ?? '').toLowerCase();
                            bool isConcluido =
                                st.contains('conclu') || st.contains('finaliz');

                            // Filtro de 24h vs Pendentes
                            if (_verFinalizadas24h) {
                              if (!isConcluido) return false;
                              if (d['data_de_finalizacao'] != null) {
                                DateTime dtFim =
                                    (d['data_de_finalizacao'] as Timestamp)
                                        .toDate();
                                if (DateTime.now().difference(dtFim).inHours >
                                    24)
                                  return false;
                              }
                            } else {
                              if (isConcluido) return false;
                            }

                            // Filtros de Texto
                            bool match(
                              String field,
                              TextEditingController ctrl,
                            ) => (d[field] ?? '')
                                .toString()
                                .toLowerCase()
                                .contains(ctrl.text.toLowerCase());
                            if (_filtroSemaforo.text.isNotEmpty &&
                                !match('semaforo', _filtroSemaforo))
                              return false;
                            if (_filtroEndereco.text.isNotEmpty &&
                                !match('endereco', _filtroEndereco))
                              return false;
                            if (_filtroEmpresa.text.isNotEmpty &&
                                !match('empresa_responsavel', _filtroEmpresa))
                              return false;
                            if (_filtroFalha.text.isNotEmpty &&
                                !match('tipo_da_falha', _filtroFalha))
                              return false;
                            if (_filtroStatus.text.isNotEmpty &&
                                !match('status', _filtroStatus))
                              return false;

                            String eq =
                                (d['equipe_responsavel'] ??
                                        d['equipe_atrelada'] ??
                                        '')
                                    .toString()
                                    .toLowerCase();
                            if (_filtroEquipe.text.isNotEmpty &&
                                !eq.contains(_filtroEquipe.text.toLowerCase()))
                              return false;

                            return true;
                          }).toList();

                          if (docsFiltrados.isEmpty)
                            return const Center(
                              child: Text(
                                'Nenhum resultado para os filtros atuais.',
                              ),
                            );

                          return SingleChildScrollView(
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
                                dataRowMinHeight: 60,
                                dataRowMaxHeight: 70,
                                columns: const [
                                  DataColumn(label: Text('Semáforo')),
                                  DataColumn(label: Text('Endereço')),
                                  DataColumn(label: Text('Falha')),
                                  DataColumn(label: Text('Equipe')),
                                  DataColumn(label: Text('Status')),
                                  DataColumn(label: Text('Abertura')),
                                  DataColumn(label: Text('Ações')),
                                ],
                                rows: docsFiltrados.map((doc) {
                                  var d = doc.data() as Map<String, dynamic>;
                                  String st = d['status'] ?? 'Aberto';
                                  bool isConcluido =
                                      st.toLowerCase().contains('finaliz') ||
                                      st.toLowerCase().contains('conclu');

                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(
                                          d['semaforo'] ?? '---',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 200,
                                          child: Text(
                                            d['endereco'] ?? '---',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(d['tipo_da_falha'] ?? '---'),
                                      ),
                                      DataCell(
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              d['equipe_responsavel'] ??
                                                  d['equipe_atrelada'] ??
                                                  '---',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (d['placa_veiculo'] != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 2,
                                                    ),
                                                color: Colors.grey.shade200,
                                                child: Text(
                                                  d['placa_veiculo'],
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _corStatus(st),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            st.toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          _formatarDataHora(
                                            d['data_de_abertura'],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: isConcluido
                                              ? [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.receipt_long,
                                                      color: Colors.green,
                                                    ),
                                                    tooltip: 'Relatório PDF',
                                                    onPressed: () =>
                                                        _gerarPdfRelatorio(d),
                                                  ),
                                                ]
                                              : [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.edit,
                                                      color: Colors.blueGrey,
                                                    ),
                                                    tooltip: 'Editar',
                                                    onPressed: () =>
                                                        _abrirModalCadastro(
                                                          docId: doc.id,
                                                          dadosAtuais: d,
                                                        ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.directions_car,
                                                      color: Colors.blue,
                                                    ),
                                                    tooltip: 'Atribuir Equipe',
                                                    onPressed: () =>
                                                        _abrirModalAtribuir(
                                                          doc.id,
                                                        ),
                                                  ),
                                                  if (st.toLowerCase() ==
                                                      'em deslocamento')
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.location_on,
                                                        color: Colors.orange,
                                                      ),
                                                      tooltip:
                                                          'Informar Chegada',
                                                      onPressed: () =>
                                                          _registrarChegada(
                                                            doc.id,
                                                          ),
                                                    ),
                                                  if (st.toLowerCase() ==
                                                      'em atendimento')
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.check_circle,
                                                        color: Colors.green,
                                                      ),
                                                      tooltip:
                                                          'Finalizar Ocorrência',
                                                      onPressed: () =>
                                                          _abrirModalFinalizar(
                                                            doc.id,
                                                            d,
                                                          ),
                                                    ),
                                                ],
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
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

  Widget _buildFilterField(String label, TextEditingController controller) {
    return SizedBox(
      width: 160,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => _onFiltroChanged(),
      ),
    );
  }
}
