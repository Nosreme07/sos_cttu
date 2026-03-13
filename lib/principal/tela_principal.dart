import 'package:flutter/material.dart';

// 1. Importação da tela de cadastros
import 'cadastros/tela_cadastro.dart'; 

// 2. IMPORTAÇÃO DO NOVO MENU REUTILIZÁVEL (ajuste o caminho se necessário)
import '../widgets/menu_usuario.dart'; 

class TelaPrincipal extends StatelessWidget {
  const TelaPrincipal({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // Faz a imagem passar por trás da AppBar
      appBar: AppBar(
        title: const Text(
          'Sistema de Ocorrências Semafóricas',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.6), // Barra superior semi-transparente
        elevation: 0,
        actions: const [
          // 3. A MÁGICA ACONTECE AQUI! Substituímos todo o código do canto superior direito por isso:
          MenuUsuario(),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 4. Imagem de Fundo padronizada igual às outras telas (ótima para a Web)
          Image.asset(
            'assets/images/tela.png',
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.4),
            colorBlendMode: BlendMode.darken,
          ),
          
          // Os Botões Centrais Responsivos
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 100.0, left: 24.0, right: 24.0, bottom: 24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900), // Limita largura em telas grandes
                child: Wrap(
                  spacing: 24.0, // Espaço horizontal entre os cartões
                  runSpacing: 24.0, // Espaço vertical entre as linhas
                  alignment: WrapAlignment.center,
                  children: [
                    _buildCard(context, 'Dashboard', Icons.dashboard, () {
                      print('Ir para Dashboard');
                    }),
                    _buildCard(context, 'Lista de\nOcorrências', Icons.list_alt, () {
                      print('Ir para Lista de Ocorrências');
                    }),
                    _buildCard(context, 'Mapa de\nOcorrências', Icons.map, () {
                      print('Ir para Mapa de Ocorrências');
                    }),
                    _buildCard(context, 'Relatórios', Icons.pie_chart, () {
                      print('Ir para Relatórios');
                    }),
                    _buildCard(context, 'Gerenciar Equipes', Icons.engineering, () {
                      print('Ir para Gerenciar Equipes');
                    }),
                    _buildCard(context, 'Cadastros', Icons.app_registration, () {
                      // Navegação real para a tela de cadastros
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const TelaCadastros()),
                      );
                    }),
                    _buildCard(context, 'Estoque', Icons.inventory_2, () {
                      print('Ir para Estoque');
                    }),
                    _buildCard(context, 'Programação', Icons.calendar_month, () {
                      print('Ir para Programação');
                    }),
                    _buildCard(context, 'Busca Semafórica', Icons.location_on, () {
                      print('Ir para Busca Semafórica');
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget personalizado para criar os botões brancos padronizados
  Widget _buildCard(BuildContext context, String titulo, IconData icone, VoidCallback onTap) {
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
                offset: const Offset(0, 5), // Sombra levemente deslocada para baixo
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 50, color: const Color(0xFF333A4A)),
              const SizedBox(height: 16),
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
}