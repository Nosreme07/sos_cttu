import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class IniciarTurnoPage extends StatefulWidget {
  const IniciarTurnoPage({super.key});

  @override
  State<IniciarTurnoPage> createState() => _IniciarTurnoPageState();
}

class _IniciarTurnoPageState extends State<IniciarTurnoPage> {
  // Controles Iniciar Turno
  final _kmInicialController = TextEditingController();
  final _nomeController = TextEditingController(text: 'Carregando...');
  
  // Controles Encerrar Turno
  final _kmFinalController = TextEditingController();

  String? _veiculoSelecionadoId;
  String? _veiculoSelecionadoPlaca;
  String? _rotaSelecionadaNumero; 

  String _nomeVistoriador = '';
  bool _confirmouIdentidade = false; 
  
  // Gerenciamento de Estado da Tela
  bool _carregandoInicial = true;
  bool _processando = false; 
  bool _isAdmin = false;
  
  // Dados do Turno Ativo (se o vistoriador já tiver um)
  String? _turnoAtivoId;
  Map<String, dynamic>? _turnoAtivoData;

  // ==== FILTROS DA ABA ADMIN (CONCLUÍDOS) ====
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  String _rotaFiltro = 'Todas';

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
        
        // AJUSTE FINO: Puxando o nome do usuário com várias possibilidades de nomenclatura no banco
        String nomeSalvo = dataUser['nomeCompleto'] ?? dataUser['nome_completo'] ?? dataUser['nome'] ?? '';
        _nomeVistoriador = nomeSalvo.isNotEmpty ? nomeSalvo : user.email!;
        
        String perfil = (dataUser['perfil'] ?? '').toString().toLowerCase(); 
        
