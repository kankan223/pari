/// API specification domain models for OpenAPI/Swagger documentation (Task 15.1).
///
/// Defines the structure for API endpoint documentation, request/response
/// schemas, and authentication requirements. All values are pure — no
/// identity, no PII, no secrets.

/// HTTP method for an API endpoint.
enum HttpMethod {
  get,
  post,
  put,
  patch,
  delete;

  /// Human-readable label.
  String get label => name.toUpperCase();
}

/// Authentication requirement for an API endpoint.
enum AuthRequirement {
  /// No authentication required.
  none,

  /// JWT Bearer token required.
  jwtBearer,

  /// API key required.
  apiKey,

  /// Both JWT and API key required.
  both;

  /// Human-readable label.
  String get label {
    switch (this) {
      case AuthRequirement.none:
        return 'None';
      case AuthRequirement.jwtBearer:
        return 'JWT Bearer';
      case AuthRequirement.apiKey:
        return 'API Key';
      case AuthRequirement.both:
        return 'JWT + API Key';
    }
  }
}

/// A single API endpoint specification.
class ApiEndpoint {
  /// HTTP method.
  final HttpMethod method;

  /// URL path (e.g., '/v1/identity/otp/request').
  final String path;

  /// Human-readable summary.
  final String summary;

  /// Detailed description.
  final String description;

  /// Authentication requirement.
  final AuthRequirement auth;

  /// Tags for grouping (e.g., ['Identity', 'OTP']).
  final List<String> tags;

  /// Request body schema name (null for GET/DELETE).
  final String? requestSchema;

  /// Response schema name.
  final String responseSchema;

  /// HTTP status codes this endpoint can return.
  final List<int> statusCodes;

  const ApiEndpoint({
    required this.method,
    required this.path,
    required this.summary,
    this.description = '',
    this.auth = AuthRequirement.none,
    this.tags = const [],
    this.requestSchema,
    required this.responseSchema,
    this.statusCodes = const [200],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiEndpoint &&
          runtimeType == other.runtimeType &&
          method == other.method &&
          path == other.path;

  @override
  int get hashCode => Object.hash(method, path);
}

/// A schema definition for request/response bodies.
class ApiSchema {
  /// Schema name (e.g., 'OtpRequest').
  final String name;

  /// Field definitions as name → type description.
  final Map<String, String> fields;

  /// Required field names.
  final List<String> requiredFields;

  /// Description of the schema.
  final String description;

  const ApiSchema({
    required this.name,
    required this.fields,
    this.requiredFields = const [],
    this.description = '',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiSchema &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}

/// Complete API specification for a service.
class ApiSpec {
  /// Service name.
  final String serviceName;

  /// API version.
  final String version;

  /// Base URL.
  final String baseUrl;

  /// All endpoints.
  final List<ApiEndpoint> endpoints;

  /// All schema definitions.
  final List<ApiSchema> schemas;

  const ApiSpec({
    required this.serviceName,
    required this.version,
    required this.baseUrl,
    this.endpoints = const [],
    this.schemas = const [],
  });

  /// Number of endpoints.
  int get endpointCount => endpoints.length;

  /// Number of schemas.
  int get schemaCount => schemas.length;

  /// Endpoints grouped by tag.
  Map<String, List<ApiEndpoint>> get endpointsByTag {
    final result = <String, List<ApiEndpoint>>{};
    for (final endpoint in endpoints) {
      for (final tag in endpoint.tags) {
        result.putIfAbsent(tag, () => []).add(endpoint);
      }
    }
    return result;
  }

  /// Endpoints requiring authentication.
  List<ApiEndpoint> get authenticatedEndpoints =>
      endpoints.where((e) => e.auth != AuthRequirement.none).toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiSpec &&
          runtimeType == other.runtimeType &&
          serviceName == other.serviceName &&
          version == other.version;

  @override
  int get hashCode => Object.hash(serviceName, version);
}
