import 'errors/app_exception.dart';

/// Resultado explícito de una operación que puede fallar.
///
/// Reemplaza el antipatrón anterior de `catch { return null; }`. Con [Result]
/// el llamador está **obligado** a considerar el caso de error, y un `null`
/// pasa a significar únicamente "no existe".
///
/// Uso:
/// ```dart
/// final resultado = await repo.crear(modelo);
/// resultado.when(
///   success: (aspirante) => irAExito(aspirante),
///   failure: (error) => mostrarError(error.message),
/// );
/// ```
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get valueOrNull => switch (this) {
        Success<T>(:final value) => value,
        Failure<T>() => null,
      };

  AppException? get errorOrNull => switch (this) {
        Success<T>() => null,
        Failure<T>(:final error) => error,
      };

  /// Colapsa ambos casos en un único valor. La forma preferida de consumirlo.
  R when<R>({
    required R Function(T value) success,
    required R Function(AppException error) failure,
  }) {
    return switch (this) {
      Success<T>(:final value) => success(value),
      Failure<T>(:final error) => failure(error),
    };
  }

  /// Igual que [when] pero solo para el caso exitoso.
  R? whenSuccess<R>(R Function(T value) success) {
    return switch (this) {
      Success<T>(:final value) => success(value),
      Failure<T>() => null,
    };
  }

  /// Transforma el valor exitoso conservando el error.
  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success<T>(:final value) => Success<R>(transform(value)),
      Failure<T>(:final error) => Failure<R>(error),
    };
  }

  /// Ejecuta [action] capturando cualquier excepción como [Failure].
  ///
  /// Centraliza el try/catch para que las capas de datos no repitan el patrón
  /// ni se vean tentadas a tragarse el error.
  static Future<Result<T>> guard<T>(Future<T> Function() action) async {
    try {
      return Success<T>(await action());
    } catch (error, stackTrace) {
      return Failure<T>(
        AppException.from(error, stackTrace: stackTrace),
      );
    }
  }

  /// Variante sincrónica de [guard].
  static Result<T> guardSync<T>(T Function() action) {
    try {
      return Success<T>(action());
    } catch (error, stackTrace) {
      return Failure<T>(
        AppException.from(error, stackTrace: stackTrace),
      );
    }
  }
}

final class Success<T> extends Result<T> {
  final T value;

  const Success(this.value);

  @override
  String toString() => 'Success($value)';
}

final class Failure<T> extends Result<T> {
  final AppException error;

  const Failure(this.error);

  @override
  String toString() => 'Failure($error)';
}
