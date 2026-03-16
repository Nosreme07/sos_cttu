import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/menu_usuario.dart'; 

class ListaOrigens extends StatefulWidget {
  const ListaOrigens({super.key});

  @override
  State<ListaOrigens> createState() => _ListaOrigensState();
}

class _ListaOrigensState extends State<ListaOrigens> {
  // Controladores para a busca
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  // --- Função para Excluir Origem ---
  Future<void> _deletarOrigem(String docId, String nomeOrigem) async {
    bool confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Origem'),
        content: Text('Tem certeza que deseja excluir a origem "$nomeOrigem"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
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
        await FirebaseFirestore.instance.collection('origens').doc(docId).delete();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Origem excluída!'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao excluir.'), backgroundColor: Colors.red));
      }
    }
  }

  // --- Função que abre o MODAL para ADICIONAR ou EDITAR ---
  void _abrirModalFormulario({String? docId, Map<String, dynamic>? dadosAtuais}) {
    final formKey = GlobalKey<FormState>();
    final origemController = TextEditingController(text: dadosAtuais?['origem'] ?? '');
    
    bool estaCarregando = false;
    bool isEditando = docId != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
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
                          isEditando ? 'Editar Origem' : 'Nova Origem',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // ÚNICO CAMPO: ORIGEM
                        TextFormField(
                          controller: origemController,
                          decoration: const InputDecoration(
                            labelText: 'Nome da Origem *', 
                            border: OutlineInputBorder(), 
                            prefixIcon: Icon(Icons.share_location)
                          ),
                          validator: (value) => value == null || value.trim().isEmpty ? 'Obrigatório' : null,
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
                                final dadosOrigem = {
                                  'origem': origemController.text.trim().toUpperCase(),
                                  'dataAtualizacao': FieldValue.serverTimestamp(),
                                };

                                if (isEditando) {
                                  await FirebaseFirestore.instance.collection('origens').doc(docId).update(dadosOrigem);
                                  if (mounted) Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado com sucesso!'), backgroundColor: Colors.green));
                                } else {
                                  dadosOrigem['dataCadastro'] = FieldValue.serverTimestamp(); 
                                  await FirebaseFirestore.instance.collection('origens').add(dadosOrigem);
                                  if (mounted) Navigator.pop(context);
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
        title: const Text('Gestão de Origens', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [ MenuUsuario() ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF262C38),
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: const Text('Nova Origem', style: TextStyle(color: Colors.white)),
        onPressed: () => _abrirModalFormulario(),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fundo
          Image.asset(
            'assets/images/tela.png',
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.4),
            colorBlendMode: BlendMode.darken,
          ),
          
          Column(
            children: [
              const SizedBox(height: 100), // Espaço abaixo da AppBar
              
              // BARRA DE PESQUISA
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _buscaController,
                  decoration: InputDecoration(
                    hintText: 'Buscar origem...',
                    prefixIcon: const Icon(Icons.search),
                    fillColor: Colors.white.withValues(alpha: 0.95),
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (valor) {
                    setState(() { _termoBusca = valor.toLowerCase(); });
                  },
                ),
              ),

              // LISTA DO FIREBASE
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('origens').orderBy('origem').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
                        if (snapshot.hasError) return const Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.white)));
                        
                        final docs = snapshot.data?.docs ?? [];
                        
                        if (docs.isEmpty) return const Center(child: Text('Nenhuma origem cadastrada.', style: TextStyle(color: Colors.white, fontSize: 18)));

                        return ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            var doc = docs[index];
                            var data = doc.data() as Map<String, dynamic>;

                            String nomeOrigem = data['origem'] ?? 'Sem Nome';

                            // Lógica do filtro de pesquisa
                            if (_termoBusca.isNotEmpty && !nomeOrigem.toLowerCase().contains(_termoBusca)) {
                              return const SizedBox.shrink(); 
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12.0),
                              color: Colors.white.withValues(alpha: 0.95),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFF262C38), 
                                  child: Icon(Icons.share_location, color: Colors.white, size: 20),
                                ),
                                title: Text(nomeOrigem, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _abrirModalFormulario(docId: doc.id, dadosAtuais: data),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deletarOrigem(doc.id, nomeOrigem),
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
        ],
      ),
    );
  }
}