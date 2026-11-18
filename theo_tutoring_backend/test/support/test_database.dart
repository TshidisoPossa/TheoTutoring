// TLS settings for the opt-in database integration tests.
//
// With THEO_TEST_DB_SSL_CA naming a CA certificate (for example the one that
// signed an isolated MySQL 8.4 test server's certificate), the server's
// certificate and host name are verified against that CA only, as
// lib/local_test_database.dart does. Without it nothing changes: the
// system's trusted roots are used.
import 'dart:io';

/// The security context for the test database connection, or null for the
/// system's trusted roots.
SecurityContext? testDatabaseSecurityContext() {
  final ca = Platform.environment['THEO_TEST_DB_SSL_CA']?.trim() ?? '';
  if (ca.isEmpty) return null;
  if (!File(ca).existsSync()) {
    throw StateError('THEO_TEST_DB_SSL_CA does not name a readable file.');
  }
  // No trusted roots: only the given CA.
  return SecurityContext()..setTrustedCertificates(ca);
}
