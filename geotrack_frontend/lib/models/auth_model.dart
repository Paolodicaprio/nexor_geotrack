class RegisterRequest {
  final String email;

  RegisterRequest({required this.email});

  Map<String, dynamic> toJson() {
    return {'email': email};
  }
}

class RegisterResponse {
  final int id;
  final String email;
  final String accessCode;
  final bool isActive;
  final DateTime createdAt;

  RegisterResponse({
    required this.id,
    required this.email,
    required this.accessCode,
    required this.isActive,
    required this.createdAt,
  });

  factory RegisterResponse.fromJson(Map<String, dynamic> json) {
    return RegisterResponse(
      id: json['id'],
      email: json['email'],
      accessCode: json['access_code'],
      isActive: json['is_active'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class LoginRequest {
  final String email;
  final String accessCode;

  LoginRequest({required this.email, required this.accessCode});

  Map<String, dynamic> toJson() {
    return {'email': email, 'access_code': accessCode};
  }
}

class LoginResponse {
  final bool success;
  final String? token;
  final String? error;

  LoginResponse({required this.success, this.token, this.error});

  factory LoginResponse.fromApiJson(Map<String, dynamic> json) {
    return LoginResponse(success: true, token: json['access_token']);
  }
}
