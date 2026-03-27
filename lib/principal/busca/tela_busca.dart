import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

// Importações para Exportação
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;

import '../../../widgets/menu_usuario.dart';

class TelaBusca extends StatefulWidget {
  const TelaBusca({super.key});

  @override
  State<TelaBusca> createState() => _TelaBuscaState();
}

class _TelaBuscaState extends State<TelaBusca> {
  final MapController _mapController = MapController();
  final TextEditingController _buscaController = TextEditingController();

  String _termoBusca = '';
  Timer? _debounce;

  String _filtroSelecionado = 'Todos';
  final List<String> _opcoesFiltro = [
    'Todos',
    'Semáforo',
    'Endereço',
    'Bairro',
    'Subárea',
    'Empresa',
    'Rota',
  ];

  final LatLng _centroPadrao = const LatLng(-8.047, -34.877);

  // --- VARIÁVEIS DE OTIMIZAÇÃO (PERFORMANCE) ---
  bool _isLoading = true;
  List<Map<String, dynamic>> _todosSemaforos = [];
  List<Map<String, dynamic>> _semaforosFiltrados = [];
  List<Marker> _marcadores = [];

  // --- ESTRUTURA PARA OS DETALHES COMPLETOS E EXPORTAÇÃO ---
  final List<Map<String, dynamic>> _gruposFormulario = [
    {
      'titulo': 'Informações Gerais',
      'icone': Icons.info_outline,
      'campos': [
        {'key': 'id', 'label': 'Número do Semáforo'},
        {'key': 'endereco', 'label': 'Endereço'},
        {'key': 'bairro', 'label': 'Bairro'},
        {'key': 'empresa', 'label': 'Empresa Responsável'},
        {'key': 'georeferencia', 'label': 'Georreferência'},
        {'key': 'rota', 'label': 'Rota'},
        {'key': 'tipo_do_controlador', 'label': 'Tipo do Controlador'},
        {'key': 'id_do_controlador', 'label': 'ID do Controlador'},
        {'key': 'subareas', 'label': 'Subáreas'},
      ],
    },
    {
      'titulo': 'Grupos Focais',
      'icone': Icons.traffic,
      'campos': [
        {'key': 'grupo_focal_veicular_tipo_i', 'label': 'GF Veicular Tipo I (Padrão)'},
        {'key': 'grupo_focal_veicular_tipo_t', 'label': 'GF Veicular Tipo T (Seta)'},
        {'key': 'grupo_focal_pedestre_simples', 'label': 'GF Pedestre Simples'},
        {'key': 'grupo_focal_pedestre_com_cronometro', 'label': 'GF Pedestre com Cronômetro'},
        {'key': 'grupo_focal_faixa_reversivel', 'label': 'GF Faixa Reversível'},
        {'key': 'grupo_focal_ciclista_com_tres_focos', 'label': 'GF Ciclista com Três Focos'},
        {'key': 'grupo_focal_ciclista_com_dois_focos', 'label': 'GF Ciclista com Dois Focos'},
        {'key': 'anteparo_tipo_i', 'label': 'Anteparo Tipo I'},
      ],
    },
    {
      'titulo': 'Veicular e Botoeiras',
      'icone': Icons.touch_app,
      'campos': [
        {'key': 'veicular_com_sequencial', 'label': 'Veicular com Sequencial'},
        {'key': 'veicular_com_cronometro', 'label': 'Veicular com Cronômetro'},
        {'key': 'sirene', 'label': 'Sirene'},
        {'key': 'horario_de_funcionamente_das_sirenes', 'label': 'Horário de Funcionamento da Sirene'},
        {'key': 'botoeira_com_dispositivo_sonoro', 'label': 'Botoeira com Dispositivo Sonoro'},
        {'key': 'botoeira_simples', 'label': 'Botoeira Simples'},
      ],
    },
    {
      'titulo': 'Energia e Comunicação',
      'icone': Icons.electric_bolt,
      'campos': [
        {'key': 'nobreak', 'label': 'Nobreak'},
        {'key': 'kit_bateria', 'label': 'Kit Bateria'},
        {'key': 'numero_do_nobreak', 'label': 'Número do Nobreak'},
        {'key': 'medidor', 'label': 'Medidor (Existente)'},
        {'key': 'numero_do_medidor', 'label': 'Número do Medidor'},
        {'key': 'kit_de_comunicacao', 'label': 'Kit de Comunicação (Existente)'},
        {'key': 'modo_de_funcionamento', 'label': 'Modo de Funcionamento'},
      ],
    },
    {
      'titulo': 'Estrutura Física',
      'icone': Icons.construction,
      'campos': [
        {'key': 'semiportico_conico', 'label': 'Semi-Pórtico Cônico'},
        {'key': 'semiportico_simples', 'label': 'Semi-Pórtico Simples'},
        {'key': 'semiportico_estruturado', 'label': 'Semi-Pórtico Estruturado'},
        {'key': 'portico_simples', 'label': 'Pórtico Simples'},
        {'key': 'portico_estruturado', 'label': 'Pórtico Estruturado'},
        {'key': 'coluna_conica', 'label': 'Coluna Cônica'},
        {'key': 'coluna_simples', 'label': 'Coluna Simples'},
        {'key': 'placa_adesiva_para_botoeira', 'label': 'Placa Adesiva para Botoeira'},
        {'key': 'conjunto_entrada_de_energia_padrao_celpe_instalado', 'label': 'Entrada de Energia CELPE Instalado'},
        {'key': 'conjunto_aterramento_para_colunas', 'label': 'Conjunto Aterramento para Colunas'},
      ],
    },
    {
      'titulo': 'Cabos, Identificação e Documentação',
      'icone': Icons.cable,
      'campos': [
        {'key': 'cabo_2x1mm', 'label': 'Cabo 2x1mm'},
        {'key': 'cabo_3x1mm', 'label': 'Cabo 3x1mm'},
        {'key': 'cabo_4x1mm', 'label': 'Cabo 4x1mm'},
        {'key': 'cabo_7x1mm', 'label': 'Cabo 7x1mm'},
        {'key': 'luminarias', 'label': 'Luminárias'},
        {'key': 'placa_de_identificacao_de_semaforo', 'label': 'Placa de Identificação'},
        {'key': 'fotossensor_equipamento', 'label': 'Fotossensor no Semáforo'},
        {'key': 'conta_contrato', 'label': 'Conta Contrato'},
        {'key': 'link_da_programacao', 'label': 'Link da Programação'},
      ],
    },
    {
      'titulo': 'Observações e Histórico',
      'icone': Icons.history_edu,
      'campos': [
        {'key': 'data_de_implantacao', 'label': 'Data de Implantação'},
        {'key': 'observacoes', 'label': 'Observações (Geral)'},
        {'key': 'observacoes_2', 'label': 'Observações 2 (Adicionais)'},
        {'key': 'historico', 'label': 'Histórico (Intervenções/Eventos)'},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // --- NOVO: CARREGAMENTO OTIMIZADO DE DADOS PARA A MEMÓRIA ---
  Future<void> _carregarDadosIniciais() async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await FirebaseFirestore.instance.collection('semaforos').get();
      List<Map<String, dynamic>> listaTemp = [];

      for (var doc in snapshot.docs) {
        var data = doc.data();
        
        // 1. Pré-processa ID e Número (Evita usar Regex na busca e ordenação)
        String idOriginal = data['id']?.toString() ?? '';
        String idFormatado = _formatarId(idOriginal);
        int numId = int.tryParse(idOriginal.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

        // 2. Pré-processa as Coordenadas
        LatLng? coords = _parseLatLng(data['georeferencia']?.toString());

        // Adiciona dados ocultos de sistema no mapa
        data['_idFormatado'] = idFormatado;
        data['_numId'] = numId;
        data['_coords'] = coords;

        listaTemp.add(data);
      }

      // Ordena a lista UMA única vez
      listaTemp.sort((a, b) => (a['_numId'] as int).compareTo(b['_numId'] as int));

      _todosSemaforos = listaTemp;
      
      // Aplica o filtro (que inicialmente vai mostrar todos)
      _aplicarFiltro();

    } catch (e) {
      debugPrint("Erro ao carregar semáforos: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- NOVO: FILTRAGEM E RENDERIZAÇÃO INSTANTÂNEA ---
  void _aplicarFiltro() {
    List<Map<String, dynamic>> filtradosTemp = _todosSemaforos.where((data) {
      if (_termoBusca.isEmpty) return true;

      String idOriginal = data['id']?.toString() ?? '';
      String idFormatado = data['_idFormatado'] ?? '';
      String endereco = data['endereco']?.toString() ?? '';
      String bairro = data['bairro']?.toString() ?? '';
      String subarea = data['subareas']?.toString() ?? '';
      String empresa = data['empresa']?.toString() ?? '';
      String rota = data['rota']?.toString() ?? '';

      bool contemTexto(String texto) => texto.toLowerCase().contains(_termoBusca);

      switch (_filtroSelecionado) {
        case 'Semáforo':
          return contemTexto(idOriginal) || contemTexto(idFormatado);
        case 'Endereço':
          return contemTexto(endereco);
        case 'Bairro':
          return contemTexto(bairro);
        case 'Subárea':
          return contemTexto(subarea);
        case 'Empresa':
          return contemTexto(empresa);
        case 'Rota':
          return contemTexto(rota);
        case 'Todos':
        default:
          return contemTexto(idOriginal) ||
              contemTexto(idFormatado) ||
              contemTexto(endereco) ||
              contemTexto(bairro) ||
              contemTexto(subarea) ||
              contemTexto(empresa) ||
              contemTexto(rota);
      }
    }).toList();

    List<Marker> marcadoresTemp = [];
    for (var data in filtradosTemp) {
      LatLng? coords = data['_coords'];
      String idFormatado = data['_idFormatado'];

      if (coords != null) {
        Widget iconeMarcador;
        String nomeEmpresa = (data['empresa'] ?? '').toString().toUpperCase();

        if (nomeEmpresa.contains('SERTTEL')) {
          iconeMarcador = Image.asset('assets/images/serttel.png', width: 45, height: 45);
        } else if (nomeEmpresa.contains('SINALVIDA')) {
          iconeMarcador = Image.asset('assets/images/sinalvida.png', width: 45, height: 45);
        } else {
          iconeMarcador = const Icon(Icons.location_on, color: Colors.redAccent, size: 45);
        }

        marcadoresTemp.add(
          Marker(
            point: coords,
            width: 60,
            height: 70,
            child: GestureDetector(
              onTap: () => _abrirDetalhesResumidos(data),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconeMarcador,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black54, width: 1),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
                    ),
                    child: Text(
                      idFormatado,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _semaforosFiltrados = filtradosTemp;
        _marcadores = marcadoresTemp;
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

  String _formatarId(String idStr) {
    if (idStr.isEmpty || idStr.contains('NUMERO')) return '000';
    String numeros = idStr.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeros.isEmpty) return idStr;
    return numeros.padLeft(3, '0');
  }

  void _focarNoMapa(LatLng coordenadas) {
    _mapController.move(coordenadas, 17.0);
  }

  // =========================================================================
  // MODAL RESUMO DO MAPA (Ao clicar no PIN)
  // =========================================================================
  void _abrirDetalhesResumidos(Map<String, dynamic> data) {
    String idFormatado = data['_idFormatado'] ?? _formatarId(data['id'] ?? '');
    LatLng? coords = data['_coords'] ?? _parseLatLng(data['georeferencia']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(top: 24, left: 20, right: 20, bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho do Modal
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.amber,
                    child: Icon(Icons.traffic, color: Colors.black87),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Semáforo $idFormatado',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2f3b4c)),
                        ),
                        Text(
                          data['endereco'] ?? '-',
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 1),

              // Dados de Resumo
              _buildInfoRow('Bairro', data['bairro']),
              _buildInfoRow('Subárea', data['subareas']),
              _buildInfoRow('Empresa', data['empresa']),
              _buildInfoRow('Rota', data['rota']),
              _buildInfoRow('Controlador', data['tipo_do_controlador']),
              _buildInfoRow('ID Controlador', data['id_do_controlador']),

              const SizedBox(height: 20),

              // Botão Traçar Rota
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2980b9), // Azul Waze/Maps
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.directions_car, color: Colors.white),
                label: const Text('Traçar Rota', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: () {
                  Navigator.pop(context);
                  if (coords != null) {
                    _abrirOpcoesDeRota(coords.latitude, coords.longitude);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este semáforo não possui coordenadas GPS.')));
                  }
                },
              ),
              const SizedBox(height: 8),

              // Botões Secundários
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0xFF2f3b4c)),
                ),
                icon: const Icon(Icons.list_alt, color: Color(0xFF2f3b4c)),
                label: const Text('Ver Detalhes Completos', style: TextStyle(color: Color(0xFF2f3b4c), fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(context);
                  _abrirModalDetalhesCompletos(data, idFormatado);
                },
              ),
              const SizedBox(height: 8),

              // Exportações
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                      label: const Text('Exportar PDF', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: () => _exportarPdfIndividual(data, idFormatado),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      icon: const Icon(Icons.table_chart, color: Colors.white, size: 18),
                      label: const Text('Exportar XLS', style: TextStyle(color: Colors.white, fontSize: 12)),
                      onPressed: () => _exportarCsvIndividual(data, idFormatado),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // --- MODAL 2: DETALHES COMPLETOS (TODA A FICHA TÉCNICA) ---
  void _abrirModalDetalhesCompletos(Map<String, dynamic> data, String idFormatado) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ficha Técnica Completa: $idFormatado',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2f3b4c)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: _gruposFormulario.map((grupo) {
                      bool temDado = grupo['campos'].any((c) => (data[c['key']] ?? '').toString().isNotEmpty);
                      if (!temDado) return const SizedBox.shrink();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(grupo['icone'], color: const Color(0xFF2f3b4c), size: 20),
                                const SizedBox(width: 8),
                                Text(grupo['titulo'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2f3b4c))),
                              ],
                            ),
                            const Divider(thickness: 1),
                            const SizedBox(height: 8),
                            ...grupo['campos'].map((campo) {
                              String valor = (data[campo['key']] ?? '').toString();
                              
                              if (valor == 'true' || valor == '1') valor = 'Sim';
                              if (valor == 'false' || valor == '0') valor = 'Não';
                              
                              if (valor.isEmpty) return const SizedBox.shrink();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${campo['label'].replaceAll(' *', '')}:',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(valor, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Voltar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- ESCOLHER APLICATIVO DE ROTA ---
  void _abrirOpcoesDeRota(double lat, double lng) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Traçar rota usando:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.map, color: Colors.green, size: 30),
                title: const Text('Google Maps', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(context);
                  final url = Uri.parse('http://maps.google.com/maps?q=$lat,$lng');
                  bool launched = await launchUrl(url, mode: LaunchMode.externalApplication);
                  if (!mounted) return;
                  if (!launched) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o Google Maps')));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.navigation, color: Colors.blue, size: 30),
                title: const Text('Waze', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(context);
                  final url = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
                  bool launched = await launchUrl(url, mode: LaunchMode.externalApplication);
                  if (!mounted) return;
                  if (!launched) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o Waze')));
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // --- FUNÇÕES DE EXPORTAÇÃO INDIVIDUAIS ---
  String _formatarDataHora() {
    final now = DateTime.now();
    final dia = now.day.toString().padLeft(2, '0');
    final mes = now.month.toString().padLeft(2, '0');
    final ano = now.year.toString();
    final hora = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$ano às $hora:$min';
  }

  Future<void> _exportarPdfIndividual(Map<String, dynamic> data, String numeroFormatado) async {
    final pdf = pw.Document();
    final dataHora = _formatarDataHora();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 10.0),
            padding: const pw.EdgeInsets.only(top: 10.0),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
            child: pw.Text(
              'Relatório gerado pelo Sistema de Ocorrências Semafóricas - SOS - $dataHora',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              textAlign: pw.TextAlign.center,
            ),
          );
        },
        build: (pw.Context context) {
          List<pw.Widget> conteudo = [
            pw.Text('Ficha Técnica do Semáforo $numeroFormatado', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 20),
          ];

          for (var grupo in _gruposFormulario) {
            bool temDado = grupo['campos'].any((c) => (data[c['key']] ?? '').toString().isNotEmpty);
            if (!temDado) continue;

            conteudo.add(pw.Text(grupo['titulo'], style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)));
            conteudo.add(pw.SizedBox(height: 8));

            List<List<String>> tabelaGrupo = [];
            for (var campo in grupo['campos']) {
              String valor = (data[campo['key']] ?? '').toString();
              if (valor.isNotEmpty) tabelaGrupo.add([campo['label'].toString().replaceAll(' *', ''), valor]);
            }

            conteudo.add(
              pw.TableHelper.fromTextArray(
                context: context,
                cellAlignment: pw.Alignment.centerLeft,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey600),
                data: <List<String>>[
                  <String>['Campo', 'Informação'],
                  ...tabelaGrupo,
                ],
              ),
            );
            conteudo.add(pw.SizedBox(height: 20));
          }
          return conteudo;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'semaforo_$numeroFormatado.pdf');
  }

  // --- NOVA FUNÇÃO: EXPORTAR PLANILHA XLSX INDIVIDUAL ---
  Future<void> _exportarCsvIndividual(Map<String, dynamic> data, String numeroFormatado) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Ficha Técnica'];
    excel.setDefaultSheet('Ficha Técnica');

    sheetObject.appendRow(<CellValue>[TextCellValue("FICHA TÉCNICA - SEMÁFORO $numeroFormatado")]);
    sheetObject.appendRow(<CellValue>[TextCellValue("")]);

    for (var grupo in _gruposFormulario) {
      bool temDado = grupo['campos'].any((c) => (data[c['key']] ?? '').toString().isNotEmpty);
      if (!temDado) continue;

      sheetObject.appendRow(<CellValue>[TextCellValue("--- ${grupo['titulo'].toString().toUpperCase()} ---")]);
      sheetObject.appendRow(<CellValue>[TextCellValue("Campo"), TextCellValue("Informação")]);
      
      for (var campo in grupo['campos']) {
        String valor = (data[campo['key']] ?? '').toString();
        if (valor.isNotEmpty) {
          sheetObject.appendRow(<CellValue>[
            TextCellValue(campo['label'].toString().replaceAll(' *', '')), 
            TextCellValue(valor)
          ]);
        }
      }
      sheetObject.appendRow(<CellValue>[TextCellValue("")]);
    }
    
    sheetObject.appendRow(<CellValue>[TextCellValue("Gerado em:"), TextCellValue(_formatarDataHora())]);

    var fileBytes = excel.encode();
    if (fileBytes != null) {
      final xfile = XFile.fromData(
        Uint8List.fromList(fileBytes),
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: 'semaforo_$numeroFormatado.xlsx'
      );
      await Share.shareXFiles([xfile], text: 'Segue a ficha técnica do semáforo $numeroFormatado.');
    }
  }

  Widget _buildInfoRow(String label, dynamic value) {
    String valStr = (value ?? '-').toString();
    if (valStr.isEmpty) valStr = '-';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 14),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2980b9))),
            TextSpan(text: valStr),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Localização de Semáforos', style: TextStyle(color: Colors.white)),
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

          _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Column(
                  children: [
                    const SizedBox(height: 100),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 800),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.grey, width: 1))),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _filtroSelecionado,
                                      icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
                                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                                      items: _opcoesFiltro.map((String f) => DropdownMenuItem<String>(value: f, child: Text(f))).toList(),
                                      onChanged: (novoValor) {
                                        setState(() {
                                          _filtroSelecionado = novoValor!;
                                          _termoBusca = _buscaController.text.toLowerCase();
                                        });
                                        _aplicarFiltro();
                                      },
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _buscaController,
                                    decoration: InputDecoration(
                                      hintText: _filtroSelecionado == 'Todos' ? 'Buscar em todos os campos...' : 'Buscar por $_filtroSelecionado...',
                                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    onChanged: (valor) {
                                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                                      _debounce = Timer(const Duration(milliseconds: 400), () {
                                        _termoBusca = valor.toLowerCase();
                                        _aplicarFiltro();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          bool isDesktop = constraints.maxWidth > 800;

                          Widget mapaWidget = Container(
                            margin: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white38, width: 3),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10)],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(initialCenter: _centroPadrao, initialZoom: 12.0),
                                children: [
                                  TileLayer(
                                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.seusistema.sos',
                                  ),
                                  MarkerLayer(markers: _marcadores),
                                ],
                              ),
                            ),
                          );

                          Widget listaWidget = Container(
                            margin: EdgeInsets.only(
                              top: isDesktop ? 16 : 0, bottom: 16, right: 16, left: isDesktop ? 0 : 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24, width: 2))),
                                  child: Text(
                                    'RESULTADO - ${_semaforosFiltrados.length}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: _semaforosFiltrados.length,
                                    itemBuilder: (context, index) {
                                      var data = _semaforosFiltrados[index];
                                      String idFormatado = data['_idFormatado'];
                                      LatLng? coords = data['_coords'];

                                      String nomeEmpresa = (data['empresa'] ?? '').toString().toUpperCase();
                                      Color corTagEmpresa = Colors.grey;
                                      if (nomeEmpresa.contains('SERTTEL')) corTagEmpresa = Colors.orange.shade700;
                                      if (nomeEmpresa.contains('SINALVIDA')) corTagEmpresa = Colors.blue.shade700;

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        child: ListTile(
                                          title: Row(
                                            children: [
                                              Text('$idFormatado - ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                              if (nomeEmpresa.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(color: corTagEmpresa, borderRadius: BorderRadius.circular(4)),
                                                  child: Text(nomeEmpresa, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                                ),
                                            ],
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 4),
                                              Text(data['endereco'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                                              Text('${data['bairro'] ?? ''} | Sub: ${data['subareas'] ?? ''}', style: const TextStyle(fontSize: 11)),
                                            ],
                                          ),
                                          trailing: const Icon(Icons.location_searching, color: Colors.blue),
                                          onTap: () {
                                            if (coords != null) {
                                              _focarNoMapa(coords);
                                              _abrirDetalhesResumidos(data);
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Semáforo sem coordenada de GPS cadastrada!')));
                                            }
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (isDesktop) {
                            return Row(
                              children: [
                                Expanded(flex: 3, child: mapaWidget),
                                Expanded(flex: 1, child: listaWidget),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                Expanded(flex: 3, child: mapaWidget),
                                Expanded(flex: 2, child: listaWidget),
                              ],
                            );
                          }
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