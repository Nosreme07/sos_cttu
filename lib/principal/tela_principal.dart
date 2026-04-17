import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Importações relativas diretas para evitar ambiguidade
import 'equipes/tela_equipes.dart';
import 'busca/tela_busca.dart';
import 'cadastros/tela_cadastro.dart';
import 'dashboard/tela_dashboard.dart';
import 'relatorios/tela_relatorios.dart';
import 'programacao/tela_programacao.dart';
import 'vistoria/vistoria_principal.dart'; // <-- NOVO IMPORT DA VISTORIA

// Importamos as ocorrências com o apelido "oc" para acabar com o conflito!
import 'ocorrencias/tela_ocorrencias.dart' as oc;
import 'ocorrencias/tela_mapa_ocorrencias.dart';

// Importação do MENU REUTILIZÁVEL
import '../widgets/menu_usuario.dart';

class TelaPrincipal extends StatefulWidget {
  const TelaPrincipal({super.key});

  @override
  State<TelaPrincipal> createState() => _TelaPrincipalState();
}

class _TelaPrincipalState extends State<TelaPrincipal> {
  String _perfilUsuario = '';
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _buscarPerfilUsuario();
  }

  Future<void> _buscarPerfilUsuario() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // 1ª TENTATIVA: Buscar pelo UID do Firebase
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get();
        if (doc.exists && doc.data() != null) {
          var dados = doc.data() as Map<String, dynamic>;
          if (dados['perfil'] != null && dados['perfil'].toString().isNotEmpty) {
            setState(() {
              _perfilUsuario = dados['perfil'].toString().toLowerCase().trim();
              _carregando = false;
            });
            return;
          }
        }

        // 2ª TENTATIVA: Buscar pelo E-mail do Firebase (Fallback)
        QuerySnapshot query = await FirebaseFirestore.instance.collection('usuarios').where('email', isEqualTo: user.email).limit(1).get();
        if (query.docs.isNotEmpty) {
          var dados = query.docs.first.data() as Map<String, dynamic>;
          if (dados['perfil'] != null && dados['perfil'].toString().isNotEmpty) {
            setState(() {
              _perfilUsuario = dados['perfil'].toString().toLowerCase().trim();
              _carregando = false;
            });
            return;
          }
        }
      } catch (e) {
        debugPrint("Erro ao buscar perfil: $e");
      }
    }
    
    // Se der erro ou não achar o perfil no banco, libera a tela, mas fica vazio
    setState(() {
      _carregando = false;
    });
  }

  // ==========================================
  // LÓGICA DE CONTROLE DE ACESSO
  // ==========================================
  bool _temAcesso(String tela) {
    // Normaliza o perfil removendo acentos para evitar bugs (ex: "técnica" vs "tecnica")
    String perfil = _perfilUsuario
        .replaceAll('é', 'e')
        .replaceAll('á', 'a')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');

    // Se estiver sem perfil, bloqueia tudo
    if (perfil.isEmpty) return false;

    // 1. ADMINS E DEVS ACESSAM TUDO
    if (perfil.contains('administrador') || perfil.contains('desenvolvedor')) {
      return true;
    }

    // 2. REGRAS ESPECÍFICAS POR PERFIL
    switch (tela) {
      case 'dashboard':
        return perfil.contains('operador central');
        
      case 'ocorrencias':
        return perfil.contains('operador central') || perfil.contains('callcenter');
        
      case 'mapa':
        return perfil.contains('operador central')|| perfil.contains('equipe tecnica');
        
      case 'relatorios':
        return perfil.contains('operador central');
        
      case 'equipes':
        return perfil.contains('operador central');
        
      case 'cadastros':
        return false; // Apenas admin e dev (já liberados na regra #1 lá no topo)
        
      case 'programacao':
        return perfil.contains('operador central') || perfil.contains('equipe tecnica');
        
      case 'busca':
        return perfil.contains('operador central') || perfil.contains('callcenter') || perfil.contains('vistoriador') || perfil.contains('equipe tecnica');
      
      // Nova regra da Vistoria bloqueando Callcenter e Equipe  
      case 'vistoria':
        return perfil.contains('operador central') || perfil.contains('vistoriador');
        
      default:
        return false;
    }
  }

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

          if (_carregando)
            const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            )
          else if (_perfilUsuario.isEmpty)
            // AVISO PARA QUANDO O BANCO NÃO TIVER O PERFIL DO USUÁRIO
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12)
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, color: Colors.red, size: 40),
                    SizedBox(height: 10),
                    Text('Perfil não identificado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                    SizedBox(height: 5),
                    Text('Sua conta não possui permissões cadastradas no sistema.', style: TextStyle(color: Colors.black87)),
                  ],
                ),
              ),
            )
          else
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
                      if (_temAcesso('dashboard'))
                        _buildCardWithImage(context, 'Dashboard', 'assets/images/dashboard.png', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaDashboard()));
                        }),
                      
                      if (_temAcesso('ocorrencias'))
                        _buildCardWithImage(context, 'Lista de\nOcorrências', 'assets/images/ocorrencias.png', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const oc.ListaOcorrencias()));
                        }),
                      
                      if (_temAcesso('mapa'))
                        _buildCardWithImage(context, 'Mapa de\nOcorrências', 'assets/images/mapas.png', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaMapaOcorrencias()));
                        }),

                      // <-- NOVO BOTÃO DA VISTORIA AQUI -->
                      if (_temAcesso('vistoria'))
                        _buildCardWithImage(context, 'Vistoria', 'assets/images/vistoria.png', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const VistoriaPrincipal()));
                        }),
                      
                      if (_temAcesso('relatorios'))
                        _buildCardWithImage(context, 'Relatórios', 'assets/images/relatorios.png', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaRelatorios()));
                        }),
                      
                      if (_temAcesso('equipes'))
                        _buildCardWithImage(context, 'Gerenciar Equipes', 'assets/images/equipe.png', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaEquipes()));
                        }),
                      
                      if (_temAcesso('cadastros'))
                        _buildCardWithImage(context, 'Cadastros', 'assets/images/cadastros.png', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaCadastros()));
                        }),
                      
                      if (_temAcesso('programacao'))
                        _buildCardWithImage(context, 'Programação', 'assets/images/programacao.png', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaProgramacao()));
                        }),
                      
                      if (_temAcesso('busca'))
                        _buildCardWithImage(context, 'Busca Semafórica', 'assets/images/localizacao.png', () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const TelaBusca()));
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

  Widget _buildBaseCard(BuildContext context, String titulo, Widget conteudoGrafico, VoidCallback onTap) {
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
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 60, child: Center(child: conteudoGrafico)),
              const SizedBox(height: 10),
              Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF333A4A)), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardWithImage(BuildContext context, String titulo, String caminhoImagem, VoidCallback onTap) {
    return _buildBaseCard(context, titulo, Image.asset(caminhoImagem, height: 85, fit: BoxFit.contain), onTap);
  }
}