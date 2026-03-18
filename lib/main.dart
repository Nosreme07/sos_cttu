import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sos_cttu/principal/tela_principal.dart';

// O arquivo de configuração do Firebase que está na mesma pasta (lib)
import 'firebase_options.dart';

// Importando a tela principal respeitando a sua nova pasta "principal"
import 'login/tela_login.dart';

void main() async {
  // Garante que o Flutter está pronto antes de conectar ao Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o Firebase para a plataforma correta (Web, Android ou iOS)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Inicia o aplicativo
  runApp(const SosApp());
}

// Classe principal que configura o tema global do aplicativo
class SosApp extends StatelessWidget {
  const SosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SOS - Sistema de Ocorrências Semafóricas',
      debugShowCheckedModeBanner: false, // Remove a faixa lateral de "DEBUG"
      // Configuração global de cores e design
      theme: ThemeData(
        primaryColor: const Color(0xFF262C38),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF262C38),
          // Se quiser o sistema em modo escuro padrão, mude para Brightness.dark
          brightness: Brightness.light,
        ),
        useMaterial3: true,

        // Padronizando o AppBar para todo o sistema
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF262C38),
          foregroundColor: Colors.white, // Cor dos ícones e textos do AppBar
          elevation: 0,
        ),
      ),

      // Aponta para a tela principal (com o fundo do semáforo e os botões dos módulos)
      home: const TelaPrincipal(),
    );
  }
}
