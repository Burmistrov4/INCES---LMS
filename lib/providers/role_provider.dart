import 'package:flutter/foundation.dart';

enum UserRole { admin, docente, estudiante, desconocido }

extension UserRoleName on UserRole {
  String get value {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.docente:
        return 'docente';
      case UserRole.estudiante:
        return 'estudiante';
      case UserRole.desconocido:
        return 'desconocido';
    }
  }
}

UserRole userRoleFromName(String? value) {
  switch (value) {
    case 'admin':
      return UserRole.admin;
    case 'docente':
      return UserRole.docente;
    case 'estudiante':
      return UserRole.estudiante;
    default:
      return UserRole.desconocido;
  }
}

class RoleProvider extends ChangeNotifier {
  UserRole _role = UserRole.desconocido;
  bool _isLoading = false;
  String? _errorMessage;

  UserRole get role => _role;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void setRole(UserRole role) {
    _role = role;
    _errorMessage = null;
    notifyListeners();
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  void reset() {
    _role = UserRole.desconocido;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }
}
