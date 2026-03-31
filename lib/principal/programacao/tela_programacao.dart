import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/menu_usuario.dart';

// ==========================================
// PAINTER: EFEITO DE LISTRAS DIAGONAIS PARA O PISCANTE
// ==========================================
class PiscantePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFFFF59D);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final stripePaint = Paint()
      ..color = const Color(0xFFFFCA28)
      ..style = PaintingStyle.fill;

    const double stripeWidth = 30.0;
    
    for (double i = -size.height; i < size.width; i += stripeWidth * 2) {
      final path = Path()
        ..moveTo(i, 0)
        ..lineTo(i + stripeWidth, 0)
        ..lineTo(i + stripeWidth + size.height, size.height)
        ..lineTo(i + size.height, size.height)
        ..close();
      canvas.drawPath(path, stripePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==========================================
// PAINTER: RÉGUA DO GRÁFICO DE GANTT
// ==========================================
class RulerPainter extends CustomPainter {
  final int tc;
  RulerPainter(this.tc);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black45
      ..strokeWidth = 1;
    final textStyle = const TextStyle(color: Colors.black54, fontSize: 9, fontWeight: FontWeight.bold);
    
    // Linha base
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint);
    
    int step = tc > 120 ? 20 : 10;
    if (tc == 0) return;

    for (int i = 0; i <= tc; i += step) {
      double x = (i / tc) * size.width;
      canvas.drawLine(Offset(x, size.height - 5), Offset(x, size.height), paint);
      
      final textSpan = TextSpan(text: '$i', style: textStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - (textPainter.width / 2), 0));
    }
  }

  @override
  bool shouldRepaint(covariant RulerPainter old) => old.tc != tc;
}

// ==========================================
// WIDGET: EDITOR DE PLANO INDIVIDUAL
// ==========================================
class PlanoEditorWidget extends StatefulWidget {
  final Map<String, dynamic> plano;
  final List<dynamic> gruposGlobais;
  final bool modoEdicao;
  final VoidCallback onUpdate;

  const PlanoEditorWidget({
    Key? key,
    required this.plano,
    required this.gruposGlobais,
    required this.modoEdicao,
    required this.onUpdate,
  }) : super(key: key);

  @override
  State<PlanoEditorWidget> createState() => _PlanoEditorWidgetState();
}

