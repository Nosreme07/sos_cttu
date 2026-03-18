import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../widgets/menu_usuario.dart';

class TelaMapaOcorrencias extends StatefulWidget {
  const TelaMapaOcorrencias({super.key});

  @override
  State<TelaMapaOcorrencias> createState() => _TelaMapaOcorrenciasState();
}

class _TelaMapaOcorrenciasState extends State<TelaMapaOcorrencias> {
  final MapController _mapController = MapController();
  final LatLng _centroPadrao = const LatLng(-8.047, -34.877);

  // Filtros
  bool _fStatusAberto = true;
  bool _fStatusDesloc = true;
  bool _fStatusAtend = true;
  bool _fPrioAlta = true;
  bool _fPrioMedia = true;
  bool _fPrioBaixa = true;
  bool _fMais24h = false;
  bool _fForaPrazo = false;
  String _filtroEmpresa = 'TODAS';

  List<String> _empresasOptions = ['TODAS'];
  Map<String, String> _mapaPrioridades = {};

  // Dados brutos baixados do Firebase
  List<QueryDocumentSnapshot> _todasOcorrencias = [];
  List<QueryDocumentSnapshot> _todasEquipes = [];

  @override
  void initState() {
    super.initState();
    _carregarAuxiliares();
  }

  Future<void> _carregarAuxiliares() async {
    final f = await FirebaseFirestore.instance.collection('falhas').get();
    Map<String, String> prios = {};
    for (var doc in f.docs) {
      prios[doc['tipo_da_falha'] ?? ''] = doc['prioridade_da_falha'] ?? 'BAIXA';
    }
    setState(() => _mapaPrioridades = prios);
  }

