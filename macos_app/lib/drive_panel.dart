import 'dart:typed_data';

import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';

import 'cy_localization.dart';
import 'drive_sync.dart';
import 'web_native_control.dart';

class DriveButton extends StatelessWidget {
  const DriveButton({super.key, required this.onOpen});
  final Future<void> Function(String, Uint8List) onOpen;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: DriveSync.instance,
    builder: (context, _) => IconButton(
      tooltip: tr(context, 'Google Drive 동기화'),
      icon: Icon(
        DriveSync.instance.error != null
            ? Icons.cloud_off_outlined
            : DriveSync.instance.connected
            ? Icons.cloud_done_outlined
            : Icons.cloud_outlined,
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => _DrivePanel(onOpen: onOpen),
      ),
    ),
  );
}

class _DrivePanel extends StatefulWidget {
  const _DrivePanel({required this.onOpen});
  final Future<void> Function(String, Uint8List) onOpen;
  @override
  State<_DrivePanel> createState() => _DrivePanelState();
}

class _DrivePanelState extends State<_DrivePanel> {
  @override
  void initState() {
    super.initState();
    if (DriveSync.instance.connected) DriveSync.instance.refresh();
  }

  bool _loading = false;
  String? _error;
  Future<void> _open(DrivePdf file) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await DriveSync.instance.download(file);
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onOpen(file.name, bytes);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = trNow('Drive 파일을 열지 못했습니다. 연결을 확인해 주세요.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: DriveSync.instance,
    builder: (context, _) {
      final sync = DriveSync.instance;
      return AlertDialog(
        title: Text(tr(context, 'Google Drive 동기화')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(
                    context,
                    sync.connected
                        ? '연결 후 여는 PDF와 책갈피·읽던 페이지를 개인 Drive에 저장합니다. 최근 5개를 표시하며, 이전 PDF는 Drive에 남습니다.'
                        : 'Google 계정을 연결하면 이후 여는 PDF와 책갈피·읽던 페이지를 개인 Drive에 저장합니다. 기존 Drive 파일 전체에 접근하지 않습니다.',
                  ),
                ),
                const SizedBox(height: 12),
                if (sync.connected)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(tr(context, sync.status)),
                  ),
                if (sync.account != null)
                  Text(
                    sync.account!,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                if (sync.busy || _loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null || sync.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error ?? tr(context, sync.error!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (!sync.connected) ...[
                  const SizedBox(height: 16),
                  WebNativeButton(
                    label: tr(context, 'Google 계정으로 Drive 연결'),
                    onPressed: sync.busy ? null : sync.connect,
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Text(
                    tr(context, 'Drive 최근 파일 · 최대 5개'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (sync.files.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        tr(context, '아직 동기화한 PDF가 없습니다. 이 창을 닫고 PDF를 열어 주세요.'),
                      ),
                    ),
                  for (final file in sync.files)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        tr(context, '{0}페이지에서 이어 읽기', ['${file.page}']),
                      ),
                      onTap: _loading ? null : () => _open(file),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _loading ? null : sync.refresh,
                        child: Text(tr(context, '새로고침')),
                      ),
                      TextButton(
                        onPressed: _loading ? null : sync.disconnect,
                        child: Text(tr(context, '연결 해제')),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  tr(
                    context,
                    '앱을 다시 실행하거나 연결이 만료되면 다시 연결해 주세요. Drive 용량이 부족해도 로컬 PDF는 계속 사용할 수 있습니다.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://kimmacaroni.github.io/CY_Viewer/privacy/'),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(tr(context, '개인정보 안내')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, '닫기')),
          ),
        ],
      );
    },
  );
}

class DriveStatus extends StatelessWidget {
  const DriveStatus({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: DriveSync.instance,
    builder: (context, _) {
      final sync = DriveSync.instance;
      if (!sync.connected && sync.error == null) return const SizedBox.shrink();
      final message = tr(context, sync.error ?? sync.status);
      return IconButton(
        tooltip: message,
        icon: Icon(
          sync.error != null
              ? Icons.cloud_off_outlined
              : Icons.cloud_done_outlined,
        ),
        onPressed: () =>
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message))),
      );
    },
  );
}

/// 연결한 계정의 최근 문서를 홈에서 바로 연다. 로컬 원본은 삭제하지 않는다.
class DriveHomeRecent extends StatefulWidget {
  const DriveHomeRecent({super.key, required this.onOpen, this.sync});
  final Future<void> Function(String, Uint8List) onOpen;
  final DriveSync? sync;
  @override
  State<DriveHomeRecent> createState() => _DriveHomeRecentState();
}

class _DriveHomeRecentState extends State<DriveHomeRecent> {
  bool _opening = false;
  bool _refreshing = false;
  String? _error;
  DriveSync get sync => widget.sync ?? DriveSync.instance;
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await sync.refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _open(DrivePdf file) async {
    if (_opening || !sync.connected) return;
    final account = sync.account;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final bytes = await sync.download(file);
      if (!mounted || !sync.connected || sync.account != account) return;
      await widget.onOpen(file.name, bytes);
    } catch (_) {
      if (mounted) setState(() => _error = 'Drive 파일을 열지 못했습니다. 연결을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) {
      if (!sync.connected) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(context, 'Drive 최근 파일 · 최대 5개'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                tr(context, '개인 Google Drive'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (sync.busy || _opening || _refreshing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null || sync.error != null)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      tr(context, _error ?? sync.error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (sync.files.isEmpty && !sync.busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(tr(context, '아직 동기화한 PDF가 없습니다. PDF를 열어 주세요.')),
                ),
              for (final file in sync.files.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    tr(context, '{0}페이지에서 이어 읽기', ['${file.page}']),
                  ),
                  onTap: _opening || _refreshing || sync.busy
                      ? null
                      : () => _open(file),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _opening || _refreshing || sync.busy
                      ? null
                      : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr(context, '새로고침')),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
