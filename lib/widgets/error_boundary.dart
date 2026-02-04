import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../services/logger_service.dart';

typedef ErrorWidgetBuilder = Widget Function(BuildContext context, Object error, StackTrace stackTrace);

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final ErrorWidgetBuilder? errorBuilder;
  final void Function(Object error, StackTrace stackTrace)? onError;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
    this.onError,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  Object _error = Object();
  StackTrace _stackTrace = StackTrace.empty;

  @override
  void didUpdateWidget(ErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {
      _hasError = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _registerErrorHandlers();
  }

  void _registerErrorHandlers() {
    FlutterError.onError = (details) {
      _handleError(details.exception, details.stack ?? StackTrace.empty);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _handleError(error, stack);
      return true;
    };
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (mounted) {
      setState(() {
        _hasError = true;
        _error = error;
        _stackTrace = stackTrace;
      });
    }
    LoggerService.instance.logError(
      message: 'ErrorBoundary 捕获到错误',
      error: error,
      stackTrace: stackTrace,
      context: {'hasError': true},
    );
    widget.onError?.call(error, stackTrace);
  }

  void _resetError() {
    if (mounted) {
      setState(() {
        _hasError = false;
        _error = Object();
        _stackTrace = StackTrace.empty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.errorBuilder?.call(context, _error, _stackTrace) ??
          _defaultErrorWidget();
    }
    return widget.child;
  }

  Widget _defaultErrorWidget() {
    return Material(
      child: Center(
child: Padding(
          padding: EdgeInsets.all(24.r),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64.sp,
                color: Colors.red[400],
              ),
              SizedBox(height: 16.h),
              Text(
                '出了点问题',
                style: Theme.of(context).textTheme.headlineSmall,
),
              SizedBox(height: 8.h),
              Text(
                _error.toString(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
),
              SizedBox(height: 24.h),
              ElevatedButton.icon(
                onPressed: _resetError,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              if (kDebugMode) ...[
SizedBox(height: 16.h),
                ExpansionTile(
                  title: const Text('错误详情'),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8.r),
                      child: SelectableText(
                        _stackTrace.toString(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.sp,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AsyncErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, Object error, VoidCallback retry)? errorBuilder;

  const AsyncErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
  });

  @override
  State<AsyncErrorBoundary> createState() => _AsyncErrorBoundaryState();
}

class _AsyncErrorBoundaryState extends State<AsyncErrorBoundary> {
  Object? _error;
  VoidCallback? _retry;

  void _resetError() {
    if (mounted) {
      setState(() {
        _error = null;
        _retry = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!, _resetError) ??
          _defaultErrorWidget();
    }
    return ErrorBoundary(
      onError: (error, stack) {
        _error = error;
        _retry = () => _resetError();
      },
      child: widget.child,
    );
  }

  Widget _defaultErrorWidget() {
    return Material(
      child: Center(
child: Padding(
          padding: EdgeInsets.all(24.r),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 64.sp,
                color: Colors.orange[400],
              ),
              SizedBox(height: 16.h),
              Text(
                '加载失败',
                style: Theme.of(context).textTheme.titleLarge,
),
              SizedBox(height: 8.h),
              Text(
                _error?.toString() ?? '未知错误',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
),
              SizedBox(height: 24.h),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
