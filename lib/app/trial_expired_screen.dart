import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/user_access_service.dart';

/// Pantalla de prueba vencida (usuario sigue logueado).
class TrialExpiredScreen extends StatelessWidget {
  final DateTime? trialEndsAt;

  const TrialExpiredScreen({super.key, required this.trialEndsAt});

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _openActivationWhatsapp(
    BuildContext context,
    ActivationContact contact,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final message = user == null
        ? 'Hola, quiero activar mi cuenta de Taller Mecanico.'
        : UserAccessService.activationMessageForUser(user);
    final encoded = Uri.encodeComponent(message);

    final webUri = Uri.parse('https://wa.me/${contact.digits}?text=$encoded');
    final appUri = Uri.parse(
      'whatsapp://send?phone=${contact.digits}&text=$encoded',
    );

    final launchedWeb = await launchUrl(
      webUri,
      mode: LaunchMode.externalApplication,
    );
    if (launchedWeb) return;

    final launchedApp = await launchUrl(
      appUri,
      mode: LaunchMode.externalApplication,
    );

    if (!launchedApp && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expirationText = (trialEndsAt == null)
        ? 'Tu periodo de prueba de 7 dias ha finalizado.'
        : 'Tu periodo de prueba de 7 dias finalizo el ${_formatDate(trialEndsAt!)}.';

    return FutureBuilder<ActivationContact>(
      future: UserAccessService.resolveActivationContact(),
      builder: (context, contactSnap) {
        final contact =
            contactSnap.data ?? UserAccessService.fallbackActivationContact();

        return Scaffold(
          appBar: AppBar(title: const Text('Prueba finalizada')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_clock_outlined, size: 56),
                        const SizedBox(height: 16),
                        const Text(
                          'Tu cuenta requiere activacion',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '$expirationText\n\nSolicita activacion por WhatsApp al administrador ${contact.e164}.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () =>
                                _openActivationWhatsapp(context, contact),
                            icon: const Icon(Icons.message_outlined),
                            label: const Text(
                              'Solicitar activacion por WhatsApp',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _logout,
                            icon: const Icon(Icons.logout),
                            label: const Text('Cerrar sesion'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
