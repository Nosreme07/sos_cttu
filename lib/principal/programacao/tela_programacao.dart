import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Importações para PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
    final paintBase = Paint()..color = Colors.black45..strokeWidth = 1;
    final paintTracoMaior = Paint()..color = Colors.black87..strokeWidth = 1.5;
    final paintTracoMedio = Paint()..color = Colors.black54..strokeWidth = 1.0;
    final paintTracoMenor = Paint()..color = Colors.black26..strokeWidth = 0.5;

    final textStyle = const TextStyle(color: Colors.black87, fontSize: 9, fontWeight: FontWeight.bold);
    
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paintBase);
    
    if (tc <= 0) return;

    for (int i = 0; i <= tc; i++) {
      double x = (i / tc) * size.width;

      if (i % 10 == 0) {
        canvas.drawLine(Offset(x, size.height - 8), Offset(x, size.height), paintTracoMaior);
        final textSpan = TextSpan(text: '$i', style: textStyle);
        final textPainter = TextPainter(text: textSpan, textDirection: ui.TextDirection.ltr);
        textPainter.layout();
        
        double dx = x - (textPainter.width / 2);
        if (i == tc) dx = x - textPainter.width - 6; 
        if (i == 0) dx = 0;

        textPainter.paint(canvas, Offset(dx, 0));
      } else if (i % 5 == 0) {
        canvas.drawLine(Offset(x, size.height - 5), Offset(x, size.height), paintTracoMedio);
      } else {
        canvas.drawLine(Offset(x, size.height - 3), Offset(x, size.height), paintTracoMenor);
      }
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
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const PlanoEditorWidget({
    super.key,
    required this.plano,
    required this.gruposGlobais,
    required this.modoEdicao,
    required this.onUpdate,
    this.onDelete,
    this.onEdit,
  });

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
      Map<String, dynamic>? existing;
      for (var p in pg) {
        if (p is Map) {
          if (p['id'] == gg['id'] || p['name'] == gg['id']) {
            existing = Map<String, dynamic>.from(p);
            break;
          }
        }
      }

      if (existing != null) {
        _localGroups.add({
          'id': gg['id'],
          'name': gg['nome'] ?? gg['name'] ?? '',
          'startCtrl': TextEditingController(text: existing['start']?.toString() ?? '0'),
          'endCtrl': TextEditingController(text: existing['end']?.toString() ?? '0'),
          'yellowCtrl': TextEditingController(text: existing['yellow']?.toString() ?? '3'),
          'allRedCtrl': TextEditingController(text: existing['allRed']?.toString() ?? '2'),
        });
      } else {
        _localGroups.add({
          'id': gg['id'],
          'name': gg['nome'] ?? gg['name'] ?? '',
          'startCtrl': TextEditingController(text: '0'),
          'endCtrl': TextEditingController(text: '0'),
          'yellowCtrl': TextEditingController(text: '3'),
          'allRedCtrl': TextEditingController(text: '2'),
        });
      }
    }
  }

  void _notificarMudanca() {
    int somaTc = 0;

    widget.plano['groups'] = _localGroups.map((g) {
      int start = int.tryParse(g['startCtrl'].text) ?? 0;
      int end = int.tryParse(g['endCtrl'].text) ?? 0;
      int yellow = int.tryParse(g['yellowCtrl'].text) ?? 3;
      int allRed = int.tryParse(g['allRedCtrl'].text) ?? 2;
      
      int verde = end >= start ? end - start : 0;
      somaTc += (verde + yellow + allRed);

      return {
        'id': g['id'],
        'name': g['id'],
        'phase': g['name'],
        'start': start,
        'end': end,
        'yellow': yellow,
        'allRed': allRed,
      };
    }).toList();
    
    if (somaTc > 0) {
      _tcCtrl.text = somaTc.toString();
      widget.plano['tc'] = somaTc;
    }

    widget.plano['offset'] = int.tryParse(_offsetCtrl.text) ?? 0;
    
    widget.onUpdate();
    setState(() {});
  }

  Widget _buildInput(TextEditingController ctrl, {Color? bg, Color? textC, double width = 45, bool? isReadOnly}) {
    bool inputHabilitado = isReadOnly == true ? false : widget.modoEdicao;
    return Container(
      width: width,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? (inputHabilitado ? Colors.white : Colors.grey.shade200),
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: ctrl,
        enabled: inputHabilitado,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center, 
        keyboardType: TextInputType.number,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textC ?? Colors.black87),
        decoration: const InputDecoration(
          border: InputBorder.none, 
          isDense: true, 
          contentPadding: EdgeInsets.zero
        ),
        onChanged: (_) => _notificarMudanca(),
      ),
    );
  }

  List<Widget> _drawSegment(double start, double duration, double tc, double width, double height, Color color, bool isRed, {String? text}) {
    if (tc <= 0 || duration <= 0) return [];
    start = start % tc;
    if (start < 0) start += tc;
    
    Widget buildBox(double w, [String? t]) {
      return Container(
        height: height,
        width: w,
        decoration: BoxDecoration(
          color: color,
          border: isRed ? null : Border.all(color: Colors.black26, width: 0.5)
        ),
        alignment: Alignment.center,
        child: (t != null && w > 20) 
            ? Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)) 
            : null,
      );
    }

    if (start + duration <= tc) {
      return [
        Positioned(
          left: (start / tc) * width,
          top: 0, bottom: 0,
          child: Center(child: buildBox((duration / tc) * width, text)),
        ),
      ];
    } else {
      double d1 = tc - start;
      double d2 = duration - d1;
      return [
        Positioned(
          left: (start / tc) * width,
          top: 0, bottom: 0,
          child: Center(child: buildBox((d1 / tc) * width, text)),
        ),
        Positioned(
          left: 0,
          top: 0, bottom: 0,
          child: Center(child: buildBox((d2 / tc) * width)), 
        ),
      ];
    }
  }

  Color _obterCorDoPlanoLocal(String planId) {
    String idFormatado = planId.toUpperCase().trim();
    if (idFormatado == 'PISCANTE') return Colors.amber.shade700;
    if (idFormatado == 'APAGADO') return Colors.grey.shade800;

    int idNum = int.tryParse(idFormatado.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    List<Color> paleta = [Colors.blue, Colors.purple, Colors.teal, Colors.indigo, Colors.pink, Colors.cyan, Colors.deepOrange, Colors.lightGreen, Colors.deepPurple, Colors.brown];
    return paleta[idNum % paleta.length];
  }

  @override
  Widget build(BuildContext context) {
    String tipoStr = widget.plano['type']?.toString() ?? 'normal';
    String planIdStr = widget.plano['planId']?.toString().toUpperCase() ?? '??';
    Color corPlano = _obterCorDoPlanoLocal(planIdStr);

    if (tipoStr == 'special') {
      Color corFundo = (planIdStr == 'PISCANTE') ? Colors.yellow.shade700 : Colors.grey.shade800;
      return Card(
        margin: const EdgeInsets.only(top: 16),
        elevation: 2,
        clipBehavior: Clip.antiAlias, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF2f3b4c), 
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('MODO $planIdStr', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                  if (widget.modoEdicao && widget.onDelete != null)
                    InkWell(
                      onTap: widget.onDelete,
                      child: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                    )
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              child: SizedBox(
                height: 60,
                child: planIdStr == 'PISCANTE' 
                  ? CustomPaint(painter: PiscantePainter()) 
                  : Container(color: corFundo),
              ),
            ),
          ]
        )
      );
    }

    int tc = int.tryParse(_tcCtrl.text) ?? 100;
    if (tc <= 0) tc = 1;

    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 2,
      clipBehavior: Clip.antiAlias, 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF2f3b4c),
              border: Border(left: BorderSide(color: corPlano, width: 4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('PLANO $planIdStr   |   Ciclo: ${tc}s', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                if (widget.modoEdicao && widget.onEdit != null && widget.onDelete != null)
                  Row(
                    children: [
                      InkWell(
                        onTap: widget.onEdit,
                        child: const Icon(Icons.edit, color: Colors.white70, size: 20),
                      ),
                      const SizedBox(width: 16),
                      InkWell(
                        onTap: widget.onDelete,
                        child: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                      ),
                    ],
                  )
              ],
            ),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
            child: Row(
              children: [
                const Text('Ciclo Auto: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                _buildInput(_tcCtrl, width: 50, isReadOnly: true, bg: Colors.grey.shade300), 
                const SizedBox(width: 16),
                const Text('Parâmetro (OFFSET): ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                  padding: const EdgeInsets.only(left: 16, right: 16),
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
                              
                              int greenDuration = end >= start ? end - start : (tc - start) + end;
                              int yellowDuration = yellow;
                              
                              int redDuration = tc - greenDuration - yellowDuration;
                              if (redDuration < 0) redDuration = 0; 
                              
                              int greenStart = start;
                              int yellowStart = (start + greenDuration) % tc;
                              int redStart = (start + greenDuration + yellowDuration) % tc;
                              
                              List<Widget> barras = [];
                              double barHeight = 24.0; 
                              
                              barras.addAll(_drawSegment(redStart.toDouble(), redDuration.toDouble(), tc.toDouble(), width, barHeight, const Color(0xFFe74c3c), true));
                              barras.addAll(_drawSegment(greenStart.toDouble(), greenDuration.toDouble(), tc.toDouble(), width, barHeight, const Color(0xFF00b050), false, text: greenDuration.toString()));
                              barras.addAll(_drawSegment(yellowStart.toDouble(), yellowDuration.toDouble(), tc.toDouble(), width, barHeight, const Color(0xFFffc000), false));

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
  final String? semaforoInicial; // <--- NOVO PARÂMETRO PARA RECEBER O COMANDO

  const TelaProgramacao({super.key, this.semaforoInicial});

  @override
  State<TelaProgramacao> createState() => _TelaProgramacaoState();
}

class _TelaProgramacaoState extends State<TelaProgramacao> {
  String? _semaforoSelecionado;
  bool _modoEdicao = false;
  bool _existeProgramacao = false;

  String _subarea = "---";
  List<String> _listaSubareas = [];
  
  String _ultimaAtualizacaoFormatada = "";
  String _observacoes = "";

  List<dynamic> _grupos = [];
  List<dynamic> _planos = [];
  Map<String, dynamic> _agendamento = {};

  List<Map<String, String>> _listaSemaforosDropdown = [];
  bool _carregandoSemaforos = true;

  @override
  void initState() {
    super.initState();
    _carregarSubareasBanco();
    _carregarSemaforosBanco(); // Esta função agora lida com o semaforoInicial no final
  }

  Color _obterCorDoPlano(String planId) {
    String idFormatado = planId.toUpperCase().trim();
    if (idFormatado == 'PISCANTE') return Colors.amber.shade700;
    if (idFormatado == 'APAGADO') return Colors.grey.shade800;

    int idNum = int.tryParse(idFormatado.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    List<Color> paleta = [Colors.blue, Colors.purple, Colors.teal, Colors.indigo, Colors.pink, Colors.cyan, Colors.deepOrange, Colors.lightGreen, Colors.deepPurple, Colors.brown];
    return paleta[idNum % paleta.length];
  }

  void _ordenarPlanos() {
    _planos.sort((a, b) {
      String idA = a['planId'].toString().toUpperCase();
      String idB = b['planId'].toString().toUpperCase();
      
      if (idA == 'PISCANTE' && idB == 'APAGADO') return -1;
      if (idA == 'APAGADO' && idB == 'PISCANTE') return 1;
      if (idA == 'PISCANTE' || idA == 'APAGADO') return 1;
      if (idB == 'PISCANTE' || idB == 'APAGADO') return -1;

      int numA = int.tryParse(idA.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      int numB = int.tryParse(idB.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return numA.compareTo(numB);
    });
  }

  Future<void> _carregarSubareasBanco() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('subareas').get();
      List<String> subs = snap.docs.map((d) => d['nome'].toString()).toList();
      subs.sort();
      if (mounted) setState(() { _listaSubareas = subs; });
    } catch(e) {}
  }

  Future<void> _carregarSemaforosBanco() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('semaforos').get();
      List<Map<String, String>> listaTemporaria = [];

      listaTemporaria.add({'value': 'DEMO', 'label': '000 - SEMÁFORO DEMO (Teste Visual)', 'subarea': '---'});

      for (var doc in snap.docs) {
        var d = doc.data();
        String idStr = (d['id'] ?? '').toString();
        String idFormatado = '000';
        if (idStr.isNotEmpty && !idStr.toUpperCase().contains('NUMERO')) {
          String numeros = idStr.replaceAll(RegExp(r'[^0-9]'), '');
          if (numeros.isNotEmpty) idFormatado = numeros.padLeft(3, '0');
        }
        String endereco = (d['endereco'] ?? '').toString();
        String subDb = (d['subareas'] ?? d['subarea'] ?? '').toString();

        if (idFormatado != '000' && endereco.isNotEmpty) {
          listaTemporaria.add({'value': doc.id, 'label': '$idFormatado - $endereco', 'subarea': subDb.isNotEmpty ? subDb : '---'});
        }
      }

      if (listaTemporaria.length > 1) {
        var demoItem = listaTemporaria.removeAt(0);
        listaTemporaria.sort((a, b) => a['label']!.compareTo(b['label']!));
        listaTemporaria.insert(0, demoItem);
      }

      if (mounted) {
        setState(() { 
          _listaSemaforosDropdown = listaTemporaria; 
          _carregandoSemaforos = false; 
        });

        // --- LÓGICA PARA AUTO-PREENCHER VINDO DO MAPA OU OCORRÊNCIAS ---
        if (widget.semaforoInicial != null && widget.semaforoInicial!.isNotEmpty) {
           try {
             var itemEncontrado = _listaSemaforosDropdown.firstWhere(
               (item) => item['label']!.startsWith(widget.semaforoInicial!)
             );
             setState(() {
               _semaforoSelecionado = itemEncontrado['value'];
               _subarea = itemEncontrado['subarea'] ?? "---";
             });
             _carregarProgramacaoDoSemaforo(_semaforoSelecionado!);
           } catch (e) {
             debugPrint("Semáforo inicial não encontrado: ${widget.semaforoInicial}");
           }
        }
      }
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
        
        String ultAuditoria = "";
        if (data['ultima_atualizacao'] != null && data['motivo_edicao'] != null && data['usuario_edicao'] != null) {
          DateTime dt = (data['ultima_atualizacao'] as Timestamp).toDate();
          String dataFormatada = DateFormat('dd/MM/yyyy - HH:mm').format(dt);
          ultAuditoria = "$dataFormatada\nMotivo: ${data['motivo_edicao']}\nPor: ${data['usuario_edicao']}";
        }

        setState(() {
          _existeProgramacao = true;
          _grupos = data['grupos'] ?? [];
          _planos = data['planos'] ?? [];
          _agendamento = data['agendamento'] ?? {};
          _subarea = data['subarea'] ?? "---";
          _observacoes = data['observacoes'] ?? "";
          _ultimaAtualizacaoFormatada = ultAuditoria;
          _ordenarPlanos();
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
      _ultimaAtualizacaoFormatada = "01/01/2026 - 12:00\nMotivo: CRIAÇÃO INICIAL\nPor: SISTEMA SOS";
      _grupos = [{'id': 'G1', 'nome': 'AV. PRINCIPAL'}, {'id': 'G2', 'nome': 'RUA LATERAL'}];
      _planos = [
        {
          'planId': '01', 'type': 'normal', 'tc': 120, 'offset': 0,
          'groups': [
            {'id': 'G1', 'name': 'G1', 'start': 0, 'end': 55, 'yellow': 3, 'allRed': 2},
            {'id': 'G2', 'name': 'G2', 'start': 60, 'end': 115, 'yellow': 3, 'allRed': 2},
          ],
        },
        {'planId': 'piscante', 'type': 'special'},
        {'planId': 'apagado', 'type': 'special'},
      ];
      _ordenarPlanos();
      _agendamento = {'seg': [{'hora': '06:00', 'nomePlano': 'PLANO 01'}, {'hora': '22:00', 'nomePlano': 'MODO PISCANTE'}]};
      _observacoes = "Neste modo, os tempos de verde funcionam com precisão e cruzam o ciclo, se necessário.";
    });
  }

  void _limparTela() {
    setState(() {
      _existeProgramacao = false; _modoEdicao = false; 
      _ultimaAtualizacaoFormatada = ""; _observacoes = "";
      _grupos = []; _planos = []; _agendamento = {};
    });
  }

  void _alternarModoEdicao() {
    setState(() => _modoEdicao = !_modoEdicao);
  }

  void _zerarTudo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zerar Programação', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text('Tem certeza que deseja ZERAR toda a programação deste semáforo?\nIsso apagará os grupos, planos e agendamentos definitivamente do banco de dados.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.black87))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              if (_semaforoSelecionado != 'DEMO' && _semaforoSelecionado != null) {
                await FirebaseFirestore.instance.collection('programacao').doc(_semaforoSelecionado).delete();
              }
              _limparTela();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Programação zerada com sucesso!'), backgroundColor: Colors.orange));
            },
            child: const Text('Sim, Zerar Tudo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ]
      )
    );
  }

  void _excluirPlano(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Plano', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text('Deseja realmente remover este plano da configuração?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.black87))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() { _planos.removeAt(index); });
              Navigator.pop(ctx);
            },
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          )
        ]
      )
    );
  }

  void _abrirModalRenomearPlano(Map<String, dynamic> plano, int index) {
    TextEditingController idCtrl = TextEditingController(text: plano['planId'].toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar Identificação', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: idCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Nome/Número do Plano', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.black87))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              setState(() { plano['planId'] = idCtrl.text.toUpperCase(); });
              Navigator.pop(ctx);
            },
            child: const Text('Salvar', style: TextStyle(color: Colors.white)),
          )
        ]
      )
    );
  }

  PdfColor _getPdfColor(Color c) {
    return PdfColor(c.red / 255.0, c.green / 255.0, c.blue / 255.0);
  }

  Future<void> _exportarPdf() async {
    if (_semaforoSelecionado == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.red)),
    );

    try {
      final pdf = pw.Document();
      final dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
      
      String semaforoLabel = _listaSemaforosDropdown.firstWhere(
          (e) => e['value'] == _semaforoSelecionado, 
          orElse: () => {'label': _semaforoSelecionado!}
      )['label']!;

      pw.Widget buildPdfGantt(List groups, int tc) {
        double ganttWidth = 360.0; 
        double rowHeight = 18.0; 
        double rulerHeight = 15.0;

        List<pw.Widget> stackChildren = [];

        stackChildren.add(
          pw.Positioned(
            left: 0, top: rulerHeight,
            child: pw.Container(width: ganttWidth, height: 1, color: PdfColors.grey600)
          )
        );

        for (int i = 0; i <= tc; i++) {
          double x = (i / tc) * ganttWidth;
          if (i % 10 == 0) {
            stackChildren.add(pw.Positioned(left: x, top: rulerHeight - 5, child: pw.Container(width: 1, height: 5, color: PdfColors.grey800)));
            double dx = x - 4;
            if (i == tc) dx = x - 10;
            if (i == 0) dx = 0;
            stackChildren.add(pw.Positioned(left: dx, top: 0, child: pw.Text('$i', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold))));
          } else if (i % 5 == 0) {
            stackChildren.add(pw.Positioned(left: x, top: rulerHeight - 3, child: pw.Container(width: 0.5, height: 3, color: PdfColors.grey600)));
          }
        }

        double currentY = rulerHeight + 5;

        for (var g in groups) {
           int start = int.tryParse(g['start']?.toString() ?? '0') ?? 0;
           int end = int.tryParse(g['end']?.toString() ?? '0') ?? 0;
           int yellow = int.tryParse(g['yellow']?.toString() ?? '3') ?? 3;
           
           int greenDuration = end >= start ? end - start : (tc - start) + end;
           int yellowDuration = yellow;
           int redDuration = tc - greenDuration - yellowDuration;
           if (redDuration < 0) redDuration = 0;

           int greenStart = start;
           int yellowStart = (start + greenDuration) % tc;
           int redStart = (start + greenDuration + yellowDuration) % tc;

           void addSegment(double st, double dur, PdfColor color, [String? txt]) {
              if (dur <= 0) return;
              double s = st % tc;
              if (s < 0) s += tc;
              
              if (s + dur <= tc) {
                 stackChildren.add(
                   pw.Positioned(
                     left: (s / tc) * ganttWidth, 
                     top: currentY + 3, 
                     child: pw.Container(width: (dur / tc) * ganttWidth, height: 12, color: color, alignment: pw.Alignment.center, child: txt != null ? pw.Text(txt, style: pw.TextStyle(color: PdfColors.white, fontSize: 6, fontWeight: pw.FontWeight.bold)) : null)
                   )
                 );
              } else {
                 double d1 = tc - s;
                 double d2 = dur - d1;
                 stackChildren.add(
                   pw.Positioned(
                     left: (s / tc) * ganttWidth, 
                     top: currentY + 3,
                     child: pw.Container(width: (d1 / tc) * ganttWidth, height: 12, color: color, alignment: pw.Alignment.center, child: txt != null ? pw.Text(txt, style: pw.TextStyle(color: PdfColors.white, fontSize: 6, fontWeight: pw.FontWeight.bold)) : null)
                   )
                 );
                 stackChildren.add(
                   pw.Positioned(
                     left: 0, top: currentY + 3,
                     child: pw.Container(width: (d2 / tc) * ganttWidth, height: 12, color: color)
                   )
                 );
              }
           }

           addSegment(redStart.toDouble(), redDuration.toDouble(), PdfColor.fromHex('#e74c3c'));
           addSegment(greenStart.toDouble(), greenDuration.toDouble(), PdfColor.fromHex('#00b050'), greenDuration.toString());
           addSegment(yellowStart.toDouble(), yellowDuration.toDouble(), PdfColor.fromHex('#ffc000'));

           currentY += rowHeight;
        }

        return pw.SizedBox(
          width: ganttWidth,
          height: currentY,
          child: pw.Stack(children: stackChildren)
        );
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          header: (context) {
            if (context.pageNumber == 1) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Ficha de Programação Semafórica', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
                  pw.Text('Gerado pelo Sistema SOS em $dataHoraAtual', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  pw.Divider(),
                  pw.SizedBox(height: 10),
                ]
              );
            }
            return pw.SizedBox.shrink();
          },
          footer: (context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                context.pageNumber == 1 
                  ? 'Página ${context.pageNumber} de ${context.pagesCount}' 
                  : 'Gerado pelo Sistema de Ocorrências Semafóricas - SOS em $dataHoraAtual   |   Página ${context.pageNumber} de ${context.pagesCount}', 
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)
              ),
            );
          },
          build: (context) {
            return [
              pw.Text('Semáforo: $semaforoLabel', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text('Subárea: $_subarea', style: const pw.TextStyle(fontSize: 12)),
              if (_ultimaAtualizacaoFormatada.isNotEmpty)
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 5),
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(color: PdfColors.grey200, border: pw.Border.all(color: PdfColors.grey400)),
                  child: pw.Text('Última Edição:\n${_ultimaAtualizacaoFormatada.replaceAll('\n', '   |   ')}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey)),
                ),
              pw.SizedBox(height: 15),

              if (_grupos.isNotEmpty) ...[
                pw.Text('Configuração de Grupos', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                pw.SizedBox(height: 4),
                ..._grupos.map((g) => pw.Text('${g['id']}: ${g['nome']}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800))),
                pw.SizedBox(height: 20),
              ],

              if (_agendamento.isNotEmpty) ...[
                pw.Text('AGENDAMENTO SEMANAL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black),),
                pw.SizedBox(height: 8),
                pw.Container(
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start, 
                    children: ['seg', 'ter', 'qua', 'qui', 'sex', 'sab', 'dom'].map((dia) {
                       List eventos = _agendamento[dia] ?? [];
                       String nomeDia = {'seg':'SEGUNDA','ter':'TERÇA','qua':'QUARTA','qui':'QUINTA','sex':'SEXTA','sab':'SÁBADO','dom':'DOMINGO'}[dia]!;
                       return pw.Expanded(
                         child: pw.Container(
                           decoration: pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(color: PdfColors.grey300))),
                           child: pw.Column(
                             children: [
                               pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(4), color: PdfColors.grey200, child: pw.Text(nomeDia, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900))),
                               ...eventos.map((ev) {
                                   String planoIdEv = ev['nomePlano'].toString().replaceAll('PLANO ', '').replaceAll('MODO ', '');
                                   Color c = _obterCorDoPlano(planoIdEv);
                                   PdfColor pdfColorBordaETexto = _getPdfColor(c);
                                   
                                   String nomeExibicaoPdf = ev['nomePlano'].toString();
                                   if (nomeExibicaoPdf == 'MODO PISCANTE') nomeExibicaoPdf = 'MODO\nPISCANTE';
                                   if (nomeExibicaoPdf == 'MODO APAGADO') nomeExibicaoPdf = 'MODO\nAPAGADO';

                                   return pw.Container(
                                     margin: const pw.EdgeInsets.all(4), padding: const pw.EdgeInsets.all(4),
                                     decoration: pw.BoxDecoration(color: PdfColors.white, border: pw.Border.all(color: pdfColorBordaETexto, width: 1.5), borderRadius: pw.BorderRadius.circular(4)),
                                     child: pw.Column(children: [
                                       pw.Text(ev['hora'], style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.black)),
                                       pw.SizedBox(height: 2), 
                                       pw.Text(nomeExibicaoPdf, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: pdfColorBordaETexto)),
                                     ])
                                   );
                               })
                             ]
                           )
                         )
                       );
                    }).toList()
                  )
                ),
                pw.SizedBox(height: 20),
              ],

              if (_planos.isNotEmpty) ...[
                pw.Text('TEMPOS DOS PLANOS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                pw.SizedBox(height: 8),
                ..._planos.map((p) {
                  String tipoStr = p['type']?.toString() ?? 'normal';
                  String planIdStr = p['planId']?.toString().toUpperCase() ?? '??';
                  
                  if (tipoStr == 'special') {
                    return pw.Wrap(
                      children: [
                        pw.Container(
                          width: double.infinity,
                          margin: const pw.EdgeInsets.only(bottom: 10),
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(color: PdfColors.grey800, borderRadius: pw.BorderRadius.circular(4)),
                          child: pw.Text('MODO $planIdStr', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                        )
                      ]
                    );
                  }

                  int tc = p['tc'] ?? 100;
                  List groups = p['groups'] ?? [];

                  return pw.Wrap(
                    children: [
                      pw.Container(
                        margin: const pw.EdgeInsets.only(bottom: 15),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300),
                          borderRadius: pw.BorderRadius.circular(4)
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: [
                            pw.Container(
                              padding: const pw.EdgeInsets.all(6),
                              decoration: const pw.BoxDecoration(color: PdfColors.grey800),
                              child: pw.Text('PLANO $planIdStr   |   Ciclo: ${tc}s   |   Offset: ${p['offset'] ?? 0}s', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10))
                            ),
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Container(
                                  width: 160, 
                                  padding: const pw.EdgeInsets.only(top: 4, bottom: 4, left: 4),
                                  child: groups.isNotEmpty 
                                    ? pw.Table(
                                        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                                        columnWidths: {
                                          0: const pw.FixedColumnWidth(40), 
                                          1: const pw.FixedColumnWidth(40), 
                                          2: const pw.FixedColumnWidth(40), 
                                          3: const pw.FixedColumnWidth(40), 
                                        },
                                        children: [
                                          pw.TableRow(
                                            children: ['Verde', 'Amarelo', 'Vm.Geral', 'Entreverde'].map((t) => 
                                              pw.Container(
                                                height: 20, 
                                                alignment: pw.Alignment.center, 
                                                child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800))
                                              )
                                            ).toList()
                                          ),
                                          ...groups.map((g) {
                                            int start = g['start'] ?? 0;
                                            int end = g['end'] ?? 0;
                                            int yellow = g['yellow'] ?? 3;
                                            int allRed = g['allRed'] ?? 2;
                                            int verde = end >= start ? end - start : (tc - start) + end;
                                            int entreverde = yellow + allRed;

                                            return pw.TableRow(
                                              children: [
                                                pw.Container(height: 18, alignment: pw.Alignment.center, color: PdfColor.fromHex('#e8f5e9'), child: pw.Text('$verde', style: pw.TextStyle(fontSize: 8, color: PdfColors.green800, fontWeight: pw.FontWeight.bold))),
                                                pw.Container(height: 18, alignment: pw.Alignment.center, color: PdfColor.fromHex('#fffde7'), child: pw.Text('$yellow', style: pw.TextStyle(fontSize: 8, color: PdfColors.orange800, fontWeight: pw.FontWeight.bold))),
                                                pw.Container(height: 18, alignment: pw.Alignment.center, color: PdfColor.fromHex('#ffebee'), child: pw.Text('$allRed', style: pw.TextStyle(fontSize: 8, color: PdfColors.red800, fontWeight: pw.FontWeight.bold))),
                                                pw.Container(height: 18, alignment: pw.Alignment.center, child: pw.Text('$entreverde', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey800))),
                                              ]
                                            );
                                          }).toList()
                                        ]
                                      )
                                    : pw.Text('Nenhum grupo configurado.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey))
                                ),
                                pw.Container(
                                  width: 376, 
                                  padding: const pw.EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
                                  child: buildPdfGantt(groups, tc)
                                )
                              ]
                            )
                          ]
                        )
                      )
                    ]
                  );
                }),
                pw.SizedBox(height: 20),
              ],

              if (_observacoes.isNotEmpty) ...[
                pw.Wrap(
                  children: [
                    pw.Text('OBSERVAÇÕES DO PROJETO', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                    pw.SizedBox(height: 8),
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(4)),
                      child: pw.Text(_observacoes, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey900))
                    )
                  ]
                )
              ]
            ];
          }
        )
      );

      if (mounted) Navigator.pop(context); 
      
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(), 
        name: 'Programacao_Semaforo_$semaforoLabel.pdf'
      );

    } catch (e) {
      if (mounted) Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: Colors.red));
    }
  }

  void _abrirModalObservacoes() {
    final TextEditingController obsController = TextEditingController(text: _observacoes);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          titlePadding: const EdgeInsets.only(left: 24, right: 8, top: 16, bottom: 8),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Observações do Projeto', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 18)),
              IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
            ],
          ),
          content: Container(
            width: 400,
            padding: const EdgeInsets.only(top: 16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black12, width: 1))),
            child: TextField(
              controller: obsController,
              enabled: _modoEdicao,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: _modoEdicao ? 'Digite as anotações e observações da programação...' : 'Sem observações cadastradas.',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: _modoEdicao ? Colors.white : Colors.grey.shade100,
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: Text(_modoEdicao ? 'Cancelar' : 'Fechar', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold))
            ),
            if (_modoEdicao)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                onPressed: () {
                  setState(() { _observacoes = obsController.text.trim(); });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Observação armazenada! Lembre-se de salvar a programação.'), backgroundColor: Colors.green));
                },
                child: const Text('Confirmar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
          ],
        );
      }
    );
  }

  void _abrirModalDefinirGrupos() {
    int passoAtual = _grupos.isNotEmpty ? 2 : 1; 
    int quantidadeGrupos = _grupos.length; 
    bool salvando = false;
    
    final TextEditingController qtdController = TextEditingController(text: quantidadeGrupos > 0 ? quantidadeGrupos.toString() : '');
    List<TextEditingController> nomesControllers = _grupos.map((g) => TextEditingController(text: g['nome'].toString())).toList();

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
                      
                      List<TextEditingController> novosControllers = [];
                      for (int i = 0; i < qtd; i++) {
                        if (i < nomesControllers.length) {
                          novosControllers.add(nomesControllers[i]);
                        } else {
                          novosControllers.add(TextEditingController());
                        }
                      }

                      setModalState(() { nomesControllers = novosControllers; quantidadeGrupos = qtd; passoAtual = 2; });
                    },
                    child: const Text('Próximo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ] else if (passoAtual == 2) ...[
                  TextButton(onPressed: salvando ? null : () { setModalState(() { passoAtual = 1; }); }, child: const Text('Voltar', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold))),
                  TextButton(
                    onPressed: salvando ? null : () {
                      setModalState(() {
                        quantidadeGrupos++;
                        nomesControllers.add(TextEditingController());
                        qtdController.text = quantidadeGrupos.toString();
                      });
                    },
                    child: const Text('+ Novo Grupo', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  ),
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

                      List<Map<String, dynamic>> planosAtualizados = [];
                      if (_planos.isNotEmpty) {
                         for (var p in _planos) {
                            if (p['type'] == 'special') {
                               planosAtualizados.add(p);
                            } else {
                               List oldGroups = p['groups'] ?? [];
                               List newGroupsData = novosGrupos.map((ng) {
                                  var existing = oldGroups.firstWhere((og) => og['id'] == ng['id'], orElse: () => null);
                                  if (existing != null) {
                                     return {
                                       'id': ng['id'],
                                       'name': ng['nome'],
                                       'start': existing['start'],
                                       'end': existing['end'],
                                       'yellow': existing['yellow'],
                                       'allRed': existing['allRed'],
                                     };
                                  } else {
                                     return {
                                       'id': ng['id'],
                                       'name': ng['nome'],
                                       'start': 0, 'end': 0, 'yellow': 3, 'allRed': 2,
                                     };
                                  }
                               }).toList();
                               
                               planosAtualizados.add({
                                  'planId': p['planId'],
                                  'type': p['type'],
                                  'tc': p['tc'],
                                  'offset': p['offset'],
                                  'groups': newGroupsData,
                               });
                            }
                         }
                      } else {
                        planosAtualizados = [
                          {
                            'planId': '01', 'type': 'normal', 'tc': 100, 'offset': 0,
                            'groups': novosGrupos.map((g) => { 'id': g['id'], 'name': g['nome'], 'start': 0, 'end': 0, 'yellow': 3, 'allRed': 2 }).toList()
                          },
                          {'planId': 'piscante', 'type': 'special'},
                          {'planId': 'apagado', 'type': 'special'},
                        ];
                      }

                      if (_semaforoSelecionado == 'DEMO') {
                         setState(() { _grupos = novosGrupos; _planos = planosAtualizados; _existeProgramacao = true; _ordenarPlanos(); });
                         Navigator.pop(context); return;
                      }

                      setModalState(() => salvando = true);
                      try {
                        await FirebaseFirestore.instance.collection('programacao').doc(_semaforoSelecionado).set({
                          'semaforo_id': _semaforoSelecionado, 
                          'grupos': novosGrupos, 
                          'planos': planosAtualizados, 
                          'ultima_atualizacao': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        
                        setState(() { _grupos = novosGrupos; _planos = planosAtualizados; _existeProgramacao = true; _ordenarPlanos(); });
                        if (mounted) Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grupos atualizados!'), backgroundColor: Colors.green));
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

  void _abrirModalDefinirPlano() {
    final formKey = GlobalKey<FormState>();
    String? planoSelecionado;
    final tcCtrl = TextEditingController(text: '100');
    final amareloCtrl = TextEditingController(text: '3');
    final vGeralCtrl = TextEditingController(text: '2');
    bool salvando = false;

    List<String> opcoesPlano = List.generate(14, (i) => (i + 2).toString().padLeft(2, '0'));

    showDialog(
      context: context, barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              titlePadding: const EdgeInsets.only(left: 24, right: 8, top: 16, bottom: 8),
              title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Adicionar Plano Extra', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 18)), IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context))]),
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
                        'type': 'normal',
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
                         setState(() { _planos = novaListaPlanos; _existeProgramacao = true; _ordenarPlanos(); });
                         Navigator.pop(context); return;
                      }

                      try {
                        await FirebaseFirestore.instance.collection('programacao').doc(_semaforoSelecionado).set({
                          'semaforo_id': _semaforoSelecionado, 'planos': novaListaPlanos, 'ultima_atualizacao': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        setState(() { _planos = novaListaPlanos; _existeProgramacao = true; _ordenarPlanos(); });
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

  void _editarAgendamentoExistente(String dia, int index, Map ev) {
    String horaAtual = ev['hora'].split(':')[0];
    String minAtual = ev['hora'].split(':')[1];
    String planoAtual = ev['nomePlano'].toString().replaceAll('PLANO ', '').replaceAll('MODO ', '').trim();
    
    List<String> horasStr = List.generate(24, (i) => i.toString().padLeft(2, '0'));
    List<String> minutosStr = List.generate(60, (i) => i.toString().padLeft(2, '0'));
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Editar Horário (${{'seg':'Segunda','ter':'Terça','qua':'Quarta','qui':'Quinta','sex':'Sexta','sab':'Sábado','dom':'Domingo'}[dia]})'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DropdownButton<String>(
                      value: horaAtual,
                      items: horasStr.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                      onChanged: (val) => setDialogState(() => horaAtual = val!)
                    ),
                    const Text(' : ', style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: minAtual,
                      items: minutosStr.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (val) => setDialogState(() => minAtual = val!)
                    ),
                  ]
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  value: _planos.any((p) => p['planId'] == planoAtual) ? planoAtual : null,
                  items: _planos.map((p) {
                    String pId = p['planId'].toString();
                    return DropdownMenuItem(value: pId, child: Text(p['type'] == 'special' ? 'MODO $pId' : 'PLANO $pId'));
                  }).toList(),
                  onChanged: (val) => setDialogState(() => planoAtual = val!)
                )
              ]
            ),
            actions: [
              TextButton(
                onPressed: () {
                   setState(() { _agendamento[dia].removeAt(index); });
                   Navigator.pop(ctx);
                },
                child: const Text('🗑️ Excluir Horário', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
              ),
              ElevatedButton(
                onPressed: () {
                   String novoNome = _planos.firstWhere((p) => p['planId'] == planoAtual)['type'] == 'special' ? 'MODO $planoAtual' : 'PLANO $planoAtual';
                   String novaHora = '$horaAtual:$minAtual';
                   
                   bool jaExiste = false;
                   for(int i=0; i<_agendamento[dia].length; i++) {
                     if (i != index && _agendamento[dia][i]['hora'] == novaHora) jaExiste = true;
                   }
                   
                   if (jaExiste) {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Já existe um plano neste horário!'), backgroundColor: Colors.red));
                     return;
                   }
                   
                   setState(() {
                      _agendamento[dia][index] = {'hora': novaHora, 'nomePlano': novoNome};
                      _agendamento[dia].sort((a, b) => a['hora'].compareTo(b['hora']));
                   });
                   Navigator.pop(ctx);
                },
                child: const Text('Salvar')
              )
            ]
          );
        }
      )
    );
  }

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
                                                        String nomeOpcao = (p['type'] == 'special') ? 'MODO $pId' : 'PLANO $pId';
                                                        if (nomeOpcao == 'MODO PISCANTE') nomeOpcao = 'MODO\nPISCANTE';
                                                        if (nomeOpcao == 'MODO APAGADO') nomeOpcao = 'MODO\nAPAGADO';

                                                        return RadioListTile<String>(title: Text(nomeOpcao, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)), value: pId, groupValue: planoMarcado, dense: true, visualDensity: VisualDensity.compact, contentPadding: const EdgeInsets.only(left: 4), activeColor: Colors.green, onChanged: (val) => setModalState(() => planoMarcado = val!));
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
                                        // VERIFICAÇÃO DE HORÁRIO DUPLICADO
                                        bool timeExists = agendamentoTemp[diaChave]!.any((ev) => ev['hora'] == horaFinal);
                                        if (timeExists) {
                                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('O horário $horaFinal já possui um plano configurado para este dia!'), backgroundColor: Colors.red));
                                        } else {
                                          agendamentoTemp[diaChave]!.add({'hora': horaFinal, 'nomePlano': nomeParaSalvar});
                                          agendamentoTemp[diaChave]!.sort((a, b) => a['hora'].compareTo(b['hora']));
                                        }
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
                                                        
                                                        String nomeExibicao = ev['nomePlano'].toString();
                                                        if (nomeExibicao == 'MODO PISCANTE') nomeExibicao = 'MODO\nPISCANTE';
                                                        if (nomeExibicao == 'MODO APAGADO') nomeExibicao = 'MODO\nAPAGADO';

                                                        return InkWell(
                                                          onTap: () {
                                                            if (_modoEdicao) {
                                                              _editarAgendamentoExistente(diaChave, index, ev);
                                                            }
                                                          },
                                                          child: Container(
                                                            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(8),
                                                            decoration: BoxDecoration(color: corEvento.withValues(alpha: 0.1), border: Border.all(color: corEvento.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(6)),
                                                            child: Column(
                                                              children: [
                                                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(ev['hora'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)), InkWell(onTap: () { setModalState(() { agendamentoTemp[diaChave]!.removeAt(index); }); }, child: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent))]),
                                                                const SizedBox(height: 4), Text(nomeExibicao, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: corEvento)),
                                                              ],
                                                            ),
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

  void _iniciarSalvamentoComMotivo() {
    if (_semaforoSelecionado == 'DEMO') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modo DEMO não salva no banco de dados!'), backgroundColor: Colors.orange));
      return;
    }

    if (!_existeProgramacao) {
       _salvarProgramacaoCompleta('CRIAÇÃO INICIAL');
       return;
    }

    final motivoCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Motivo da Edição', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Descreva brevemente o motivo da alteração nesta programação:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Ex: AJUSTE DE TEMPO DE VERDE, NOVA FASE...'),
            )
          ]
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.black87))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, informe o motivo da edição!'), backgroundColor: Colors.red));
                return;
              }
              Navigator.pop(ctx);
              _salvarProgramacaoCompleta(motivoCtrl.text.trim().toUpperCase());
            },
            child: const Text('Confirmar e Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ]
      )
    );
  }

  Future<String> _getNomeUsuarioLogado() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'SISTEMA';
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        var d = doc.data() as Map<String, dynamic>;
        if (d['nomeCompleto'] != null && d['nomeCompleto'].toString().isNotEmpty) {
          return d['nomeCompleto'].toString().toUpperCase();
        }
      }
    } catch (e) {}
    return (user.displayName ?? user.email ?? 'SISTEMA').toUpperCase();
  }

  Future<void> _salvarProgramacaoCompleta(String motivo) async {
    try {
      String nomeUser = await _getNomeUsuarioLogado();

      await FirebaseFirestore.instance.collection('programacao').doc(_semaforoSelecionado).set({
        'semaforo_id': _semaforoSelecionado,
        'grupos': _grupos,
        'planos': _planos,
        'agendamento': _agendamento,
        'observacoes': _observacoes,
        'ultima_atualizacao': FieldValue.serverTimestamp(),
        'subarea': _subarea,
        'motivo_edicao': motivo,
        'usuario_edicao': nomeUser,
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Toda a programação foi salva com sucesso!'), backgroundColor: Colors.green));
      
      setState(() { 
        _modoEdicao = false; 
        _ultimaAtualizacaoFormatada = "${DateFormat('dd/MM/yyyy - HH:mm').format(DateTime.now())}\nMotivo: $motivo\nPor: $nomeUser";
      });
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
                                      Autocomplete<Map<String, String>>(
                                        optionsBuilder: (TextEditingValue textEditingValue) {
                                          if (textEditingValue.text == '') {
                                            return _listaSemaforosDropdown;
                                          }
                                          return _listaSemaforosDropdown.where((Map<String, String> option) {
                                            return option['label']!.toLowerCase().contains(textEditingValue.text.toLowerCase());
                                          });
                                        },
                                        displayStringForOption: (Map<String, String> option) => option['label']!,
                                        onSelected: (Map<String, String> selection) {
                                          setState(() {
                                            _semaforoSelecionado = selection['value'];
                                            if (_semaforoSelecionado == 'DEMO') {
                                              _carregarDemo();
                                            } else {
                                              var selectedItem = _listaSemaforosDropdown.firstWhere((item) => item['value'] == _semaforoSelecionado);
                                              _subarea = selectedItem['subarea'] ?? "---";
                                              _carregarProgramacaoDoSemaforo(_semaforoSelecionado!);
                                            }
                                          });
                                        },
                                        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                                          if (_semaforoSelecionado != null && textEditingController.text.isEmpty) {
                                             var item = _listaSemaforosDropdown.firstWhere((e) => e['value'] == _semaforoSelecionado, orElse: () => {'label':''});
                                             textEditingController.text = item['label']!;
                                          }
                                          return TextField(
                                            controller: textEditingController,
                                            focusNode: focusNode,
                                            decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                              fillColor: Color(0xFFf8f9fa),
                                              filled: true,
                                              hintText: 'Pesquisar Semáforo...',
                                              suffixIcon: Icon(Icons.search),
                                            ),
                                          );
                                        },
                                        optionsViewBuilder: (context, onSelected, options) {
                                          return Align(
                                            alignment: Alignment.topLeft,
                                            child: Material(
                                              elevation: 4.0,
                                              child: ConstrainedBox(
                                                constraints: const BoxConstraints(maxHeight: 250, maxWidth: 600),
                                                child: ListView.builder(
                                                  padding: EdgeInsets.zero,
                                                  shrinkWrap: true,
                                                  itemCount: options.length,
                                                  itemBuilder: (BuildContext context, int index) {
                                                    final Map<String, String> option = options.elementAt(index);
                                                    return InkWell(
                                                      onTap: () => onSelected(option),
                                                      child: Padding(
                                                        padding: const EdgeInsets.all(12.0),
                                                        child: Text(option['label']!, style: TextStyle(fontWeight: option['value'] == 'DEMO' ? FontWeight.bold : FontWeight.normal)),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(flex: 1, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Grupos Atuais', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)), const SizedBox(height: 4), if (_grupos.isEmpty) const Text('Nenhum grupo definido', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)), ..._grupos.map((g) => Text('${g['id']}: ${g['nome']}', style: const TextStyle(fontSize: 12, color: Colors.black87)))] )),
                              Expanded(
                                flex: 1, 
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, 
                                  children: [
                                    const Text('Subárea', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)), 
                                    const SizedBox(height: 4), 
                                    if (_modoEdicao && _listaSubareas.isNotEmpty)
                                      DropdownButtonFormField<String>(
                                        value: _listaSubareas.contains(_subarea) ? _subarea : null,
                                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                        items: _listaSubareas.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                        onChanged: (val) {
                                          setState(() => _subarea = val ?? "---");
                                        }
                                      )
                                    else
                                      Text(_subarea, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue))
                                  ] 
                                )
                              ),
                              Expanded(
                                flex: 1, 
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, 
                                  children: [
                                    const Text('Última Edição', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)), 
                                    const SizedBox(height: 4), 
                                    if (_ultimaAtualizacaoFormatada.isEmpty)
                                      const Text('Nenhum registro', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey))
                                    else
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blueGrey.shade200)),
                                        child: Text(_ultimaAtualizacaoFormatada, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                                      )
                                  ] 
                                )
                              ),
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
                                  _buildCustomButton('📝 OBSERVAÇÕES', Colors.purple, _abrirModalObservacoes),
                                  _buildCustomButton('💾 SALVAR PROGRAMAÇÃO', Colors.deepPurple, _iniciarSalvamentoComMotivo),
                                ],
                                if (_existeProgramacao && !_modoEdicao) ...[
                                  _buildCustomButton('✏️ EDITAR PROGRAMAÇÃO', Colors.blueGrey, _alternarModoEdicao),
                                  _buildCustomButton('📄 EXPORTAR PDF', Colors.red, _exportarPdf),
                                  _buildCustomButton('📝 VER OBSERVAÇÕES', Colors.purple, _abrirModalObservacoes),
                                  _buildCustomButton('🗑️ ZERAR TUDO', Colors.black87, _zerarTudo),
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
                                      ...eventos.asMap().entries.map((entry) {
                                          int index = entry.key;
                                          var ev = entry.value;

                                          String planoIdEv = ev['nomePlano'].toString().replaceAll('PLANO ', '').replaceAll('MODO ', '');
                                          Color corEvento = _obterCorDoPlano(planoIdEv);
                                          
                                          String nomeExibicao = ev['nomePlano'].toString();
                                          if (nomeExibicao == 'MODO PISCANTE') nomeExibicao = 'MODO\nPISCANTE';
                                          if (nomeExibicao == 'MODO APAGADO') nomeExibicao = 'MODO\nAPAGADO';

                                          return InkWell(
                                            onTap: () {
                                              if (_modoEdicao) {
                                                _editarAgendamentoExistente(dia, index, ev);
                                              }
                                            },
                                            child: Container(
                                              margin: const EdgeInsets.all(4), padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(color: corEvento.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: corEvento.withValues(alpha: 0.5))),
                                              child: Column(children: [Text(ev['hora'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2f3b4c))), const SizedBox(height: 2), Text(nomeExibicao, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: corEvento), textAlign: TextAlign.center)]),
                                            ),
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

                    if (_planos.isNotEmpty) ...[
                      _buildSectionTitle('TEMPOS DOS PLANOS'),
                      
                      ..._planos.asMap().entries.map((entry) {
                        int index = entry.key;
                        var p = entry.value;
                        return PlanoEditorWidget(
                          plano: p,
                          gruposGlobais: _grupos,
                          modoEdicao: _modoEdicao,
                          onUpdate: () => setState(() {}),
                          onDelete: () => _excluirPlano(index),
                          onEdit: () => _abrirModalRenomearPlano(p, index),
                        );
                      }), 
                    ],

                    if (_observacoes.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildSectionTitle('OBSERVAÇÕES DO PROJETO'),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          _observacoes,
                          style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                        ),
                      ),
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