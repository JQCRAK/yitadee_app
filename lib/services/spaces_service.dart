import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class SpacesService {
  SpacesService._();
  static final SpacesService instance = SpacesService._();

  static const _accessKey  = 'DO801KT87LKGCHXVZXUA';
  static const _secretKey  = 'QYTTQO9ysqpw7rTkat4JmAQ9GtZuCJjZsv7lArQE/Rg';
  static const _region     = 'sfo3';
  static const _bucketName = 'app-yitadee';
  static const _host       = '$_bucketName.$_region.digitaloceanspaces.com';
  static const _cdnBase    = 'https://$_bucketName.$_region.cdn.digitaloceanspaces.com';

  // ─── Sube archivo con key específico — retorna URL pública CDN o null ─────
  Future<String?> uploadWithKey(
    String key,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    // ── GUARD: nunca subir bytes vacíos ──────────────────────────────────────
    if (bytes.isEmpty) {
      debugPrint('[SpacesService] ERROR: bytes vacíos para key=$key');
      return null;
    }

    final success = await _upload(key: key, bytes: bytes, contentType: contentType);
    return success ? '$_cdnBase/$key' : null;
  }

  // ─── Upload profile photo ─────────────────────────────────────────────────
  Future<String?> uploadProfilePhoto(String userId, Uint8List imageBytes) async {
    if (imageBytes.isEmpty) return null;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final key = 'profile_photos/${userId}_$timestamp.jpg';
    return uploadWithKey(key, imageBytes);
  }

  // ─── Upload music cover ───────────────────────────────────────────────────
  Future<String?> uploadMusicCover(String songId, Uint8List imageBytes) async {
    if (imageBytes.isEmpty) return null;
    final key = 'music/covers/$songId.jpg';
    return uploadWithKey(key, imageBytes);
  }

  // ─── Upload music track ───────────────────────────────────────────────────
  Future<String?> uploadMusicTrack(String songId, Uint8List audioBytes) async {
    if (audioBytes.isEmpty) return null;
    final key = 'music/tracks/$songId.mp3';
    return uploadWithKey(key, audioBytes, contentType: 'audio/mpeg');
  }

  // ─── Elimina archivo del bucket ───────────────────────────────────────────
  Future<bool> deleteFile(String key) async {
    if (key.isEmpty) return false;
    try {
      final now         = DateTime.now().toUtc();
      final dateStr     = _formatDate(now);
      final dateTimeStr = _formatDateTime(now);

      const emptyHash =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

      final canonicalHeaders =
          'host:$_host\n'
          'x-amz-content-sha256:$emptyHash\n'
          'x-amz-date:$dateTimeStr\n';

      const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

      final canonicalRequest =
          'DELETE\n'
          '/$key\n'
          '\n'
          '$canonicalHeaders\n'
          '$signedHeaders\n'
          '$emptyHash';

      final credentialScope = '$dateStr/$_region/s3/aws4_request';

      final stringToSign =
          'AWS4-HMAC-SHA256\n'
          '$dateTimeStr\n'
          '$credentialScope\n'
          '${sha256.convert(utf8.encode(canonicalRequest))}';

      final signingKey = _signingKey(dateStr);
      final signature  = Hmac(sha256, signingKey)
          .convert(utf8.encode(stringToSign))
          .toString();

      final authorization =
          'AWS4-HMAC-SHA256 '
          'Credential=$_accessKey/$credentialScope, '
          'SignedHeaders=$signedHeaders, '
          'Signature=$signature';

      final url      = Uri.parse('https://$_host/$key');
      final response = await http.delete(
        url,
        headers: {
          'Host':                 _host,
          'x-amz-date':           dateTimeStr,
          'x-amz-content-sha256': emptyHash,
          'Authorization':        authorization,
        },
      );

      return response.statusCode == 204 || response.statusCode == 404;
    } catch (e) {
      debugPrint('[SpacesService] deleteFile error: $e');
      return false;
    }
  }

  // ─── Método interno de subida ─────────────────────────────────────────────
  Future<bool> _upload({
    required String    key,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    // ── GUARD: verificar bytes antes de firmar ───────────────────────────────
    if (bytes.isEmpty) {
      debugPrint('[SpacesService] _upload ERROR: bytes vacíos, key=$key');
      return false;
    }

    try {
      final now         = DateTime.now().toUtc();
      final dateStr     = _formatDate(now);
      final dateTimeStr = _formatDateTime(now);
      final payloadHash = sha256.convert(bytes).toString();

      // ── Content-Length para forzar body en iOS ──────────────────────────
      // NOTA: Content-Length NO se incluye en SignedHeaders porque
      // DigitalOcean Spaces rechaza con 403 cuando está en la firma.
      // Se envía solo en el header del request para forzar el body en iOS.
      final contentLength = bytes.length.toString();

      // SignedHeaders: sin content-length (evita 403 en Spaces)
      final canonicalHeaders =
          'content-type:$contentType\n'
          'host:$_host\n'
          'x-amz-acl:public-read\n'
          'x-amz-content-sha256:$payloadHash\n'
          'x-amz-date:$dateTimeStr\n';

      const signedHeaders =
          'content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date';

      final canonicalRequest =
          'PUT\n'
          '/$key\n'
          '\n'
          '$canonicalHeaders\n'
          '$signedHeaders\n'
          '$payloadHash';

      final credentialScope = '$dateStr/$_region/s3/aws4_request';

      final stringToSign =
          'AWS4-HMAC-SHA256\n'
          '$dateTimeStr\n'
          '$credentialScope\n'
          '${sha256.convert(utf8.encode(canonicalRequest))}';

      final signingKey = _signingKey(dateStr);
      final signature  = Hmac(sha256, signingKey)
          .convert(utf8.encode(stringToSign))
          .toString();

      final authorization =
          'AWS4-HMAC-SHA256 '
          'Credential=$_accessKey/$credentialScope, '
          'SignedHeaders=$signedHeaders, '
          'Signature=$signature';

      final url = Uri.parse('https://$_host/$key');

      // ── http.Request manual — fuerza bodyBytes y Content-Length en iOS ───
      // http.put() en iOS puede perder el body. Request + bodyBytes es
      // la forma más confiable de garantizar que los bytes lleguen completos.
      final request = http.Request('PUT', url);
      request.bodyBytes = bytes;
      // Forzar Content-Length explícito DESPUÉS de asignar bodyBytes
      // para que no sea sobreescrito por el cliente HTTP en iOS
      request.headers.addAll({
        'Host':                 _host,
        'Content-Type':         contentType,
        'Content-Length':       contentLength, // fuerza body completo en iOS
        'x-amz-date':           dateTimeStr,
        'x-amz-content-sha256': payloadHash,
        'x-amz-acl':            'public-read',
        'Authorization':        authorization,
      });

      final streamedResponse = await request.send();
      final statusCode       = streamedResponse.statusCode;

      if (statusCode != 200 && statusCode != 201) {
        // Leer body del error para debug
        final responseBody = await streamedResponse.stream.bytesToString();
        debugPrint('[SpacesService] Upload FAILED key=$key status=$statusCode body=$responseBody');
        return false;
      }

      debugPrint('[SpacesService] Upload OK key=$key size=${bytes.length} bytes');
      return true;

    } catch (e, stack) {
      debugPrint('[SpacesService] _upload EXCEPTION key=$key error=$e');
      debugPrint(stack.toString());
      return false;
    }
  }

  // ─── Helpers de firma AWS4 ────────────────────────────────────────────────
  List<int> _signingKey(String dateStr) {
    final kDate    = _hmac(utf8.encode('AWS4$_secretKey'), utf8.encode(dateStr));
    final kRegion  = _hmac(kDate,    utf8.encode(_region));
    final kService = _hmac(kRegion,  utf8.encode('s3'));
    return           _hmac(kService, utf8.encode('aws4_request'));
  }

  List<int> _hmac(List<int> key, List<int> data) =>
      Hmac(sha256, key).convert(data).bytes;

  String _formatDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime dt) =>
      '${_formatDate(dt)}T'
      '${dt.hour.toString().padLeft(2, '0')}'
      '${dt.minute.toString().padLeft(2, '0')}'
      '${dt.second.toString().padLeft(2, '0')}Z';
}