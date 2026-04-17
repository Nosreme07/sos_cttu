import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// IMPORTAÇÃO DO MENU (LOGOUT E PERFIL)
import '../../widgets/menu_usuario.dart';

class IniciarTurnoPage extends StatefulWidget {
  const IniciarTurnoPage({super.key});

  @override
  State<IniciarTurnoPage> createState() => _IniciarTurnoPageState();
}

class _IniciarTurnoPageState extends State<IniciarTurnoPage> {
  final _kmInicialController = TextEditingController();
  final _nomeController = TextEditingController(text: 'Carregando...');
  final _kmFinalController = TextEditingController();

  String? _veiculoSelecionadoId;
  String? _veiculoSelecionadoPlaca;
  String? _rotaSelecionadaNumero; 

  String _nomeVistoriador = '';
  bool _confirmouIdentidade = false; 
  bool _carregandoInicial = true;
  bool _processando = false; 
  bool _isAdmin = false;
  
  String? _turnoAtivoId;
  Map<String, dynamic>? _turnoAtivoData;

  @override
  void initState() {
    super.initState();
    _buscarDadosIniciais();
  }

  @override
  void dispose() {
    _kmInicialController.dispose();
    _kmFinalController.dispose();
    _nomeController.dispose();
    super.dispose();
  }

  Future<void> _buscarDadosIniciais() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final docUser = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
      if (docUser.exists) {
        final dataUser = docUser.data()!;
        String nomeSalvo = dataUser['nomeCompleto'] ?? dataUser['nome_completo'] ?? dataUser['nome'] ?? '';
        _nomeVistoriador = nomeSalvo.isNotEmpty ? nomeSalvo.toUpperCase() : user.email!.toUpperCase();
        String perfil = (dataUser['perfil'] ?? '').toString().toLowerCase(); 
        if (perfil.contains('admin') || perfil.contains('desenvolvedor') || perfil.contains('operador central')) {
          _isAdmin = true;
        }
      }

      if (!_isAdmin) {
        final turnoAtivoQuery = await FirebaseFirestore.instance
            .collection('turnos')
            .where('vistoriador_uid', isEqualTo: user.uid)
            .where('status', isEqualTo: 'ativo')
            .limit(1)
            .get();

        if (turnoAtivoQuery.docs.isNotEmpty) {
          _turnoAtivoId = turnoAtivoQuery.docs.first.id;
          _turnoAtivoData = turnoAtivoQuery.docs.first.data();
        }
      }

      if (mounted) {
        setState(() {
          _nomeController.text = _nomeVistoriador;
          _carregandoInicial = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _carregandoInicial = false);
    }
  }

  // ============================================================
  // LÓGICA DE ENCERRAMENTO COM ALERTA E PDF COMPLETO
  // ============================================================

