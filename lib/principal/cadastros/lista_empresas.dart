import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // Necessário para os formatadores de texto
import 'package:brasil_fields/brasil_fields.dart'; // O nosso novo pacote de máscaras BR

import '../../widgets/menu_usuario.dart';

class ListaEmpresas extends StatefulWidget {
  const ListaEmpresas({super.key});

  @override
  State<ListaEmpresas> createState() => _ListaEmpresasState();
}

class _ListaEmpresasState extends State<ListaEmpresas> {
  // --- Função para Excluir Empresa ---
  Future<void> _deletarEmpresa(String docId, String nome) async {
    bool confirmar =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir Empresa'),
            content: Text('Tem certeza que deseja excluir a empresa $nome?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Excluir',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmar) {
      try {
        await FirebaseFirestore.instance
            .collection('empresas')
            .doc(docId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Empresa excluída!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro ao excluir.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // --- Função que abre o MODAL para ADICIONAR ou EDITAR ---
  void _abrirModalFormulario({
    String? docId,
    Map<String, dynamic>? dadosAtuais,
  }) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(
      text: dadosAtuais?['nome'] ?? '',
    );
    final cnpjController = TextEditingController(
      text: dadosAtuais?['cnpj'] ?? '',
    );
    final enderecoController = TextEditingController(
      text: dadosAtuais?['endereco'] ?? '',
    );
    final contatoController = TextEditingController(
      text: dadosAtuais?['contato'] ?? '',
    );

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
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
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
                          isEditando ? 'Editar Empresa' : 'Nova Empresa',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // NOME (Único campo Obrigatório)
                        TextFormField(
                          controller: nomeController,
                          decoration: const InputDecoration(
                            labelText: 'Nome da Empresa *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.business),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'O nome da empresa é obrigatório'
                              : null,
                        ),
                        const SizedBox(height: 12),

                        // CNPJ (Opcional e com Máscara)
                        TextFormField(
                          controller: cnpjController,
                          decoration: const InputDecoration(
                            labelText: 'CNPJ',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.assignment_ind),
                          ),
                          keyboardType: TextInputType
                              .number, // Abre o teclado numérico no celular
                          inputFormatters: [
                            FilteringTextInputFormatter
                                .digitsOnly, // Aceita só números
                            CnpjInputFormatter(), // Aplica a máscara XX.XXX.XXX/XXXX-XX automaticamente
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ENDEREÇO (Opcional)
                        TextFormField(
                          controller: enderecoController,
                          decoration: const InputDecoration(
                            labelText: 'Endereço',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_on),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // CONTATO (Opcional e com Máscara inteligente para Fixo e Celular)
                        TextFormField(
                          controller: contatoController,
                          decoration: const InputDecoration(
                            labelText: 'Contato (Telefone/Celular)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.contact_phone),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            TelefoneInputFormatter(), // Adapta sozinho para (XX) XXXX-XXXX ou (XX) XXXXX-XXXX
                          ],
                        ),
                        const SizedBox(height: 24),

                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF262C38),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: estaCarregando
                              ? null
                              : () async {
                                  if (formKey.currentState!.validate()) {
                                    setStateModal(() => estaCarregando = true);

                                    try {
                                      final dadosEmpresa = {
                                        'nome': nomeController.text
                                            .trim()
                                            .toUpperCase(),
                                        'cnpj': cnpjController.text.trim(),
                                        'endereco': enderecoController.text
                                            .trim(),
                                        'contato': contatoController.text
                                            .trim(),
                                        'dataAtualizacao':
                                            FieldValue.serverTimestamp(),
                                      };

                                      if (isEditando) {
                                        await FirebaseFirestore.instance
                                            .collection('empresas')
                                            .doc(docId)
                                            .update(dadosEmpresa);
                                        if (mounted) Navigator.pop(context);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Atualizado com sucesso!',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      } else {
                                        dadosEmpresa['dataCadastro'] =
                                            FieldValue.serverTimestamp();
                                        await FirebaseFirestore.instance
                                            .collection('empresas')
                                            .add(dadosEmpresa);
                                        if (mounted) Navigator.pop(context);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Criado com sucesso!',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Erro: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    } finally {
                                      setStateModal(
                                        () => estaCarregando = false,
                                      );
                                    }
                                  }
                                },
                          child: estaCarregando
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  isEditando ? 'ATUALIZAR' : 'CADASTRAR',
                                  style: const TextStyle(color: Colors.white),
                                ),
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
        title: const Text(
          'Lista de Empresas',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [MenuUsuario()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF262C38),
        icon: const Icon(Icons.add_business, color: Colors.white),
        label: const Text(
          'Nova Empresa',
          style: TextStyle(color: Colors.white),
        ),
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
            padding: const EdgeInsets.only(
              top: 100.0,
              left: 16.0,
              right: 16.0,
              bottom: 16.0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('empresas')
                      .orderBy('nome')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting)
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    if (snapshot.hasError)
                      return const Center(
                        child: Text(
                          'Erro ao carregar dados.',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                      return const Center(
                        child: Text(
                          'Nenhuma empresa cadastrada.',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      );

                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        var doc = snapshot.data!.docs[index];
                        var data = doc.data() as Map<String, dynamic>;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          color: Colors.white.withValues(alpha: 0.95),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFF262C38),
                              child: Icon(Icons.factory, color: Colors.white),
                            ),
                            title: Text(
                              data['nome'] ?? 'Sem Nome',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Só mostra o CNPJ e Contato na lista se a pessoa tiver preenchido
                                if (data['cnpj'] != null &&
                                    data['cnpj'].toString().isNotEmpty)
                                  Text('CNPJ: ${data['cnpj']}'),
                                if (data['contato'] != null &&
                                    data['contato'].toString().isNotEmpty)
                                  Text(
                                    'Contato: ${data['contato']}',
                                    style: const TextStyle(
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => _abrirModalFormulario(
                                    docId: doc.id,
                                    dadosAtuais: data,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deletarEmpresa(
                                    doc.id,
                                    data['nome'] ?? 'esta empresa',
                                  ),
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
