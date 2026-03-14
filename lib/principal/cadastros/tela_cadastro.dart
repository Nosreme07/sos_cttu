import 'package:flutter/material.dart';
import 'lista_usuarios.dart';
import 'lista_empresas.dart';
import 'lista_veiculos.dart';
import '../../widgets/menu_usuario.dart';

class TelaCadastros extends StatelessWidget {
  const TelaCadastros({super.key});

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
        iconTheme: const IconThemeData(color: Colors.white),
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
                constraints: const BoxConstraints(maxWidth: 800),
                child: Wrap(
                  spacing: 20.0,
                  runSpacing: 20.0,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildCard(
                      context,
                      'Usuários',
                      Image.asset(
                        'assets/images/usuario.png',
                        width: 50,
                        height: 50,
                      ),
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ListaUsuarios(),
                          ),
                        );
                      },
                    ),

                    _buildCard(
                      context,
                      'Semáforos',
                      const Icon(
                        Icons.traffic,
                        size: 50,
                        color: Color(0xFF333A4A),
                      ),
                      () {
                        print("Clicou em Semáforos");
                      },
                    ),

                    _buildCard(
                      context,
                      'Falhas',
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 50,
                        color: Color(0xFF333A4A),
                      ),
                      () {
                        print("Clicou em Falhas");
                      },
                    ),

                    _buildCard(
                      context,
                      'Origem',
                      const Icon(
                        Icons.list_alt,
                        size: 50,
                        color: Color(0xFF333A4A),
                      ),
                      () {
                        print("Clicou em Origem");
                      },
                    ),

                    _buildCard(
                      context,
                      'Integrantes',
                      const Icon(
                        Icons.engineering,
                        size: 50,
                        color: Color(0xFF333A4A),
                      ),
                      () {
                        print("Clicou em Integrantes");
                      },
                    ),

                    // O BOTÃO DE VEÍCULO ATUALIZADO
                    _buildCard(
                      context,
                      'Veículo',
                      Image.asset(
                        'assets/images/veiculo.png',
                        width: 50,
                        height: 50,
                      ),
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ListaVeiculos(),
                          ),
                        );
                      },
                    ),
                    _buildCard(
                      context,
                      'Materiais',
                      const Icon(
                        Icons.inventory,
                        size: 50,
                        color: Color(0xFF333A4A),
                      ),
                      () {
                        print("Clicou em Materiais");
                      },
                    ),

                    // 2. O BOTÃO DE EMPRESA ATUALIZADO
                    _buildCard(
                      context,
                      'Empresa',
                      Image.asset(
                        'assets/images/empresa.png',
                        width: 50,
                        height: 50,
                      ),
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ListaEmpresas(),
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

  Widget _buildCard(
    BuildContext context,
    String titulo,
    Widget iconeOuImagem,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconeOuImagem,
              const SizedBox(height: 16),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 16,
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
}
