import 'package:civic_commons/documentation/domain/api_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.1 — API Specification Domain', () {
    group('HttpMethod', () {
      test('has all standard HTTP methods', () {
        expect(HttpMethod.values.length, 5);
        expect(HttpMethod.values, contains(HttpMethod.get));
        expect(HttpMethod.values, contains(HttpMethod.post));
        expect(HttpMethod.values, contains(HttpMethod.put));
        expect(HttpMethod.values, contains(HttpMethod.patch));
        expect(HttpMethod.values, contains(HttpMethod.delete));
      });

      test('label returns uppercase method name', () {
        expect(HttpMethod.get.label, 'GET');
        expect(HttpMethod.post.label, 'POST');
        expect(HttpMethod.delete.label, 'DELETE');
      });
    });

    group('AuthRequirement', () {
      test('has all auth types', () {
        expect(AuthRequirement.values.length, 4);
      });

      test('label returns human-readable name', () {
        expect(AuthRequirement.none.label, 'None');
        expect(AuthRequirement.jwtBearer.label, 'JWT Bearer');
        expect(AuthRequirement.apiKey.label, 'API Key');
        expect(AuthRequirement.both.label, 'JWT + API Key');
      });
    });

    group('ApiEndpoint', () {
      test('constructs with required fields', () {
        const endpoint = ApiEndpoint(
          method: HttpMethod.get,
          path: '/v1/identity/otp/request',
          summary: 'Request OTP',
          responseSchema: 'OtpResponse',
        );
        expect(endpoint.method, HttpMethod.get);
        expect(endpoint.path, '/v1/identity/otp/request');
        expect(endpoint.summary, 'Request OTP');
        expect(endpoint.auth, AuthRequirement.none);
        expect(endpoint.tags, isEmpty);
        expect(endpoint.requestSchema, isNull);
      });

      test('equality by method and path', () {
        const a = ApiEndpoint(
          method: HttpMethod.get,
          path: '/v1/test',
          summary: 'A',
          responseSchema: 'Resp',
        );
        const b = ApiEndpoint(
          method: HttpMethod.get,
          path: '/v1/test',
          summary: 'B',
          responseSchema: 'Resp',
        );
        const c = ApiEndpoint(
          method: HttpMethod.post,
          path: '/v1/test',
          summary: 'A',
          responseSchema: 'Resp',
        );
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('ApiSchema', () {
      test('constructs with fields', () {
        const schema = ApiSchema(
          name: 'OtpRequest',
          fields: {
            'phone': 'string (E.164)',
            'blind_hash_id': 'string (64-hex)',
          },
          requiredFields: ['phone'],
        );
        expect(schema.name, 'OtpRequest');
        expect(schema.fields.length, 2);
        expect(schema.requiredFields, contains('phone'));
      });

      test('equality by name', () {
        const a = ApiSchema(name: 'Test', fields: {});
        const b = ApiSchema(name: 'Test', fields: {'x': 'int'});
        const c = ApiSchema(name: 'Other', fields: {});
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('ApiSpec', () {
      test('constructs with endpoints and schemas', () {
        const spec = ApiSpec(
          serviceName: 'Identity Service',
          version: 'v1',
          baseUrl: 'https://api.civiccommons.org',
          endpoints: [
            ApiEndpoint(
              method: HttpMethod.post,
              path: '/v1/identity/otp/request',
              summary: 'Request OTP',
              auth: AuthRequirement.none,
              tags: ['Identity', 'OTP'],
              responseSchema: 'OtpResponse',
            ),
          ],
          schemas: [
            ApiSchema(
              name: 'OtpResponse',
              fields: {'blind_hash_id': 'string'},
            ),
          ],
        );
        expect(spec.serviceName, 'Identity Service');
        expect(spec.endpointCount, 1);
        expect(spec.schemaCount, 1);
      });

      test('endpointsByTag groups correctly', () {
        const spec = ApiSpec(
          serviceName: 'Test',
          version: 'v1',
          baseUrl: 'https://test.com',
          endpoints: [
            ApiEndpoint(
              method: HttpMethod.get,
              path: '/a',
              summary: 'A',
              tags: ['Tag1', 'Tag2'],
              responseSchema: 'Resp',
            ),
            ApiEndpoint(
              method: HttpMethod.get,
              path: '/b',
              summary: 'B',
              tags: ['Tag1'],
              responseSchema: 'Resp',
            ),
          ],
        );
        final byTag = spec.endpointsByTag;
        expect(byTag['Tag1']!.length, 2);
        expect(byTag['Tag2']!.length, 1);
      });

      test('authenticatedEndpoints filters correctly', () {
        const spec = ApiSpec(
          serviceName: 'Test',
          version: 'v1',
          baseUrl: 'https://test.com',
          endpoints: [
            ApiEndpoint(
              method: HttpMethod.get,
              path: '/public',
              summary: 'Public',
              responseSchema: 'Resp',
            ),
            ApiEndpoint(
              method: HttpMethod.get,
              path: '/protected',
              summary: 'Protected',
              auth: AuthRequirement.jwtBearer,
              responseSchema: 'Resp',
            ),
          ],
        );
        expect(spec.authenticatedEndpoints.length, 1);
        expect(spec.authenticatedEndpoints.first.path, '/protected');
      });

      test('equality by service name and version', () {
        const a = ApiSpec(
          serviceName: 'Svc',
          version: 'v1',
          baseUrl: 'https://a.com',
        );
        const b = ApiSpec(
          serviceName: 'Svc',
          version: 'v1',
          baseUrl: 'https://b.com',
        );
        const c = ApiSpec(
          serviceName: 'Svc',
          version: 'v2',
          baseUrl: 'https://a.com',
        );
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PII audit', () {
      test('no PII in method labels', () {
        for (final method in HttpMethod.values) {
          expect(method.label, isNot(contains('@')));
          expect(method.label, isNot(contains('+')));
        }
      });

      test('no PII in auth labels', () {
        for (final auth in AuthRequirement.values) {
          expect(auth.label, isNot(contains('@')));
          // Note: '+' in 'JWT + API Key' is a separator, not a phone prefix
          expect(auth.label, isNot(contains(RegExp(r'\+[0-9]{10}'))));
        }
      });
    });
  });
}
