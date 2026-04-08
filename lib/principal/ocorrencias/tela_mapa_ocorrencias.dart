import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import '../programacao/tela_programacao.dart';

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

class TelaMapaOcorrencias extends StatefulWidget {
  const TelaMapaOcorrencias({super.key});

  @override
  State<TelaMapaOcorrencias> createState() => _TelaMapaOcorrenciasState();
}

class _TelaMapaOcorrenciasState extends State<TelaMapaOcorrencias> {
  final MapController _mapController = MapController();
  final LatLng _centroPadrao = const LatLng(-8.047, -34.877);
  final ImagePicker _picker = ImagePicker();

  bool _fStatusAberto = true;
  bool _fStatusDesloc = true;
  bool _fStatusAtend = true;
  bool _fPrioAlta = true;
  bool _fPrioMedia = true;
  bool _fPrioBaixa = true;
  bool _fMais24h = false;
  bool _fForaPrazo = false;
  String _filtroEmpresa = 'TODAS';

  bool _filtrosVisiveis = true;

  List<String> _empresasOptions = ['TODAS'];
  Map<String, String> _mapaPrioridades = {};
  Map<String, LatLng> _mapaCoordenadasSemaforos = {}; 

  List<QueryDocumentSnapshot> _todasOcorrencias = [];
  List<QueryDocumentSnapshot> _todasEquipes = [];
  
  List<Map<String, dynamic>> _semaforosAux = [];
  List<Map<String, dynamic>> _falhasAux = [];
  
  // Listas Otimizadas para o Modal de Cadastro
  List<String> _opcoesSemaforos = [];
  List<String> _opcoesFalhas = [];
  List<String> _opcoesOrigens = [];
  List<String> _opcoesMateriais = [];

  late Stream<QuerySnapshot> _streamOcorrencias;
  late Stream<QuerySnapshot> _streamEquipes;

  @override
  void initState() {
    super.initState();
    _streamOcorrencias = FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').snapshots();
    _streamEquipes = FirebaseFirestore.instance.collection('equipes').snapshots();
    _carregarAuxiliares();
  }

