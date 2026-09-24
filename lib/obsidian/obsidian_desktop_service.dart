import 'package:flutter/services.dart';

enum ObsidianHostState { idle, launching, hosted, failed }

class ObsidianHostBounds {
  final int x;
  final int y;
  final int width;
  final int height;

  const ObsidianHostBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, Object> toMap() {
    return {'x': x, 'y': y, 'width': width, 'height': height};
  }
}

class ObsidianHostStatus {
  final ObsidianHostState state;
  final String message;

  const ObsidianHostStatus({required this.state, required this.message});

  factory ObsidianHostStatus.fromMap(Object? value) {
    if (value is! Map) {
      return const ObsidianHostStatus(
        state: ObsidianHostState.failed,
        message: 'The native Obsidian host returned an invalid response.',
      );
    }

    final stateName = value['state']?.toString();
    final state = switch (stateName) {
      'launching' => ObsidianHostState.launching,
      'hosted' => ObsidianHostState.hosted,
      'failed' => ObsidianHostState.failed,
      _ => ObsidianHostState.idle,
    };

    return ObsidianHostStatus(
      state: state,
      message: value['message']?.toString() ?? '',
    );
  }
}

class ObsidianDesktopService {
  const ObsidianDesktopService();

  static const MethodChannel _channel = MethodChannel(
    'fptu_se_brain/obsidian_desktop',
  );

  Future<bool> isInstalled() async {
    return await _channel.invokeMethod<bool>('isInstalled') ?? false;
  }

  Future<void> openDownloadPage() async {
    await _channel.invokeMethod<void>('openDownloadPage');
  }

  Future<ObsidianHostStatus> startHosting({
    required String vaultPath,
    required String filePath,
    required ObsidianHostBounds bounds,
  }) async {
    final result = await _channel.invokeMethod<Object?>('startHosting', {
      'vaultPath': vaultPath,
      'filePath': filePath,
      ...bounds.toMap(),
    });

    return ObsidianHostStatus.fromMap(result);
  }

  Future<ObsidianHostStatus> updateHostBounds(ObsidianHostBounds bounds) async {
    final result = await _channel.invokeMethod<Object?>(
      'updateHostBounds',
      bounds.toMap(),
    );

    return ObsidianHostStatus.fromMap(result);
  }

  Future<ObsidianHostStatus> getHostStatus() async {
    final result = await _channel.invokeMethod<Object?>('getHostStatus');
    return ObsidianHostStatus.fromMap(result);
  }

  Future<void> hideHost() async {
    await _channel.invokeMethod<void>('hideHost');
  }

  Future<void> focusHost() async {
    await _channel.invokeMethod<void>('focusHost');
  }
}
