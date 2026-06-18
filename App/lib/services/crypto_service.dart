import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;

class CryptoService {
  // 💡 AES-256 requires exactly a 32-byte key. 
  // In a real production app, fetch this from a secure backend or .env file.
  static final _key = encrypt.Key.fromUtf8('eduportal_secure_key_32_bytes_!!'); 
  static final _iv = encrypt.IV.fromUtf8('eduportal_iv_16b'); // 16 bytes for IV

  static final _encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));

  /// Encrypts a JSON Map into a secure Base64 cipher string
  static String encryptPayload(Map<String, dynamic> data) {
    try {
      final jsonString = jsonEncode(data);
      final encrypted = _encrypter.encrypt(jsonString, iv: _iv);
      return encrypted.base64;
    } catch (e) {
      return '';
    }
  }

  /// Decrypts a secure Base64 cipher string back into a JSON Map
  static Map<String, dynamic>? decryptPayload(String encryptedBase64) {
    try {
      final decrypted = _encrypter.decrypt64(encryptedBase64, iv: _iv);
      return jsonDecode(decrypted) as Map<String, dynamic>;
    } catch (e) {
      // 💡 If decryption fails, it means the QR code is NOT from our app (or is tampered with)
      return null; 
    }
  }
}