  Future<void> _processarEncerramento() async {
    if (_kmFinalController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o KM Final!'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _processando = true);

    try {
      DateTime now = DateTime.now();
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime dataBase = DateTime(2024, 1, 1);
      int diasPassados = now.difference(dataBase).inDays;
      String grupoDeHoje = (diasPassados % 2 == 0) ? 'A' : 'B';
      String rotaAtiva = _turnoAtivoData!['rota_numero'].toString();

      var semaforosSnapshot = await FirebaseFirestore.instance
          .collection('semaforos')
          .where('rota', isEqualTo: rotaAtiva)
          .get();

      var semaforosMeta = semaforosSnapshot.docs.where((doc) {
        String lado = (doc.data()['lado_vistoria'] ?? doc.data()['grupo'] ?? 'A').toString().toUpperCase();
        return lado == grupoDeHoje;
      }).toList();

      var vistoriasHojeSnapshot = await FirebaseFirestore.instance
          .collection('vistoria')
          .where('criado_em', isGreaterThanOrEqualTo: startOfDay)
          .get();

      Set<String> semaforosMetaIds = semaforosMeta.map((s) => s.data()['id'].toString()).toSet();
      
      var vistoriasDaRotaHoje = vistoriasHojeSnapshot.docs.where((doc) {
        return semaforosMetaIds.contains(doc['semaforo_id'].toString());
      }).toList();

      var vistoriasDesteTurno = vistoriasDaRotaHoje.where((doc) => doc['turno_id'] == _turnoAtivoId).toList();

      Set<String> vistoriadosHojeIds = vistoriasDaRotaHoje.map((doc) => doc['semaforo_id'].toString()).toSet();

      List<Map<String, dynamic>> listaPendentes = semaforosMeta.where((doc) {
        String idSemaforo = (doc.data()['id'] ?? doc.data()['numero'] ?? '').toString();
        return !vistoriadosHojeIds.contains(idSemaforo);
      }).map((doc) => doc.data()).toList();

      int totalMeta = semaforosMeta.length;
      int realizadosHojeTotal = vistoriadosHojeIds.length;
      int pendentesGlobais = totalMeta - realizadosHojeTotal;

      if (pendentesGlobais > 0) {
        if (!mounted) return;
        bool? confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Semáforos Pendentes!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            content: Text('Atenção $_nomeVistoriador, ainda restam $pendentesGlobais semáforos para vistoriar nesta rota hoje.\n\nTem certeza que deseja encerrar o expediente mesmo assim? (Outra equipe poderá assumir o restante da rota).'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VOLTAR')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true), 
                child: const Text('SIM, ENCERRAR', style: TextStyle(color: Colors.white))
              ),
            ],
          ),
        );

        if (confirmar != true) {
          setState(() => _processando = false);
          return;
        }
      }

      await _gerarRelatorioFinalPDF(
        vistoriasDesteTurno: vistoriasDesteTurno,
        pendentesGlobais: listaPendentes,
        totalMeta: totalMeta,
        realizadosGlobais: realizadosHojeTotal,
        kmFinal: _kmFinalController.text.trim()
      );