  String _formatarId(String idStr) {
    if (idStr.isEmpty || idStr.toUpperCase().contains('NUMERO')) return '000';
    String numeros = idStr.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeros.isEmpty) return idStr;
    return numeros.padLeft(3, '0');
  }

  LatLng? _parseLatLng(dynamic geo) {
    if (geo == null) return null;
    if (geo is GeoPoint) return LatLng(geo.latitude, geo.longitude);
    
    String geoStr = geo.toString().trim();
    if (geoStr.isEmpty) return null;

    geoStr = geoStr.replaceAll(RegExp(r'[^\d\.,-]+'), ' ').trim();
    var partes = geoStr.split(RegExp(r'[\s,]+'));
    
    List<double> nums = [];
    for (var p in partes) {
      double? val = double.tryParse(p);
      if (val != null) nums.add(val);
    }

    if (nums.length >= 2) return LatLng(nums[0], nums[1]);
    return null;
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

      QuerySnapshot query = await FirebaseFirestore.instance.collection('usuarios').where('email', isEqualTo: usuarioLogado.email).limit(1).get();
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

  Future<void> _carregarAuxiliares() async {
    try {
      final resultados = await Future.wait([
        FirebaseFirestore.instance.collection('falhas').get(),
        FirebaseFirestore.instance.collection('semaforos').get(),
        FirebaseFirestore.instance.collection('origens').get(),
        FirebaseFirestore.instance.collection('materiais').get(),
      ]);

      final f = resultados[0];
      final s = resultados[1];
      final o = resultados[2];
      final m = resultados[3];

      Map<String, String> prios = {};
      List<Map<String, dynamic>> falhasLocal = [];
      for (var doc in f.docs) {
        var d = doc.data() as Map<String, dynamic>? ?? {};
        String tipo = (d['tipo_da_falha'] ?? d['falha'] ?? '').toString();
        String prio = (d['prioridade_da_falha'] ?? d['prioridade'] ?? 'BAIXA').toString();
        if (tipo.isNotEmpty) {
          prios[tipo] = prio;
          falhasLocal.add({'falha': tipo, 'prioridade': prio, 'prazo': (d['prazo'] ?? '').toString()});
        }
      }

      Map<String, LatLng> coords = {};
      List<Map<String, dynamic>> semaforosLocal = [];
      for (var doc in s.docs) {
        var d = doc.data() as Map<String, dynamic>? ?? {};
        String idSemaforo = _formatarId((d['numero'] ?? d['id'] ?? doc.id).toString());
        
        dynamic geoData = d['georeferencia'] ?? d['coordenadas'] ?? d['localizacao'];
        LatLng? latLng = _parseLatLng(geoData);
        if (latLng == null && d['latitude'] != null && d['longitude'] != null) {
          double? lat = double.tryParse(d['latitude'].toString());
          double? lng = double.tryParse(d['longitude'].toString());
          if (lat != null && lng != null) latLng = LatLng(lat, lng);
        }
        if (idSemaforo.isNotEmpty && latLng != null) coords[idSemaforo] = latLng; 
        
        semaforosLocal.add({
          'id': idSemaforo,
          'endereco': (d['endereco'] ?? '').toString(),
          'bairro': (d['bairro'] ?? '').toString(),
          'empresa': (d['empresa'] ?? '').toString(),
        });
      }

      List<String> origensLocal = o.docs.map((doc) => ((doc.data() as Map<String, dynamic>)['origem'] ?? '').toString()).where((origem) => origem.isNotEmpty).toList();
      List<String> materiaisLocal = m.docs.map((doc) => ((doc.data() as Map<String, dynamic>)['nome'] ?? (doc.data() as Map<String, dynamic>)['descricao'] ?? (doc.data() as Map<String, dynamic>)['material'] ?? '').toString().toUpperCase()).where((mat) => mat.isNotEmpty).toList();
      
      origensLocal.sort();
      semaforosLocal.sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
      falhasLocal.sort((a, b) => a['falha'].toString().compareTo(b['falha'].toString()));
      materiaisLocal.sort();

      if (mounted) {
        setState(() {
          _mapaPrioridades = prios;
          _mapaCoordenadasSemaforos = coords;
          _semaforosAux = semaforosLocal;
          _falhasAux = falhasLocal;
          
          _opcoesSemaforos = semaforosLocal.map((sem) => "${sem['id']} - ${sem['endereco']}").toSet().toList();
          _opcoesFalhas = falhasLocal.map((fal) => fal['falha'] as String).toSet().toList();
          _opcoesOrigens = origensLocal.toSet().toList();
          _opcoesMateriais = materiaisLocal.toSet().toList();
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar auxiliares no Mapa: $e");
    }
  }

  Future<Uint8List> _adicionarCarimboNaFoto(Uint8List imageBytes) async {
    try {
      final codec = kIsWeb ? await ui.instantiateImageCodec(imageBytes) : await ui.instantiateImageCodec(imageBytes, targetWidth: 800);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(image, Offset.zero, Paint());
      final paintRect = Paint()..color = Colors.black54;
      canvas.drawRect(Rect.fromLTWH(0, image.height.toDouble() - 60, image.width.toDouble(), 60), paintRect);
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

  String _formatarDataHora(dynamic t) {
    if (t == null) return '---';
    if (t is Timestamp) return DateFormat('dd/MM/yy HH:mm\'h\'').format(t.toDate());
    if (t is DateTime) return DateFormat('dd/MM/yy HH:mm\'h\'').format(t);
    return t.toString(); 
  }

  String _formatarDataHoraCompleta(dynamic t) {
    if (t == null) return '---';
    if (t is Timestamp) return DateFormat('dd/MM/yyyy HH:mm:ss').format(t.toDate());
    if (t is DateTime) return DateFormat('dd/MM/yyyy HH:mm:ss').format(t);
    return t.toString(); 
  }

  String _calcularPrazo(Timestamp? dataAbertura, dynamic minutosPrazoStr) {
    if (dataAbertura == null || minutosPrazoStr == null) return 'Indefinido';
    int minutos = int.tryParse(minutosPrazoStr.toString()) ?? 0;
    if (minutos == 0) return 'Indefinido';
    DateTime limite = dataAbertura.toDate().add(Duration(minutes: minutos));
    return DateFormat('dd/MM/yy HH:mm\'h\'').format(limite);
  }

  bool _estaForaDoPrazo(Timestamp? dataAbertura, dynamic minutosPrazoStr) {
    if (dataAbertura == null || minutosPrazoStr == null) return false;
    int minutos = int.tryParse(minutosPrazoStr.toString()) ?? 0;
    if (minutos == 0) return false;
    DateTime limite = dataAbertura.toDate().add(Duration(minutes: minutos));
    return DateTime.now().isAfter(limite);
  }

  bool _maisDe24h(Timestamp? dataAbertura) {
    if (dataAbertura == null) return false;
    return DateTime.now().difference(dataAbertura.toDate()).inHours >= 24;
  }

  int _getStatusWeight(String statusRaw) {
    String st = statusRaw.toLowerCase();
    if (st.contains('aberto') || st.contains('pendente') || st.contains('aguardando')) return 1;
    if (st.contains('deslocamento')) return 2;
    if (st.contains('atendimento')) return 3;
    if (st.contains('conclu') || st.contains('finaliz')) return 4;
    return 5; 
  }

  Color _corStatusReal(String statusRaw) {
    String st = statusRaw.toLowerCase();
    if (st.contains('aberto') || st.contains('pendente') || st.contains('aguardando')) return Colors.redAccent;
    if (st.contains('deslocamento')) return Colors.orange;
    if (st.contains('atendimento')) return Colors.green;
    if (st.contains('conclu') || st.contains('finaliz')) return Colors.blueGrey;
    return Colors.grey;
  }

  bool _passouNoFiltro(Map<String, dynamic> data) {
    String st = (data['status'] ?? 'aberto').toString().toLowerCase();
    if (st.contains('conclu') || st.contains('finaliz')) return false; 

    bool statusOK = false;
    if (st.contains('deslocamento') && _fStatusDesloc) statusOK = true;
    else if (st.contains('atendimento') && _fStatusAtend) statusOK = true;
    else if ((st.contains('aberto') || st.contains('pendente')) && _fStatusAberto) statusOK = true;
    if (!statusOK) return false;

    String prio = (_mapaPrioridades[data['tipo_da_falha']] ?? 'BAIXA').toLowerCase();
    bool prioOK = false;
    if (prio.contains('alta') && _fPrioAlta) prioOK = true;
    else if ((prio.contains('med') || prio.contains('méd')) && _fPrioMedia) prioOK = true;
    else if (prio.contains('baixa') && _fPrioBaixa) prioOK = true;
    if (!prioOK) return false;

    if (_filtroEmpresa != 'TODAS' && data['empresa_responsavel'] != _filtroEmpresa) return false;
    if (_fMais24h && !_maisDe24h(data['data_de_abertura'])) return false;
    if (_fForaPrazo && !_estaForaDoPrazo(data['data_de_abertura'], data['prazo'])) return false;

    return true;
  }

  // =================================================================================
  // MODAIS (CADASTRO E FINALIZAÇÃO) - OTIMIZADOS
  // =================================================================================

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
                
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: semaforoDropdownValue),
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return _opcoesSemaforos;
                    }
                    return _opcoesSemaforos.where((String option) {
                      return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  onSelected: (String selection) {
                    semaforoSel = selection;
                    semaforoMenuCtrl.text = selection;
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    textEditingController.addListener(() {
                      semaforoMenuCtrl.text = textEditingController.text;
                      semaforoSel = textEditingController.text;
                    });
                    
                    return TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      inputFormatters: [UpperCaseTextFormatter()],
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Semáforo *',
                        hintText: 'Pesquisar Semáforo...',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Icon(Icons.search),
                      ),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4.0,
                        borderRadius: BorderRadius.circular(4),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: 200, maxWidth: MediaQuery.of(context).size.width - 48),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final String option = options.elementAt(index);
                              return InkWell(
                                onTap: () => onSelected(option),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Text(option),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
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

  void _abrirModalFinalizar(String docId, Map<String, dynamic> dados) {
    bool defeitoConstatado = true;
    bool estaSalvando = false;
    bool estaArrastandoArea = false;

    String falha = dados['tipo_da_falha'] ?? '';
    final acaoCtrl = TextEditingController();
    
    List<Map<String, dynamic>> materiaisUsados = [];
    final materialCtrl = TextEditingController();
    final qtdCtrl = TextEditingController();

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
                        materiaisUsados.clear(); 
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

                // --- INÍCIO: MATERIAIS UTILIZADOS ---
                if (defeitoConstatado) ...[
                  const Text('MATERIAIS UTILIZADOS (Opcional)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownMenu<String>(
                          expandedInsets: EdgeInsets.zero,
                          controller: materialCtrl,
                          enableFilter: true, enableSearch: true,
                          label: const Text('Buscar Material'),
                          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
                          dropdownMenuEntries: _opcoesMateriais.map((m) => DropdownMenuEntry(value: m, label: m)).toList(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: qtdCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Qtd', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: () {
                          if (materialCtrl.text.isNotEmpty && qtdCtrl.text.isNotEmpty) {
                            setStateModal(() {
                              materiaisUsados.add({
                                'material': materialCtrl.text.toUpperCase(),
                                'quantidade': qtdCtrl.text
                              });
                              materialCtrl.clear();
                              qtdCtrl.clear();
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um material e informe a quantidade.')));
                          }
                        },
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ],
                  ),
                  if (materiaisUsados.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        children: materiaisUsados.asMap().entries.map((e) {
                          int idx = e.key;
                          Map mat = e.value;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text('${mat['quantidade']}x - ${mat['material']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              InkWell(
                                onTap: () => setStateModal(() => materiaisUsados.removeAt(idx)),
                                child: const Icon(Icons.delete, color: Colors.red, size: 20),
                              )
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                // --- FIM: MATERIAIS UTILIZADOS ---

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
                          if (defeitoConstatado && falhaMenuCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha a falha encontrada!')));
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
                              'acao_equipe': acaoCtrl.text.toUpperCase(),
                              'materiais_utilizados': materiaisUsados,
                              'fotos_finalizacao': fotosBase64,
                              'usuario_finalizacao': nomeUsuario, 
                            });

                            if (mounted) Navigator.pop(context);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atendimento concluído!'), backgroundColor: Colors.green));
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

  // =================================================================================
  // LÓGICA DE AÇÕES (SECUNDÁRIAS)
  // =================================================================================

  void _atribuirEquipe(String docIdOcorrencia) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final equipesAtivas = _todasEquipes.where((e) => (e.data() as Map)['status'] == 'ativo').toList();
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Atribuir Equipe', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(height: 10),
              if (equipesAtivas.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Text('Nenhuma equipe ATIVA encontrada no momento.'))
              else
                ...equipesAtivas.map((eq) {
                  var data = eq.data() as Map<String, dynamic>;
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
                        await FirebaseFirestore.instance.collection('Gerenciamento_ocorrencias').doc(docIdOcorrencia).update({
                          'equipe_atrelada': nomeLider,
                          'equipe_responsavel': nomeLider,
                          'integrantes_equipe': ints, 
                          'placa_veiculo': placa,
                          'equipe_responsavel_id': eq.id,
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

  // --- NOVA VISUALIZAÇÃO DE DETALHES TIPO CARD ---
  void _abrirDetalhes(String docId, Map<String, dynamic> data) {
    String st = (data['status'] ?? 'aberto').toString().toLowerCase();
    Color corBase = Colors.redAccent;
    if (st.contains('deslocamento')) corBase = Colors.orange;
    if (st.contains('atendimento')) corBase = Colors.green;
    
    String empresa = (data['empresa_semaforo'] ?? '').toString();
    if (empresa.isEmpty) {
      String numSemAux = _formatarId(data['semaforo']?.toString() ?? '');
      var semInfo = _semaforosAux.firstWhere((s) => s['id'] == numSemAux, orElse: () => <String, dynamic>{});
      empresa = (semInfo['empresa'] ?? '---').toString();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${data['semaforo'] ?? '---'} - ${data['endereco'] ?? '---'} ($empresa)',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: corBase, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    data['status']?.toString().toUpperCase() ?? 'ABERTO',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            
            _buildInfoRow('Nº da ocorrência', data['numero_da_ocorrencia']),
            _buildInfoRow('Falha', data['tipo_da_falha']),
            _buildInfoRow('Detalhes', data['detalhes']),
            _buildInfoRow('Prazo Limite', _calcularPrazo(data['data_de_abertura'], data['prazo'])),
            _buildInfoRow('Equipe atrelada', data['equipe_atrelada'] ?? data['equipe_responsavel'] ?? 'Nenhuma'),
            const SizedBox(height: 15),

            if (st.contains('atendimento')) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () {
                  Navigator.pop(context);
                  _abrirModalFinalizar(docId, data); 
                },
                child: const Text('Finalizar Atendimento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _atribuirEquipe(docId);
                },
                child: const Text('Trocar Equipe', style: TextStyle(color: Colors.black87)),
              ),
            ] else if (st.contains('deslocamento')) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () {
                  Navigator.pop(context);
                  _registrarChegada(docId);
                },
                child: const Text('Informar Chegada (Iniciar Atendimento)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _atribuirEquipe(docId);
                },
                child: const Text('Trocar Equipe', style: TextStyle(color: Colors.black87)),
              ),
            ] else ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () {
                  Navigator.pop(context);
                  _atribuirEquipe(docId);
                },
                child: const Text('Atribuir Equipe Responsável', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],

            const SizedBox(height: 15),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.history, color: Colors.blueGrey),
                  label: const Text('Histórico (Últimas 5)', style: TextStyle(color: Colors.blueGrey)),
                  onPressed: () {
                    String numSem = _formatarId(data['semaforo']?.toString() ?? '');
                    var hist = _todasOcorrencias.where((oc) {
                      var d = oc.data() as Map<String, dynamic>;
                      return _formatarId(d['semaforo']?.toString() ?? '') == numSem;
                    }).toList();
                    hist.sort((a, b) {
                      var dA = a.data() as Map<String, dynamic>;
                      var dB = b.data() as Map<String, dynamic>;
                      DateTime dtA = dA['data_de_abertura'] != null ? (dA['data_de_abertura'] as Timestamp).toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      DateTime dtB = dB['data_de_abertura'] != null ? (dB['data_de_abertura'] as Timestamp).toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      return dtB.compareTo(dtA);
                    });
                    
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFFE8EAF6),
                        title: Text('Histórico de Recorrência do $numSem', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 18)),
                        content: SizedBox(
                          width: 500,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: hist.length > 5 ? 5 : hist.length,
                            itemBuilder: (c, i) {
                              var d = hist[i].data() as Map<String, dynamic>;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 1,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          _abrirDetalhesCompletos(d);
                                        },
                                        child: Text(
                                          'Nº Ocorrência: ${d['numero_da_ocorrencia'] ?? hist[i].id}',
                                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, fontSize: 15),
                                        ),
                                      ),
                                      const Divider(),
                                      const SizedBox(height: 4),
                                      Text('Abertura: ${_formatarDataHoraCompleta(d['data_de_abertura'])}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                      Text('Fechamento: ${_formatarDataHoraCompleta(d['data_de_finalizacao'])}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                      Text('Equipe Responsável: ${d['equipe_atrelada'] ?? d['equipe_responsavel'] ?? '-'}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                      Text('Falha relatada: ${d['tipo_da_falha'] ?? '-'}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                      RichText(
                                        text: TextSpan(
                                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                                          children: [
                                            const TextSpan(text: 'Falha encontrada: ', style: TextStyle(fontWeight: FontWeight.bold)),
                                            TextSpan(text: (d['falha_aparente_final'] ?? '-').toString()),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                          )
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar', style: TextStyle(fontWeight: FontWeight.bold)))]
                      )
                    );
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.map, color: Colors.blueGrey),
                  label: const Text('Google Maps', style: TextStyle(color: Colors.blueGrey)),
                  onPressed: () async {
                    String numSem = _formatarId(data['semaforo']?.toString() ?? '');
                    LatLng? c = _mapaCoordenadasSemaforos[numSem]; 
                    if (c != null) {
                      final url = Uri.parse('http://maps.google.com/maps?q=${c.latitude},${c.longitude}');
                      launchUrl(url, mode: LaunchMode.externalApplication);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coordenadas não encontradas para este semáforo no banco.')));
                    }
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.directions_car, color: Colors.blueGrey),
                  label: const Text('Waze', style: TextStyle(color: Colors.blueGrey)),
                  onPressed: () async {
                    String numSem = _formatarId(data['semaforo']?.toString() ?? '');
                    LatLng? c = _mapaCoordenadasSemaforos[numSem]; 
                    if (c != null) {
                      final url = Uri.parse('https://waze.com/ul?ll=${c.latitude},${c.longitude}&navigate=yes');
                      launchUrl(url, mode: LaunchMode.externalApplication);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coordenadas não encontradas para este semáforo no banco.')));
                    }
                  },
                ),
              ],
            ),
            
            const SizedBox(height: 10),
ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade600,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.settings_input_component, color: Colors.white),
              label: const Text('Acessar Programação', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                // Extrai apenas os números (ex: se for "002 - AV..." vai pegar "002")
                String numSem = (data['semaforo']?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                if (numSem.isNotEmpty) numSem = numSem.padLeft(3, '0');

                Navigator.pop(context); // Fecha o modal de detalhes
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TelaProgramacao(semaforoInicial: numSem),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            TextSpan(text: (value ?? '---').toString()),
          ],
        ),
      ),
    );
  }

  // --- MODAL DE DETALHES COMPLETOS (BOTTOM SHEET) ---
  void _abrirDetalhesCompletos(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Detalhes: ${data['numero_da_ocorrencia'] ?? data['id'] ?? 'S/N'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 18),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('Semáforo / End.', '${data['semaforo']} - ${data['endereco']}'),
                    _buildInfoRow('Empresa', data['empresa_semaforo'] ?? data['empresa_responsavel']),
                    _buildInfoRow('Origem', data['origem_da_ocorrencia']),
                    const Divider(),
                    _buildInfoRow('Data Abertura', _formatarDataHoraCompleta(data['data_de_abertura'])),
                    _buildInfoRow('Data Atendimento', _formatarDataHoraCompleta(data['data_atendimento'])),
                    _buildInfoRow('Data Finalização', _formatarDataHoraCompleta(data['data_de_finalizacao'])),
                    const Divider(),
                    _buildInfoRow('Usuário Abertura', data['usuario_abertura'] ?? data['usuario']),
                    _buildInfoRow('Equipe Resp.', data['equipe_atrelada'] ?? data['equipe_responsavel']),
                    _buildInfoRow('Placa', data['placa_veiculo']),
                    const Divider(),
                    _buildInfoRow('Status', data['status']?.toString().toUpperCase()),
                    _buildInfoRow('Falha Relatada', data['tipo_da_falha']),
                    _buildInfoRow('Detalhes/Abertura', data['detalhes']),
                    _buildInfoRow('Falha Encontrada', data['falha_aparente_final']),
                    _buildInfoRow('Ação Técnica', data['acao_equipe']),
                    
                    if (data['materiais_utilizados'] != null && (data['materiais_utilizados'] as List).isNotEmpty) ...[
                      const Divider(),
                      const Text('Materiais Utilizados:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2c3e50), fontSize: 13)),
                      const SizedBox(height: 6),
                      ...(data['materiais_utilizados'] as List).map((mat) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('${mat['quantidade']}x - ${mat['material']}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        );
                      }),
                    ],
                    
                    if (data['fotos_finalizacao'] != null && (data['fotos_finalizacao'] as List).isNotEmpty) ...[
                      const Divider(),
                      const Text('Fotos da Finalização:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2c3e50), fontSize: 13)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: (data['fotos_finalizacao'] as List).map((base64Str) {
                          try {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(base64Decode(base64Str), width: 100, height: 100, fit: BoxFit.cover),
                            );
                          } catch (e) {
                            return const SizedBox.shrink();
                          }
                        }).toList(),
                      ),
                    ]
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
                backgroundColor: Colors.blueGrey,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Voltar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarPendentes() {
    final pendentes = _todasOcorrencias.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      String st = (d['status'] ?? '').toLowerCase();
      bool isAberto = st.contains('aberto') || st.contains('pendente') || st.contains('aguardando');
      String eq = (d['equipe_responsavel'] ?? d['equipe_atrelada'] ?? '').toString().trim();
      return isAberto && (eq.isEmpty || eq == '-' || eq == 'null');
    }).toList();

    if (pendentes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text('Nenhuma ocorrência aguardando.', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pendentes.length,
      itemBuilder: (context, index) {
        var d = pendentes[index].data() as Map<String, dynamic>;
        
        String empresa = (d['empresa_semaforo'] ?? '').toString();
        if (empresa.isEmpty) {
          String numSemAux = _formatarId(d['semaforo']?.toString() ?? '');
          var semInfo = _semaforosAux.firstWhere((s) => s['id'] == numSemAux, orElse: () => <String, dynamic>{});
          empresa = (semInfo['empresa'] ?? '---').toString();
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: const Border(left: BorderSide(color: Colors.redAccent, width: 4)),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            title: Text('🚦 ${d['semaforo']} - ${d['tipo_da_falha']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            subtitle: Text('${d['endereco'] ?? ''}\nEmpresa: $empresa', style: const TextStyle(fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(60, 30)),
              onPressed: () => _atribuirEquipe(pendentes[index].id),
              child: const Text('Atribuir', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            onTap: () {
              String numSem = _formatarId(d['semaforo']?.toString() ?? '');
              LatLng? c = _mapaCoordenadasSemaforos[numSem];
              if (c != null) _mapController.move(c, 17);
              _abrirDetalhes(pendentes[index].id, d);
            },
          ),
        );
      },
    );
  }

  Widget _buildSidebarEquipes() {
    final ativas = _todasEquipes.where((e) => (e.data() as Map)['status'] == 'ativo').toList();
    if (ativas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text('Nenhuma equipe em campo no momento.', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: ativas.length,
      itemBuilder: (context, index) {
        var eq = ativas[index].data() as Map<String, dynamic>;
        
        String tipoVeiculo = (eq['tipo_veiculo'] ?? eq['tipo'] ?? '').toString().toUpperCase();
        String placa = eq['placa'] ?? 'S/ PLACA';
        String placaExibicao = tipoVeiculo.isNotEmpty ? '$placa ($tipoVeiculo)' : placa;
        
        String nomeLider = (eq['integrantes_str'] ?? '').toString().split(',').first.trim().toUpperCase();
        if (nomeLider.isEmpty) nomeLider = "Equipe $placa";

        final tarefas = _todasOcorrencias.where((oc) {
          var d = oc.data() as Map<String, dynamic>;
          String eqResp = (d['equipe_responsavel'] ?? d['equipe_atrelada'] ?? '').toString().toUpperCase();
          if (!eqResp.contains(nomeLider) && !eqResp.contains(placa)) return false;

          String st = (d['status'] ?? '').toLowerCase();
          bool isConcluido = st.contains('conclu') || st.contains('finaliz');
          
          if (isConcluido) {
            if (d['data_de_finalizacao'] != null) {
              DateTime dtFim = (d['data_de_finalizacao'] as Timestamp).toDate();
              if (DateTime.now().difference(dtFim).inHours > 24) return false; 
            }
          }
          return true;
        }).toList();

        tarefas.sort((a, b) {
          int getOrder(Map<String, dynamic> data) {
            String s = (data['status'] ?? '').toString().toLowerCase();
            if (s.contains('atendimento')) return 0;
            if (s.contains('deslocamento')) return 1;
            return 2;
          }
          return getOrder(a.data() as Map<String, dynamic>).compareTo(getOrder(b.data() as Map<String, dynamic>));
        });

        return Card(
          color: const Color(0xFF3e4a5d),
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: const Color(0xFF232d3b),
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('🚗 $placaExibicao\n$nomeLider', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(4)),
                      child: Text(eq['empresa'] ?? 'EXTERNA', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: tarefas.isEmpty
                    ? const Text('Equipe Disponível', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 11))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: tarefas.map((tDoc) {
                          var t = tDoc.data() as Map<String, dynamic>;
                          String st = (t['status'] ?? 'aberto').toLowerCase();
                          bool isConcluido = st.contains('conclu') || st.contains('finaliz');
                          
                          Color corStatus = Colors.redAccent;
                          if (st.contains('deslocamento')) corStatus = Colors.orange;
                          if (st.contains('atendimento')) corStatus = Colors.green;
                          if (isConcluido) corStatus = Colors.blueGrey;
                          
                          String empresaSemaforo = (t['empresa_semaforo'] ?? '').toString();
                          if (empresaSemaforo.isEmpty) {
                            String numSemAux = _formatarId(t['semaforo']?.toString() ?? '');
                            var semInfo = _semaforosAux.firstWhere((s) => s['id'] == numSemAux, orElse: () => <String, dynamic>{});
                            empresaSemaforo = (semInfo['empresa'] ?? '---').toString();
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: corStatus, width: 4)),
                              color: Colors.grey.shade100,
                            ),
                            child: InkWell(
                              onTap: () {
                                _abrirDetalhes(tDoc.id, t);
                                String numSem = _formatarId(t['semaforo']?.toString() ?? '');
                                LatLng? c = _mapaCoordenadasSemaforos[numSem];
                                if (c != null) _mapController.move(c, 17);
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isConcluido ? 'FINALIZADO: ${t['semaforo']}' : '${t['semaforo']} - ${t['tipo_da_falha']}', 
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 11, 
                                      color: corStatus,
                                      decoration: isConcluido ? TextDecoration.lineThrough : null, 
                                    )
                                  ),
                                  Text('${t['endereco'] ?? ''}\nEmpresa: $empresaSemaforo', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Colors.black87)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Mapa de Ocorrências', style: TextStyle(color: Colors.white)),
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

          StreamBuilder<QuerySnapshot>(
            stream: _streamOcorrencias,
            builder: (context, snapshotOcc) {
              return StreamBuilder<QuerySnapshot>(
                stream: _streamEquipes,
                builder: (context, snapshotEq) {
                  if (!snapshotOcc.hasData || !snapshotEq.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }

                  _todasOcorrencias = snapshotOcc.data!.docs;
                  _todasEquipes = snapshotEq.data!.docs;
                  
                  Set<String> emps = {'TODAS'};
                  for (var oc in _todasOcorrencias) {
                    String e = (oc.data() as Map<String, dynamic>)['empresa_responsavel'] ?? '';
                    if (e.isNotEmpty) emps.add(e);
                  }
                  _empresasOptions = emps.toList()..sort();
                  if (!_empresasOptions.contains(_filtroEmpresa)) {
                    _filtroEmpresa = 'TODAS';
                  }

                  List<QueryDocumentSnapshot> ocorrenciasParaMapa = _todasOcorrencias.where(
                    (doc) => _passouNoFiltro(doc.data() as Map<String, dynamic>)
                  ).toList();

                  // Agrupando ocorrências por Semáforo (para o caso de múltiplos pinos no mesmo lugar)
                  Map<String, List<QueryDocumentSnapshot>> mapaAgrupado = {};
                  for (var doc in ocorrenciasParaMapa) {
                    var data = doc.data() as Map<String, dynamic>;
                    String numSem = _formatarId(data['semaforo']?.toString() ?? '');
                    if (!mapaAgrupado.containsKey(numSem)) {
                      mapaAgrupado[numSem] = [];
                    }
                    mapaAgrupado[numSem]!.add(doc);
                  }

                  List<Marker> marcadores = [];
                  mapaAgrupado.forEach((numSem, listaDocs) {
                    LatLng? coords = _mapaCoordenadasSemaforos[numSem];
                    if (coords != null) {
                      // Determina o status "pior" para exibir o ícone correto
                      int piorPeso = 99;
                      String assetPath = 'assets/images/aberto.png'; 
                      
                      for (var d in listaDocs) {
                        var data = d.data() as Map<String, dynamic>;
                        String st = (data['status'] ?? 'aberto').toString().toLowerCase();
                        int w = _getStatusWeight(st);
                        if (w < piorPeso) {
                          piorPeso = w;
                          if (st.contains('deslocamento')) {
                            assetPath = 'assets/images/deslocamento.png';
                          } else if (st.contains('atendimento')) {
                            assetPath = 'assets/images/atendimento.png';
                          } else {
                            assetPath = 'assets/images/aberto.png';
                          }
                        }
                      }

                      marcadores.add(
                        Marker(
                          point: coords,
                          width: 60, 
                          height: 70, 
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: () {
                              if (listaDocs.length == 1) {
                                // Se for só 1, abre direto
                                _abrirDetalhes(listaDocs.first.id, listaDocs.first.data() as Map<String, dynamic>);
                              } else {
                                // Se tiver mais de 1, abre modal para escolher
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('Ocorrências no Semáforo $numSem', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                    content: SizedBox(
                                      width: double.maxFinite,
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: listaDocs.length,
                                        itemBuilder: (c, i) {
                                          var data = listaDocs[i].data() as Map<String, dynamic>;
                                          return Card(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            child: ListTile(
                                              title: Text(data['tipo_da_falha'] ?? ''),
                                              subtitle: Text('Status: ${data['status']}'),
                                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                              onTap: () {
                                                Navigator.pop(ctx); // Fecha a lista
                                                _abrirDetalhes(listaDocs[i].id, data); // Abre os detalhes da selecionada
                                              },
                                            ),
                                          );
                                        }
                                      )
                                    ),
                                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))]
                                  )
                                );
                              }
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Stack(
                                  children: [
                                    Image.asset(
                                      assetPath,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.warning, color: Colors.red),
                                    ),
                                    if (listaDocs.length > 1) // Mostra selo se tiver mais de uma
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                          child: Text('${listaDocs.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      )
                                  ]
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.black54, width: 1),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
                                  ),
                                  child: Text(
                                    numSem,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  });

                  return Column(
                    children: [
                      const SizedBox(height: 90),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            bool isDesktop = constraints.maxWidth > 900;

                            Widget mapaWidget = Container(
                              margin: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white38, width: 3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Stack(
                                  children: [
                                    FlutterMap(
                                      mapController: _mapController,
                                      options: MapOptions(initialCenter: _centroPadrao, initialZoom: 12.0),
                                      children: [
                                        TileLayer(
                                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                          userAgentPackageName: 'com.seusistema.sos',
                                        ),
                                        MarkerLayer(markers: marcadores),
                                      ],
                                    ),
                                    
                                    Positioned(
                                      top: 10, left: 10,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF5cb85c),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        ),
                                        icon: const Icon(Icons.add, color: Colors.white, size: 18),
                                        label: const Text('NOVA OCORRÊNCIA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                        onPressed: () => _abrirModalCadastro(),
                                      ),
                                    ),
                                    
                                    Positioned(
                                      top: 10, right: 10,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 400),
                                        curve: Curves.fastOutSlowIn,
                                        width: _filtrosVisiveis ? 180 : 0,
                                        height: _filtrosVisiveis ? 460 : 0, 
                                        padding: _filtrosVisiveis ? const EdgeInsets.all(12) : EdgeInsets.zero,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.95),
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black26)],
                                        ),
                                        child: _filtrosVisiveis ? SingleChildScrollView(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  const Text('FILTROS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                                  IconButton(
                                                    icon: const Icon(Icons.visibility_off, size: 16, color: Colors.blueGrey),
                                                    onPressed: () => setState(() => _filtrosVisiveis = false),
                                                    padding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
                                                  ),
                                                ],
                                              ),
                                              const Divider(),
                                              const Text('STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                              _buildCheckboxFiltro('Aberto', _fStatusAberto, (v) => setState(() => _fStatusAberto = v ?? false)),
                                              _buildCheckboxFiltro('Desloc.', _fStatusDesloc, (v) => setState(() => _fStatusDesloc = v ?? false)),
                                              _buildCheckboxFiltro('Atend.', _fStatusAtend, (v) => setState(() => _fStatusAtend = v ?? false)),
                                              const Divider(),
                                              const Text('PRIORIDADE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                              _buildCheckboxFiltro('Alta', _fPrioAlta, (v) => setState(() => _fPrioAlta = v ?? false)),
                                              _buildCheckboxFiltro('Média', _fPrioMedia, (v) => setState(() => _fPrioMedia = v ?? false)),
                                              _buildCheckboxFiltro('Baixa', _fPrioBaixa, (v) => setState(() => _fPrioBaixa = v ?? false)),
                                              const Divider(),
                                              const Text('ALERTAS DE TEMPO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                                              _buildCheckboxFiltro('> 24h', _fMais24h, (v) => setState(() => _fMais24h = v ?? false)),
                                              _buildCheckboxFiltro('Fora Prazo', _fForaPrazo, (v) => setState(() => _fForaPrazo = v ?? false)),
                                              const Divider(),
                                              DropdownButtonFormField<String>(
                                                isDense: true,
                                                style: const TextStyle(fontSize: 11, color: Colors.black87),
                                                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                                                value: _filtroEmpresa,
                                                items: _empresasOptions.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
                                                onChanged: (v) => setState(() => _filtroEmpresa = v!),
                                              ),
                                            ],
                                          ),
                                        ) : Container(),
                                      ),
                                    ),
                                    
                                    if (!_filtrosVisiveis)
                                      Positioned(
                                        top: 10, right: 10,
                                        child: FloatingActionButton.small(
                                          backgroundColor: Colors.white,
                                          onPressed: () => setState(() => _filtrosVisiveis = true),
                                          child: const Icon(Icons.filter_alt, color: Colors.blueGrey),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );

                            Widget sidebarWidget = Container(
                              margin: EdgeInsets.only(top: isDesktop ? 16 : 0, bottom: 16, right: 16, left: isDesktop ? 0 : 16),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 16, bottom: 8, left: 10, right: 10),
                                      child: Text('OCORRÊNCIAS EM ABERTO', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
                                    ),
                                    _buildSidebarPendentes(),
                                    
                                    const Padding(
                                      padding: EdgeInsets.only(top: 16, bottom: 8, left: 10, right: 10),
                                      child: Text('EQUIPES EM CAMPO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
                                    ),
                                    _buildSidebarEquipes(),
                                  ],
                                ),
                              ),
                            );

                            if (isDesktop) {
                              return Row(children: [Expanded(flex: 3, child: mapaWidget), Expanded(flex: 1, child: sidebarWidget)]);
                            } else {
                              return Column(children: [Expanded(flex: 3, child: mapaWidget), Expanded(flex: 2, child: sidebarWidget)]);
                            }
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxFiltro(String title, bool value, ValueChanged<bool?> onChanged) {
    return SizedBox(
      height: 30, 
      child: CheckboxListTile(
        title: Text(title, style: const TextStyle(fontSize: 11)),
        value: value,
        onChanged: onChanged,
        dense: true, contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
        controlAffinity: ListTileControlAffinity.leading, 
      ),
    );
  }
}