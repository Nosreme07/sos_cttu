import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

class ListaOcorrencias extends StatefulWidget {
  const ListaOcorrencias({super.key});

  @override
  State<ListaOcorrencias> createState() => _ListaOcorrenciasState();
}

class _ListaOcorrenciasState extends State<ListaOcorrencias> {
  bool _verFinalizadas24h = false;
  final TextEditingController _filtroSemaforo = TextEditingController();
  final TextEditingController _filtroEndereco = TextEditingController();
  final TextEditingController _filtroEmpresa = TextEditingController();
  final TextEditingController _filtroFalha = TextEditingController();
  final TextEditingController _filtroEquipe = TextEditingController();
  final TextEditingController _filtroStatus = TextEditingController();
  final TextEditingController _filtroNumero = TextEditingController();

  int? _sortColumnIndex = 5; 
  bool _sortAscending = false; 

  List<Map<String, dynamic>> _semaforosAux = [];
  List<Map<String, dynamic>> _falhasAux = [];
  
  // Listas Otimizadas para o Modal
  List<String> _opcoesSemaforos = [];
  List<String> _opcoesFalhas = [];
  List<String> _opcoesOrigens = [];

  Timer? _debounce;
  final ImagePicker _picker = ImagePicker();

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

  Future<String> _getNomeUsuario() async {
    User? usuarioLogado = FirebaseAuth.instance.currentUser;
    if (usuarioLogado == null) return 'SISTEMA';

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('usuarios').doc(usuarioLogado.uid).get();
      if (doc.exists && doc.data() != null) {
        var data = doc.data() as Map<String, dynamic>;
        if (data['nomeCompleto'] != null && data['nomeCompleto'].toString().isNotEmpty) {
          return data['nomeCompleto'].toString().toUpperCase();
        }
      }

      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('usuarios')
          .where('email', isEqualTo: usuarioLogado.email)
          .limit(1)
          .get();
          
      if (query.docs.isNotEmpty) {
        var data = query.docs.first.data() as Map<String, dynamic>;
        if (data['nomeCompleto'] != null && data['nomeCompleto'].toString().isNotEmpty) {
          return data['nomeCompleto'].toString().toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('Erro ao buscar nome do usuário: $e');
    }

    return (usuarioLogado.displayName ?? usuarioLogado.email ?? 'SISTEMA').toUpperCase();
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
      final o = await FirebaseFirestore.instance.collection('origens').get();

      List<Map<String, dynamic>> semaforosLocal = s.docs.map<Map<String, dynamic>>((doc) {
        var d = doc.data();
        return <String, dynamic>{
          'id': _formatarId((d['id'] ?? '').toString()),
          'endereco': (d['endereco'] ?? '').toString(),
          'bairro': (d['bairro'] ?? '').toString(),
          'empresa': (d['empresa'] ?? '').toString(),
        };
      }).toList();
      semaforosLocal.sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));

      List<Map<String, dynamic>> falhasLocal = f.docs.map<Map<String, dynamic>>((doc) {
        var d = doc.data();
        return <String, dynamic>{
          'falha': (d['tipo_da_falha'] ?? d['falha'] ?? '').toString(),
          'prioridade': (d['prioridade'] ?? 'MÉDIA').toString(),
          'prazo': (d['prazo'] ?? '').toString(),
        };
      }).where((item) => item['falha'].toString().isNotEmpty).toList();
      falhasLocal.sort((a, b) => a['falha'].toString().compareTo(b['falha'].toString()));

      List<String> origensLocal = o.docs.map((doc) {
        var d = doc.data();
        return (d['origem'] ?? '').toString();
      }).where((origem) => origem.isNotEmpty).toList();
      origensLocal.sort();

