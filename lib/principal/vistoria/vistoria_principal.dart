import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ATENÇÃO: Cole esses arquivos na mesma pasta (lib/principal/vistoria/)
import 'iniciar_turno_page.dart';
import 'formulario_rota_page.dart';
import 'relatorios_page.dart'; 
import 'gerenciar_rotas_page.dart'; 

// IMPORTAÇÃO DO MENU (LOGOUT E PERFIL)
import '../../widgets/menu_usuario.dart';

class VistoriaPrincipal extends StatefulWidget {
  const VistoriaPrincipal({super.key});

  @override
  State<VistoriaPrincipal> createState() => _VistoriaPrincipalState();
}

class _VistoriaPrincipalState extends State<VistoriaPrincipal> {
  bool _isAdmin = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _verificarPerfil();
  }

  Future<void> _verificarPerfil() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          String perfil = (doc.data()!['perfil'] ?? '').toString().toLowerCase();
          
          if (mounted) {
            setState(() {
              // Verifica se é administrador, desenvolvedor ou central
              _isAdmin = perfil.contains('admin') || 
                         perfil.contains('desenvolvedor') || 
                         perfil.contains('operador central');
              _isLoading = false;
            });
          }
          return;
        }
      } catch (e) {
        debugPrint('Erro ao verificar perfil no menu: $e');
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu de Vistoria', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.teal.shade200,
        actions: const [MenuUsuario()], 
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.teal))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMenuButton(
                  context: context,
                  title: 'Turno',
                  subtitle: 'Registre veículo, KM e Rota do dia',
                  icon: Icons.play_circle_fill,
                  color: Colors.teal.shade600,
                  page: const IniciarTurnoPage(),
                ),
                const SizedBox(height: 20),
                
                // ===== TRAVA DE SEGURANÇA =====
                // O botão de Gerenciar Rotas SÓ aparece se for Admin
                if (_isAdmin) ...[
                  _buildMenuButton(
                    context: context,
                    title: 'Rotas',
                    subtitle: 'Organizar ordem e visualização',
                    icon: Icons.route,
                    color: Colors.purple.shade600,
                    page: const GerenciarRotasPage(),
                  ),
                  const SizedBox(height: 20),
                ],

                _buildMenuButton(
                  context: context,
                  title: 'Formulário',
                  subtitle: 'Lista de semáforos da rota ativa',
                  icon: Icons.list_alt,
                  color: Colors.orange.shade600,
                  page: const FormularioRotaPage(),
                ),
                const SizedBox(height: 20),

                _buildMenuButton(
                  context: context,
                  title: 'Relatórios',
                  subtitle: 'Consulte o histórico de vistorias',
                  icon: Icons.history_edu,
                  color: Colors.blue.shade600,
                  page: const RelatoriosPage(),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildMenuButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Widget page,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => page));
      },
      child: Row(
        children: [
          Icon(icon, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.white70)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios),
        ],
      ),
    );
  }
}