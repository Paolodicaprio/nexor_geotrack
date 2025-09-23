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

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      success: json['access_token'] != null,
      token: json['access_token'],
      error: json['detail'] ?? json['error'],
    );
  }
}

class RegisterRequest {
  final String email;

  RegisterRequest({required this.email});

  Map<String, dynamic> toJson() {
    return {'email': email};
  }
}

class RegisterResponse {
  final bool success;
  final String? accessCode;
  final String? error;

  RegisterResponse({required this.success, this.accessCode, this.error});

  factory RegisterResponse.fromJson(Map<String, dynamic> json) {
    return RegisterResponse(
      success: json['access_code'] != null,
      accessCode: json['access_code'],
      error: json['detail'] ?? json['error'],
    );
  }
}
