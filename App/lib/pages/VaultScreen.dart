import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import '../constants/theme.dart';
import '../services/auth_service.dart';

class VaultPage extends StatefulWidget {
  final String currentUserId;
  const VaultPage({super.key, required this.currentUserId});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _vaultItems = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String? _localVaultDirectory;

  // 💡 State flags specifically for operations
  bool _isUploadingFile = false;
  http.Client? _activeUploadClient;
  final Map<String, http.Client> _activeDownloadClients = {};

  @override
  void initState() {
    super.initState();
    _initLocalDirectory().then((_) {
      _fetchVaultRecords();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _activeUploadClient?.close();
    for (var client in _activeDownloadClients.values) {
      client.close();
    }
    super.dispose();
  }

  Future<void> _initLocalDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final vaultDir = Directory('${directory.path}/edu_vault');
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    setState(() {
      _localVaultDirectory = vaultDir.path;
    });
  }

  Future<void> _fetchVaultRecords() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService.getAuthToken();
      // 💡 FIX: Safely parse URL using Uri.https to automatically encode the token
      final url = Uri.https(
        'flutter-app-development-mu.vercel.app',
        '/api/vault/records',
        {'token': token ?? ''},
      );

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _vaultItems = data
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _vaultItems.sort(
              (a, b) =>
                  (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
            );
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Server rejected vault record query.");
      }
    } catch (e) {
      debugPrint("Vault Fetch Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showToast("Failed to connect to the document vault.", isError: true);
      }
    }
  }

  // 💡 Streamed Secure Upload with Live Progress Dialog
  Future<void> _uploadDocument() async {
    if (_isUploadingFile) return;

    bool isDialogVisible = false;

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) return;

      final pickedFile = result.files.single;
      final localFile = File(pickedFile.path!);
      final int totalBytes = await localFile.length();

      setState(() {
        _isUploadingFile = true;
        _activeUploadClient = http.Client();
      });

      _showTransferProgressDialog(
        title: "Uploading to Vault",
        fileName: pickedFile.name,
        totalBytes: totalBytes,
        isUpload: true,
        onCancel: () {
          // 💡 FIX: Set flag to prevent double-popping
          isDialogVisible = false;
          Navigator.pop(context);
          _activeUploadClient?.close();
        },
      );
      isDialogVisible = true;

      final token = await AuthService.getAuthToken();
      final url = Uri.https(
        'flutter-app-development-mu.vercel.app',
        '/api/vault/upload',
      );

      final request = http.MultipartRequest("POST", url);
      request.fields['token'] = token ?? '';

      int uploadedBytes = 0;
      final stream = localFile.openRead();
      final progressStream = stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (data, sink) {
            uploadedBytes += data.length;
            _transferProgressNotifier.value = TransferProgress(
              uploadedBytes,
              totalBytes,
            );
            sink.add(data);
          },
        ),
      );

      final multipartFile = http.MultipartFile(
        'file',
        progressStream,
        totalBytes,
        filename: pickedFile.name,
      );
      request.files.add(multipartFile);

      final response = await _activeUploadClient!.send(request);
      final responseBody = await http.Response.fromStream(response);

      // 💡 FIX: Reliably close the dialog using the tracker flag
      if (mounted && isDialogVisible) {
        Navigator.pop(context);
        isDialogVisible = false;
      }

      if (response.statusCode == 200) {
        _showToast("File secured in your vault successfully!", isError: false);
        _fetchVaultRecords();
      } else {
        throw Exception("API Gateway returned ${response.statusCode}");
      }
    } on PlatformException catch (_) {
      _showToast(
        "File manager access denied. Please allow storage permissions.",
        isError: true,
      );
    } catch (e) {
      // 💡 FIX: If an exception is thrown during upload, ensure dialog is still closed
      if (mounted && isDialogVisible) {
        Navigator.pop(context);
        isDialogVisible = false;
      }

      if (e is http.ClientException || e is TimeoutException) {
        _showToast("Upload cancelled by user.", isError: true);
      } else {
        debugPrint("Vault Upload Error: $e");
        _showToast(
          "Failed to upload document. Please try again.",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingFile = false);
      _activeUploadClient = null;
    }
  }

  Future<String?> _resolveCloudDownloadUrl(String fileId) async {
    try {
      final token = await AuthService.getAuthToken();
      // 💡 FIX: Safely parse URL using Uri.https. Special chars like '+' in base64 IDs won't break anymore.
      final url = Uri.https(
        'flutter-app-development-mu.vercel.app',
        '/api/files/resolve',
        {'file_id': fileId, 'token': token ?? ''},
      );

      // 💡 FIX: Added timeout to prevent hanging forever
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = json.decode(response.body);
        return decoded['url']?.toString();
      }
    } catch (e) {
      debugPrint("Cloud URL Resolution Error: $e");
    }
    return null;
  }

  // 💡 Streamed Secure Download with Live Progress Dialog
  Future<void> _handleDocumentAction(
    Map<String, dynamic> item, {
    bool shareOnly = false,
  }) async {
    final String fileId = item['file_id']?.toString() ?? '';
    final String fileName = item['file_name']?.toString() ?? 'document.file';
    final int totalSize = item['file_size'] is int
        ? item['file_size']
        : int.tryParse(item['file_size'].toString()) ?? 0;

    if (_activeDownloadClients.containsKey(fileId)) {
      _showToast("This file is already being downloaded.", isError: false);
      return;
    }

    bool isDialogVisible = false;

    try {
      if (_localVaultDirectory == null) await _initLocalDirectory();
      final String localFilePath = p.join(
        _localVaultDirectory!,
        '${item['id']}_$fileName',
      );
      final File localFile = File(localFilePath);

      if (!await localFile.exists()) {
        final client = http.Client();
        setState(() => _activeDownloadClients[fileId] = client);

        _showTransferProgressDialog(
          title: "Downloading to Cache",
          fileName: fileName,
          totalBytes: totalSize,
          isUpload: false,
          onCancel: () {
            isDialogVisible = false;
            Navigator.pop(context); // Close dialog safely
            client.close();
          },
        );
        isDialogVisible = true;

        // 1. Resolve URL
        _transferProgressNotifier.value = TransferProgress(
          0,
          totalSize,
          isResolving: true,
        );
        final resolvedUrl = await _resolveCloudDownloadUrl(fileId);

        if (resolvedUrl == null) {
          throw Exception("Could not map file to a secure download path.");
        }

        // 2. Stream Data
        final request = http.Request('GET', Uri.parse(resolvedUrl));
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          int downloadedBytes = 0;
          final contentLength = response.contentLength ?? totalSize;

          final sink = localFile.openWrite();

          await for (final chunk in response.stream) {
            sink.add(chunk);
            downloadedBytes += chunk.length;
            _transferProgressNotifier.value = TransferProgress(
              downloadedBytes,
              contentLength,
            );
          }

          await sink.close();

          // 💡 FIX: Safely pop dialog using boolean flag
          if (mounted && isDialogVisible) {
            Navigator.pop(context);
            isDialogVisible = false;
          }

          setState(() {});
        } else {
          throw Exception("Corrupted document stream received.");
        }
      }

      // Execute subsequent action (Open or Share)
      if (shareOnly) {
        await Share.shareXFiles([
          XFile(localFile.path),
        ], text: 'Document securely shared from EduPortal Vault: $fileName');
      } else {
        final result = await OpenFile.open(localFile.path);
        if (result.type != ResultType.done && mounted) {
          _showToast(
            "No installed app found capable of opening this file format.",
            isError: true,
          );
        }
      }
    } catch (e) {
      // 💡 BUG FIXED HERE: This catch block previously did not pop the dialog.
      // If any network drop/error occurred, it stayed stuck on "Negotiating tunnel" forever.
      if (mounted && isDialogVisible) {
        Navigator.pop(context);
        isDialogVisible = false;
      }

      if (e is http.ClientException || e is TimeoutException) {
        // Clean up partial file on cancel or drop
        final String localFilePath = p.join(
          _localVaultDirectory!,
          '${item['id']}_$fileName',
        );
        final partialFile = File(localFilePath);
        if (await partialFile.exists()) await partialFile.delete();
        _showToast("Download cancelled or connection dropped.", isError: true);
      } else {
        debugPrint("Vault Document Action Error: $e");
        _showToast("Failed to process document.", isError: true);
      }
    } finally {
      if (mounted) setState(() => _activeDownloadClients.remove(fileId));
    }
  }

  Future<void> _handleDocumentPurge(Map<String, dynamic> item) async {
    try {
      final recordId = item['id'].toString();
      final token = await AuthService.getAuthToken();

      // 💡 FIX: Safely parse URL using Uri.https
      final url = Uri.https(
        'flutter-app-development-mu.vercel.app',
        '/api/vault/delete',
        {'record_id': recordId, 'token': token ?? ''},
      );
      final response = await http
          .delete(url)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final String fileName = item['file_name']?.toString() ?? 'document';
        if (_localVaultDirectory != null) {
          final File localFile = File(
            p.join(_localVaultDirectory!, '${item['id']}_$fileName'),
          );
          if (await localFile.exists()) await localFile.delete();
        }

        setState(() {
          _vaultItems.removeWhere((element) => element['id'] == item['id']);
        });

        _showToast("Document permanently deleted from Vault.", isError: false);
      } else {
        throw Exception("Server rejected delete command.");
      }
    } catch (e) {
      debugPrint("Vault Purge Error: $e");
      _showToast("Failed to delete document from Vault.", isError: true);
    }
  }

  void _showToast(String message, {bool isError = true}) {
    if (!mounted) return;
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            EduComponents.icon(
              context: context,
              iconData: isError ? EduIcons.danger : EduIcons.success,
              color: isError ? systemExt.btnDangerText : Colors.greenAccent,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: isError ? systemExt.btnDangerText : Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError
            ? systemExt.btnDangerBg
            : EduDesignTokens.slate900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          side: BorderSide(
            color: isError ? systemExt.btnDangerBorder : Colors.transparent,
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _isOfflineCached(String id, String fileName) {
    if (_localVaultDirectory == null) return false;
    final file = File(p.join(_localVaultDirectory!, '${id}_$fileName'));
    return file.existsSync();
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(2)} MB';
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      final List<String> months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${date.day} ${months[date.month - 1]}, ${date.year}';
    } catch (_) {
      return 'Unknown Date';
    }
  }

  // 💡 ValueNotifier to broadcast progress smoothly without rebuilding the entire UI
  final ValueNotifier<TransferProgress> _transferProgressNotifier =
      ValueNotifier(TransferProgress(0, 1));

  void _showTransferProgressDialog({
    required String title,
    required String fileName,
    required int totalBytes,
    required bool isUpload,
    required VoidCallback onCancel,
  }) {
    _transferProgressNotifier.value = TransferProgress(0, totalBytes);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final systemExt = Theme.of(
          context,
        ).extension<EduPortalThemeExtension>()!;

        return WillPopScope(
          onWillPop: () async => false, // Prevent dismissing by back button
          child: Dialog(
            backgroundColor: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
              side: BorderSide(color: systemExt.borderNeutral),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: EduDesignTokens.indigo50.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: EduComponents.icon(
                          context: context,
                          iconData: isUpload
                              ? const SolarIcon(
                                  SolarIcons.UploadSquare,
                                  weight: SolarIconWeight.bold,
                                )
                              : const SolarIcon(
                                  SolarIcons.Download,
                                  weight: SolarIconWeight.bold,
                                ),
                          color: Theme.of(context).primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              fileName,
                              style: TextStyle(
                                color: EduDesignTokens.slate400,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  ValueListenableBuilder<TransferProgress>(
                    valueListenable: _transferProgressNotifier,
                    builder: (context, progress, child) {
                      final double percent = progress.totalBytes > 0
                          ? (progress.currentBytes / progress.totalBytes).clamp(
                              0.0,
                              1.0,
                            )
                          : 0.0;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                progress.isResolving
                                    ? "Negotiating secure tunnel..."
                                    : '${_formatFileSize(progress.currentBytes)} / ${_formatFileSize(progress.totalBytes)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              Text(
                                '${(percent * 100).toInt()}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              EduDesignTokens.radiusFull,
                            ),
                            child: LinearProgressIndicator(
                              value: progress.isResolving ? null : percent,
                              minHeight: 8,
                              backgroundColor: systemExt.btnSoftBg,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 28),
                  OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: systemExt.btnDangerText,
                      side: BorderSide(color: systemExt.btnDangerBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          EduDesignTokens.radiusXl,
                        ),
                      ),
                    ),
                    child: const Text(
                      'Cancel Transfer',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;

    final filteredItems = _vaultItems.where((item) {
      final name = (item['file_name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: systemExt.pageBackground),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personal Vault',
                          style: textTheme.titleLarge?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Secure cloud storage for your academic files',
                          style: textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(
                      EduDesignTokens.radiusXl,
                    ),
                    border: Border.all(color: systemExt.borderNeutral),
                    boxShadow: systemExt.cardBaseShadow,
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: "Search your vault...",
                      hintStyle: textTheme.bodyMedium?.copyWith(
                        color: EduDesignTokens.slate400,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: EduComponents.icon(
                          context: context,
                          iconData: const SolarIcon(
                            SolarIcons.Magnifer,
                            weight: SolarIconWeight.outline,
                          ),
                          color: EduDesignTokens.slate400,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),

              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: Theme.of(context).primaryColor,
                        ),
                      )
                    : RefreshIndicator(
                        color: Theme.of(context).primaryColor,
                        onRefresh: _fetchVaultRecords,
                        child: filteredItems.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  8,
                                  24,
                                  100,
                                ),
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                itemCount: filteredItems.length,
                                itemBuilder: (context, index) {
                                  return _buildVaultItemCard(
                                    filteredItems[index],
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploadingFile ? null : _uploadDocument,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: EduComponents.icon(
          context: context,
          iconData: const SolarIcon(
            SolarIcons.UploadSquare,
            weight: SolarIconWeight.bold,
          ),
          color: Colors.white,
        ),
        label: const Text(
          'Upload File',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.only(top: 80.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: EduDesignTokens.slate100.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: EduComponents.icon(
                  context: context,
                  iconData: const SolarIcon(
                    SolarIcons.FolderOpen,
                    weight: SolarIconWeight.outline,
                  ),
                  size: 64,
                  color: EduDesignTokens.slate300,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _searchQuery.isEmpty ? 'Your Vault is Empty' : 'No Files Found',
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isEmpty
                    ? 'Upload documents, assignments, and study materials safely.'
                    : 'Try adjusting your search criteria.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVaultItemCard(Map<String, dynamic> item) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final theme = Theme.of(context);

    final String fileId = item['file_id']?.toString() ?? '';
    final fileName = item['file_name']?.toString() ?? 'Document';
    final fileSize = _formatFileSize(item['file_size'] as int? ?? 0);
    // Restored the date formatter
    final date = _formatDate(item['created_at']?.toString() ?? '');
    final extension = item['extension']?.toString().toLowerCase() ?? 'file';

    final bool isOffline = _isOfflineCached(item['id'].toString(), fileName);
    final bool isDownloading = _activeDownloadClients.containsKey(fileId);

    SolarIconData getFileIcon() {
      switch (extension) {
        case 'pdf':
          return SolarIcons.DocumentsMinimalistic;
        case 'doc':
        case 'docx':
          return SolarIcons.DocumentText;
        case 'xls':
        case 'xlsx':
          return SolarIcons.FileText;
        case 'jpg':
        case 'jpeg':
        case 'png':
          return SolarIcons.Gallery;
        case 'zip':
        case 'rar':
          return SolarIcons.Archive;
        default:
          return SolarIcons.File;
      }
    }

    Widget buildTrailingWidget() {
      if (isDownloading) {
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: theme.primaryColor,
          ),
        );
      } else if (isOffline) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EduComponents.icon(
              context: context,
              iconData: const SolarIcon(
                SolarIcons.CheckCircle,
                weight: SolarIconWeight.bold,
              ),
              color: EduDesignTokens.emerald500,
              size: 18,
            ),
            const SizedBox(width: 8),
            EduComponents.icon(
              context: context,
              iconData: const SolarIcon(
                SolarIcons.AltArrowRight,
                weight: SolarIconWeight.outline,
              ),
              color: EduDesignTokens.slate400,
              size: 18,
            ),
          ],
        );
      } else {
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _handleDocumentAction(item),
          icon: EduComponents.icon(
            context: context,
            iconData: const SolarIcon(
              SolarIcons.Download,
              weight: SolarIconWeight.outline,
            ),
            color: theme.primaryColor,
            size: 24,
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: EduComponents.card(
        context: context,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          onTap: () => _handleDocumentAction(item),
          onLongPress: () => _showVaultActionSheet(item),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: systemExt.btnSoftBg,
              borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
            ),
            child: EduComponents.icon(
              context: context,
              iconData: SolarIcon(
                getFileIcon(),
                weight: SolarIconWeight.outline,
              ),
              color: systemExt.btnSoftText,
              size: 24,
            ),
          ),
          title: Text(
            fileName,
            style: textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Integrated the date into the subtitle row
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              children: [
                Text(
                  '${extension.toUpperCase()} · $fileSize',
                  style: textTheme.bodyMedium?.copyWith(fontSize: 11),
                ),
                const SizedBox(width: 8),
                EduComponents.icon(
                  context: context,
                  iconData: const SolarIcon(
                    SolarIcons.ClockCircle,
                    weight: SolarIconWeight.outline,
                  ),
                  size: 11,
                  color: EduDesignTokens.slate400,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    date,
                    style: textTheme.bodyMedium?.copyWith(
                      fontSize: 11,
                      color: EduDesignTokens.slate400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          trailing: buildTrailingWidget(),
        ),
      ),
    );
  }

  void _showVaultActionSheet(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EduDesignTokens.radius3xl),
        ),
      ),
      builder: (context) {
        final systemExt = Theme.of(
          context,
        ).extension<EduPortalThemeExtension>()!;
        final textTheme = Theme.of(context).textTheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: EduDesignTokens.slate300.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  item['file_name'] ?? 'Vault Document',
                  style: textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text('Storage Settings', style: textTheme.labelSmall),
                const Divider(height: 24, thickness: 1),

                ListTile(
                  leading: EduComponents.icon(
                    context: context,
                    iconData: const SolarIcon(
                      SolarIcons.FolderOpen,
                      weight: SolarIconWeight.outline,
                    ),
                    color: Theme.of(context).primaryColor,
                  ),
                  title: const Text('Open Document'),
                  onTap: () {
                    Navigator.pop(context);
                    _handleDocumentAction(item);
                  },
                ),
                ListTile(
                  leading: EduComponents.icon(
                    context: context,
                    iconData: const SolarIcon(
                      SolarIcons.Share,
                      weight: SolarIconWeight.outline,
                    ),
                    color: Theme.of(context).primaryColor,
                  ),
                  title: const Text('Share File'),
                  onTap: () {
                    Navigator.pop(context);
                    _handleDocumentAction(item, shareOnly: true);
                  },
                ),
                ListTile(
                  leading: EduComponents.icon(
                    context: context,
                    iconData: const SolarIcon(
                      SolarIcons.TrashBinMinimalistic,
                      weight: SolarIconWeight.outline,
                    ),
                    color: systemExt.btnDangerText,
                  ),
                  title: Text(
                    'Delete from Vault',
                    style: TextStyle(color: systemExt.btnDangerText),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmPurgeDialog(item);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmPurgeDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) {
        final systemExt = Theme.of(
          context,
        ).extension<EduPortalThemeExtension>()!;
        final dialogTheme = Theme.of(context);

        return AlertDialog(
          backgroundColor: dialogTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
            side: BorderSide(color: systemExt.borderNeutral),
          ),
          title: Text(
            'Purge Vault File?',
            style: dialogTheme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'This action permanently wipes the document from both your personal cloud vault and offline cache.',
            style: dialogTheme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: EduDesignTokens.slate400,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _handleDocumentPurge(item);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: systemExt.btnDangerBg,
                foregroundColor: systemExt.btnDangerText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                  side: BorderSide(color: systemExt.btnDangerBorder),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Purge Asset',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Data class to wrap transfer progress
class TransferProgress {
  final int currentBytes;
  final int totalBytes;
  final bool isResolving;

  TransferProgress(
    this.currentBytes,
    this.totalBytes, {
    this.isResolving = false,
  });
}