      await _encerrarTurnoNoDB();

    } catch (e) {
      if (mounted) {
        setState(() => _processando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao encerrar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _gerarRelatorioFinalPDF({
    required List<QueryDocumentSnapshot> vistoriasDesteTurno,
    required List<Map<String, dynamic>> pendentesGlobais,
    required int totalMeta,
    required int realizadosGlobais,
    required String kmFinal,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dataHoraFim = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
    final dataHoraInicio = _turnoAtivoData!['data_inicio'] != null 
        ? DateFormat('dd/MM/yyyy HH:mm:ss').format((_turnoAtivoData!['data_inicio'] as Timestamp).toDate())
        : '---';

    double kI = double.tryParse(_turnoAtivoData!['km_inicial'].toString()) ?? 0;
    double kF = double.tryParse(kmFinal) ?? 0;
    double kTotal = kF - kI;
    double percentualGlobal = totalMeta > 0 ? (realizadosGlobais / totalMeta) * 100 : 0;

    var defeitosDoTurno = vistoriasDesteTurno.where((doc) => (doc.data() as Map)['teve_anormalidade'] == true).toList();

    String idsPendentesFormatados = pendentesGlobais.isNotEmpty 
        ? pendentesGlobais.map((p) => (p['id'] ?? p['numero'] ?? '').toString()).where((s) => s.isNotEmpty).join(' - ')
        : 'NENHUM PENDENTE';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(32),
        footer: (pw.Context context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: pw.EdgeInsets.only(top: 20),
          child: pw.Column(
            children: [
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Gerado pelo Sistema de Ocorrências Semafóricas - SOS', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  pw.Text('$dataHoraFim  -  Pág. ${context.pageNumber}/${context.pagesCount}', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ]
              ),
            ]
          )
        ),
        build: (pw.Context context) => [
          pw.Header(level: 0, child: pw.Text('RELATÓRIO DE FECHAMENTO DE EXPEDIENTE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 15),
          
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _pdfInfoRow('Rota:', _turnoAtivoData!['rota_numero'].toString()),
              _pdfInfoRow('Vistoriador:', _nomeVistoriador),
              _pdfInfoRow('Placa da Moto:', _turnoAtivoData!['placa'].toString()),
              _pdfInfoRow('Início / Fim:', '$dataHoraInicio  até  $dataHoraFim'),
              _pdfInfoRow('KM Inicial / Final:', '$kI km / $kF km (Total: ${kTotal.toStringAsFixed(1)} km)'),
            ]
          ),

          pw.SizedBox(height: 15),
          pw.Text('ESTATÍSTICA DA ROTA HOJE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _pdfStatCard('Meta Total', totalMeta.toString()),
              _pdfStatCard('Vistoriados (Geral)', realizadosGlobais.toString()),
              _pdfStatCard('Vistoriados por Você', vistoriasDesteTurno.length.toString()),
              _pdfStatCard('Pendentes (Faltam)', pendentesGlobais.length.toString()),
              _pdfStatCard('Conclusão (Geral)', '${percentualGlobal.toStringAsFixed(1)}%'),
            ]
          ),

          pw.SizedBox(height: 20),
          pw.Text('OCORRÊNCIAS LANÇADAS NESTE TURNO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.red900)),
          pw.SizedBox(height: 5),
          if (defeitosDoTurno.isEmpty)
            pw.Text('Nenhum defeito registrado neste turno.', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic))
          else
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['Semáforo', 'Falha Identificada', 'Horário'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
              headerDecoration: pw.BoxDecoration(color: PdfColors.red800),
              cellStyle: pw.TextStyle(fontSize: 9),
              data: defeitosDoTurno.map((d) {
                var val = d.data() as Map<String, dynamic>;
                return [
                  val['semaforo_id'].toString(),
                  val['falha_registrada'].toString(),
                  val['data_hora_fim'].toString().split(' ').last,
                ];
              }).toList(),
            ),

          pw.SizedBox(height: 20),
          pw.Text('SEMÁFOROS PENDENTES (NÃO VISTORIADOS HOJE)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.orange900)),
          pw.SizedBox(height: 5),
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.orange50,
              border: pw.Border.all(color: PdfColors.orange200),
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              idsPendentesFormatados,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: pendentesGlobais.isEmpty ? PdfColors.green900 : PdfColors.orange900),
            ),
          ),

          pw.SizedBox(height: 40),
          pw.Column(
            children: [
              pw.Container(width: 250, decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 1)))),
              pw.SizedBox(height: 5),
              pw.Text(_nomeVistoriador, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text('Assinatura do Vistoriador', style: pw.TextStyle(fontSize: 9)),
            ],
            mainAxisAlignment: pw.MainAxisAlignment.center
          ),
        ]
      )
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: 'Relatorio_Vistoria_${_turnoAtivoData!['rota_numero']}.pdf');
  }

  pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 4),
      child: pw.RichText(text: pw.TextSpan(style: pw.TextStyle(fontSize: 10), children: [
        pw.TextSpan(text: '$label ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TextSpan(text: value),
      ]))
    );
  }

  pw.Widget _pdfStatCard(String label, String value) {
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
      child: pw.Column(
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9)),
          pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ]
      )
    );
  }

  Future<void> _encerrarTurnoNoDB() async {
    await FirebaseFirestore.instance.collection('turnos').doc(_turnoAtivoId).update({
      'status': 'concluido',
      'km_final': _kmFinalController.text.trim(),
      'data_fim': FieldValue.serverTimestamp(),
    });

    String? idVeiculo = _turnoAtivoData!['veiculo_id'];
    if (idVeiculo != null) {
      await FirebaseFirestore.instance.collection('veiculos').doc(idVeiculo).update({'em_uso': false});
    }

    if (mounted) {
      setState(() {
        _turnoAtivoId = null;
        _turnoAtivoData = null;
        _veiculoSelecionadoId = null;
        _rotaSelecionadaNumero = null;
        _kmInicialController.clear();
        _kmFinalController.clear();
        _confirmouIdentidade = false;
        _processando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expediente encerrado e relatório gerado!'), backgroundColor: Colors.green));
    }
  }

  // ==========================================
  // WIDGET INICIAR TURNO
  // ==========================================

  Future<void> _salvarTurno() async {
    if (!_confirmouIdentidade) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirme sua identidade!'), backgroundColor: Colors.orange));
      return;
    }
    if (_veiculoSelecionadoId == null || _rotaSelecionadaNumero == null || _kmInicialController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha todos os campos!'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _processando = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final novoTurnoRef = await FirebaseFirestore.instance.collection('turnos').add({
        'vistoriador_uid': user.uid,
        'vistoriador_nome': _nomeVistoriador,
        'veiculo_id': _veiculoSelecionadoId,
        'placa': _veiculoSelecionadoPlaca,
        'km_inicial': _kmInicialController.text.trim(),
        'km_final': null,
        'rota_id': _rotaSelecionadaNumero, 
        'rota_numero': _rotaSelecionadaNumero,
        'status': 'ativo', 
        'data_inicio': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('veiculos').doc(_veiculoSelecionadoId).update({'em_uso': true});
      final turnoCriado = await novoTurnoRef.get();

      if (mounted) {
        setState(() {
          _turnoAtivoId = turnoCriado.id;
          _turnoAtivoData = turnoCriado.data();
          _processando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _processando = false);
    }
  }

  Widget _buildVisaoIniciarTurno() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.motorcycle, size: 60, color: Colors.teal),
          const SizedBox(height: 24),
          const Text('Vistoriador Responsável:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _nomeController, readOnly: true, decoration: InputDecoration(border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.person), filled: true, fillColor: Colors.grey.shade200)),
          CheckboxListTile(title: const Text('Confirmo que sou o vistoriador acima.'), value: _confirmouIdentidade, activeColor: Colors.teal, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, onChanged: (v) => setState(() => _confirmouIdentidade = v ?? false)),
          const SizedBox(height: 20),
          const Text('Moto Disponível:', style: TextStyle(fontWeight: FontWeight.bold)),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('veiculos').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              var veiculos = snapshot.data!.docs.where((d) {
                var data = d.data() as Map<String, dynamic>;
                return data['em_uso'] != true && (data['tipo']?.toString().toLowerCase() == 'moto' || data['tipo_veiculo']?.toString().toLowerCase() == 'moto'); 
              }).toList();
              
              if (veiculos.isEmpty) return const Text('Nenhuma moto disponível.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold));
              veiculos.sort((a, b) => (a.data() as Map)['placa'].toString().compareTo((b.data() as Map)['placa'].toString()));

              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.motorcycle)),
                hint: const Text('Escolha uma placa...'),
                initialValue: _veiculoSelecionadoId,
                items: veiculos.map((v) => DropdownMenuItem(value: v.id, child: Text((v.data() as Map)['placa']))).toList(),
                onChanged: (v) => setState(() { _veiculoSelecionadoId = v; _veiculoSelecionadoPlaca = (veiculos.firstWhere((d) => d.id == v).data() as Map)['placa']; }),
              );
            }
          ),
          const SizedBox(height: 20),
          const Text('KM Inicial:', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: _kmInicialController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.speed), suffixText: 'km')),
          const SizedBox(height: 20),
          const Text('Rota Disponível:', style: TextStyle(fontWeight: FontWeight.bold)),
          
          // TRAVA DAS ROTAS DISPONÍVEIS REVISADA
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('turnos').where('status', isEqualTo: 'ativo').snapshots(),
            builder: (context, snapshotTurnos) {
              if (!snapshotTurnos.hasData) return const LinearProgressIndicator();
              Set emUso = snapshotTurnos.data!.docs.map((d) => (d.data() as Map)['rota_numero'].toString().replaceFirst(RegExp(r'^0+'), '')).toSet();
              
              DateTime now = DateTime.now();
              DateTime startOfDay = DateTime(now.year, now.month, now.day);

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('vistoria').where('criado_em', isGreaterThanOrEqualTo: startOfDay).snapshots(),
                builder: (context, snapshotVistorias) {
                  if (!snapshotVistorias.hasData) return const LinearProgressIndicator();

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('semaforos').get().asStream(),
                    builder: (context, snapshotSemaforos) {
                      if (!snapshotSemaforos.hasData) return const LinearProgressIndicator();

                      DateTime dataBase = DateTime(2024, 1, 1);
                      int diasPassados = DateTime.now().difference(dataBase).inDays;
                      String grupoDeHoje = (diasPassados % 2 == 0) ? 'A' : 'B';

                      Map<String, int> metaPorRota = {};
                      Map<String, String> rotaDoSemaforo = {};

                      for (var doc in snapshotSemaforos.data!.docs) {
                        var data = doc.data() as Map<String, dynamic>;
                        String rota = data['rota']?.toString().trim().replaceFirst(RegExp(r'^0+'), '') ?? '';
                        String id = (data['id'] ?? data['numero'])?.toString() ?? '';
                        String lado = (data['lado_vistoria'] ?? data['grupo'] ?? 'A').toString().toUpperCase();

                        if (rota.isNotEmpty && id.isNotEmpty) {
                          rotaDoSemaforo[id] = rota;
                          if (lado == grupoDeHoje) {
                            metaPorRota[rota] = (metaPorRota[rota] ?? 0) + 1;
                          }
                        }
                      }

                      Map<String, Set<String>> vistoriasPorRota = {};
                      for (var doc in snapshotVistorias.data!.docs) {
                        var data = doc.data() as Map<String, dynamic>;
                        String idSem = data['semaforo_id']?.toString() ?? '';
                        String rota = rotaDoSemaforo[idSem] ?? '';
                        if (rota.isNotEmpty) {
                          vistoriasPorRota.putIfAbsent(rota, () => {}).add(idSem);
                        }
                      }

                      List<String> rotasList = [];
                      metaPorRota.forEach((rota, meta) {
                        int concluidos = vistoriasPorRota[rota]?.length ?? 0;
                        if (!emUso.contains(rota) && concluidos < meta) {
                          rotasList.add(rota);
                        }
                      });

                      rotasList.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

                      if (rotasList.isEmpty) {
                        return const Text('Todas as rotas do dia já foram concluídas ou estão em andamento.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold));
                      }

                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.route)),
                        hint: const Text('Escolha uma rota...'),
                        initialValue: rotasList.contains(_rotaSelecionadaNumero) ? _rotaSelecionadaNumero : null,
                        items: rotasList.map((r) => DropdownMenuItem(value: r, child: Text('Rota $r'))).toList(),
                        onChanged: (v) => setState(() => _rotaSelecionadaNumero = v),
                      );
                    }
                  );
                }
              );
            }
          ),
          const SizedBox(height: 40),
          SizedBox(height: 55, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white), onPressed: _processando ? null : _salvarTurno, child: _processando ? const CircularProgressIndicator(color: Colors.white) : const Text('INICIAR VISTORIA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }

  // ==========================================
  // VISÃO DO VISTORIADOR: ENCERRAR TURNO
  // ==========================================
  Widget _buildVisaoEncerrarTurno() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle, size: 60, color: Colors.green),
          const SizedBox(height: 16),
          const Text('Turno em andamento!', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
          const SizedBox(height: 32),
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(children: [
                ListTile(leading: const Icon(Icons.route, color: Colors.teal), title: const Text('Rota'), subtitle: Text(_turnoAtivoData!['rota_numero'].toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                const Divider(),
                ListTile(leading: const Icon(Icons.motorcycle, color: Colors.teal), title: const Text('Moto'), subtitle: Text(_turnoAtivoData!['placa'].toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                const Divider(),
                ListTile(leading: const Icon(Icons.speed, color: Colors.teal), title: const Text('KM Inicial'), subtitle: Text('${_turnoAtivoData!['km_inicial']} km', style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
            ),
          ),
          const SizedBox(height: 32),
          const Text('Informe o KM Final:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _kmFinalController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.speed), suffixText: 'km')),
          const SizedBox(height: 32),
          SizedBox(height: 55, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white), icon: _processando ? const SizedBox.shrink() : const Icon(Icons.stop_circle), label: _processando ? const CircularProgressIndicator(color: Colors.white) : const Text('ENCERRAR EXPEDIENTE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), onPressed: _processando ? null : _processarEncerramento)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregandoInicial) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    return Scaffold(
      appBar: AppBar(title: const Text('Meu Expediente'), backgroundColor: Colors.teal.shade400, foregroundColor: Colors.white, actions: const [MenuUsuario()]),
      body: _turnoAtivoId != null ? _buildVisaoEncerrarTurno() : _buildVisaoIniciarTurno(), 
    );
  }
}