  void _atualizarListaEmpresas() {
    Set<String> emps = {};
    for (var oc in _todasOcorrencias) {
      String e =
          (oc.data() as Map<String, dynamic>)['empresa_responsavel'] ?? '';
      if (e.isNotEmpty) emps.add(e);
    }
    List<String> lista = emps.toList()..sort();
    lista.insert(0, 'TODAS');
    if (_empresasOptions.length != lista.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _empresasOptions = lista);
      });
    }
  }

  LatLng? _parseLatLng(String? geo) {
    if (geo == null || geo.isEmpty) return null;
    var partes = geo.trim().split(RegExp(r'[\s,]+'));
    if (partes.length >= 2) {
      double? lat = double.tryParse(partes[0]);
      double? lng = double.tryParse(partes[1]);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return null;
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

  // --- FILTRO GIGANTE DO MAPA ---
  bool _passouNoFiltro(Map<String, dynamic> data) {
    String st = (data['status'] ?? 'aberto').toString().toLowerCase();
    if (st.contains('conclu') || st.contains('finaliz'))
      return false; // Nunca mostra os finalizados no mapa

    bool statusOK = false;
    if (st.contains('deslocamento') && _fStatusDesloc)
      statusOK = true;
    else if (st.contains('atendimento') && _fStatusAtend)
      statusOK = true;
    else if ((st.contains('aberto') || st.contains('pendente')) &&
        _fStatusAberto)
      statusOK = true;
    if (!statusOK) return false;

    String prio = (_mapaPrioridades[data['tipo_da_falha']] ?? 'BAIXA')
        .toLowerCase();
    bool prioOK = false;
    if (prio.contains('alta') && _fPrioAlta)
      prioOK = true;
    else if ((prio.contains('med') || prio.contains('méd')) && _fPrioMedia)
      prioOK = true;
    else if (prio.contains('baixa') && _fPrioBaixa)
      prioOK = true;
    if (!prioOK) return false;

    if (_filtroEmpresa != 'TODAS' &&
        data['empresa_responsavel'] != _filtroEmpresa)
      return false;
    if (_fMais24h && !_maisDe24h(data['data_de_abertura'])) return false;
    if (_fForaPrazo &&
        !_estaForaDoPrazo(data['data_de_abertura'], data['prazo']))
      return false;

    return true;
  }

  // =================================================================================
  // LÓGICA DE AÇÕES (MODAIS)
  // =================================================================================

  void _atribuirEquipe(String docIdOcorrencia) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final equipesAtivas = _todasEquipes
            .where((e) => (e.data() as Map)['status'] == 'ativo')
            .toList();
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
              if (equipesAtivas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nenhuma equipe ATIVA encontrada no momento.'),
                )
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
                            .doc(docIdOcorrencia)
                            .update({
                              'equipe_atrelada': nomeLider,
                              'equipe_responsavel': nomeLider,
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

  void _abrirDetalhes(String docId, Map<String, dynamic> data) {
    String st = (data['status'] ?? 'aberto').toString().toLowerCase();
    Color corBase = Colors.redAccent;
    if (st.contains('deslocamento')) corBase = Colors.orange;
    if (st.contains('atendimento')) corBase = Colors.green;

    String prioridade = _mapaPrioridades[data['tipo_da_falha']] ?? 'MÉDIA';

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
                    'Ocorrência - ${data['semaforo']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: corBase,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    data['status'] ?? 'ABERTO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('Endereço', data['endereco']),
            _buildInfoRow('Falha', data['tipo_da_falha']),
            _buildInfoRow('Prioridade', prioridade),
            _buildInfoRow('Detalhes', data['detalhes']),
            _buildInfoRow(
              'Prazo Limite',
              _calcularPrazo(data['data_de_abertura'], data['prazo']),
            ),
            const SizedBox(height: 15),

            // BOTÕES DE AÇÃO BASEADOS NO STATUS
            if (st.contains('atendimento')) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Finalização completa na tela "Lista de Ocorrências"!',
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Finalizar Atendimento',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _atribuirEquipe(docId);
                },
                child: const Text(
                  'Trocar Equipe',
                  style: TextStyle(color: Colors.black87),
                ),
              ),
            ] else if (st.contains('deslocamento')) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () {
                  Navigator.pop(context);
                  _registrarChegada(docId);
                },
                child: const Text(
                  'Informar Chegada (Iniciar Atendimento)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _atribuirEquipe(docId);
                },
                child: const Text(
                  'Trocar Equipe',
                  style: TextStyle(color: Colors.black87),
                ),
              ),
            ] else ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () {
                  Navigator.pop(context);
                  _atribuirEquipe(docId);
                },
                child: const Text(
                  'Atribuir Equipe Responsável',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),
            TextButton.icon(
              icon: const Icon(Icons.directions_car, color: Colors.blueGrey),
              label: const Text(
                'Navegar com Waze',
                style: TextStyle(color: Colors.blueGrey),
              ),
              onPressed: () async {
                LatLng? c = _parseLatLng(data['georeferencia']);
                if (c != null) {
                  final url = Uri.parse(
                    'https://waze.com/ul?ll=${c.latitude},${c.longitude}&navigate=yes',
                  );
                  launchUrl(url, mode: LaunchMode.externalApplication);
                }
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
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            TextSpan(text: (value ?? '---').toString()),
          ],
        ),
      ),
    );
  }

  // =================================================================================
  // SIDEBAR WIDGETS
  // =================================================================================

  Widget _buildSidebarPendentes() {
    final pendentes = _todasOcorrencias.where((doc) {
      var d = doc.data() as Map<String, dynamic>;
      String st = (d['status'] ?? '').toLowerCase();
      bool isAberto =
          st.contains('aberto') ||
          st.contains('pendente') ||
          st.contains('aguardando');
      String eq = (d['equipe_responsavel'] ?? d['equipe_atrelada'] ?? '')
          .toString()
          .trim();
      return isAberto && (eq.isEmpty || eq == '-' || eq == 'null');
    }).toList();

    if (pendentes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Nenhuma ocorrência aguardando.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pendentes.length,
      itemBuilder: (context, index) {
        var d = pendentes[index].data() as Map<String, dynamic>;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: const Border(
            left: BorderSide(color: Colors.redAccent, width: 4),
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 4,
            ),
            title: Text(
              '🚦 ${d['semaforo']} - ${d['tipo_da_falha']}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            subtitle: Text(
              d['endereco'] ?? '',
              style: const TextStyle(fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(60, 30),
              ),
              onPressed: () => _atribuirEquipe(pendentes[index].id),
              child: const Text(
                'Atribuir',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            onTap: () {
              LatLng? c = _parseLatLng(d['georeferencia']);
              if (c != null) _mapController.move(c, 17);
            },
          ),
        );
      },
    );
  }

  Widget _buildSidebarEquipes() {
    final ativas = _todasEquipes
        .where((e) => (e.data() as Map)['status'] == 'ativo')
        .toList();
    if (ativas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Nenhuma equipe em campo no momento.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: ativas.length,
      itemBuilder: (context, index) {
        var eq = ativas[index].data() as Map<String, dynamic>;
        String placa = eq['placa'] ?? 'S/ PLACA';
        String nomeLider = (eq['integrantes_str'] ?? '')
            .toString()
            .split(',')
            .first
            .trim()
            .toUpperCase();
        if (nomeLider.isEmpty) nomeLider = "Equipe $placa";

        // Filtra as ocorrências que pertencem a esta equipe
        final tarefas = _todasOcorrencias.where((oc) {
          var d = oc.data() as Map<String, dynamic>;
          String st = (d['status'] ?? '').toLowerCase();
          if (st.contains('conclu') || st.contains('finaliz'))
            return false; // Oculta concluídos do painel

          String eqResp =
              (d['equipe_responsavel'] ?? d['equipe_atrelada'] ?? '')
                  .toString()
                  .toUpperCase();
          return eqResp.contains(nomeLider) || eqResp.contains(placa);
        }).toList();

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
                      child: Text(
                        '🚗 $placa\n$nomeLider',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        eq['empresa'] ?? 'EXTERNA',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: tarefas.isEmpty
                    ? const Text(
                        'Equipe Disponível',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                          fontSize: 11,
                        ),
                      )
                    : Column(
                        children: tarefas.map((tDoc) {
                          var t = tDoc.data() as Map<String, dynamic>;
                          String st = (t['status'] ?? 'aberto').toLowerCase();
                          Color corStatus = Colors.redAccent;
                          if (st.contains('deslocamento'))
                            corStatus = Colors.orange;
                          if (st.contains('atendimento'))
                            corStatus = Colors.green;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: corStatus, width: 4),
                              ),
                              color: Colors.grey.shade100,
                            ),
                            child: InkWell(
                              onTap: () => _abrirDetalhes(tDoc.id, t),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${t['semaforo']} - ${t['tipo_da_falha']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: corStatus,
                                    ),
                                  ),
                                  Text(
                                    t['endereco'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.black87,
                                    ),
                                  ),
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

  // =================================================================================
  // BUILD PRINCIPAL
  // =================================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Mapa de Ocorrências',
          style: TextStyle(color: Colors.white),
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

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('ocorrencias')
                .snapshots(),
            builder: (context, snapshotOcc) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('equipes')
                    .snapshots(),
                builder: (context, snapshotEq) {
                  if (!snapshotOcc.hasData || !snapshotEq.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }

                  _todasOcorrencias = snapshotOcc.data!.docs;
                  _todasEquipes = snapshotEq.data!.docs;
                  _atualizarListaEmpresas(); // Mantém o dropdown de empresas do filtro atualizado

                  // Filtra para o Mapa (Agrupando por coordenadas iguais para criar badges se precisar)
                  List<QueryDocumentSnapshot> ocorrenciasParaMapa =
                      _todasOcorrencias
                          .where(
                            (doc) => _passouNoFiltro(
                              doc.data() as Map<String, dynamic>,
                            ),
                          )
                          .toList();

                  List<Marker> marcadores = [];
                  for (var doc in ocorrenciasParaMapa) {
                    var data = doc.data() as Map<String, dynamic>;
                    LatLng? coords = _parseLatLng(data['georeferencia']);
                    if (coords != null) {
                      String st = (data['status'] ?? 'aberto')
                          .toString()
                          .toLowerCase();
                      Color iconColor = Colors.redAccent;
                      IconData iconShape = Icons.location_on;

                      if (st.contains('deslocamento')) {
                        iconColor = Colors.orange;
                        iconShape = Icons.directions_car;
                      }
                      if (st.contains('atendimento')) {
                        iconColor = Colors.green;
                        iconShape = Icons.build;
                      }

                      marcadores.add(
                        Marker(
                          point: coords,
                          width: 45,
                          height: 45,
                          child: GestureDetector(
                            onTap: () => _abrirDetalhes(doc.id, data),
                            child: CircleAvatar(
                              backgroundColor: Colors.white,
                              child: Icon(
                                iconShape,
                                color: iconColor,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  }

                  return Column(
                    children: [
                      const SizedBox(height: 90),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            bool isDesktop = constraints.maxWidth > 900;

                            // WIDGET DO MAPA (COM O PAINEL DE FILTRO DENTRO)
                            Widget mapaWidget = Container(
                              margin: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white38,
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Stack(
                                  children: [
                                    FlutterMap(
                                      mapController: _mapController,
                                      options: MapOptions(
                                        initialCenter: _centroPadrao,
                                        initialZoom: 12.0,
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate:
                                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                          userAgentPackageName:
                                              'com.seusistema.sos',
                                        ),
                                        MarkerLayer(markers: marcadores),
                                      ],
                                    ),
                                    // PAINEL DE FILTROS FLUTUANTE NO MAPA
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: Container(
                                        width: 180,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.95,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              blurRadius: 5,
                                              color: Colors.black26,
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'STATUS',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            CheckboxListTile(
                                              title: const Text(
                                                'Aberto',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              value: _fStatusAberto,
                                              onChanged: (v) => setState(
                                                () => _fStatusAberto = v!,
                                              ),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            CheckboxListTile(
                                              title: const Text(
                                                'Desloc.',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              value: _fStatusDesloc,
                                              onChanged: (v) => setState(
                                                () => _fStatusDesloc = v!,
                                              ),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            CheckboxListTile(
                                              title: const Text(
                                                'Atend.',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              value: _fStatusAtend,
                                              onChanged: (v) => setState(
                                                () => _fStatusAtend = v!,
                                              ),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),

                                            const Divider(),
                                            const Text(
                                              'PRIORIDADE',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            CheckboxListTile(
                                              title: const Text(
                                                'Alta',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              value: _fPrioAlta,
                                              onChanged: (v) => setState(
                                                () => _fPrioAlta = v!,
                                              ),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            CheckboxListTile(
                                              title: const Text(
                                                'Média',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              value: _fPrioMedia,
                                              onChanged: (v) => setState(
                                                () => _fPrioMedia = v!,
                                              ),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            CheckboxListTile(
                                              title: const Text(
                                                'Baixa',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              value: _fPrioBaixa,
                                              onChanged: (v) => setState(
                                                () => _fPrioBaixa = v!,
                                              ),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),

                                            const Divider(),
                                            const Text(
                                              'ALERTAS DE TEMPO',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                            CheckboxListTile(
                                              title: const Text(
                                                '> 24h',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              value: _fMais24h,
                                              onChanged: (v) => setState(
                                                () => _fMais24h = v!,
                                              ),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            CheckboxListTile(
                                              title: const Text(
                                                'Fora Prazo',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              value: _fForaPrazo,
                                              onChanged: (v) => setState(
                                                () => _fForaPrazo = v!,
                                              ),
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),

                                            const Divider(),
                                            DropdownButtonFormField<String>(
                                              isDense: true,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.black87,
                                              ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: InputBorder.none,
                                              ),
                                              value: _filtroEmpresa,
                                              items: _empresasOptions
                                                  .map(
                                                    (e) => DropdownMenuItem(
                                                      value: e,
                                                      child: Text(
                                                        e,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) => setState(
                                                () => _filtroEmpresa = v!,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            // WIDGET SIDEBAR (PENDENTES E EQUIPES)
                            Widget sidebarWidget = Container(
                              margin: EdgeInsets.only(
                                top: isDesktop ? 16 : 0,
                                bottom: 16,
                                right: 16,
                                left: isDesktop ? 0 : 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(
                                        top: 16,
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        'OCORRÊNCIAS EM ABERTO',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                    _buildSidebarPendentes(),

                                    const Padding(
                                      padding: EdgeInsets.only(
                                        top: 24,
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        'EQUIPES EM CAMPO',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                    _buildSidebarEquipes(),
                                  ],
                                ),
                              ),
                            );

                            if (isDesktop) {
                              return Row(
                                children: [
                                  Expanded(flex: 3, child: mapaWidget),
                                  Expanded(flex: 1, child: sidebarWidget),
                                ],
                              );
                            } else {
                              return Column(
                                children: [
                                  Expanded(flex: 3, child: mapaWidget),
                                  Expanded(flex: 2, child: sidebarWidget),
                                ],
                              );
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
}