class _PlanoEditorWidgetState extends State<PlanoEditorWidget> {
  late TextEditingController _tcCtrl;
  late TextEditingController _offsetCtrl;
  List<Map<String, dynamic>> _localGroups = [];

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(covariant PlanoEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plano != widget.plano || oldWidget.gruposGlobais != widget.gruposGlobais) {
      _initControllers();
    }
  }

  void _initControllers() {
    _tcCtrl = TextEditingController(text: widget.plano['tc']?.toString() ?? '100');
    _offsetCtrl = TextEditingController(text: widget.plano['offset']?.toString() ?? '0');

    _localGroups.clear();
    List<dynamic> pg = widget.plano['groups'] ?? [];
    
    for (var gg in widget.gruposGlobais) {
      var existing = pg.firstWhere((p) => p['id'] == gg['id'] || p['name'] == gg['id'], orElse: () => null);
      if (existing != null) {
        _localGroups.add({
          'id': gg['id'],
          'name': gg['nome'],
          'startCtrl': TextEditingController(text: existing['start']?.toString() ?? '0'),
          'endCtrl': TextEditingController(text: existing['end']?.toString() ?? '0'),
          'yellowCtrl': TextEditingController(text: existing['yellow']?.toString() ?? '3'),
          'allRedCtrl': TextEditingController(text: existing['allRed']?.toString() ?? '2'),
        });
      } else {
        _localGroups.add({
          'id': gg['id'],
          'name': gg['nome'],
          'startCtrl': TextEditingController(text: '0'),
          'endCtrl': TextEditingController(text: '0'),
          'yellowCtrl': TextEditingController(text: '3'),
          'allRedCtrl': TextEditingController(text: '2'),
        });
      }
    }
  }

  void _notificarMudanca() {
    widget.plano['tc'] = int.tryParse(_tcCtrl.text) ?? 100;
    widget.plano['offset'] = int.tryParse(_offsetCtrl.text) ?? 0;
    widget.plano['groups'] = _localGroups.map((g) => {
      'id': g['id'],
      'name': g['id'],
      'phase': g['name'],
      'start': int.tryParse(g['startCtrl'].text) ?? 0,
      'end': int.tryParse(g['endCtrl'].text) ?? 0,
      'yellow': int.tryParse(g['yellowCtrl'].text) ?? 3,
      'allRed': int.tryParse(g['allRedCtrl'].text) ?? 2,
    }).toList();
    
    widget.onUpdate();
    setState(() {});
  }

  Widget _buildInput(TextEditingController ctrl, {Color? bg, Color? textC, double width = 45}) {
    return Container(
      width: width,
      height: 26,
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: ctrl,
        enabled: widget.modoEdicao,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textC ?? Colors.black87),
        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.only(bottom: 12)),
        onChanged: (_) => _notificarMudanca(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String tipoStr = widget.plano['type']?.toString() ?? 'normal';
    String planIdStr = widget.plano['planId']?.toString().toUpperCase() ?? '??';

    if (tipoStr == 'special') {
      Color corFundo = (planIdStr == 'PISCANTE') ? Colors.yellow.shade700 : Colors.grey.shade800;
      return Container(
        margin: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFF2f3b4c)), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(8), color: const Color(0xFF2f3b4c),
              child: Text('MODO $planIdStr', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 60,
              child: planIdStr == 'PISCANTE' 
                ? CustomPaint(painter: PiscantePainter()) 
                : Container(color: corFundo),
            ),
          ]
        )
      );
    }

    int tc = int.tryParse(_tcCtrl.text) ?? 100;
    if (tc <= 0) tc = 1;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF2f3b4c), width: 1),
        borderRadius: BorderRadius.circular(4),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF2f3b4c),
            child: Text('PLANO $planIdStr', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Text('Ciclo: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                _buildInput(_tcCtrl, width: 50),
                const Text(' Seg.   Parâmetro (OFFSET): ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                _buildInput(_offsetCtrl, width: 50),
              ],
            ),
          ),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(flex: 2, child: Text('Grupo', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Início', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Fim', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Verde', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Amarelo', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Vm.Geral', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Entreverde', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                    ..._localGroups.map((g) {
                      int start = int.tryParse(g['startCtrl'].text) ?? 0;
                      int end = int.tryParse(g['endCtrl'].text) ?? 0;
                      int yellow = int.tryParse(g['yellowCtrl'].text) ?? 3;
                      int allRed = int.tryParse(g['allRedCtrl'].text) ?? 2;
                      
                      int verde = end >= start ? end - start : (tc - start) + end;
                      int entreverde = yellow + allRed;

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Expanded(flex: 2, child: Text(g['id'], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12))),
                            Expanded(flex: 2, child: Center(child: _buildInput(g['startCtrl']))),
                            Expanded(flex: 2, child: Center(child: _buildInput(g['endCtrl']))),
                            Expanded(flex: 2, child: Center(child: Container(width: 45, height: 26, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.green.shade50, border: Border.all(color: Colors.green.shade200), borderRadius: BorderRadius.circular(4)), child: Text('$verde', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12))))),
                            Expanded(flex: 2, child: Center(child: _buildInput(g['yellowCtrl'], bg: Colors.amber.shade50, textC: Colors.orange.shade800))),
                            Expanded(flex: 2, child: Center(child: _buildInput(g['allRedCtrl'], bg: Colors.red.shade50, textC: Colors.red.shade800))),
                            Expanded(flex: 2, child: Center(child: Container(width: 45, height: 26, alignment: Alignment.center, child: Text('$entreverde', style: const TextStyle(color: Colors.black54, fontSize: 12))))),
                          ],
                        ),
                      );
                    }).toList()
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300))),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 27, width: double.infinity,
                        child: CustomPaint(painter: RulerPainter(tc)),
                      ),
                      ..._localGroups.map((g) {
                        return SizedBox(
                          height: 38,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              double width = constraints.maxWidth;
                              int start = int.tryParse(g['startCtrl'].text) ?? 0;
                              int end = int.tryParse(g['endCtrl'].text) ?? 0;
                              int yellow = int.tryParse(g['yellowCtrl'].text) ?? 3;
                              
                              double startPx = (start / tc) * width;
                              double endPx = (end / tc) * width;
                              
                              bool cruzaVerde = end < start;
                              
                              List<Widget> barras = [];
                              
                              barras.add(Center(child: Container(height: 6, color: Colors.red.shade600)));

                              if (!cruzaVerde) {
                                barras.add(Positioned(left: startPx, width: endPx - startPx, child: Center(child: Container(height: 16, color: const Color(0xFF00b050)))));
                              } else {
                                barras.add(Positioned(left: startPx, right: 0, child: Center(child: Container(height: 16, color: const Color(0xFF00b050)))));
                                barras.add(Positioned(left: 0, width: endPx, child: Center(child: Container(height: 16, color: const Color(0xFF00b050)))));
                              }

                              int endY = end + yellow;
                              if (endY <= tc) {
                                barras.add(Positioned(left: endPx, width: (yellow / tc) * width, child: Center(child: Container(height: 16, color: const Color(0xFFffc000)))));
                              } else {
                                double w1 = width - endPx;
                                double w2 = ((endY - tc) / tc) * width;
                                barras.add(Positioned(left: endPx, right: 0, child: Center(child: Container(height: 16, color: const Color(0xFFffc000)))));
                                barras.add(Positioned(left: 0, width: w2, child: Center(child: Container(height: 16, color: const Color(0xFFffc000)))));
                              }

                              return Stack(children: barras);
                            },
                          ),
                        );
                      }).toList()
                    ],
                  ),
                )
              )
            ],
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
            child: Text(
              widget.modoEdicao ? 'Modo Edição' : 'Modo Leitura',
              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: widget.modoEdicao ? Colors.redAccent : Colors.grey),
            ),
          )
        ],
      ),
    );
  }
}


