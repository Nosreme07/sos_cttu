import 'package:flutter/material.dart';

import 'relatorio_ocorrencias.dart';
import 'relatorio_equipes.dart';
import 'relatorio_recorrencias.dart';
import 'relatorio_semaforos.dart'; // <-- Agora todos estão ativados!

import '../../widgets/menu_usuario.dart';

class TelaRelatorios extends StatelessWidget {
  const TelaRelatorios({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Menu de Relatórios',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
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
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 100.0, left: 24.0, right: 24.0, bottom: 24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Wrap(
                  spacing: 30.0,
                  runSpacing: 30.0,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildCardWithImage(context, 'Ocorrências', 'assets/images/relatorio_ocorrencias.png', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaRelatorioOcorrencias()));
                    }),
                    _buildCardWithImage(context, 'Equipes', 'assets/images/relatorio_equipes.png', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaRelatorioEquipes()));
                    }),
                    _buildCardWithImage(context, 'Recorrências', 'assets/images/relatorio_recorrencias.png', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaRelatorioRecorrencias()));
                    }),
                    _buildCardWithImage(context, 'Semáforos', 'assets/images/relatorio_semaforos.png', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaRelatorioSemaforos()));
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

  Widget _buildCardWithImage(BuildContext context, String titulo, String caminhoImagem, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 200,
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 5))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 80,
                child: Center(
                  child: Image.asset(
                    caminhoImagem, height: 80, fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.bar_chart, size: 60, color: Colors.blueGrey),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF333A4A)), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}