class TaskOperationResult {
  final bool success;
  final String message;
  final String errorDetails;

  const TaskOperationResult({
    required this.success,
    required this.message,
    this.errorDetails = '',
  });

  factory TaskOperationResult.success(String message) {
    return TaskOperationResult(success: true, message: message);
  }

  factory TaskOperationResult.failure(String message, [String details = '']) {
    return TaskOperationResult(
      success: false,
      message: message,
      errorDetails: details,
    );
  }
}