      setState(() {
        _semaforosAux = semaforosLocal;
        _falhasAux = falhasLocal;
        
        // Geração Antecipada das Listas do Modal (Otimização de Performance)
        _opcoesSemaforos = semaforosLocal.map((sem) => "${sem['id']} - ${sem['endereco']}").toSet().toList();
        _opcoesFalhas = falhasLocal.map((fal) => fal['falha'] as String).toSet().toList();
        _opcoesOrigens = origensLocal.toSet().toList();
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

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  String _formatarDataHora(Timestamp? t) {
    if (t == null) return '---';
    return DateFormat('dd/MM/yy HH:mm\'h\'').format(t.toDate());
  }

  String _formatarDataHoraCompleta(Timestamp? t) {
    if (t == null) return 'NÃO REGISTRADO';
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(t.toDate());
  }

  Future<Uint8List> _adicionarCarimboNaFoto(Uint8List imageBytes) async {
    try {
      final codec = kIsWeb
          ? await ui.instantiateImageCodec(imageBytes)
          : await ui.instantiateImageCodec(imageBytes, targetWidth: 800);

      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(image, Offset.zero, Paint());

      final paintRect = Paint()..color = Colors.black54;
      canvas.drawRect(
        Rect.fromLTWH(0, image.height.toDouble() - 60, image.width.toDouble(), 60),
        paintRect,
      );

      final textStyle = ui.TextStyle(color: Colors.yellowAccent, fontSize: 24, fontWeight: FontWeight.bold);
      final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.right);
      final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
        ..pushStyle(textStyle)
        ..addText('REGISTRO: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}');

      final paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: image.width.toDouble() - 20));
      canvas.drawParagraph(paragraph, Offset(0, image.height.toDouble() - 45));

      final picture = recorder.endRecording();
      final img = await picture.toImage(image.width, image.height);
      final pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);

