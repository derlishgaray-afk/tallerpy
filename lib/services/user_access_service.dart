import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ActivationContact {
  final String e164;
  final String digits;

  const ActivationContact({required this.e164, required this.digits});
}

class UserAccessService {
  static const int trialDays = 7;

  // Cambia este numero si cambia el contacto del administrador.
  static const String activationWhatsappFallbackE164 = '+595986872691';
  static const String activationWhatsappFallbackDigits = '595986872691';

  static DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static Future<void> ensureUserAccessDocument(User user) async {
    try {
      final userRef = _userRef(user.uid);
      final userSnap = await userRef.get();
      final now = DateTime.now();
      final trialEnd = now.add(const Duration(days: trialDays));

      if (!userSnap.exists) {
        await userRef.set({
          'email': user.email,
          'displayName': user.displayName,
          'isActive': false,
          'trialStartedAt': Timestamp.fromDate(now),
          'trialEndsAt': Timestamp.fromDate(trialEnd),
          'profile': {
            'name': '',
            'owner': '',
            'address': '',
            'phone': '',
            'ruc': '',
          },
          'settings': {
            'theme': 'system',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final data = userSnap.data() ?? <String, dynamic>{};
      final updates = <String, dynamic>{};

      if (data['trialStartedAt'] == null || data['trialEndsAt'] == null) {
        updates['trialStartedAt'] = Timestamp.fromDate(now);
        updates['trialEndsAt'] = Timestamp.fromDate(trialEnd);
      }

      if ((data['email'] == null || data['email'].toString().isEmpty) &&
          user.email != null) {
        updates['email'] = user.email;
      }

      if ((data['displayName'] == null ||
              data['displayName'].toString().isEmpty) &&
          user.displayName != null &&
          user.displayName!.trim().isNotEmpty) {
        updates['displayName'] = user.displayName!.trim();
      }

      if (data['isActive'] == null) {
        updates['isActive'] = false;
      }

      if (data['settings'] == null) {
        updates['settings'] = {
          'theme': 'system',
          'updatedAt': FieldValue.serverTimestamp(),
        };
      }

      if (updates.isNotEmpty) {
        updates['updatedAt'] = FieldValue.serverTimestamp();
        await userRef.set(updates, SetOptions(merge: true));
      }
    } on FirebaseException catch (e) {
      // No bloquea el login si Firestore no permite escribir.
      if (e.code == 'permission-denied') return;
      rethrow;
    }
  }

  static DateTime? readDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static DateTime? authCreatedAt(User user) {
    final raw = user.metadata.creationTime;
    if (raw == null) return null;
    return DateTime(
      raw.year,
      raw.month,
      raw.day,
      raw.hour,
      raw.minute,
      raw.second,
    );
  }

  static DateTime? authTrialEndsAt(User user) {
    final createdAt = authCreatedAt(user);
    if (createdAt == null) return null;
    return createdAt.add(const Duration(days: trialDays));
  }

  static bool trialStillActive(DateTime? trialEndsAt) {
    if (trialEndsAt == null) return false;
    return !DateTime.now().isAfter(trialEndsAt);
  }

  static String activationMessageForUser(User user) {
    final identity = (user.email != null && user.email!.trim().isNotEmpty)
        ? user.email!.trim()
        : user.uid;
    return 'Hola, mi período de prueba de Taller Mecánico terminó y quiero activar mi cuenta. Usuario: $identity';
  }

  static String immediateActivationMessage({User? user}) {
    final identity = (user?.email != null && user!.email!.trim().isNotEmpty)
        ? user.email!.trim()
        : (user?.uid ?? '');

    if (identity.isEmpty) {
      return 'Hola, quiero solicitar activación inmediata para mi cuenta de Taller Mecánico.';
    }

    return 'Hola, quiero solicitar activación inmediata para mi cuenta de Taller Mecánico. Usuario: $identity';
  }

  static String _sanitizeDigits(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    // Soporte basico para numeros locales Paraguay (ej: 0986xxxxxx -> 595986xxxxxx).
    if (digits.startsWith('0')) {
      digits = '595${digits.substring(1)}';
    }
    return digits;
  }

  static ActivationContact fallbackActivationContact() {
    return const ActivationContact(
      e164: activationWhatsappFallbackE164,
      digits: activationWhatsappFallbackDigits,
    );
  }

  static ActivationContact _contactFromRaw(String raw) {
    final digits = _sanitizeDigits(raw);
    if (digits.isEmpty) return fallbackActivationContact();
    return ActivationContact(e164: '+$digits', digits: digits);
  }

  static Future<ActivationContact> resolveActivationContact() async {
    try {
      final admins = await FirebaseFirestore.instance
          .collection('users')
          .where('isAdmin', isEqualTo: true)
          .limit(1)
          .get();

      if (admins.docs.isEmpty) return fallbackActivationContact();

      final data = admins.docs.first.data();
      final profile = (data['profile'] as Map<String, dynamic>?) ?? {};

      final raw = (data['activationWhatsapp'] ?? profile['phone'] ?? '')
          .toString();

      if (raw.trim().isEmpty) return fallbackActivationContact();
      return _contactFromRaw(raw);
    } on FirebaseException catch (_) {
      return fallbackActivationContact();
    }
  }
}
