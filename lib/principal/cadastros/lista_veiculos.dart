import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:brasil_fields/brasil_fields.dart'; // Para a máscara da Placa

import '../../widgets/menu_usuario.dart';

class ListaVeiculos extends StatefulWidget {
  const ListaVeiculos({super.key});

  @override
  State<ListaVeiculos> createState() => _ListaVeiculosState();
}

class _ListaVeiculosState extends State<ListaVeiculos> {
  // Lista de tipos de veículos
  final List<String> _tiposVeiculo = [
    'Moto',
    'Carro Passeio',
    'Carro com Cesto',
    'Pick-up',
    'Caminhão Munck',
  ];

  // --- Função para Excluir Veículo ---
  Future<void> _deletarVeiculo(String docId, String placa) async {
    bool confirmar =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir Veículo'),
            content: Text(
              'Tem certeza que deseja excluir o veículo placa $placa?',
            ),
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
            .collection('veiculos')
            .doc(docId)
            .delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Veículo excluído!'),
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
    final marcaController = TextEditingController(
      text: dadosAtuais?['marca'] ?? '',
    );
    final modeloController = TextEditingController(
      text: dadosAtuais?['modelo'] ?? '',
    );
    final placaController = TextEditingController(
      text: dadosAtuais?['placa'] ?? '',
    );
    final empresaController = TextEditingController(
      text: dadosAtuais?['empresa'] ?? '',
    );
    String? tipoSelecionado = dadosAtuais?['tipo'];

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
                          isEditando ? 'Editar Veículo' : 'Novo Veículo',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // PLACA (Obrigatório e com Máscara)
                        TextFormField(
                          controller: placaController,
                          decoration: const InputDecoration(
                            labelText: 'Placa *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.pin),
                          ),
                          textCapitalization: TextCapitalization
                              .characters, // Força teclado em maiúsculo
                          inputFormatters: [
                            PlacaVeiculoInputFormatter(), // Máscara automática padrão ou Mercosul
                          ],
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'A placa é obrigatória'
                              : null,
                        ),
                        const SizedBox(height: 12),

                        // TIPO (Obrigatório)
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Tipo de Veículo *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.directions_car),
                          ),
                          value: tipoSelecionado,
                          items: _tiposVeiculo
                              .map(
                                (t) =>
                                    DropdownMenuItem(value: t, child: Text(t)),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setStateModal(() => tipoSelecionado = val),
                          validator: (value) =>
                              value == null ? 'Obrigatório' : null,
                        ),
                        const SizedBox(height: 12),

                        // MARCA (Opcional)
                        TextFormField(
                          controller: marcaController,
                          decoration: const InputDecoration(
                            labelText: 'Marca',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.branding_watermark),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // MODELO (Opcional)
                        TextFormField(
                          controller: modeloController,
                          decoration: const InputDecoration(
                            labelText: 'Modelo',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.car_repair),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // EMPRESA (Opcional - Pode ser digitado manualmente por enquanto)
                        TextFormField(
                          controller: empresaController,
                          decoration: const InputDecoration(
                            labelText: 'Empresa',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.factory),
                          ),
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
                                      final dadosVeiculo = {
                                        'placa': placaController.text
                                            .trim()
                                            .toUpperCase(),
                                        'tipo': tipoSelecionado,
                                        'marca': marcaController.text
                                            .trim()
                                            .toUpperCase(),
                                        'modelo': modeloController.text
                                            .trim()
                                            .toUpperCase(),
                                        'empresa': empresaController.text
                                            .trim()
                                            .toUpperCase(),
                                        'dataAtualizacao':
                                            FieldValue.serverTimestamp(),
                                      };

                                      if (isEditando) {
                                        await FirebaseFirestore.instance
                                            .collection('veiculos')
                                            .doc(docId)
                                            .update(dadosVeiculo);
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
                                        dadosVeiculo['dataCadastro'] =
                                            FieldValue.serverTimestamp();
                                        await FirebaseFirestore.instance
                                            .collection('veiculos')
                                            .add(dadosVeiculo);
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
          'Lista de Veículos',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [MenuUsuario()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF262C38),
        icon: const Icon(Icons.add_circle, color: Colors.white),
        label: const Text(
          'Novo Veículo',
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
                      .collection('veiculos')
                      .orderBy('placa')
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
                          'Nenhum veículo cadastrado.',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      );

                    return ListView.builder(
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        var doc = snapshot.data!.docs[index];
                        var data = doc.data() as Map<String, dynamic>;

                        // Descobrir qual o modelo/marca para exibir no título
                        String tituloCarro =
                            '${data['marca'] ?? ''} ${data['modelo'] ?? ''}'
                                .trim();
                        if (tituloCarro.isEmpty)
                          tituloCarro = data['tipo'] ?? 'Veículo';

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
                              child: Icon(
                                Icons.local_shipping,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              tituloCarro,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Placa: ${data['placa']}',
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Tipo: ${data['tipo']}',
                                  style: const TextStyle(
                                    color: Colors.blueGrey,
                                  ),
                                ),
                                if (data['empresa'] != null &&
                                    data['empresa'].toString().isNotEmpty)
                                  Text('Empresa: ${data['empresa']}'),
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
                                  onPressed: () => _deletarVeiculo(
                                    doc.id,
                                    data['placa'] ?? 'este veículo',
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
