import 'package:flutter/material.dart';
import 'package:sos_cttu/principal/equipes/tela_equipes.dart';

// Importações das telas do sistema
import 'busca/tela_busca.dart';
import 'programacao/tela_programacao.dart';
import 'cadastros/tela_cadastro.dart';
import 'ocorrencias/tela_ocorrencias.dart';
import 'ocorrencias/tela_mapa_ocorrencias.dart';
import 'dashboard/tela_dashboard.dart';
import 'relatorios/tela_relatorios.dart';
import 'relatorios/tela_mapa_relatorios.dart';

// Importação do MENU REUTILIZÁVEL
import '../widgets/menu_usuario.dart';

class TelaPrincipal extends StatelessWidget {
  const TelaPrincipal({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Sistema de Ocorrências Semafóricas',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
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

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(
                top: 100.0,
                left: 24.0,
                right: 24.0,
                bottom: 24.0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Wrap(
                  spacing: 24.0,
                  runSpacing: 24.0,
                  alignment: WrapAlignment.center,
                  children: [
                    // BOTÃO DASHBOARD ATUALIZADO
                    _buildCardWithImage(
                      context,
                      'Dashboard',
                      'assets/images/dashboard.png', // Certifique-se de que o nome da imagem está correto
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TelaDashboard(),
                          ),
                        );
                      },
                    ),

                    // --- BOTÃO LISTA DE OCORRÊNCIAS ATUALIZADO ---
                    _buildCardWithImage(
                      context,
                      'Lista de\nOcorrências',
                      'assets/images/ocorrencias.png', // Usando a imagem que você pediu
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const ListaOcorrencias(), // Navegação ativada
                          ),
                        );
                      },
                    ),

                    // BOTÃO MAPA DE OCORRÊNCIAS ATUALIZADO
                    _buildCardWithImage(
                      context,
                      'Mapa de\nOcorrências',
                      'assets/images/mapas.png',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TelaMapaOcorrencias(),
                          ),
                        );
                      },
                    ),

                    // BOTÃO RELATÓRIOS ATUALIZADO
                    _buildCardWithImage(
                      context,
                      'Relatórios',
                      'assets/images/relatorios.png',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TelaRelatorios(),
                          ),
                        );
                      },
                    ),

                    // BOTÃO GERENCIAR EQUIPES
                    _buildCardWithImage(
                      context,
                      'Gerenciar Equipes',
                      'assets/images/equipe.png',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TelaEquipes(),
                          ),
                        );
                      },
                    ),

                    // BOTÃO DE CADASTROS
                    _buildCardWithImage(
                      context,
                      'Cadastros',
                      'assets/images/cadastros.png',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TelaCadastros(),
                          ),
                        );
                      },
                    ),

                    // BOTÃO GERENCIAR PROGRAMAÇÃO
                    _buildCardWithImage(
                      context,
                      'Programação',
                      'assets/images/programacao.png',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TelaProgramacao(),
                          ),
                        );
                      },
                    ),

                    // BOTÃO DE BUSCA SEMAFÓRICA
                    _buildCardWithImage(
                      context,
                      'Busca Semafórica',
                      'assets/images/localizacao.png',
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TelaBusca(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- MÉTODOS AUXILIARES PADRONIZADOS ---

  Widget _buildBaseCard(
    BuildContext context,
    String titulo,
    Widget conteudoGrafico,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 60, child: Center(child: conteudoGrafico)),
              const SizedBox(height: 10),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333A4A),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardWithIcon(
    BuildContext context,
    String titulo,
    IconData icone,
    VoidCallback onTap,
  ) {
    return _buildBaseCard(
      context,
      titulo,
      Icon(icone, size: 50, color: const Color(0xFF333A4A)),
      onTap,
    );
  }

  Widget _buildCardWithImage(
    BuildContext context,
    String titulo,
    String caminhoImagem,
    VoidCallback onTap,
  ) {
    return _buildBaseCard(
      context,
      titulo,
      Image.asset(caminhoImagem, height: 85, fit: BoxFit.contain),
      onTap,
    );
  }
}

class TelaEquipe {
  const TelaEquipe();
}
