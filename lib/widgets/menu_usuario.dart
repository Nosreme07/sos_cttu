import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Importe a sua tela de login para podermos redirecionar o usuário ao sair
import '../login/tela_login.dart';

class MenuUsuario extends StatelessWidget {
  const MenuUsuario({super.key});

  // Função para fazer o logout
  Future<void> _sairDoSistema(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      // Remove todas as telas do histórico e joga o usuário de volta pro Login
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const TelaLogin()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pega o ID do usuário logado no Firebase Auth
    final usuarioAtual = FirebaseAuth.instance.currentUser;

    if (usuarioAtual == null) {
      return const SizedBox.shrink(); // Se não tiver ninguém logado, não mostra nada
    }

    // Busca os dados complementares (nome, perfil) lá do Firestore em tempo real
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('usuarios').doc(usuarioAtual.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data?.data() == null) {
          // Enquanto carrega, mostra um botão genérico
          return const Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
          );
        }

        var dados = snapshot.data!.data() as Map<String, dynamic>;
        String username = dados['username'] ?? 'Usuário';
        String perfil = dados['perfil'] ?? 'Sem Perfil';
        String inicial = username.isNotEmpty ? username[0].toUpperCase() : 'U';

        return Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: PopupMenuButton<String>(
            offset: const Offset(0, 50), // Empurra o menu um pouco para baixo
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tooltip: 'Opções da Conta',
            // O botão visual que fica na barra superior
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.blueAccent,
                  child: Text(inicial, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                const Icon(Icons.arrow_drop_down, color: Colors.white),
              ],
            ),
            // O conteúdo que "cai" ao clicar (igual ao seu print)
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                enabled: false, // Desabilita o clique nesta área, serve só como visualização
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: Color(0xFFE3F2FD),
                        child: Icon(Icons.person, size: 40, color: Color(0xFF1976D2)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        username,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                      ),
                      Text(
                        perfil.toUpperCase(),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const PopupMenuDivider(), // Uma linhazinha separadora
              PopupMenuItem<String>(
                value: 'sair',
                child: SizedBox(
                  width: double.infinity, // Ocupa toda a largura do menu
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF5350), // Vermelho igual ao seu print
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () {
                      Navigator.pop(context); // Fecha o menu flutuante
                      _sairDoSistema(context); // Executa o logout
                    },
                    child: const Text('Sair do Sistema', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}