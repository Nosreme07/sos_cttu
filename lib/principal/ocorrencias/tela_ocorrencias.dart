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

  // Listas Auxiliares
  List<Map<String, dynamic>> _semaforosAux = [];
  List<Map<String, dynamic>> _falhasAux = [];
  List<String> _origensAux = [];
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

  String _formatarId(String idStr) {
    if (idStr.isEmpty || idStr.toUpperCase().contains('NUMERO')) return '000';
    String numeros = idStr.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeros.isEmpty) return idStr;
    return numeros.padLeft(3, '0');
  }

  Future<String> _gerarNumeroOcorrencia() async {
    int anoAtual = DateTime.now().year;
    DocumentReference contadorRef = FirebaseFirestore.instance.collection('contadores').doc('ocorrencias_$anoAtual');
    
    return await FirebaseFirestore.instance.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(contadorRef);
      int sequencia = 1;
      if (snapshot.exists) {
        sequencia = ((snapshot.data() as Map<String, dynamic>)['atual'] ?? 0) + 1;
        transaction.update(contadorRef, {'atual': sequencia});
      } else {
        transaction.set(contadorRef, {'atual': 1});
      }
      return '$anoAtual-${sequencia.toString().padLeft(4, '0')}';
    });
  }

  Future<void> _carregarDadosAuxiliares() async {
    try {
      final s = await FirebaseFirestore.instance.collection('semaforos').get();
      final f = await FirebaseFirestore.instance.collection('falhas').get();
      final e = await FirebaseFirestore.instance.collection('estoque').get();
      final o = await FirebaseFirestore.instance.collection('origens').get();

      setState(() {
        _semaforosAux = s.docs.map<Map<String, dynamic>>((doc) {
          var d = doc.data() as Map<String, dynamic>;
          return <String, dynamic>{
            'id': _formatarId((d['id'] ?? '').toString()),
            'endereco': (d['endereco'] ?? '').toString(),
            'bairro': (d['bairro'] ?? '').toString(),
            'empresa': (d['empresa'] ?? '').toString(),
          };
        }).toList();
        _semaforosAux.sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));

        _falhasAux = f.docs.map<Map<String, dynamic>>((doc) {
          var d = doc.data() as Map<String, dynamic>;
          return <String, dynamic>{
            'falha': (d['falha'] ?? '').toString(),
            'prioridade': (d['prioridade'] ?? 'MÉDIA').toString(),
            'prazo': (d['prazo'] ?? '').toString(),
          };
        }).where((item) => item['falha'].toString().isNotEmpty).toList();
        _falhasAux.sort((a, b) => a['falha'].toString().compareTo(b['falha'].toString()));

        _origensAux = o.docs.map((doc) {
          var d = doc.data() as Map<String, dynamic>;
          return (d['origem'] ?? '').toString();
        }).where((origem) => origem.isNotEmpty).toList();
        _origensAux.sort();

        _estoqueAux = e.docs.map((doc) {
          var d = doc.data() as Map<String, dynamic>;
          return (d['descricao'] ?? '').toString();
        }).toList();
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
    // Removido o \n para deixar a data em 1 linha e caber o divisor
    return DateFormat('dd/MM/yy HH:mm\'h\'').format(t.toDate());
  }

  void _abrirModalCadastro({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    bool estaSalvando = false; 
    
    String semaforoSel = dadosAtuais?['semaforo'] ?? '';
    String falhaSel = dadosAtuais?['tipo_da_falha'] ?? '';
    String origemSel = dadosAtuais?['origem_da_ocorrencia'] ?? '';

    List<String> opcoesSemaforos = _semaforosAux.map((s) => "${s['id']} - ${s['endereco']}").toSet().toList();
    if (semaforoSel.isNotEmpty && !opcoesSemaforos.any((e) => e.startsWith(semaforoSel))) {
      opcoesSemaforos.add(semaforoSel);
    }
    String semaforoDropdownValue = semaforoSel.isEmpty
        ? ''
        : opcoesSemaforos.firstWhere((e) => e.startsWith(semaforoSel), orElse: () => semaforoSel);

    List<String> opcoesFalhas = _falhasAux.map((f) => f['falha'] as String).toSet().toList();
    if (falhaSel.isNotEmpty && !opcoesFalhas.contains(falhaSel)) {
      opcoesFalhas.add(falhaSel);
    }

    List<String> opcoesOrigens = _origensAux.toSet().toList();
    if (origemSel.isNotEmpty && !opcoesOrigens.contains(origemSel)) {
      opcoesOrigens.add(origemSel);
    }

    final semaforoMenuCtrl = TextEditingController(text: semaforoDropdownValue);
    final falhaMenuCtrl = TextEditingController(text: falhaSel);
    final origemMenuCtrl = TextEditingController(text: origemSel);
    final detalhesCtrl = TextEditingController(text: dadosAtuais?['detalhes'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2c3e50)),
                ),
                const Divider(),
                const SizedBox(height: 10),
                
                LayoutBuilder(
                  builder: (context, constraints) {
                    return DropdownMenu<String>(
                      width: constraints.maxWidth,
                      controller: semaforoMenuCtrl,
                      enableFilter: true,
                      enableSearch: true,
                      label: const Text('Semáforo *'),
                      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                      initialSelection: semaforoDropdownValue.isEmpty ? null : semaforoDropdownValue,
                      dropdownMenuEntries: opcoesSemaforos.map((s) => DropdownMenuEntry(value: s, label: s)).toList(),
                      onSelected: (val) => semaforoSel = val ?? '',
                    );
                  }
                ),
                const SizedBox(height: 12),
                
                LayoutBuilder(
                  builder: (context, constraints) {
                    return DropdownMenu<String>(
                      width: constraints.maxWidth,
                      controller: falhaMenuCtrl,
                      enableFilter: true,
                      enableSearch: true,
                      label: const Text('Tipo da Falha *'),
                      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                      initialSelection: falhaSel.isEmpty ? null : falhaSel,
                      dropdownMenuEntries: opcoesFalhas.map((f) => DropdownMenuEntry(value: f, label: f)).toList(),
                      onSelected: (val) => falhaSel = val ?? '',
                    );
                  }
                ),
                const SizedBox(height: 12),

                LayoutBuilder(
                  builder: (context, constraints) {
                    return DropdownMenu<String>(
                      width: constraints.maxWidth,
                      controller: origemMenuCtrl,
                      enableFilter: true,
                      enableSearch: true,
                      label: const Text('Origem *'),
                      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                      initialSelection: origemSel.isEmpty ? null : origemSel,
                      dropdownMenuEntries: opcoesOrigens.map((o) => DropdownMenuEntry(value: o, label: o)).toList(),
                      onSelected: (val) => origemSel = val ?? '',
                    );
                  }
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: detalhesCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Detalhes da Ocorrência', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5cb85c), padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: estaSalvando ? null : () async {
                    if (semaforoMenuCtrl.text.isEmpty || !opcoesSemaforos.contains(semaforoMenuCtrl.text)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um semáforo válido!')));
                      return;
                    }
                    if (falhaMenuCtrl.text.isEmpty || !opcoesFalhas.contains(falhaMenuCtrl.text)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma falha válida!')));
                      return;
                    }
                    if (origemMenuCtrl.text.isEmpty || !opcoesOrigens.contains(origemMenuCtrl.text)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma origem válida!')));
                      return;
                    }

                    if (formKey.currentState!.validate()) {
                      setStateModal(() => estaSalvando = true);
                      try {
                        String semaforoFinal = semaforoMenuCtrl.text.split(' - ')[0];
                        String falhaFinal = falhaMenuCtrl.text;
                        String origemFinal = origemMenuCtrl.text;

                        Map<String, dynamic> payload = {
                          'semaforo': semaforoFinal,
                          'tipo_da_falha': falhaFinal,
                          'origem_da_ocorrencia': origemFinal,
                          'detalhes': detalhesCtrl.text.toUpperCase(),
                          'data_atualizacao': FieldValue.serverTimestamp(),
                        };

                        var semInfo = _semaforosAux.firstWhere((s) => s['id'] == semaforoFinal, orElse: () => <String, dynamic>{});
                        var falhaInfo = _falhasAux.firstWhere((f) => f['falha'] == falhaFinal, orElse: () => <String, dynamic>{});

                        payload['empresa_semaforo'] = semInfo['empresa'] ?? ''; 
                        payload['prazo'] = falhaInfo['prazo'] ?? '';

                        if (docId == null) {
                          String numOcorrencia = await _gerarNumeroOcorrencia();
                          payload['numero_da_ocorrencia'] = numOcorrencia;
                          payload['status'] = 'Aberto';
                          payload['data_de_abertura'] = FieldValue.serverTimestamp();
                          payload['endereco'] = semInfo['endereco'] ?? '';
                          payload['bairro'] = semInfo['bairro'] ?? '';
                          
                          await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').add(payload);
                        } else {
                          await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').doc(docId).update(payload);
                        }
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
                      } finally {
                         if (mounted) setStateModal(() => estaSalvando = false);
                      }
                    }
                  },
                  child: estaSalvando 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Salvar Ocorrência', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _abrirModalAtribuir(String docId) async {
    final equipesSnapshot = await FirebaseFirestore.instance.collection('equipes').where('status', isEqualTo: 'ativo').get();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Atribuir Equipe', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 10),
              if (equipesSnapshot.docs.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Text('Nenhuma equipe ATIVA encontrada no momento.'))
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
                      leading: const Icon(Icons.directions_car, color: Colors.blueGrey),
                      title: Text('$placa - $empresa', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(ints, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.check_circle_outline, color: Colors.green),
                      onTap: () async {
                        await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').doc(docId).update({
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

  void _registrarChegada(String docId) async {
    bool? conf = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar Chegada', style: TextStyle(color: Colors.orange)),
        content: const Text('Confirmar que a equipe chegou ao local e iniciará o atendimento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (conf == true) {
      await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').doc(docId).update({
        'status': 'Em atendimento',
        'data_atendimento': FieldValue.serverTimestamp(),
      });
    }
  }

  void _abrirModalFinalizar(String docId, Map<String, dynamic> dados) {
    bool defeitoConstatado = true;
    String falha = dados['tipo_da_falha'] ?? '';
    final descricaoCtrl = TextEditingController();
    final acaoCtrl = TextEditingController();

    List<String> opcoesFalhas = _falhasAux.map((f) => f['falha'] as String).toSet().toList();
    if (falha.isNotEmpty && !opcoesFalhas.contains(falha)) opcoesFalhas.add(falha);
    final falhaMenuCtrl = TextEditingController(text: falha);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => Padding(
          padding: EdgeInsets.only(top: 24, left: 24, right: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Finalizar Ocorrência', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.all(10),
                  color: Colors.blue.shade50,
                  child: Text('Falha Original: ${dados['tipo_da_falha'] ?? '---'}\nDetalhes: ${dados['detalhes'] ?? '---'}', style: const TextStyle(fontSize: 12)),
                ),
                SwitchListTile(
                  title: const Text('Foi constatado defeito?', style: TextStyle(fontWeight: FontWeight.bold)),
                  value: defeitoConstatado,
                  activeColor: Colors.green,
                  onChanged: (v) => setStateModal(() => defeitoConstatado = v),
                ),
                if (defeitoConstatado) ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return DropdownMenu<String>(
                        width: constraints.maxWidth,
                        controller: falhaMenuCtrl,
                        enableFilter: true,
                        enableSearch: true,
                        label: const Text('Falha Encontrada *'),
                        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                        initialSelection: falha.isEmpty ? null : falha,
                        dropdownMenuEntries: opcoesFalhas.map((f) => DropdownMenuEntry(value: f, label: f)).toList(),
                      );
                    }
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: descricaoCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Como encontrou o semáforo? *', border: OutlineInputBorder()),
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: acaoCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Ação Técnica da Equipe *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: () async {
                    if (defeitoConstatado && (falhaMenuCtrl.text.isEmpty || descricaoCtrl.text.isEmpty)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha a falha e descrição!')));
                      return;
                    }
                    if (acaoCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Descreva a ação realizada!')));
                      return;
                    }

                    await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').doc(docId).update({
                      'status': 'Finalizado',
                      'data_de_finalizacao': FieldValue.serverTimestamp(),
                      'falha_aparente_final': defeitoConstatado ? falhaMenuCtrl.text : 'DEFEITO NÃO CONSTATADO',
                      'descricao_encontro': defeitoConstatado ? descricaoCtrl.text.toUpperCase() : 'DEFEITO NÃO CONSTATADO',
                      'acao_equipe': acaoCtrl.text.toUpperCase(),
                      'usuario_finalizacao': 'Técnico App', 
                    });
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Concluir Atendimento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _gerarPdfRelatorio(Map<String, dynamic> dados) async {
    final pdf = pw.Document();
    String numOcc = dados['numero_da_ocorrencia'] ?? dados['id'] ?? 'N/A';

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('RELATÓRIO DE OCORRÊNCIA FINALIZADA', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text('Ocorrência Nº: $numOcc', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('Semáforo: ${dados['semaforo']} - ${dados['endereco']}'),
            pw.Text('Bairro: ${dados['bairro']}'),
            pw.Text('Prioridade: ${_falhasAux.firstWhere((f) => f['falha'] == dados['tipo_da_falha'], orElse: () => <String, dynamic>{'prioridade': '---'})['prioridade']}'),
            pw.Text('Prazo (h): ${dados['prazo'] ?? '---'}'),
            pw.SizedBox(height: 15),
            pw.Text('DADOS DA ABERTURA', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
            pw.Text('Falha Registrada: ${dados['tipo_da_falha']}'),
            pw.Text('Origem: ${dados['origem_da_ocorrencia']}'),
            pw.Text('Detalhes: ${dados['detalhes']}'),
            pw.SizedBox(height: 15),
            pw.Text('DADOS DO ATENDIMENTO', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.orange)),
            pw.Text('Equipe Responsável: ${dados['equipe_responsavel']}'),
            pw.Text('Veículo: ${dados['placa_veiculo'] ?? '---'}'),
            pw.Text('Ação Técnica: ${dados['acao_equipe'] ?? '---'}'),
            pw.Text('Como Encontrou: ${dados['descricao_encontro'] ?? '---'}'),
            pw.Text('Falha Final: ${dados['falha_aparente_final'] ?? '---'}'),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Ocorrencia_$numOcc.pdf');
  }

  Color _corStatus(String status) {
    String st = status.toLowerCase();
    if (st == 'aberto') return Colors.redAccent;
    if (st == 'em deslocamento') return Colors.orange;
    if (st == 'em atendimento') return Colors.green; 
    if (st.contains('conclu') || st.contains('finaliz')) return Colors.blueGrey; 
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Lista de Ocorrências', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5cb85c), padding: const EdgeInsets.all(16)),
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text('Nova Ocorrência', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => _abrirModalCadastro(),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: _verFinalizadas24h ? Colors.orange : Colors.blue, padding: const EdgeInsets.all(16)),
                            icon: Icon(_verFinalizadas24h ? Icons.pending_actions : Icons.history, color: Colors.white),
                            label: Text(_verFinalizadas24h ? 'Voltar para Pendentes' : 'Finalizadas (24h)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => setState(() => _verFinalizadas24h = !_verFinalizadas24h),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(8)),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildFilterField('Nº Ocorrência', _filtroNumero),
                            _buildFilterField('Semáforo', _filtroSemaforo),
                            _buildFilterField('Endereço', _filtroEndereco),
                            _buildFilterField('Empresa', _filtroEmpresa),
                            _buildFilterField('Falha', _filtroFalha),
                            _buildFilterField('Equipe', _filtroEquipe),
                            _buildFilterField('Status', _filtroStatus),
                            ActionChip(
                              backgroundColor: Colors.grey.shade600,
                              label: const Text('Limpar Filtros', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').orderBy('data_de_abertura', descending: true).snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const Center(child: Text('Nenhuma ocorrência encontrada. Clique em "Nova Ocorrência" para começar!'));
                          }

                          final docsFiltrados = snapshot.data!.docs.where((doc) {
                            var d = doc.data() as Map<String, dynamic>;
                            String st = (d['status'] ?? '').toLowerCase();
                            bool isConcluido = st.contains('conclu') || st.contains('finaliz');

                            if (_verFinalizadas24h) {
                              if (!isConcluido) return false;
                              if (d['data_de_finalizacao'] != null) {
                                DateTime dtFim = (d['data_de_finalizacao'] as Timestamp).toDate();
                                if (DateTime.now().difference(dtFim).inHours > 24) return false;
                              }
                            } else {
                              if (isConcluido) return false;
                            }

                            bool match(String field, TextEditingController ctrl) => (d[field] ?? '').toString().toLowerCase().contains(ctrl.text.toLowerCase());

                            if (_filtroNumero.text.isNotEmpty && !match('numero_da_ocorrencia', _filtroNumero)) return false;
                            if (_filtroSemaforo.text.isNotEmpty && !match('semaforo', _filtroSemaforo)) return false;
                            if (_filtroEndereco.text.isNotEmpty && !match('endereco', _filtroEndereco)) return false;
                            if (_filtroEmpresa.text.isNotEmpty && !match('empresa_semaforo', _filtroEmpresa)) return false;
                            if (_filtroFalha.text.isNotEmpty && !match('tipo_da_falha', _filtroFalha)) return false;
                            if (_filtroStatus.text.isNotEmpty && !match('status', _filtroStatus)) return false;

                            String eq = (d['equipe_responsavel'] ?? d['equipe_atrelada'] ?? '').toString().toLowerCase();
                            if (_filtroEquipe.text.isNotEmpty && !eq.contains(_filtroEquipe.text.toLowerCase())) return false;

                            return true;
                          }).toList();

                          if (docsFiltrados.isEmpty) {
                            return const Center(child: Text('Nenhum resultado para os filtros atuais.'));
                          }

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(const Color(0xFF2c3e50)),
                                headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                dataRowMaxHeight: 110, // Aumentado para garantir espaço na quebra de linha
                                dataRowMinHeight: 70,
                                columns: const [
                                  DataColumn(label: Text('Nº / Sem. - Endereço')),
                                  DataColumn(label: Text('Falha')),
                                  DataColumn(label: Text('Empresa')),
                                  DataColumn(label: Text('Equipe')),
                                  DataColumn(label: Text('Status')),
                                  DataColumn(label: Text('Abertura / Prazo')),
                                  DataColumn(label: Text('Ações')),
                                ],
                                rows: docsFiltrados.map((doc) {
                                  var d = doc.data() as Map<String, dynamic>;
                                  String st = d['status'] ?? 'Aberto';
                                  bool isConcluido = st.toLowerCase().contains('finaliz') || st.toLowerCase().contains('conclu');
                                  
                                  // --- LÓGICA DE EMPRESA (COM FALLBACK) ---
                                  String empresa = (d['empresa_semaforo'] ?? '').toString();
                                  if (empresa.isEmpty) {
                                    var semInfo = _semaforosAux.firstWhere((s) => s['id'] == d['semaforo'], orElse: () => <String, dynamic>{});
                                    empresa = (semInfo['empresa'] ?? '---').toString();
                                  }

                                  // --- LÓGICA DO PRAZO CALCULADO ---
                                  String txtPrazo = '---';
                                  if (d['data_de_abertura'] != null) {
                                    DateTime aberturaDt = (d['data_de_abertura'] as Timestamp).toDate();
                                    String prazoMinStr = (d['prazo'] ?? '').toString();
                                    if (prazoMinStr.isEmpty) {
                                       var falhaDoc = _falhasAux.firstWhere((f) => f['falha'] == d['tipo_da_falha'], orElse: () => <String, dynamic>{});
                                       prazoMinStr = (falhaDoc['prazo'] ?? '0').toString();
                                    }
                                    int prazoMinutos = int.tryParse(prazoMinStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                                    if (prazoMinutos > 0) {
                                       DateTime limite = aberturaDt.add(Duration(minutes: prazoMinutos));
                                       txtPrazo = DateFormat('dd/MM/yy HH:mm\'h\'').format(limite);
                                    }
                                  }

                                  return DataRow(
                                    cells: [
                                      // 1. Nº / Semáforo - Endereço
                                      DataCell(
                                        SizedBox(
                                          width: 250, // Caixa limite para FORÇAR a quebra do endereço
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                d['numero_da_ocorrencia'] ?? '---',
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 11),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${d['semaforo'] ?? '---'} - ${d['endereco'] ?? '---'}',
                                                maxLines: 3,
                                                softWrap: true,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      
                                      // 2. Falha (Voltou a ser separada)
                                      DataCell(
                                        SizedBox(
                                          width: 150,
                                          child: Text(
                                            d['tipo_da_falha'] ?? '---',
                                            maxLines: 3,
                                            softWrap: true,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 10, color: Colors.red.shade800, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),

                                      // 3. Empresa (Voltou a ser separada)
                                      DataCell(
                                        SizedBox(
                                          width: 80,
                                          child: Text(
                                            empresa, 
                                            style: TextStyle(fontSize: 10, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                                            maxLines: 2,
                                            softWrap: true,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      // 4. Equipe
                                      DataCell(
                                        SizedBox(
                                          width: 160,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                d['equipe_responsavel'] ?? d['equipe_atrelada'] ?? '---',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                                                softWrap: true,
                                              ),
                                              if (d['placa_veiculo'] != null)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  margin: const EdgeInsets.only(top: 4),
                                                  color: Colors.grey.shade200,
                                                  child: Text(d['placa_veiculo'], style: const TextStyle(fontSize: 9)),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // 5. Status
                                      DataCell(
                                        SizedBox(
                                          width: 90,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: _corStatus(st), borderRadius: BorderRadius.circular(4)),
                                            child: Text(st.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                        )
                                      ),

                                      // 6. Abertura / Prazo (Com a linha divisória e no mesmo bloco)
                                      DataCell(
                                        SizedBox(
                                          width: 95,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(_formatarDataHora(d['data_de_abertura']), style: const TextStyle(fontSize: 10)),
                                              Container(
                                                margin: const EdgeInsets.symmetric(vertical: 4),
                                                height: 1,
                                                color: Colors.grey.shade400,
                                              ),
                                              Text(txtPrazo, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                            ],
                                          ),
                                        )
                                      ),

                                      // 7. Ações (Liberadas, sem serem cortadas)
                                      DataCell(
                                        SizedBox(
                                          width: 160, 
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: isConcluido
                                                ? [
                                                    IconButton(
                                                      icon: const Icon(Icons.receipt_long, color: Colors.green, size: 20),
                                                      tooltip: 'Relatório PDF',
                                                      onPressed: () => _gerarPdfRelatorio(d),
                                                    ),
                                                  ]
                                                : [
                                                    IconButton(
                                                      icon: const Icon(Icons.edit, color: Colors.blueGrey, size: 20),
                                                      tooltip: 'Editar',
                                                      onPressed: () => _abrirModalCadastro(docId: doc.id, dadosAtuais: d),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.directions_car, color: Colors.blue, size: 20),
                                                      tooltip: 'Atribuir Equipe',
                                                      onPressed: () => _abrirModalAtribuir(doc.id),
                                                    ),
                                                    if (st.toLowerCase() == 'em deslocamento')
                                                      IconButton(
                                                        icon: const Icon(Icons.location_on, color: Colors.orange, size: 20),
                                                        tooltip: 'Informar Chegada',
                                                        onPressed: () => _registrarChegada(doc.id),
                                                      ),
                                                    if (st.toLowerCase() == 'em atendimento')
                                                      IconButton(
                                                        icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                                        tooltip: 'Finalizar Ocorrência',
                                                        onPressed: () => _abrirModalFinalizar(doc.id, d),
                                                      ),
                                                  ],
                                          ),
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