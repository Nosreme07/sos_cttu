import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ListaUsuarios extends StatefulWidget {
  const ListaUsuarios({super.key});

  @override
  State<ListaUsuarios> createState() => _ListaUsuariosState();
}

class _ListaUsuariosState extends State<ListaUsuarios> {
  // Lista de perfis para o Dropdown
  final List<String> _perfis = [
    'Callcenter', 'Vistoriador', 'Equipe técnica',
    'Operador central', 'Administrador', 'Desenvolvedor'
  ];

  // --- Função para Excluir Usuário ---
  Future<void> _deletarUsuario(String docId, String nome) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Usuário'),
        content: Text('Tem certeza que deseja excluir o usuário $nome?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirmar) {
      try {
        await FirebaseFirestore.instance.collection('usuarios').doc(docId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Usuário excluído!'), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao excluir.'), backgroundColor: Colors.red));
        }
      }
    }
  }

  // --- Função que abre o MODAL para ADICIONAR ou EDITAR ---
  void _abrirModalFormulario({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: dadosAtuais?['nomeCompleto'] ?? '');
    final usuarioController = TextEditingController(text: dadosAtuais?['username'] ?? '');
    final emailController = TextEditingController(text: dadosAtuais?['email'] ?? '');
    final senhaController = TextEditingController(); // Senha é sempre vazia (para criar ou trocar)
    String? perfilSelecionado = dadosAtuais?['perfil'];
    
    bool ocultarSenha = true;
    bool estaCarregando = false;
    bool isEditando = docId != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite que o modal ocupe quase a tela toda se o teclado abrir
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder( // StatefulBuilder é necessário para atualizar a tela dentro do modal (ex: mostrar/ocultar senha)
          builder: (context, setStateModal) {
            return Padding(
              // Este padding faz o modal subir junto com o teclado do celular
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          isEditando ? 'Editar Usuário' : 'Novo Usuário',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: nomeController,
                          decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                          validator: (value) => value!.isEmpty ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: usuarioController,
                          decoration: const InputDecoration(labelText: 'Usuário (nome.sobrenome)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge)),
                          // Se estiver editando, não deixa mudar o nome de usuário (boa prática)
                          enabled: !isEditando,
                          validator: (value) {
                            if (value!.isEmpty) return 'Obrigatório';
                            if (!value.contains('.')) return 'Formato inválido';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: emailController,
                          decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                          enabled: !isEditando, // E-mail é chave no Firebase Auth, melhor não permitir edição direta aqui
                          validator: (value) => !value!.contains('@') ? 'E-mail inválido' : null,
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Perfil de Acesso', border: OutlineInputBorder(), prefixIcon: Icon(Icons.admin_panel_settings)),
                          value: perfilSelecionado,
                          items: _perfis.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (val) => setStateModal(() => perfilSelecionado = val),
                          validator: (value) => value == null ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        // Campo de senha. Se for edição, a senha não é obrigatória (só preenche se quiser trocar)
                        TextFormField(
                          controller: senhaController,
                          obscureText: ocultarSenha,
                          decoration: InputDecoration(
                            labelText: isEditando ? 'Nova Senha (deixe em branco para não alterar)' : 'Senha',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(ocultarSenha ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setStateModal(() => ocultarSenha = !ocultarSenha),
                            ),
                          ),
                          validator: (value) {
                            if (!isEditando && value!.isEmpty) return 'Obrigatório';
                            if (value!.isNotEmpty && !RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{7,}$').hasMatch(value)) {
                              return 'Mínimo 7 caracteres, c/ letra e número';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF262C38),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: estaCarregando ? null : () async {
                            if (formKey.currentState!.validate()) {
                              setStateModal(() => estaCarregando = true);

                              try {
                                if (isEditando) {
                                  // --- LÓGICA DE ATUALIZAÇÃO ---
                                  await FirebaseFirestore.instance.collection('usuarios').doc(docId).update({
                                    'nomeCompleto': nomeController.text.trim().toUpperCase(),
                                    'perfil': perfilSelecionado,
                                  });
                                  // Nota: Se a senha for preenchida na edição, envolveria lógica complexa no Auth (precisa relogar),
                                  // então, em sistemas simples, atualizamos apenas dados de perfil.
                                  
                                  if (mounted) Navigator.pop(context); // Fecha o modal
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado com sucesso!'), backgroundColor: Colors.green));

                                } else {
                                  // --- LÓGICA DE CRIAÇÃO (Igual à tela anterior) ---
                                  UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                                    email: emailController.text.trim(),
                                    password: senhaController.text,
                                  );

                                  await FirebaseFirestore.instance.collection('usuarios').doc(cred.user!.uid).set({
                                    'nomeCompleto': nomeController.text.trim().toUpperCase(),
                                    'username': usuarioController.text.trim().toLowerCase(),
                                    'email': emailController.text.trim().toLowerCase(),
                                    'perfil': perfilSelecionado,
                                    'dataCadastro': FieldValue.serverTimestamp(),
                                    'ativo': true,
                                  });

                                  if (mounted) Navigator.pop(context); // Fecha o modal
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Criado com sucesso!'), backgroundColor: Colors.green));
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
                              } finally {
                                setStateModal(() => estaCarregando = false);
                              }
                            }
                          },
                          child: estaCarregando 
                              ? const CircularProgressIndicator(color: Colors.white) 
                              : Text(isEditando ? 'ATUALIZAR' : 'CADASTRAR', style: const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Lista de Usuários', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF262C38),
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Novo Usuário', style: TextStyle(color: Colors.white)),
        // Ao clicar em novo, chama a função do Modal SEM passar ID (Modo Criação)
        onPressed: () => _abrirModalFormulario(),
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
          
          Padding(
            padding: const EdgeInsets.only(top: 100.0, left: 16.0, right: 16.0, bottom: 16.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('usuarios').orderBy('nomeCompleto').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
                    if (snapshot.hasError) return const Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.white)));
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Nenhum usuário cadastrado.', style: TextStyle(color: Colors.white, fontSize: 18)));

                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        var doc = snapshot.data!.docs[index];
                        var data = doc.data() as Map<String, dynamic>;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          color: Colors.white.withValues(alpha: 0.95),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF262C38),
                              child: Text(
                                data['nomeCompleto'] != null && data['nomeCompleto'].isNotEmpty ? data['nomeCompleto'][0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(data['nomeCompleto'] ?? 'Sem Nome', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('User: ${data['username'] ?? ''}'),
                                Text('Perfil: ${data['perfil'] ?? ''}', style: const TextStyle(color: Colors.blueGrey)),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Ao clicar no Editar, chama a mesma função, mas PASSANDO OS DADOS ATUAIS
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _abrirModalFormulario(docId: doc.id, dadosAtuais: data),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deletarUsuario(doc.id, data['nomeCompleto'] ?? 'este usuário'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}