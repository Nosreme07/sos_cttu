import 'package:flutter/material.dart';

import '../../widgets/menu_usuario.dart';

class TelaProgramacao extends StatefulWidget {
  const TelaProgramacao({super.key});

  @override
  State<TelaProgramacao> createState() => _TelaProgramacaoState();
}

class _TelaProgramacaoState extends State<TelaProgramacao> {
  String? _semaforoSelecionado;
  bool _modoEdicao = false;
  bool _existeProgramacao = false;

  // Variáveis de Estado
  String _subarea = "---";

  // Ignorando os warnings amarelos de unused por enquanto,
  // pois usaremos essas variáveis na integração com o banco!
  // ignore: unused_field
  String _ultimaAtualizacao = "";
  // ignore: unused_field
  String _motivoEdicao = "";
  // ignore: unused_field
  String _observacoes = "";

  List<dynamic> _grupos = [];
  List<dynamic> _planos = [];
  Map<String, dynamic> _agendamento = {};

  // Mock Data para o botão DEMO (Igual ao seu HTML)
  void _carregarDemo() {
    setState(() {
      _existeProgramacao = true;
      _subarea = "ZONA SUL";
      _grupos = [
        {'id': 'G1', 'nome': 'Av. Principal'},
        {'id': 'G2', 'nome': 'Rua Lateral'},
      ];
      _planos = [
        {
          'planId': '1',
          'type': 'normal',
          'tc': 100,
          'offset': 0,
          'groups': [
            {
              'name': 'G1',
              'phase': 'Av. Principal',
              'start': 0,
              'end': 45,
              'yellow': 3,
              'allRed': 2,
            },
            {
              'name': 'G2',
              'phase': 'Rua Lateral',
              'start': 50,
              'end': 95,
              'yellow': 3,
              'allRed': 2,
            },
          ],
        },
        {'planId': 'piscante', 'type': 'special'},
      ];
      _agendamento = {
        'seg': [
          {'hora': '06:00', 'nomePlano': 'PLANO 1'},
          {'hora': '22:00', 'nomePlano': 'PISCANTE'},
        ],
      };
    });
  }

  void _limparTela() {
    setState(() {
      _existeProgramacao = false;
      _modoEdicao = false;
      _subarea = "---";
      _ultimaAtualizacao = "";
      _motivoEdicao = "";
      _observacoes = "";
      _grupos = [];
      _planos = [];
      _agendamento = {};
    });
  }

  void _alternarModoEdicao() {
    setState(() {
      _modoEdicao = !_modoEdicao;
    });
  }

