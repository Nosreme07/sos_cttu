import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sos_cttu/login/tela_login.dart';
import 'firebase_options.dart';

// Importação da Tela Principal que inicia o sistema
import 'principal/tela_principal.dart'; 
// import 'login/tela_login.dart'; // <-- Descomente essa linha e troque abaixo se o seu app começar pelo Login

void main() async {
  // 1. Garante que os widgets do Flutter estão iniciados antes do Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Inicializa o banco de dados
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 3. Dá a partida no aplicativo
  runApp(const SosApp());
}

class SosApp extends StatelessWidget {
  const SosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SOS CTTU',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Padronizando o AppBar para todo o sistema (como estava no seu projeto)
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF262C38),
          foregroundColor: Colors.white, 
          elevation: 0,
        ),
      ),
      // Aponta para a tela inicial do sistema
      home: const TelaPrincipal(), 
    );
  }
}