      if (pngBytes == null) return imageBytes;
      return pngBytes.buffer.asUint8List();
    } catch (e) {
      return imageBytes;
    }
  }

  // --- MODAL DE CADASTRO OTIMIZADO ---
  void _abrirModalCadastro({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    bool estaSalvando = false;

    String semaforoSel = dadosAtuais?['semaforo'] ?? '';
    String falhaSel = dadosAtuais?['tipo_da_falha'] ?? '';
    String origemSel = dadosAtuais?['origem_da_ocorrencia'] ?? '';

    String semaforoDropdownValue = '';
    if (semaforoSel.isNotEmpty) {
      int idx = _opcoesSemaforos.indexWhere((e) => e.startsWith(semaforoSel));
      if (idx != -1) {
        semaforoDropdownValue = _opcoesSemaforos[idx];
      } else {
        _opcoesSemaforos.add(semaforoSel);
        semaforoDropdownValue = semaforoSel;
      }
    }

    if (falhaSel.isNotEmpty && !_opcoesFalhas.contains(falhaSel)) _opcoesFalhas.add(falhaSel);
    if (origemSel.isNotEmpty && !_opcoesOrigens.contains(origemSel)) _opcoesOrigens.add(origemSel);

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
            top: 24, left: 24, right: 24,
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
                DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero, // Preenche a largura sem precisar de LayoutBuilder
                  controller: semaforoMenuCtrl,
                  enableFilter: true, enableSearch: true,
                  label: const Text('Semáforo *'),
                  inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                  initialSelection: semaforoDropdownValue.isEmpty ? null : semaforoDropdownValue,
                  dropdownMenuEntries: _opcoesSemaforos.map((s) => DropdownMenuEntry(value: s, label: s)).toList(),
                  onSelected: (val) => semaforoSel = val ?? '',
                ),
                const SizedBox(height: 12),
                DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  controller: falhaMenuCtrl,
                  enableFilter: true, enableSearch: true,
                  label: const Text('Tipo da Falha *'),
                  inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                  initialSelection: falhaSel.isEmpty ? null : falhaSel,
                  dropdownMenuEntries: _opcoesFalhas.map((f) => DropdownMenuEntry(value: f, label: f)).toList(),
                  onSelected: (val) => falhaSel = val ?? '',
                ),
                const SizedBox(height: 12),
                DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  controller: origemMenuCtrl,
                  enableFilter: true, enableSearch: true,
                  label: const Text('Origem *'),
                  inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                  initialSelection: origemSel.isEmpty ? null : origemSel,
                  dropdownMenuEntries: _opcoesOrigens.map((o) => DropdownMenuEntry(value: o, label: o)).toList(),
                  onSelected: (val) => origemSel = val ?? '',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: detalhesCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(labelText: 'Detalhes da Ocorrência', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5cb85c), padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: estaSalvando
                      ? null
                      : () async {
                          if (semaforoMenuCtrl.text.isEmpty || !_opcoesSemaforos.contains(semaforoMenuCtrl.text)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um semáforo válido!')));
                            return;
                          }
                          if (falhaMenuCtrl.text.isEmpty || !_opcoesFalhas.contains(falhaMenuCtrl.text)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma falha válida!')));
                            return;
                          }
                          if (origemMenuCtrl.text.isEmpty || !_opcoesOrigens.contains(origemMenuCtrl.text)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma origem válida!')));
                            return;
                          }
                          
                          if (formKey.currentState!.validate()) {
                            setStateModal(() => estaSalvando = true);
                            try {
                              String semaforoFinal = semaforoMenuCtrl.text.split(' - ')[0];
                              String falhaFinal = falhaMenuCtrl.text;
                              String origemFinal = origemMenuCtrl.text;

                              QuerySnapshot duplicatas = await FirebaseFirestore.instance
                                  .collection('Gerenciamento_ocorrencias')
                                  .where('semaforo', isEqualTo: semaforoFinal)
                                  .where('tipo_da_falha', isEqualTo: falhaFinal)
                                  .get();

                              bool existeAtiva = duplicatas.docs.any((docSnap) {
                                if (docId != null && docSnap.id == docId) return false; 
                                String statusStr = (docSnap.data() as Map<String, dynamic>)['status']?.toString().toLowerCase() ?? '';
                                return !statusStr.contains('finaliz') && !statusStr.contains('conclu');
                              });

                              if (existeAtiva) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Já existe uma ocorrência EM ANDAMENTO com esta mesma falha para este semáforo!', style: TextStyle(fontWeight: FontWeight.bold)),
                                      backgroundColor: Colors.red,
                                      duration: Duration(seconds: 4),
                                    )
                                );
                                setStateModal(() => estaSalvando = false);
                                return;
                              }

                              var semInfo = _semaforosAux.firstWhere((s) => s['id'] == semaforoFinal, orElse: () => <String, dynamic>{});
                              var falhaInfo = _falhasAux.firstWhere((f) => f['falha'] == falhaFinal, orElse: () => <String, dynamic>{});

                              String nomeUsuario = await _getNomeUsuario();

                              Map<String, dynamic> payload = {
                                'semaforo': semaforoFinal,
                                'tipo_da_falha': falhaFinal,
                                'origem_da_ocorrencia': origemFinal,
                                'detalhes': detalhesCtrl.text.toUpperCase(),
                                'data_atualizacao': FieldValue.serverTimestamp(),
                                'empresa_semaforo': semInfo['empresa'] ?? '',
                                'prazo': falhaInfo['prazo'] ?? '',
                              };

                              if (docId == null) {
                                String numOcorrencia = await _gerarNumeroOcorrencia();
                                payload['numero_da_ocorrencia'] = numOcorrencia;
                                payload['status'] = 'Aberto';
                                payload['data_de_abertura'] = FieldValue.serverTimestamp();
                                payload['endereco'] = semInfo['endereco'] ?? '';
                                payload['bairro'] = semInfo['bairro'] ?? '';
                                payload['usuario_abertura'] = nomeUsuario; 
                                
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
                          'integrantes_equipe': ints, 
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
    bool estaSalvando = false;
    bool estaArrastandoArea = false;

    String falha = dados['tipo_da_falha'] ?? '';
    final descricaoCtrl = TextEditingController();
    final acaoCtrl = TextEditingController();
    List<Uint8List> fotosSelecionadas = [];

    if (falha.isNotEmpty && !_opcoesFalhas.contains(falha)) {
      _opcoesFalhas.add(falha);
    }
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
                  onChanged: (v) {
                    setStateModal(() {
                      defeitoConstatado = v;
                      if (!defeitoConstatado) {
                        acaoCtrl.text = 'A EQUIPE RELATA QUE REALIZOU UMA VISTORIA COMPLETA E O SEMÁFORO NÃO APRESENTOU DEFEITO.';
                      } else {
                        acaoCtrl.clear();
                      }
                    });
                  },
                ),
                if (defeitoConstatado) ...[
                  DropdownMenu<String>(
                    expandedInsets: EdgeInsets.zero,
                    controller: falhaMenuCtrl,
                    enableFilter: true, enableSearch: true,
                    label: const Text('Falha Encontrada *'),
                    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                    initialSelection: falha.isEmpty ? null : falha,
                    dropdownMenuEntries: _opcoesFalhas.map((f) => DropdownMenuEntry(value: f, label: f)).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: descricaoCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    decoration: const InputDecoration(labelText: 'Como encontrou o semáforo? *', border: OutlineInputBorder()),
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: acaoCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(labelText: 'Ação Técnica da Equipe *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),

                const Text('Fotos do Serviço (Max: 4)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 8),

                if (fotosSelecionadas.isNotEmpty)
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: fotosSelecionadas.length,
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 100, height: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                                image: DecorationImage(image: MemoryImage(fotosSelecionadas[index]), fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 2, right: 10,
                              child: GestureDetector(
                                onTap: () => setStateModal(() => fotosSelecionadas.removeAt(index)),
                                child: const CircleAvatar(radius: 12, backgroundColor: Colors.red, child: Icon(Icons.close, size: 14, color: Colors.white)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt), label: const Text('Câmera'),
                        onPressed: fotosSelecionadas.length >= 4 ? null : () async {
                          final XFile? foto = await _picker.pickImage(source: ImageSource.camera);
                          if (foto != null) {
                            Uint8List bytes = await foto.readAsBytes();
                            Uint8List carimbada = await _adicionarCarimboNaFoto(bytes);
                            setStateModal(() => fotosSelecionadas.add(carimbada));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library), label: const Text('Galeria / PC'),
                        onPressed: fotosSelecionadas.length >= 4 ? null : () async {
                          final List<XFile> fotos = await _picker.pickMultiImage();
                          for (var foto in fotos) {
                            if (fotosSelecionadas.length >= 4) break;
                            Uint8List bytes = await foto.readAsBytes();
                            Uint8List carimbada = await _adicionarCarimboNaFoto(bytes);
                            setStateModal(() => fotosSelecionadas.add(carimbada));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (fotosSelecionadas.length < 4)
                  DropTarget(
                    onDragEntered: (detail) => setStateModal(() => estaArrastandoArea = true),
                    onDragExited: (detail) => setStateModal(() => estaArrastandoArea = false),
                    onDragDone: (detail) async {
                      setStateModal(() => estaArrastandoArea = false);
                      for (var file in detail.files) {
                        if (fotosSelecionadas.length >= 4) break;
                        if (file.mimeType?.startsWith('image/') ?? true) {
                          Uint8List bytes = await file.readAsBytes();
                          Uint8List carimbada = await _adicionarCarimboNaFoto(bytes);
                          setStateModal(() => fotosSelecionadas.add(carimbada));
                        }
                      }
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          final List<XFile> fotos = await _picker.pickMultiImage();
                          for (var foto in fotos) {
                            if (fotosSelecionadas.length >= 4) break;
                            Uint8List bytes = await foto.readAsBytes();
                            Uint8List carimbada = await _adicionarCarimboNaFoto(bytes);
                            setStateModal(() => fotosSelecionadas.add(carimbada));
                          }
                        },
                        child: Container(
                          height: 90, width: double.infinity,
                          decoration: BoxDecoration(
                            color: estaArrastandoArea ? Colors.green.withValues(alpha: 0.1) : Colors.grey.shade50,
                            border: Border.all(color: estaArrastandoArea ? Colors.green : Colors.grey.shade300, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_upload, color: estaArrastandoArea ? Colors.green : Colors.blueGrey, size: 28),
                                const SizedBox(height: 4),
                                Text(
                                  'Ou arraste as imagens e solte aqui\n(Clique para abrir a galeria)',
                                  style: TextStyle(color: estaArrastandoArea ? Colors.green : Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: estaSalvando
                      ? null
                      : () async {
                          if (defeitoConstatado && (falhaMenuCtrl.text.isEmpty || descricaoCtrl.text.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha a falha e descrição!')));
                            return;
                          }
                          if (acaoCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Descreva a ação realizada!')));
                            return;
                          }

                          setStateModal(() => estaSalvando = true);

                          try {
                            List<String> fotosBase64 = [];
                            for (Uint8List fotoBytes in fotosSelecionadas) {
                              fotosBase64.add(base64Encode(fotoBytes));
                            }

                            String nomeUsuario = await _getNomeUsuario();

                            await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').doc(docId).update({
                              'status': 'Finalizado',
                              'data_de_finalizacao': FieldValue.serverTimestamp(),
                              'falha_aparente_final': defeitoConstatado ? falhaMenuCtrl.text : 'DEFEITO NÃO CONSTATADO',
                              'descricao_encontro': defeitoConstatado ? descricaoCtrl.text.toUpperCase() : 'DEFEITO NÃO CONSTATADO',
                              'acao_equipe': acaoCtrl.text.toUpperCase(),
                              'fotos_finalizacao': fotosBase64,
                              'usuario_finalizacao': nomeUsuario, 
                            });

                            if (mounted) Navigator.pop(context);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
                            setStateModal(() => estaSalvando = false);
                          }
                        },
                  child: estaSalvando
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Concluir Atendimento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _abrirModalVisualizar(Map<String, dynamic> dados) {
    String numOcc = dados['numero_da_ocorrencia'] ?? dados['id'] ?? 'N/A';
    
    DateTime? aberturaDt = dados['data_de_abertura'] != null ? (dados['data_de_abertura'] as Timestamp).toDate() : null;
    DateTime? finalizacaoDt = dados['data_de_finalizacao'] != null ? (dados['data_de_finalizacao'] as Timestamp).toDate() : null;
    
    String textoVencimento = 'Não';
    String prazoStr = (dados['prazo'] ?? '').toString();
    if (prazoStr.isEmpty) {
      var falhaDoc = _falhasAux.firstWhere((f) => f['falha'] == dados['tipo_da_falha'], orElse: () => <String, dynamic>{});
      prazoStr = (falhaDoc['prazo'] ?? '0').toString();
    }
    int prazoMinutos = int.tryParse(prazoStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (aberturaDt != null && finalizacaoDt != null && prazoMinutos > 0) {
      DateTime limite = aberturaDt.add(Duration(minutes: prazoMinutos));
      if (finalizacaoDt.isAfter(limite)) {
        int minutosExcedidos = finalizacaoDt.difference(limite).inMinutes;
        textoVencimento = 'Sim ($minutosExcedidos minutos excedidos)';
      }
    }

    String integrantesRaw = dados['integrantes_equipe'] ?? dados['equipe_responsavel'] ?? dados['equipe_atrelada'] ?? '---';
    String integrantesFormatados = integrantesRaw != '---'
        ? integrantesRaw.split(',').map((e) => '- ${e.trim().toUpperCase()}').join('\n')
        : '---';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Ocorrência Nº $numOcc', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2c3e50))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                
                _infoRow('Semáforo:', '${dados['semaforo']} - ${dados['endereco']}'),
                _infoRow('Bairro:', dados['bairro'] ?? '---'),
                _infoRow('Origem:', dados['origem_da_ocorrencia'] ?? '---'),
                const SizedBox(height: 10),
                
                const Text('DATAS E PRAZOS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                _infoRow('Abertura:', _formatarDataHoraCompleta(dados['data_de_abertura'])),
                _infoRow('Atendimento:', _formatarDataHoraCompleta(dados['data_atendimento'])),
                _infoRow('Finalização:', _formatarDataHoraCompleta(dados['data_de_finalizacao'])),
                _infoRow('Ocorrência Venceu:', textoVencimento, corValor: textoVencimento.startsWith('Sim') ? Colors.red : Colors.green),
                const SizedBox(height: 10),

                const Text('ENVOLVIDOS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                _infoRow('Gerada por:', dados['usuario_abertura'] ?? 'Sistema'),
                _infoRow('Finalizada por:', dados['usuario_finalizacao'] ?? '---'),
                
                const Padding(
                  padding: EdgeInsets.only(bottom: 4, top: 4),
                  child: Text('Equipe Responsável:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(integrantesFormatados, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                ),
                
                _infoRow('Veículo:', dados['placa_veiculo'] ?? '---'),
                const SizedBox(height: 10),

                const Text('DADOS TÉCNICOS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                _infoRow('Falha Relatada:', dados['tipo_da_falha'] ?? '---'),
                _infoRow('Falha Encontrada:', dados['falha_aparente_final'] ?? '---'),
                _infoRow('Ação Técnica:', dados['acao_equipe'] ?? '---'),
                const SizedBox(height: 15),

                if (dados['fotos_finalizacao'] != null && (dados['fotos_finalizacao'] as List).isNotEmpty) ...[
                  const Text('FOTOS ANEXADAS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10, runSpacing: 10,
                    children: (dados['fotos_finalizacao'] as List).map((base64Str) {
                      try {
                        return Container(
                          height: 150, width: 150,
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(base64Decode(base64Str), fit: BoxFit.cover),
                          ),
                        );
                      } catch (e) {
                        return const SizedBox.shrink();
                      }
                    }).toList(),
                  )
                ]
              ],
            ),
          ),
        ),
      )
    );
  }

  Widget _infoRow(String label, String value, {Color? corValor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          children: [
            TextSpan(text: '$label ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value, style: TextStyle(color: corValor ?? Colors.black87)),
          ],
        ),
      ),
    );
  }

  Future<void> _gerarPdfRelatorio(Map<String, dynamic> dados) async {
    final pdf = pw.Document();
    String numOcc = dados['numero_da_ocorrencia'] ?? dados['id'] ?? 'N/A';

    DateTime? aberturaDt = dados['data_de_abertura'] != null ? (dados['data_de_abertura'] as Timestamp).toDate() : null;
    DateTime? finalizacaoDt = dados['data_de_finalizacao'] != null ? (dados['data_de_finalizacao'] as Timestamp).toDate() : null;
    
    String textoVencimento = 'Não';
    String prazoStr = (dados['prazo'] ?? '').toString();
    if (prazoStr.isEmpty) {
      var falhaDoc = _falhasAux.firstWhere((f) => f['falha'] == dados['tipo_da_falha'], orElse: () => <String, dynamic>{});
      prazoStr = (falhaDoc['prazo'] ?? '0').toString();
    }
    int prazoMinutos = int.tryParse(prazoStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (aberturaDt != null && finalizacaoDt != null && prazoMinutos > 0) {
      DateTime limite = aberturaDt.add(Duration(minutes: prazoMinutos));
      if (finalizacaoDt.isAfter(limite)) {
        int minutosExcedidos = finalizacaoDt.difference(limite).inMinutes;
        textoVencimento = 'Sim ($minutosExcedidos minutos excedidos)';
      }
    }
    
    String integrantesRaw = dados['integrantes_equipe'] ?? dados['equipe_responsavel'] ?? dados['equipe_atrelada'] ?? '---';
    String integrantesFormatados = integrantesRaw != '---'
        ? integrantesRaw.split(',').map((e) => '- ${e.trim().toUpperCase()}').join('\n')
        : '---';

    List<pw.Widget> imagensPdf = [];
    if (dados['fotos_finalizacao'] != null) {
      for (String base64Str in (dados['fotos_finalizacao'] as List)) {
        try {
          final imageBytes = base64Decode(base64Str);
          imagensPdf.add(
            pw.Container(
              margin: const pw.EdgeInsets.all(4),
              height: 110, width: 110,
              child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.cover)
            )
          );
        } catch (e) {
          // ignora imagem invalida
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(40),
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Relatório gerado pelo sistema de ocorrência semafóricas - SOS em ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          );
        },
        build: (pw.Context context) => [
          pw.Text('RELATÓRIO DE OCORRÊNCIA', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
          pw.Divider(),
          pw.SizedBox(height: 10),
          
          pw.Text('Nº da ocorrência: $numOcc', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Semáforo: ${dados['semaforo'] ?? '---'} - ${dados['endereco'] ?? '---'}'),
          pw.Text('Bairro: ${dados['bairro'] ?? '---'}'),
          pw.Text('Origem: ${dados['origem_da_ocorrencia'] ?? '---'}'),
          pw.SizedBox(height: 15),
          
          pw.Text('DATAS E PRAZOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
          pw.Text('Data de abertura: ${_formatarDataHoraCompleta(dados['data_de_abertura'])}'),
          pw.Text('Data de atendimento: ${_formatarDataHoraCompleta(dados['data_atendimento'])}'),
          pw.Text('Data de finalização: ${_formatarDataHoraCompleta(dados['data_de_finalizacao'])}'),
          pw.Text('Ocorrência venceu: $textoVencimento', style: pw.TextStyle(color: textoVencimento.startsWith('Sim') ? PdfColors.red : PdfColors.black)),
          pw.SizedBox(height: 15),
          
          pw.Text('ENVOLVIDOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
          pw.Text('Ocorrência gerada por: ${dados['usuario_abertura'] ?? 'Sistema'}'),
          pw.Text('Ocorrência Finalizada por: ${dados['usuario_finalizacao'] ?? '---'}'),
          pw.SizedBox(height: 6),
          pw.Text('Equipe responsável:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text(integrantesFormatados),
          pw.SizedBox(height: 6),
          pw.Text('Veículo: ${dados['placa_veiculo'] ?? '---'}'),
          pw.SizedBox(height: 15),
          
          pw.Text('DADOS TÉCNICOS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
          pw.Text('Falha Relatada: ${dados['tipo_da_falha'] ?? '---'}'),
          pw.Text('Falha encontrada: ${dados['falha_aparente_final'] ?? '---'}'),
          pw.Text('Ação técnica: ${dados['acao_equipe'] ?? '---'}'),
          pw.SizedBox(height: 20),

          if (imagensPdf.isNotEmpty) ...[
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text('FOTOS ANEXADAS:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: imagensPdf,
            )
          ]
        ],
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
      body: SelectionArea(
        child: Stack(
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
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: _verFinalizadas24h ? Colors.orange : Colors.blue,
                                  padding: const EdgeInsets.all(16)),
                              icon: Icon(_verFinalizadas24h ? Icons.pending_actions : Icons.history, color: Colors.white),
                              label: Text(_verFinalizadas24h ? 'Voltar para Pendentes' : 'Finalizadas (24h)',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1400),
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        margin: const EdgeInsets.only(top: 8, bottom: 24, left: 16, right: 16),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator());
                            }
                            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                              return const Padding(
                                  padding: EdgeInsets.all(40.0),
                                  child: Text('Nenhuma ocorrência encontrada. Clique em "Nova Ocorrência" para começar!'));
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

                              bool match(String field, TextEditingController ctrl) {
                                String valor;
                                if (field == 'empresa_semaforo' && (d[field] == null || d[field].toString().isEmpty)) {
                                  var semInfo = _semaforosAux.firstWhere((s) => s['id'] == d['semaforo'], orElse: () => <String, dynamic>{});
                                  valor = (semInfo['empresa'] ?? '').toString();
                                } else {
                                  valor = (d[field] ?? '').toString();
                                }
                                return valor.toLowerCase().contains(ctrl.text.toLowerCase());
                              }

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

                            if (_sortColumnIndex != null) {
                              docsFiltrados.sort((a, b) {
                                var d1 = a.data() as Map<String, dynamic>;
                                var d2 = b.data() as Map<String, dynamic>;
                                
                                int compare = 0;
                                switch (_sortColumnIndex) {
                                  case 0:
                                    String n1 = (d1['numero_da_ocorrencia'] ?? '').toString();
                                    String n2 = (d2['numero_da_ocorrencia'] ?? '').toString();
                                    compare = n1.compareTo(n2);
                                    break;
                                  case 1:
                                    String f1 = (d1['tipo_da_falha'] ?? '').toString();
                                    String f2 = (d2['tipo_da_falha'] ?? '').toString();
                                    compare = f1.compareTo(f2);
                                    break;
                                  case 2:
                                    String e1 = (d1['empresa_semaforo'] ?? '').toString();
                                    if (e1.isEmpty) {
                                        var s1 = _semaforosAux.firstWhere((s) => s['id'] == d1['semaforo'], orElse: () => <String, dynamic>{});
                                        e1 = (s1['empresa'] ?? '').toString();
                                    }
                                    String e2 = (d2['empresa_semaforo'] ?? '').toString();
                                    if (e2.isEmpty) {
                                        var s2 = _semaforosAux.firstWhere((s) => s['id'] == d2['semaforo'], orElse: () => <String, dynamic>{});
                                        e2 = (s2['empresa'] ?? '').toString();
                                    }
                                    compare = e1.compareTo(e2);
                                    break;
                                  case 3:
                                    String eq1 = (d1['equipe_responsavel'] ?? d1['equipe_atrelada'] ?? '').toString();
                                    String eq2 = (d2['equipe_responsavel'] ?? d2['equipe_atrelada'] ?? '').toString();
                                    compare = eq1.compareTo(eq2);
                                    break;
                                  case 4:
                                    String st1 = (d1['status'] ?? '').toString();
                                    String st2 = (d2['status'] ?? '').toString();
                                    compare = st1.compareTo(st2);
                                    break;
                                  case 5:
                                    if (_verFinalizadas24h) {
                                      DateTime dt1 = d1['data_de_finalizacao'] != null ? (d1['data_de_finalizacao'] as Timestamp).toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                                      DateTime dt2 = d2['data_de_finalizacao'] != null ? (d2['data_de_finalizacao'] as Timestamp).toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                                      compare = dt1.compareTo(dt2);
                                    } else {
                                      DateTime dt1 = d1['data_de_abertura'] != null ? (d1['data_de_abertura'] as Timestamp).toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                                      DateTime dt2 = d2['data_de_abertura'] != null ? (d2['data_de_abertura'] as Timestamp).toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                                      compare = dt1.compareTo(dt2);
                                    }
                                    break;
                                }
                                return _sortAscending ? compare : -compare;
                              });
                            }

                            if (docsFiltrados.isEmpty) {
                              return const Padding(
                                  padding: EdgeInsets.all(40.0),
                                  child: Text('Nenhum resultado para os filtros atuais.'));
                            }

                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  sortColumnIndex: _sortColumnIndex,
                                  sortAscending: _sortAscending,
                                  headingRowColor: WidgetStateProperty.all(const Color(0xFF2c3e50)),
                                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  dataRowMaxHeight: 110,
                                  dataRowMinHeight: 70,
                                  columns: [
                                    DataColumn(onSort: _onSort, label: const Expanded(child: Text('Nº / Sem. - Endereço', textAlign: TextAlign.center))),
                                    DataColumn(onSort: _onSort, label: const Expanded(child: Text('Falha', textAlign: TextAlign.center))),
                                    DataColumn(onSort: _onSort, label: const Expanded(child: Text('Empresa', textAlign: TextAlign.center))),
                                    DataColumn(onSort: _onSort, label: const Expanded(child: Text('Equipe', textAlign: TextAlign.center))),
                                    DataColumn(onSort: _onSort, label: const Expanded(child: Text('Status', textAlign: TextAlign.center))),
                                    DataColumn(onSort: _onSort, label: Expanded(child: Text(_verFinalizadas24h ? 'Finalização' : 'Abertura / Prazo', textAlign: TextAlign.center))),
                                    const DataColumn(label: Expanded(child: Text('Ações', textAlign: TextAlign.center))),
                                  ],
                                  rows: docsFiltrados.map((doc) {
                                    var d = doc.data() as Map<String, dynamic>;
                                    String st = d['status'] ?? 'Aberto';
                                    bool isConcluido = st.toLowerCase().contains('finaliz') || st.toLowerCase().contains('conclu');

                                    String empresa = (d['empresa_semaforo'] ?? '').toString();
                                    if (empresa.isEmpty) {
                                      var semInfo = _semaforosAux.firstWhere((s) => s['id'] == d['semaforo'], orElse: () => <String, dynamic>{});
                                      empresa = (semInfo['empresa'] ?? '---').toString();
                                    }

                                    String txtPrazo = '---';
                                    bool prazoVencido = false;

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
                                        if (!isConcluido && DateTime.now().isAfter(limite)) {
                                          prazoVencido = true;
                                        }
                                      }
                                    }

                                    return DataRow(cells: [
                                      DataCell(
                                        SizedBox(
                                          width: 250,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                d['numero_da_ocorrencia'] ?? '---',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${d['semaforo'] ?? '---'} - ${d['endereco'] ?? '---'}',
                                                maxLines: 3, softWrap: true, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 150,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                d['tipo_da_falha'] ?? '---',
                                                maxLines: 3, softWrap: true, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: 11, color: Colors.red.shade800, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 90,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                empresa,
                                                textAlign: TextAlign.center, maxLines: 2, softWrap: true, overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 11, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 160,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                d['equipe_responsavel'] ?? d['equipe_atrelada'] ?? '---',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                                softWrap: true,
                                              ),
                                              if (d['placa_veiculo'] != null)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  margin: const EdgeInsets.only(top: 4),
                                                  color: Colors.grey.shade200,
                                                  child: Text(d['placa_veiculo'], style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 100,
                                          child: Container(
                                            alignment: Alignment.center,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(color: _corStatus(st), borderRadius: BorderRadius.circular(4)),
                                              child: Text(st.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 120,
                                          child: _verFinalizadas24h
                                              ? Center(
                                                  child: Text(
                                                    _formatarDataHora(d['data_de_finalizacao']),
                                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                )
                                              : Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  crossAxisAlignment: CrossAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      _formatarDataHora(d['data_de_abertura']),
                                                      style: const TextStyle(fontSize: 11),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                    Container(
                                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                                      height: 1, color: Colors.grey.shade400,
                                                    ),
                                                    Text(
                                                      txtPrazo,
                                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: prazoVencido ? Colors.red : Colors.blueGrey),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 160,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: isConcluido
                                                ? [
                                                    IconButton(
                                                      icon: const Icon(Icons.visibility, color: Colors.blue, size: 22),
                                                      tooltip: 'Visualizar Ocorrência',
                                                      onPressed: () => _abrirModalVisualizar(d),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 22),
                                                      tooltip: 'Baixar PDF',
                                                      onPressed: () => _gerarPdfRelatorio(d),
                                                    ),
                                                  ]
                                                : [
                                                    IconButton(
                                                      icon: const Icon(Icons.edit, color: Colors.blueGrey, size: 22),
                                                      tooltip: 'Editar',
                                                      onPressed: () => _abrirModalCadastro(docId: doc.id, dadosAtuais: d),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.directions_car, color: Colors.blue, size: 22),
                                                      tooltip: 'Atribuir Equipe',
                                                      onPressed: () => _abrirModalAtribuir(doc.id),
                                                    ),
                                                    if (st.toLowerCase() == 'em deslocamento')
                                                      IconButton(
                                                        icon: const Icon(Icons.location_on, color: Colors.orange, size: 22),
                                                        tooltip: 'Informar Chegada',
                                                        onPressed: () => _registrarChegada(doc.id),
                                                      ),
                                                    if (st.toLowerCase() == 'em atendimento')
                                                      IconButton(
                                                        icon: const Icon(Icons.check_circle, color: Colors.green, size: 22),
                                                        tooltip: 'Finalizar Ocorrência',
                                                        onPressed: () => _abrirModalFinalizar(doc.id, d),
                                                      ),
                                                  ],
                                          ),
                                        ),
                                      ),
                                    ]);
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
      ),
    );
  }

  Widget _buildFilterField(String label, TextEditingController controller) {
    return SizedBox(
      width: 160,
      child: TextField(
        controller: controller,
        inputFormatters: [UpperCaseTextFormatter()],
        textCapitalization: TextCapitalization.characters,
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