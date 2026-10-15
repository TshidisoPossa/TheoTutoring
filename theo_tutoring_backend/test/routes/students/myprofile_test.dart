import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../../routes/students/myprofile.dart' as route;

class _MockRequestContext extends Mock implements RequestContext {}

class _MockRequest extends Mock implements Request {}

void main() {
  group('GET /students/myprofile', () {
    late RequestContext context;
    late Request request;

    setUp(() {
      context = _MockRequestContext();
      request = _MockRequest();
      when(() => context.request).thenReturn(request);
      when(() => request.method).thenReturn(HttpMethod.get);
      when(() => request.headers).thenReturn({});
    });

    test('returns 401 when Authorization is missing', () async {
      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('returns 401 when the Authorization header is malformed', () async {
      when(() => request.headers).thenReturn({
        'Authorization': 'Basic not-a-valid-token',
      });

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('returns 405 for methods other than GET', () async {
      when(() => request.method).thenReturn(HttpMethod.post);

      final response = await route.onRequest(context);

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
