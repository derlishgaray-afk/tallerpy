import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/user_access_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'operation-not-allowed':
        return 'Este método no está habilitado en Firebase Auth.';
      case 'popup-closed-by-user':
        return 'Se canceló el inicio de sesión.';
      case 'user-disabled':
        return 'Esta cuenta fue deshabilitada.';
      default:
        return e.message ?? e.code;
    }
  }

  Future<void> _signInWithProvider(AuthProvider provider) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = FirebaseAuth.instance;
      final cred = kIsWeb
          ? await auth.signInWithPopup(provider)
          : await auth.signInWithProvider(provider);

      if (cred.user != null) {
        try {
          await UserAccessService.ensureUserAccessDocument(cred.user!);
        } catch (_) {
          // Si falla Firestore no se bloquea el inicio de sesión.
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _mapAuthError(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    provider.addScope('email');
    await _signInWithProvider(provider);
  }

  Future<void> _signInWithApple() async {
    final provider = AppleAuthProvider();
    provider.addScope('email');
    provider.addScope('name');
    await _signInWithProvider(provider);
  }

  Future<void> _requestImmediateActivation() async {
    final contact = await UserAccessService.resolveActivationContact();
    final message = UserAccessService.immediateActivationMessage(
      user: FirebaseAuth.instance.currentUser,
    );
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

    if (!launchedApp && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ingreso al Taller')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Inicia sesión con Google o Apple. Si no tienes cuenta, se crea automáticamente.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Si ya te registraste, usa el mismo proveedor para ingresar.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Las cuentas nuevas tienen 7 días de prueba.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _signInWithGoogle,
                    icon: const Icon(Icons.g_mobiledata),
                    label: const Text('Ingresar con Google'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _signInWithApple,
                    icon: const Icon(Icons.apple),
                    label: const Text('Ingresar con Apple'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _requestImmediateActivation,
                    icon: const Icon(Icons.message_outlined),
                    label: const Text('Solicitar activación inmediata'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