// ==========================================
// TELA PRINCIPAL (APP)
// ==========================================
class TelaProgramacao extends StatefulWidget {
  const TelaProgramacao({super.key});

  @override
  State<TelaProgramacao> createState() => _TelaProgramacaoState();
}

class _TelaProgramacaoState extends State<TelaProgramacao> {
  String? _semaforoSelecionado;
  bool _modoEdicao = false;
  bool _existeProgramacao = false;

  String _subarea = "---";
  // ignore: unused_field
  String _ultimaAtualizacao = "";
  // ignore: unused_field
  String _motivoEdicao = "";
  // ignore: unused_field
  String _observacoes = "";

  List<dynamic> _grupos = [];
  List<dynamic> _planos = [];
  Map<String, dynamic> _agendamento = {};

  List<Map<String, String>> _listaSemaforosDropdown = [];
  bool _carregandoSemaforos = true;

  @override
  void initState() {
    super.initState();
    _carregarSemaforosBanco();
  }

  Color _obterCorDoPlano(String planId) {
    String idFormatado = planId.toUpperCase().trim();
    if (idFormatado == 'PISCANTE') return Colors.amber.shade700;
    if (idFormatado == 'APAGADO') return Colors.grey.shade800;

    int idNum = int.tryParse(idFormatado.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    List<Color> paleta = [Colors.blue, Colors.purple, Colors.teal, Colors.indigo, Colors.pink, Colors.cyan, Colors.deepOrange, Colors.lightGreen, Colors.deepPurple, Colors.brown];
    return paleta[idNum % paleta.length];
  }

  Future<void> _carregarSemaforosBanco() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('semaforos').get();
      List<Map<String, String>> listaTemporaria = [];

      listaTemporaria.add({'value': 'DEMO', 'label': '000 - SEMÁFORO DEMO (Teste Visual)'});

      for (var doc in snap.docs) {
        var d = doc.data();
        String idStr = (d['id'] ?? '').toString();
        String idFormatado = '000';
        if (idStr.isNotEmpty && !idStr.toUpperCase().contains('NUMERO')) {
          String numeros = idStr.replaceAll(RegExp(r'[^0-9]'), '');
          if (numeros.isNotEmpty) idFormatado = numeros.padLeft(3, '0');
        }
        String endereco = (d['endereco'] ?? '').toString();
        if (idFormatado != '000' && endereco.isNotEmpty) {
          listaTemporaria.add({'value': doc.id, 'label': '$idFormatado - $endereco'});
        }
      }

      if (listaTemporaria.length > 1) {
        var demoItem = listaTemporaria.removeAt(0);
        listaTemporaria.sort((a, b) => a['label']!.compareTo(b['label']!));
        listaTemporaria.insert(0, demoItem);
      }

      if (mounted) setState(() { _listaSemaforosDropdown = listaTemporaria; _carregandoSemaforos = false; });
    } catch (e) {
      if (mounted) setState(() { _listaSemaforosDropdown = [{'value': 'DEMO', 'label': '000 - SEMÁFORO DEMO (Teste Visual)'}]; _carregandoSemaforos = false; });
    }
  }

  Future<void> _carregarProgramacaoDoSemaforo(String semaforoDocId) async {
    _limparTela(); 
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('programacao').doc(semaforoDocId).get();
      if (doc.exists && doc.data() != null) {
        var data = doc.data() as Map<String, dynamic>;
        setState(() {
          _existeProgramacao = true;
          _grupos = data['grupos'] ?? [];
          _planos = data['planos'] ?? [];
          _agendamento = data['agendamento'] ?? {};
          _subarea = data['subarea'] ?? "---";
          _observacoes = data['observacoes'] ?? "";
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Programação carregada!'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
      } else {
        setState(() => _existeProgramacao = false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao carregar dados do banco.'), backgroundColor: Colors.red));
    }
  }

  void _carregarDemo() {
    setState(() {
      _existeProgramacao = true;
      _subarea = "ZONA SUL";
      _grupos = [{'id': 'G1', 'nome': 'AV. PRINCIPAL'}, {'id': 'G2', 'nome': 'RUA LATERAL'}];
      _planos = [
        {
          'planId': '01', 'type': 'normal', 'tc': 120, 'offset': 0,
          'groups': [
            {'id': 'G1', 'name': 'G1', 'start': 0, 'end': 95, 'yellow': 4, 'allRed': 1},
            {'id': 'G2', 'name': 'G2', 'start': 100, 'end': 113, 'yellow': 6, 'allRed': 1},
          ],
        },
        {'planId': 'piscante', 'type': 'special'},
      ];
      _agendamento = {'seg': [{'hora': '06:00', 'nomePlano': 'PLANO 01'}, {'hora': '22:00', 'nomePlano': 'MODO PISCANTE'}]};
    });
  }

  void _limparTela() {
    setState(() {
      _existeProgramacao = false; _modoEdicao = false; _subarea = "---";
      _ultimaAtualizacao = ""; _motivoEdicao = ""; _observacoes = "";
      _grupos = []; _planos = []; _agendamento = {};
    });
  }

  void _alternarModoEdicao() {
    setState(() => _modoEdicao = !_modoEdicao);
  }

  // MODAL DEFINIR GRUPOS
  void _abrirModalDefinirGrupos() {
    int passoAtual = 1; int quantidadeGrupos = 0; bool salvando = false;
    final TextEditingController qtdController = TextEditingController();
    List<TextEditingController> nomesControllers = [];

    showDialog(
      context: context, barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              titlePadding: const EdgeInsets.only(left: 24, right: 8, top: 16, bottom: 8),
              title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Configuração de Grupos', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 18)), IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context))]),
              content: Container(
                width: 400, padding: const EdgeInsets.only(top: 8), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black12, width: 1))),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (passoAtual == 1) ...[
                        const Text('Quantos grupos este semáforo tem?', style: TextStyle(color: Colors.black87, fontSize: 14)), const SizedBox(height: 12),
                        TextField(controller: qtdController, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: 'Ex: 2', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
                      ] else if (passoAtual == 2) ...[
                        const Text('Defina o endereço/nome de cada grupo:', style: TextStyle(color: Colors.black87, fontSize: 14)), const SizedBox(height: 16),
                        ...List.generate(quantidadeGrupos, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Nome do Grupo ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)), const SizedBox(height: 6),
                                TextField(controller: nomesControllers[index], textCapitalization: TextCapitalization.characters, decoration: InputDecoration(hintText: 'Ex: Av. Principal', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14))),
                              ],
                            ),
                          );
                        }),
                      ]
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              actions: [
                if (passoAtual == 1) ...[
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    onPressed: () {
                      int? qtd = int.tryParse(qtdController.text.trim());
                      if (qtd == null || qtd <= 0 || qtd > 10) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantidade inválida (1 a 10).'), backgroundColor: Colors.red)); return; }
                      nomesControllers = List.generate(qtd, (index) => TextEditingController());
                      setModalState(() { quantidadeGrupos = qtd; passoAtual = 2; });
                    },
                    child: const Text('Próximo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ] else if (passoAtual == 2) ...[
                  TextButton(onPressed: salvando ? null : () { setModalState(() { passoAtual = 1; }); }, child: const Text('Voltar', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    onPressed: salvando ? null : () async {
                      bool camposValidos = true; List<Map<String, dynamic>> novosGrupos = [];
                      for (int i = 0; i < quantidadeGrupos; i++) {
                        String nome = nomesControllers[i].text.trim().toUpperCase();
                        if (nome.isEmpty) { camposValidos = false; break; }
                        novosGrupos.add({'id': 'G${i + 1}', 'nome': nome});
                      }
                      if (!camposValidos) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha todos os grupos.'), backgroundColor: Colors.red)); return; }

                      if (_semaforoSelecionado == 'DEMO') {
                         setState(() { _grupos = novosGrupos; _existeProgramacao = true; });
                         Navigator.pop(context); return;
                      }

                      setModalState(() => salvando = true);
                      try {
                        await FirebaseFirestore.instance.collection('programacao').doc(_semaforoSelecionado).set({
                          'semaforo_id': _semaforoSelecionado, 'grupos': novosGrupos, 'ultima_atualizacao': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        setState(() { _grupos = novosGrupos; _existeProgramacao = true; });
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                        setModalState(() => salvando = false);
                      }
                    },
                    child: salvando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Salvar Grupos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ]
              ],
            );
          }
        );
      }
    );
  }

  // MODAL DEFINIR PLANO
  void _abrirModalDefinirPlano() {
    final formKey = GlobalKey<FormState>();
    String? planoSelecionado;
    final tcCtrl = TextEditingController(text: '100');
    final amareloCtrl = TextEditingController(text: '3');
    final vGeralCtrl = TextEditingController(text: '2');
    bool salvando = false;

    List<String> opcoesPlano = List.generate(15, (i) => (i + 1).toString().padLeft(2, '0'));
    opcoesPlano.addAll(['PISCANTE', 'APAGADO']);

    showDialog(
      context: context, barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              titlePadding: const EdgeInsets.only(left: 24, right: 8, top: 16, bottom: 8),
              title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Adicionar Novo Plano', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 18)), IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context))]),
              content: Container(
                width: 500, padding: const EdgeInsets.only(top: 8), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black12, width: 1))),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Número do Plano', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)), const SizedBox(height: 6),
                      DropdownButtonFormField<String>(decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)), hint: const Text('Selecione...'), value: planoSelecionado, items: opcoesPlano.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(), onChanged: (val) => setModalState(() => planoSelecionado = val), validator: (val) => val == null ? 'Obrigatório' : null),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Ciclo (seg)', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)), const SizedBox(height: 6), TextFormField(controller: tcCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)))] )), const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Amarelo Padrão', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)), const SizedBox(height: 6), TextFormField(controller: amareloCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)))] )), const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('V. Geral Padrão', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)), const SizedBox(height: 6), TextFormField(controller: vGeralCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)))] )),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              actions: [
                TextButton(onPressed: salvando ? null : () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: salvando ? null : () async {
                    if (formKey.currentState!.validate()) {
                      bool jaExiste = _planos.any((p) => p['planId'] == planoSelecionado);
                      if (jaExiste) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este plano já existe!'), backgroundColor: Colors.red)); return; }

                      setModalState(() => salvando = true);
                      
                      Map<String, dynamic> novoPlano = {
                        'planId': planoSelecionado,
                        'type': (planoSelecionado == 'PISCANTE' || planoSelecionado == 'APAGADO') ? 'special' : 'normal',
                        'tc': int.tryParse(tcCtrl.text) ?? 100,
                        'offset': 0,
                        'groups': _grupos.map((g) => {
                          'id': g['id'],
                          'name': g['nome'],
                          'start': 0,
                          'end': 0,
                          'yellow': int.tryParse(amareloCtrl.text) ?? 3,
                          'allRed': int.tryParse(vGeralCtrl.text) ?? 2,
                        }).toList(), 
                      };

                      List<dynamic> novaListaPlanos = List.from(_planos);
                      novaListaPlanos.add(novoPlano);

                      if (_semaforoSelecionado == 'DEMO') {
                         setState(() { _planos = novaListaPlanos; _existeProgramacao = true; });
                         Navigator.pop(context); return;
                      }

                      try {
                        await FirebaseFirestore.instance.collection('programacao').doc(_semaforoSelecionado).set({
                          'semaforo_id': _semaforoSelecionado, 'planos': novaListaPlanos, 'ultima_atualizacao': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        setState(() { _planos = novaListaPlanos; _existeProgramacao = true; });
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                        setModalState(() => salvando = false);
                      }
                    }
                  },
                  child: salvando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Criar Plano', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  // MODAL AGENDAMENTO
  void _abrirModalAgendamento() {
    String horaSelecionada = '12'; String minutoSelecionado = '00'; String diaMarcado = 'Todos os dias'; String? planoMarcado; bool salvando = false;
    Map<String, List<dynamic>> agendamentoTemp = {};
    for (String d in ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom']) { agendamentoTemp[d] = List.from(_agendamento[d] ?? []); }
    List<String> horasStr = List.generate(24, (i) => i.toString().padLeft(2, '0'));
    List<String> minutosStr = List.generate(60, (i) => i.toString().padLeft(2, '0'));
    List<String> opcoesDias = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Sáb / Dom', 'Seg / Sex', 'Seg / Sáb', 'Todos os dias'];

    List<String> _obterChavesDias(String selecao) {
      switch (selecao) {
        case 'Domingo': return ['dom']; case 'Segunda': return ['seg']; case 'Terça': return ['ter']; case 'Quarta': return ['qua']; case 'Quinta': return ['qui']; case 'Sexta': return ['sex']; case 'Sábado': return ['sab']; case 'Sáb / Dom': return ['sab', 'dom']; case 'Seg / Sex': return ['seg', 'ter', 'qua', 'qui', 'sex']; case 'Seg / Sáb': return ['seg', 'ter', 'qua', 'qui', 'sex', 'sab']; case 'Todos os dias': return ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'];
        default: return [];
      }
    }

    showDialog(
      context: context, barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: const Color(0xFFf0f2f5),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.95, height: MediaQuery.of(context).size.height * 0.90,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), decoration: const BoxDecoration(color: Color(0xFF2f3b4c), borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Editor de Programação Semanal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)), InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white, size: 24))]),
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 260, padding: const EdgeInsets.all(16), color: Colors.white,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                                  child: Column(
                                    children: [
                                      const Text('HORÁRIO DE INÍCIO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)), const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text('HORA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), const SizedBox(width: 8),
                                          Container(height: 36, width: 55, padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: horaSelecionada, isExpanded: true, items: horasStr.map((h) => DropdownMenuItem(value: h, child: Center(child: Text(h, style: const TextStyle(fontWeight: FontWeight.bold))))).toList(), onChanged: (val) => setModalState(() => horaSelecionada = val!)))),
                                          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text(':', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                                          Container(height: 36, width: 55, padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: minutoSelecionado, isExpanded: true, items: minutosStr.map((m) => DropdownMenuItem(value: m, child: Center(child: Text(m, style: const TextStyle(fontWeight: FontWeight.bold))))).toList(), onChanged: (val) => setModalState(() => minutoSelecionado = val!)))),
                                          const SizedBox(width: 8), const Text('MIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                                          child: Column(
                                            children: [
                                              Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))), child: const Text('Dias da Semana', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                              Expanded(
                                                child: ListView(
                                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                                  children: opcoesDias.map((dia) {
                                                    return Column(children: [RadioListTile<String>(title: Text(dia, style: const TextStyle(fontSize: 11)), value: dia, groupValue: diaMarcado, dense: true, visualDensity: VisualDensity.compact, contentPadding: const EdgeInsets.only(left: 4), activeColor: Colors.blueAccent, onChanged: (val) => setModalState(() => diaMarcado = val!)), if (dia == 'Sábado') const Divider(height: 1, endIndent: 10, indent: 10, color: Colors.black26)]);
                                                  }).toList(),
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
                                          child: Column(
                                            children: [
                                              Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))), child: const Text('Planos Criados', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                              Expanded(
                                                child: _planos.isEmpty
                                                  ? const Center(child: Text('Nenhum plano criado.', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey)))
                                                  : ListView(
                                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                                      children: _planos.map((p) {
                                                        String pId = p['planId'].toString();
                                                        return RadioListTile<String>(title: Text((p['type'] == 'special') ? 'MODO $pId' : 'PLANO $pId', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), value: pId, groupValue: planoMarcado, dense: true, visualDensity: VisualDensity.compact, contentPadding: const EdgeInsets.only(left: 4), activeColor: Colors.green, onChanged: (val) => setModalState(() => planoMarcado = val!));
                                                      }).toList(),
                                                    ),
                                              )
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade300, foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                  onPressed: () {
                                    if (planoMarcado == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um plano primeiro!'), backgroundColor: Colors.red)); return; }
                                    String horaFinal = '$horaSelecionada:$minutoSelecionado';
                                    String nomeParaSalvar = (_planos.firstWhere((p) => p['planId'] == planoMarcado)['type'] == 'special') ? 'MODO $planoMarcado' : 'PLANO $planoMarcado';
                                    setModalState(() {
                                      for (String diaChave in _obterChavesDias(diaMarcado)) {
                                        agendamentoTemp[diaChave]!.add({'hora': horaFinal, 'nomePlano': nomeParaSalvar});
                                        agendamentoTemp[diaChave]!.sort((a, b) => a['hora'].compareTo(b['hora']));
                                      }
                                    });
                                  },
                                  child: const Text('Adicionar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                )
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16), color: Colors.white, child: const Text('Editor de Agendamento', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2f3b4c)))),
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                                    child: IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'].map((diaChave) {
                                          String nomeColuna = {'seg':'SEGUNDA','ter':'TERÇA','qua':'QUARTA','qui':'QUINTA','sex':'SEXTA','sab':'SÁBADO','dom':'DOMINGO'}[diaChave]!;
                                          List eventosDoDia = agendamentoTemp[diaChave] ?? [];
                                          return Expanded(
                                            child: Container(
                                              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade200))),
                                              child: Column(
                                                children: [
                                                  Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12), color: Colors.grey.shade100, child: Text(nomeColuna, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                                                  Expanded(
                                                    child: ListView.builder(
                                                      padding: const EdgeInsets.all(8), itemCount: eventosDoDia.length,
                                                      itemBuilder: (context, index) {
                                                        var ev = eventosDoDia[index];
                                                        String planoIdEv = ev['nomePlano'].toString().replaceAll('PLANO ', '').replaceAll('MODO ', '');
                                                        Color corEvento = _obterCorDoPlano(planoIdEv);
                                                        return Container(
                                                          margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8),
                                                          decoration: BoxDecoration(color: corEvento.withValues(alpha: 0.1), border: Border.all(color: corEvento.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(6)),
                                                          child: Column(
                                                            children: [
                                                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(ev['hora'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)), InkWell(onTap: () { setModalState(() { agendamentoTemp[diaChave]!.removeAt(index); }); }, child: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent))]),
                                                              const SizedBox(height: 4), Text(ev['nomePlano'], textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: corEvento)),
                                                            ],
                                                          ),
                                                        );
                                                      }
                                                    ),
                                                  )
                                                ],
                                              ),
                                            )
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16), color: Colors.white,
                                  child: Center(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade300, foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                      onPressed: salvando ? null : () async {
                                        if (_semaforoSelecionado == 'DEMO') { setState(() { _agendamento = agendamentoTemp; }); Navigator.pop(context); return; }
                                        setModalState(() => salvando = true);
                                        try {
                                          await FirebaseFirestore.instance.collection('programacao').doc(_semaforoSelecionado).set({'semaforo_id': _semaforoSelecionado, 'agendamento': agendamentoTemp, 'ultima_atualizacao': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                                          setState(() { _agendamento = agendamentoTemp; });
                                          if (mounted) Navigator.pop(context);
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                                          setModalState(() => salvando = false);
                                        }
                                      },
                                      child: salvando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black54, strokeWidth: 2)) : const Text('Salvar e Exibir', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
                                  ),
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  // ==========================================
  // COMPONENTES DE UI DA TELA PRINCIPAL
  // ==========================================
  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF25303d), borderRadius: BorderRadius.circular(6), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 5, offset: const Offset(0, 2))]),
      child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
    );
  }

  Widget _buildCustomButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
      onPressed: onPressed, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  // ==========================================
  // SALVAMENTO GLOBAL NO BANCO
  // ==========================================
  Future<void> _salvarProgramacaoCompleta() async {
    if (_semaforoSelecionado == 'DEMO') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modo DEMO não salva no banco de dados!'), backgroundColor: Colors.orange));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('programacao').doc(_semaforoSelecionado).set({
        'semaforo_id': _semaforoSelecionado,
        'grupos': _grupos,
        'planos': _planos,
        'agendamento': _agendamento,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Toda a programação foi salva com sucesso!'), backgroundColor: Colors.green));
      setState(() { _modoEdicao = false; });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar no banco: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Programação Semafórica', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [MenuUsuario()],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/tela.png', fit: BoxFit.cover, color: Colors.black.withValues(alpha: 0.4), colorBlendMode: BlendMode.darken),

          SingleChildScrollView(
            padding: const EdgeInsets.only(top: 100, left: 16, right: 16, bottom: 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- PAINEL DE CONFIGURAÇÃO TOPO ---
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: const Border(top: BorderSide(color: Colors.orange, width: 4)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Selecione o Semáforo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                    const SizedBox(height: 8),
                                    if (_carregandoSemaforos)
                                      const LinearProgressIndicator(color: Colors.orange)
                                    else
                                      DropdownButtonFormField<String>(
                                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, fillColor: Color(0xFFf8f9fa), filled: true),
                                        value: _semaforoSelecionado,
                                        hint: const Text('Selecione...', style: TextStyle(fontStyle: FontStyle.italic)),
                                        isExpanded: true, 
                                        items: _listaSemaforosDropdown.map((item) => DropdownMenuItem<String>(value: item['value'], child: Text(item['label']!, style: TextStyle(fontWeight: item['value'] == 'DEMO' ? FontWeight.bold : FontWeight.normal, color: item['value'] == 'DEMO' ? Colors.blueGrey : Colors.black87), overflow: TextOverflow.ellipsis))).toList(),
                                        onChanged: (val) {
                                          setState(() => _semaforoSelecionado = val);
                                          if (val == 'DEMO') { _carregarDemo(); } else if (val != null) { _carregarProgramacaoDoSemaforo(val); }
                                        },
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(flex: 1, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Grupos Atuais', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)), const SizedBox(height: 4), if (_grupos.isEmpty) const Text('Nenhum grupo definido', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)), ..._grupos.map((g) => Text('${g['id']}: ${g['nome']}', style: const TextStyle(fontSize: 12, color: Colors.black87)))] )),
                              Expanded(flex: 1, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Subárea', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)), const SizedBox(height: 4), Text(_subarea, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue))] )),
                            ],
                          ),

                          if (_semaforoSelecionado != null) ...[
                            const Divider(height: 30),
                            Wrap(
                              spacing: 10, runSpacing: 10,
                              children: [
                                if (!_existeProgramacao || _modoEdicao) ...[
                                  _buildCustomButton('🚦 DEFINIR GRUPOS', Colors.orange, _abrirModalDefinirGrupos),
                                  _buildCustomButton('📝 DEFINIR PLANO', Colors.green, _abrirModalDefinirPlano),
                                  _buildCustomButton('📅 DEFINIR AGENDAMENTO', Colors.blue, _abrirModalAgendamento),
                                  _buildCustomButton('📝 OBSERVAÇÕES', Colors.purple, () {}),
                                  _buildCustomButton('💾 SALVAR PROGRAMAÇÃO', Colors.deepPurple, _salvarProgramacaoCompleta),
                                ],
                                if (_existeProgramacao && !_modoEdicao) ...[
                                  _buildCustomButton('✏️ EDITAR PROGRAMAÇÃO', Colors.blueGrey, _alternarModoEdicao),
                                  _buildCustomButton('📄 EXPORTAR PDF', Colors.red, () {}),
                                  _buildCustomButton('🗑️ EXCLUIR TUDO', Colors.black87, () {}),
                                ],
                                if (_existeProgramacao && _modoEdicao) ...[
                                  _buildCustomButton('🚫 CANCELAR EDIÇÃO', Colors.redAccent, _alternarModoEdicao),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- AGENDAMENTO SEMANAL ---
                    if (_agendamento.isNotEmpty) ...[
                      _buildSectionTitle('AGENDAMENTO SEMANAL'),
                      Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)), border: Border.all(color: Colors.grey.shade300)),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'].map((dia) {
                              String nomeDia = {'seg': 'Segunda', 'ter': 'Terça', 'qua': 'Quarta', 'qui': 'Quinta', 'sex': 'Sexta', 'sab': 'Sábado', 'dom': 'Domingo'}[dia]!;
                              List eventos = _agendamento[dia] ?? [];

                              return Expanded(
                                child: Container(
                                  decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))),
                                  child: Column(
                                    children: [
                                      Container(width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.grey.shade200, child: Text(nomeDia, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                      ...eventos.map((ev) {
                                          String planoIdEv = ev['nomePlano'].toString().replaceAll('PLANO ', '').replaceAll('MODO ', '');
                                          Color corEvento = _obterCorDoPlano(planoIdEv);
                                          return Container(
                                            margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(color: corEvento.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: corEvento.withValues(alpha: 0.5))),
                                            child: Column(children: [Text(ev['hora'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2f3b4c))), const SizedBox(height: 2), Text(ev['nomePlano'], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: corEvento), textAlign: TextAlign.center)]),
                                          );
                                        }
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // --- TEMPOS DOS PLANOS (EDITÁVEIS) ---
                    if (_planos.isNotEmpty) ...[
                      _buildSectionTitle('TEMPOS DOS PLANOS'),
                      
                      ..._planos.map((p) {
                        return PlanoEditorWidget(
                          plano: p,
                          gruposGlobais: _grupos,
                          modoEdicao: _modoEdicao,
                          onUpdate: () => setState(() {}),
                        );
                      }), 
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}