  // ==========================================
  // COMPONENTES DE UI
  // ==========================================

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF25303d),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildCustomButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: Icon(icon, color: Colors.white, size: 18),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      onPressed: onPressed,
    );
  }

  // ==========================================
  // GRÁFICO DE BARRAS DO PLANO (GANTT)
  // ==========================================
  Widget _buildDiagrama(Map<String, dynamic> plano) {
    if (plano['type'] == 'special') {
      Color corFundo = plano['planId'] == 'piscante'
          ? Colors.yellow.shade600
          : Colors.grey.shade600;
      return Container(
        height: 60,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: corFundo,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            'PLANO ${plano['planId'].toString().toUpperCase()}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    int tc = plano['tc'] ?? 100;
    List groups = plano['groups'] ?? [];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tabela de Dados (Esquerda)
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Container(
                  color: Colors.grey.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text(
                        'Grupo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'Início',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'Fim',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'Verde',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                ...groups.map((g) {
                  int tvd = (g['end'] >= g['start'])
                      ? g['end'] - g['start']
                      : (tc - g['start']) + g['end'];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.black12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text(
                          g['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Text('${g['start']}'),
                        Text('${g['end']}'),
                        Text(
                          '$tvd',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Gráfico (Direita)
          Expanded(
            flex: 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                double width = constraints.maxWidth;
                return SizedBox(
                  height: (groups.length * 30.0) + 30, // Altura dinâmica
                  child: Stack(
                    children: [
                      // Régua (Fundo)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 20,
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.black87,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Barras dos Grupos
                      ...groups
                          .asMap()
                          .entries
                          .map((entry) {
                            int idx = entry.key;
                            var g = entry.value;
                            double yPos = 25.0 + (idx * 30.0);

                            double startPx = (g['start'] / tc) * width;
                            double endPx = (g['end'] / tc) * width;

                            bool cruzaCiclo = g['end'] < g['start'];

                            List<Widget> barras = [];

                            // Fundo Vermelho
                            barras.add(
                              Positioned(
                                top: yPos + 6,
                                left: 0,
                                width: width,
                                height: 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade400,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            );

                            if (!cruzaCiclo) {
                              double widthVerde = endPx - startPx;
                              barras.add(
                                Positioned(
                                  top: yPos,
                                  left: startPx,
                                  width: widthVerde,
                                  height: 18,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      border: Border.all(color: Colors.black12),
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              double width1 = width - startPx;
                              double width2 = endPx;
                              barras.add(
                                Positioned(
                                  top: yPos,
                                  left: startPx,
                                  width: width1,
                                  height: 18,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      border: Border.all(color: Colors.black12),
                                    ),
                                  ),
                                ),
                              );
                              barras.add(
                                Positioned(
                                  top: yPos,
                                  left: 0,
                                  width: width2,
                                  height: 18,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      border: Border.all(color: Colors.black12),
                                    ),
                                  ),
                                ),
                              );
                            }

                            return Stack(children: barras);
                          })
                          .expand((element) => element.children),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Programação Semafórica',
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

          SingleChildScrollView(
            padding: const EdgeInsets.only(
              top: 100,
              left: 16,
              right: 16,
              bottom: 40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- PAINEL DE CONFIGURAÇÃO TOPO ---
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(
                          top: BorderSide(color: Colors.orange, width: 4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                          ),
                        ],
                      ),
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
                                    const Text(
                                      'Selecione o Semáforo',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        fillColor: Color(0xFFf8f9fa),
                                        filled: true,
                                      ),
                                      value: _semaforoSelecionado,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'DEMO',
                                          child: Text(
                                            '000 - SEMÁFORO DEMO (Teste Visual)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        setState(
                                          () => _semaforoSelecionado = val,
                                        );
                                        if (val == 'DEMO') {
                                          _carregarDemo();
                                        } else {
                                          _limparTela();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 1,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Grupos Atuais',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ..._grupos.map(
                                      (g) => Text(
                                        '${g['id']}: ${g['nome']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Subárea',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _subarea,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          if (_semaforoSelecionado != null) ...[
                            const Divider(height: 30),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (!_existeProgramacao || _modoEdicao) ...[
                                  _buildCustomButton(
                                    '🚦 DEFINIR GRUPOS',
                                    Icons.traffic,
                                    Colors.orange,
                                    () {},
                                  ),
                                  _buildCustomButton(
                                    '📝 DEFINIR PLANO',
                                    Icons.add_chart,
                                    Colors.green,
                                    () {},
                                  ),
                                  _buildCustomButton(
                                    '📅 DEFINIR AGENDAMENTO',
                                    Icons.calendar_month,
                                    Colors.blue,
                                    () {},
                                  ),
                                  _buildCustomButton(
                                    '📝 OBSERVAÇÕES',
                                    Icons.note,
                                    Colors.purple,
                                    () {},
                                  ),
                                  _buildCustomButton(
                                    '💾 SALVAR PROGRAMAÇÃO',
                                    Icons.save,
                                    Colors.deepPurple,
                                    () {},
                                  ),
                                ],
                                if (_existeProgramacao && !_modoEdicao) ...[
                                  _buildCustomButton(
                                    '✏️ EDITAR PROGRAMAÇÃO',
                                    Icons.edit,
                                    Colors.blueGrey,
                                    _alternarModoEdicao,
                                  ),
                                  _buildCustomButton(
                                    '📄 EXPORTAR PDF',
                                    Icons.picture_as_pdf,
                                    Colors.red,
                                    () {},
                                  ),
                                  _buildCustomButton(
                                    '🗑️ EXCLUIR TUDO',
                                    Icons.delete,
                                    Colors.black87,
                                    () {},
                                  ),
                                ],
                                if (_existeProgramacao && _modoEdicao) ...[
                                  _buildCustomButton(
                                    '🚫 CANCELAR EDIÇÃO',
                                    Icons.cancel,
                                    Colors.redAccent,
                                    _alternarModoEdicao,
                                  ),
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
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(6),
                          ),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children:
                              [
                                'seg',
                                'ter',
                                'qua',
                                'qui',
                                'sex',
                                'sab',
                                'dom',
                              ].map((dia) {
                                String nomeDia = {
                                  'seg': 'Segunda',
                                  'ter': 'Terça',
                                  'qua': 'Quarta',
                                  'qui': 'Quinta',
                                  'sex': 'Sexta',
                                  'sab': 'Sábado',
                                  'dom': 'Domingo',
                                }[dia]!;
                                List eventos = _agendamento[dia] ?? [];

                                return Expanded(
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 150,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(8),
                                          color: Colors.grey.shade200,
                                          child: Text(
                                            nomeDia,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        ...eventos.map(
                                          (ev) => Container(
                                            margin: const EdgeInsets.all(4),
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.blue.shade300,
                                              ),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  ev['hora'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                Text(
                                                  ev['nomePlano'],
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // --- PLANOS (CORREÇÃO APLICADA AQUI) ---
                    if (_planos.isNotEmpty) ...[
                      _buildSectionTitle('TEMPOS DOS PLANOS'),
                      
                      // O uso do map aqui agora está correto e limpo
                      ..._planos.map((p) {
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade300),
                              right: BorderSide(color: Colors.grey.shade300),
                              bottom: BorderSide(color: Colors.grey.shade300),
                              left: const BorderSide(
                                color: Colors.blue,
                                width: 4,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                color: Colors.grey.shade100,
                                child: Text(
                                  p['type'] == 'special'
                                      ? 'MODO ${p['planId'].toString().toUpperCase()}'
                                      : 'PLANO ${p['planId']}   |   Ciclo: ${p['tc']}s',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              _buildDiagrama(p),
                            ],
                          ),
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