        if (perfil.contains('administrador') || perfil.contains('admin')) {
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

      setState(() {
        _nomeController.text = _nomeVistoriador;
        _carregandoInicial = false;
      });
      
    } catch (e) {
      debugPrint('Erro ao carregar dados iniciais: $e');
      setState(() => _carregandoInicial = false);
    }
  }

  Future<void> _salvarTurno() async {
    if (!_confirmouIdentidade) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, marque a caixa confirmando sua identidade!'), backgroundColor: Colors.orange));
      return;
    }

    if (_veiculoSelecionadoId == null || _rotaSelecionadaNumero == null || _kmInicialController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha todos os campos obrigatórios!'), backgroundColor: Colors.red));
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

      // Atualiza apenas a moto para "em uso"
      await FirebaseFirestore.instance.collection('veiculos').doc(_veiculoSelecionadoId).update({'em_uso': true});

      final turnoCriado = await novoTurnoRef.get();
      setState(() {
        _turnoAtivoId = turnoCriado.id;
        _turnoAtivoData = turnoCriado.data();
        _processando = false;
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turno Iniciado com sucesso! Boa vistoria.'), backgroundColor: Colors.green));
    } catch (e) {
      setState(() => _processando = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao iniciar turno: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _encerrarTurno() async {
    if (_kmFinalController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe a Quilometragem (KM) Final!'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _processando = true);

    try {
      await FirebaseFirestore.instance.collection('turnos').doc(_turnoAtivoId).update({
        'status': 'concluido',
        'km_final': _kmFinalController.text.trim(),
        'data_fim': FieldValue.serverTimestamp(),
      });

      // Libera apenas a moto
      String? idVeiculo = _turnoAtivoData!['veiculo_id'];
      if (idVeiculo != null) {
        await FirebaseFirestore.instance.collection('veiculos').doc(idVeiculo).update({'em_uso': false});
      }

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

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turno Encerrado com sucesso! Excelente trabalho.'), backgroundColor: Colors.green));
    } catch (e) {
      setState(() => _processando = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao encerrar turno: $e'), backgroundColor: Colors.red));
    }
  }

  // ==========================================
  // FUNÇÕES DE EXPORTAÇÃO E FILTRO (ADMIN)
  // ==========================================
  Future<void> _selecionarData(BuildContext context, bool isInicio) async {
    DateTime initial = DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: isInicio ? 'SELECIONE A DATA INICIAL' : 'SELECIONE A DATA FINAL',
    );

    if (picked != null) {
      setState(() {
        if (isInicio) {
          _dataInicioFiltro = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        } else {
          _dataFimFiltro = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
  }

  Widget _buildBotaoData(String label, DateTime? data, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.teal.shade200), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 18, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data == null ? label : DateFormat('dd/MM/yy').format(data),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: data == null ? Colors.grey : Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportarPDFTurnos(List<DocumentSnapshot> turnos) async {
    if (turnos.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando PDF...'), backgroundColor: Colors.teal));
    
    try {
      final pdf = pw.Document();
      String dataHoraAtual = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          footer: (pw.Context context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount} - Gerado em $dataHoraAtual', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))
          ),
          build: (pw.Context context) {
            return [
              pw.Header(level: 0, child: pw.Text('Relatório de Expedientes Concluídos', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                context: context,
                headers: ['Vistoriador', 'Rota', 'Moto', 'Início', 'Fim', 'KM Inicial', 'KM Final'],
                data: turnos.map((doc) {
                  var t = doc.data() as Map<String, dynamic>;
                  String inicio = t['data_inicio'] != null ? DateFormat('dd/MM/yy HH:mm').format((t['data_inicio'] as Timestamp).toDate()) : '-';
                  String fim = t['data_fim'] != null ? DateFormat('dd/MM/yy HH:mm').format((t['data_fim'] as Timestamp).toDate()) : '-';
                  return [
                    t['vistoriador_nome'] ?? '-', 
                    t['rota_numero'] ?? '-', 
                    t['placa'] ?? '-', 
                    inicio, 
                    fim, 
                    t['km_inicial']?.toString() ?? '-', 
                    t['km_final']?.toString() ?? '-'
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
                cellAlignment: pw.Alignment.centerLeft, cellStyle: const pw.TextStyle(fontSize: 9),
              ),
            ];
          }
        )
      );
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Turnos_Concluidos.pdf');
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar PDF!'), backgroundColor: Colors.red));
    }
  }

  Future<void> _exportarXLSTurnos(List<DocumentSnapshot> turnos) async {
    if (turnos.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gerando Excel...'), backgroundColor: Colors.green));
    try {
      String csv = '\uFEFF'; 
      csv += 'VISTORIADOR;ROTA;MOTO;INICIO;FIM;KM INICIAL;KM FINAL\n';
      
      for (var doc in turnos) {
        var t = doc.data() as Map<String, dynamic>;
        String inicio = t['data_inicio'] != null ? DateFormat('dd/MM/yy HH:mm').format((t['data_inicio'] as Timestamp).toDate()) : '-';
        String fim = t['data_fim'] != null ? DateFormat('dd/MM/yy HH:mm').format((t['data_fim'] as Timestamp).toDate()) : '-';
        
        csv += '${t['vistoriador_nome']};${t['rota_numero']};${t['placa']};$inicio;$fim;${t['km_inicial']};${t['km_final']}\n';
      }
      
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/Turnos_Concluidos.xls';
      final file = File(path);
      await file.writeAsBytes(utf8.encode(csv));
      await Share.shareXFiles([XFile(path)], text: 'Planilha de Turnos Concluídos');
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao gerar Excel!'), backgroundColor: Colors.red));
    }
  }


  // ==========================================
  // ABA 1 DO ADMIN: EM ANDAMENTO
  // ==========================================
  Widget _buildAbaEmAndamento() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.teal.shade50,
          child: const Column(
            children: [
              Icon(Icons.directions_run, size: 48, color: Colors.teal),
              SizedBox(height: 8),
              Text('Vistoriadores em Rota', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
              Text('Acompanhamento em tempo real', style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('turnos').where('status', isEqualTo: 'ativo').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.red), textAlign: TextAlign.center,));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              final turnos = snapshot.data!.docs.toList();
              
              turnos.sort((a, b) {
                var dataA = a.data() as Map<String, dynamic>;
                var dataB = b.data() as Map<String, dynamic>;
                Timestamp? tempoA = dataA['data_inicio'] as Timestamp?;
                Timestamp? tempoB = dataB['data_inicio'] as Timestamp?;
                if (tempoA == null && tempoB == null) return 0;
                if (tempoA == null) return 1;
                if (tempoB == null) return -1;
                return tempoB.compareTo(tempoA); 
              });

              if (turnos.isEmpty) return const Center(child: Text('Nenhum vistoriador em campo no momento.', style: TextStyle(color: Colors.grey, fontSize: 16)));

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: turnos.length,
                itemBuilder: (context, index) {
                  final t = turnos[index].data() as Map<String, dynamic>;
                  String horaInicio = t['data_inicio'] != null ? DateFormat('dd/MM/yy - HH:mm').format((t['data_inicio'] as Timestamp).toDate()) : 'Aguardando...';

                  return Card(
                    elevation: 2, margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.teal.shade100, child: const Icon(Icons.person, color: Colors.teal)),
                      title: Text(t['vistoriador_nome'] ?? 'Desconhecido', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('Rota: ${t['rota_numero'] ?? 'S/R'} | Moto: ${t['placa'] ?? 'S/P'}'),
                          Text('Início: $horaInicio', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        ],
                      ),
                      trailing: const Icon(Icons.motorcycle, color: Colors.teal),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

// ==========================================
  // ABA 2 DO ADMIN: CONCLUÍDOS (À PROVA DE FALHAS)
  // ==========================================
  Widget _buildAbaConcluidos() {
    return Column(
      children: [
        // Painel de Filtros e Botões
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  _buildBotaoData('Data Inicial', _dataInicioFiltro, () => _selecionarData(context, true)),
                  const SizedBox(width: 8),
                  _buildBotaoData('Data Final', _dataFimFiltro, () => _selecionarData(context, false)),
                ],
              ),
              const SizedBox(height: 12),
              
              // Dropdown de Rotas (Agora lendo de semaforos)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('semaforos').snapshots(),
                builder: (context, snapshot) {
                  List<String> rotasDisponiveis = ['Todas'];
                  if (snapshot.hasData) {
                    Set<String> rotasUnicas = {};
                    for (var doc in snapshot.data!.docs) {
                      var data = doc.data() as Map<String, dynamic>;
                      // ASSUMINDO QUE O CAMPO NO BANCO SE CHAMA 'rota'
                      if (data['rota'] != null && data['rota'].toString().isNotEmpty) {
                        rotasUnicas.add(data['rota'].toString().trim());
                      }
                    }
                    List<String> listaOrdenada = rotasUnicas.toList()..sort((a, b) => a.compareTo(b));
                    rotasDisponiveis.addAll(listaOrdenada);
                  }
                  
                  return InputDecorator(
                    decoration: InputDecoration(labelText: 'Filtrar por Rota', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: rotasDisponiveis.contains(_rotaFiltro) ? _rotaFiltro : 'Todas',
                        items: rotasDisponiveis.map((r) => DropdownMenuItem(value: r, child: Text(r == 'Todas' ? 'Todas as Rotas' : 'Rota $r'))).toList(),
                        onChanged: (val) => setState(() => _rotaFiltro = val!),
                      ),
                    ),
                  );
                }
              ),
              const SizedBox(height: 12),
              if (_dataInicioFiltro != null || _dataFimFiltro != null || _rotaFiltro != 'Todas')
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Limpar Filtros'),
                    onPressed: () => setState(() { _dataInicioFiltro = null; _dataFimFiltro = null; _rotaFiltro = 'Todas'; }),
                  ),
                ),
            ],
          ),
        ),
        
        // Lista de Concluídos
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('turnos').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              // Filtro 100% Local (Garante que vai achar o "finalizado")
              var turnosFiltrados = snapshot.data!.docs.where((doc) {
                var t = doc.data() as Map<String, dynamic>;
                
                // 1. Filtro de Status
                String status = (t['status'] ?? '').toString().toLowerCase().trim();
                if (status != 'finalizado' && status != 'concluido') return false;
                
                // 2. Filtro Rota (Ignorando zeros à esquerda pra evitar conflito 01 vs 1)
                String rotaDb = (t['rota_numero'] ?? '').toString().replaceFirst(RegExp(r'^0+'), '');
                String filtroLimpo = _rotaFiltro.replaceFirst(RegExp(r'^0+'), '');
                if (_rotaFiltro != 'Todas' && rotaDb != filtroLimpo) return false;
                
                // 3. Filtro Data (pela data final do turno)
                if (_dataInicioFiltro != null || _dataFimFiltro != null) {
                  if (t['data_fim'] == null) return false;
                  DateTime dataFim = (t['data_fim'] as Timestamp).toDate();
                  
                  if (_dataInicioFiltro != null && dataFim.isBefore(_dataInicioFiltro!)) return false;
                  if (_dataFimFiltro != null && dataFim.isAfter(_dataFimFiltro!)) return false;
                }
                return true;
              }).toList();

              turnosFiltrados.sort((a, b) {
                Timestamp? tempoA = (a.data() as Map)['data_fim'] as Timestamp?;
                Timestamp? tempoB = (b.data() as Map)['data_fim'] as Timestamp?;
                if (tempoA == null && tempoB == null) return 0;
                if (tempoA == null) return 1;
                if (tempoB == null) return -1;
                return tempoB.compareTo(tempoA); 
              });

              return Column(
                children: [
                  Container(
                    color: Colors.grey.shade200, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total: ${turnosFiltrados.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        Row(
                          children: [
                            IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.red), tooltip: 'Exportar PDF', onPressed: turnosFiltrados.isEmpty ? null : () => _exportarPDFTurnos(turnosFiltrados)),
                            IconButton(icon: const Icon(Icons.grid_on, color: Colors.green), tooltip: 'Exportar Excel', onPressed: turnosFiltrados.isEmpty ? null : () => _exportarXLSTurnos(turnosFiltrados)),
                          ],
                        )
                      ],
                    ),
                  ),
                  Expanded(
                    child: turnosFiltrados.isEmpty
                      ? const Center(child: Text('Nenhum turno concluído encontrado com estes filtros.', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: turnosFiltrados.length,
                          itemBuilder: (context, index) {
                            final t = turnosFiltrados[index].data() as Map<String, dynamic>;
                            String horaFim = t['data_fim'] != null ? DateFormat('dd/MM/yy HH:mm').format((t['data_fim'] as Timestamp).toDate()) : '-';
                            String kmRodado = 'N/A';
                            
                            try {
                              if (t['km_inicial'] != null && t['km_final'] != null) {
                                double kI = double.parse(t['km_inicial'].toString());
                                double kF = double.parse(t['km_final'].toString());
                                kmRodado = '${(kF - kI).toStringAsFixed(1)} km rodados';
                              }
                            } catch (_) {}

                            return Card(
                              elevation: 1, margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: Colors.grey.shade300, child: const Icon(Icons.check, color: Colors.green)),
                                title: Text(t['vistoriador_nome'] ?? 'Desconhecido', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('Rota: ${t['rota_numero'] ?? 'S/R'} | Moto: ${t['placa'] ?? 'S/P'}', style: const TextStyle(color: Colors.black87)),
                                    Text('Encerrado: $horaFim', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                  ],
                                ),
                                trailing: Text(kmRodado, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12)),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // VISÃO DO VISTORIADOR: INICIAR TURNO
  // ==========================================
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
          TextField(
            controller: _nomeController,
            readOnly: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person),
              filled: true,
              fillColor: Colors.grey.shade200, 
            ),
          ),
          CheckboxListTile(
            title: const Text('Confirmo que sou o vistoriador acima e estou assumindo esta rota.'),
            value: _confirmouIdentidade,
            activeColor: Colors.teal,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (bool? value) {
              setState(() {
                _confirmouIdentidade = value ?? false;
              });
            },
          ),
          const SizedBox(height: 20),
          
          const Text('Selecione a Moto Disponível:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('veiculos').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('Erro ao carregar veículos: ${snapshot.error}', style: const TextStyle(color: Colors.red));
              if (!snapshot.hasData) return const LinearProgressIndicator();
              
              // AJUSTE FINO: Mostra apenas veículos que não estão em uso E que são do tipo 'moto'
              var veiculos = snapshot.data!.docs.where((doc) {
                var data = doc.data() as Map<String, dynamic>;
                
                bool naoEstaEmUso = data['em_uso'] != true;
                
                String tipoVeiculo = (data['tipo'] ?? data['tipo_veiculo'] ?? '').toString().toLowerCase().trim();
                bool eMoto = tipoVeiculo == 'moto' || tipoVeiculo == 'motocicleta';
                
                return naoEstaEmUso && eMoto; 
              }).toList();
              
              if (veiculos.isEmpty) return const Text('Todas as motos estão em uso ou não há motos cadastradas.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold));

              veiculos.sort((a, b) {
                var dataA = a.data() as Map<String, dynamic>;
                var dataB = b.data() as Map<String, dynamic>;
                return (dataA['placa'] ?? '').toString().compareTo((dataB['placa'] ?? '').toString());
              });

              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.motorcycle)),
                hint: const Text('Escolha uma placa...'),
                value: _veiculoSelecionadoId,
                items: veiculos.map((doc) {
                  var v = doc.data() as Map<String, dynamic>;
                  return DropdownMenuItem(
                    value: doc.id,
                    child: Text("${v['placa']} - ${v['modelo'] ?? ''}"),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _veiculoSelecionadoId = val;
                    _veiculoSelecionadoPlaca = (veiculos.firstWhere((d) => d.id == val).data() as Map<String, dynamic>)['placa'];
                  });
                },
              );
            }
          ),
          const SizedBox(height: 20),

          const Text('Quilometragem (KM) Inicial:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _kmInicialController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.speed),
              hintText: 'Ex: 12500',
              suffixText: 'km'
            ),
          ),
          const SizedBox(height: 20),

          const Text('Selecione a Rota Disponível:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('semaforos').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('Erro ao carregar rotas: ${snapshot.error}', style: const TextStyle(color: Colors.red));
              if (!snapshot.hasData) return const LinearProgressIndicator();
              
              Set<String> rotasUnicas = {};
              for (var doc in snapshot.data!.docs) {
                var data = doc.data() as Map<String, dynamic>;
                if (data['rota'] != null && data['rota'].toString().isNotEmpty) {
                  rotasUnicas.add(data['rota'].toString().trim());
                }
              }
              
              List<String> rotas = rotasUnicas.toList();
              
              if (rotas.isEmpty) return const Text('Nenhuma rota encontrada nos cadastros.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold));

              rotas.sort((a, b) => a.compareTo(b));

              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.route)),
                hint: const Text('Escolha uma rota...'),
                value: _rotaSelecionadaNumero,
                items: rotas.map((r) {
                  return DropdownMenuItem(
                    value: r,
                    child: Text("Rota $r"),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _rotaSelecionadaNumero = val;
                  });
                },
              );
            }
          ),
          const SizedBox(height: 40),

          SizedBox(
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
              onPressed: _processando ? null : _salvarTurno,
              child: _processando 
                ? const CircularProgressIndicator(color: Colors.white) 
                : const Text('INICIAR VISTORIA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  // ==========================================
  // VISÃO DO VISTORIADOR: ENCERRAR TURNO (ATIVO)
  // ==========================================
  Widget _buildVisaoEncerrarTurno() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle, size: 60, color: Colors.green),
          const SizedBox(height: 16),
          const Text('Você possui um turno em andamento!', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
          const SizedBox(height: 32),
          
          Card(
            color: Colors.green.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.green.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person, color: Colors.teal),
                    title: const Text('Vistoriador', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text(_turnoAtivoData!['vistoriador_nome'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.route, color: Colors.teal),
                    title: const Text('Rota Assumida', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text('Rota ${_turnoAtivoData!['rota_numero']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.motorcycle, color: Colors.teal),
                    title: const Text('Veículo (Placa)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text(_turnoAtivoData!['placa'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.speed, color: Colors.teal),
                    title: const Text('KM Inicial', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text('${_turnoAtivoData!['km_inicial']} km', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          const Text('Para concluir seu expediente, informe a quilometragem atual da moto:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _kmFinalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.speed),
              labelText: 'KM Final',
              hintText: 'Ex: 12550',
              suffixText: 'km'
            ),
          ),
          const SizedBox(height: 32),

          SizedBox(
            height: 55,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
              icon: _processando ? const SizedBox.shrink() : const Icon(Icons.stop_circle),
              label: _processando 
                ? const CircularProgressIndicator(color: Colors.white) 
                : const Text('ENCERRAR EXPEDIENTE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: _processando ? null : _encerrarTurno,
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregandoInicial) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // SE O USUÁRIO FOR ADMINISTRADOR -> Mostra o painel com as abas (Em Andamento / Concluídos)
    if (_isAdmin) {
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Monitoramento de Turnos', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.teal.shade500,
            foregroundColor: Colors.white,
            bottom: const TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(icon: Icon(Icons.directions_run), text: 'Em Andamento'),
                Tab(icon: Icon(Icons.history), text: 'Concluídos'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _buildAbaEmAndamento(),
              _buildAbaConcluidos(),
            ],
          ),
        ),
      );
    } 
    
    // SE O USUÁRIO FOR VISTORIADOR -> Mostra a tela simples (Iniciar ou Encerrar Turno)
    else {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Meu Expediente'),
          backgroundColor: Colors.teal.shade400,
          foregroundColor: Colors.white,
        ),
        body: _turnoAtivoId != null
            ? _buildVisaoEncerrarTurno() 
            : _buildVisaoIniciarTurno(), 
      );
    }
  }
}