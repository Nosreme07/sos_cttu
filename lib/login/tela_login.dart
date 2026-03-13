import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../principal/tela_principal.dart';

class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key});

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _formKey = GlobalKey<FormState>();
  
  // Mudamos de e-mail para usuário
  final _usuarioController = TextEditingController(); 
  final _senhaController = TextEditingController();
  
  bool _ocultarSenha = true;
  bool _estaACaregar = false;

  @override
  void dispose() {
    _usuarioController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  // --- LÓGICA DE LOGIN COM USUÁRIO ---
  Future<void> _fazerLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() { _estaACaregar = true; });

      try {
        String usuarioDigitado = _usuarioController.text.trim().toLowerCase();

        // 1. Busca no Firestore se esse "nome.sobrenome" existe
        var snapshot = await FirebaseFirestore.instance
            .collection('usuarios')
            .where('username', isEqualTo: usuarioDigitado)
            .get();

        if (snapshot.docs.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Usuário não encontrado no sistema.'), backgroundColor: Colors.red),
            );
          }
          setState(() { _estaACaregar = false; });
          return;
        }

        // 2. Se achou, pega o e-mail real atrelado a ele no banco
        String emailDoUsuario = snapshot.docs.first.data()['email'];

        // 3. Faz o login no Firebase Auth usando o e-mail e a senha
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailDoUsuario,
          password: _senhaController.text,
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const TelaPrincipal()),
          );
        }
      } on FirebaseAuthException catch (e) {
        String mensagemErro = 'Erro ao fazer login. Verifique seus dados.';
        if (e.code == 'invalid-credential' || e.code == 'wrong-password') {
          mensagemErro = 'Senha incorreta.';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagemErro), backgroundColor: Colors.red));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro inesperado. Tente novamente.'), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) {
          setState(() { _estaACaregar = false; });
        }
      }
    }
  }

  // --- LÓGICA DE ESQUECI A SENHA ---
  void _mostrarDialogoEsqueciSenha() {
    final resetEmailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar Senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Informe o e-mail associado ao seu usuário para receber o link de redefinição de senha.'),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailController,
              decoration: const InputDecoration(
                labelText: 'Seu E-mail',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Fecha o pop-up
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF262C38)),
            onPressed: () async {
              try {
                // Envia o e-mail padrão do Firebase para redefinir senha
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: resetEmailController.text.trim()
                );
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('E-mail de recuperação enviado!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Erro ao enviar e-mail. Verifique se ele está correto.'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Enviar Link', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // IMAGEM DE FUNDO PADRÃO
          Image.asset(
            'assets/images/tela.png',
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.5),
            colorBlendMode: BlendMode.darken,
          ),
          
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  color: Colors.white.withValues(alpha: 0.95),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 12,
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          
                          // --- A SUA LOGO AQUI ---
                          // Como no pubspec já liberamos a pasta 'assets/images/', o Flutter vai achar!
                          Image.asset(
                            'assets/images/logo.png',
                            height: 100, // Ajuste a altura conforme necessário
                            errorBuilder: (context, error, stackTrace) {
                              // Se a imagem não for encontrada, mostra um ícone de fallback
                              return const Icon(Icons.traffic, size: 80, color: Color(0xFF262C38));
                            },
                          ),
                          const SizedBox(height: 16),
                          
                          const Text(
                            'SOS CTTU',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF262C38)),
                            textAlign: TextAlign.center,
                          ),
                          const Text(
                            'Sistema de Ocorrências Semafóricas',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // --- CAMPO DO USUÁRIO (NOME.SOBRENOME) ---
                          TextFormField(
                            controller: _usuarioController,
                            decoration: const InputDecoration(
                              labelText: 'Usuário (nome.sobrenome)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Informe seu usuário';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // --- CAMPO DA SENHA ---
                          TextFormField(
                            controller: _senhaController,
                            obscureText: _ocultarSenha,
                            decoration: InputDecoration(
                              labelText: 'Senha',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(_ocultarSenha ? Icons.visibility : Icons.visibility_off),
                                onPressed: () {
                                  setState(() { _ocultarSenha = !_ocultarSenha; });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Informe sua senha';
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // --- BOTÃO DE ENTRAR ---
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF262C38),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _estaACaregar ? null : _fazerLogin,
                              child: _estaACaregar
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text('ENTRAR', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // --- BOTÃO DE ESQUECI A SENHA ---
                          TextButton(
                            onPressed: _mostrarDialogoEsqueciSenha,
                            child: const Text(
                              'Esqueci minha senha',
                              style: TextStyle(
                                color: Color(0xFF262C38),
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}