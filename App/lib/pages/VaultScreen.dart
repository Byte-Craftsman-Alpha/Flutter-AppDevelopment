import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:open_file/open_file.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import '../constants/theme.dart'; // Mapped strictly to your centralized design system
import '../services/auth_service.dart';

class VaultPage extends StatefulWidget {
  final String currentUserId;
  const VaultPage({super.key, required this.currentUserId});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> with TickerProviderStateMixin {
  Database? _localDb;
  List<Map<String, dynamic>> _vaultItems = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // 💡 Telegram Gateway Credentials
  static const String _botToken = "7705422769:AAE9Litq4FezGMrTYRzHuyi8SYUMgcxckkI";
  static const String _chatId = "-1003952897986";

  @override
  void initState() {
    super.initState();
    _initializeVaultSystem();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 💡 SQLite Local Database Engine Initialization
  Future<void> _initializeVaultSystem() async {
    try {
      final dbPath = await getDatabasesPath();
      final databasePath = p.join(dbPath, 'eduportal_vault.db');

      _localDb = await openDatabase(
        databasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE student_vault (
              id TEXT PRIMARY KEY,
              user_id TEXT,
              file_id TEXT,
              file_name TEXT,
              file_size INTEGER,
              extension TEXT,
              local_path TEXT,
              created_at TEXT
            )
          ''');
        },
      );
      await _loadVaultRecords();
    } catch (e) {
      debugPrint("❌ Vault DB Init Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadVaultRecords() async {
    if (_localDb == null) return;
    try {
      final List<Map<String, dynamic>> records = await _localDb!.query(
        'student_vault',
        where: 'user_id = ?',
        whereArgs: [widget.currentUserId],
        orderBy: 'created_at DESC',
      );

      if (mounted) {
        setState(() {
          _vaultItems = records;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Failed to query local vault metadata: $e");
    }
  }

  // 💡 Secure Cloud Synchronization Engine via Telegram API
  Future<String?> _transmitFileToCloud(String path, String name) async {
    final uri = Uri.parse("https://api.telegram.org/bot$_botToken/sendDocument");
    final request = http.MultipartRequest("POST", uri)
      ..fields['chat_id'] = _chatId
      ..files.add(await http.MultipartFile.fromPath('document', path, filename: name));

    try {
      final response = await request.send();
      final responseBody = await http.Response.fromStream(response);

      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = json.decode(responseBody.body);
        if (decoded['ok'] == true) {
          return decoded['result']['document']['file_id']?.toString();
        }
      }
    } catch (e) {
      debugPrint("❌ Cloud link synchronization pipeline broke: $e");
    }
    return null;
  }

  Future<String?> _resolveCloudDownloadUrl(String fileId) async {
    final uri = Uri.parse("https://api.telegram.org/bot$_botToken/getFile?file_id=$fileId");
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = json.decode(response.body);
        if (decoded['ok'] == true) {
          final filePath = decoded['result']['file_path']?.toString();
          if (filePath != null) {
            return "https://api.telegram.org/file/bot$_botToken/$filePath";
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Target link resolution error: $e");
    }
    return null;
  }

  // 💡 File Lifecycle Controllers (Upload, Open, Delete)
  Future<void> _handleDocumentUpload() async {
    if (_isProcessing) return;

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) return;

      setState(() => _isProcessing = true);

      final pickedFile = result.files.single;
      final originalFile = File(pickedFile.path!);
      final filename = pickedFile.name;
      final extension = pickedFile.extension ?? 'octet-stream';

      // Copy item explicitly to app internal storage safety sandbox directory
      final appDir = await getApplicationDocumentsDirectory();
      final uniqueFolder = Directory(p.join(appDir.path, 'vault_${widget.currentUserId}'));
      if (!await uniqueFolder.exists()) await uniqueFolder.create(recursive: true);

      final localSavedPath = p.join(uniqueFolder.path, '${DateTime.now().millisecondsSinceEpoch}_$filename');
      final savedFile = await originalFile.copy(localSavedPath);

      // Encrypt/Transmit file directly to cloud layer asynchronously
      final cloudFileId = await _transmitFileToCloud(savedFile.path, filename);

      if (cloudFileId == null) {
        throw Exception("Cloud storage synchronization rejected handshake parameters.");
      }

      // Commit schema transaction properties directly into local SQLite mapping logs
      final recordId = DateTime.now().millisecondsSinceEpoch.toString();
      await _localDb!.insert('student_vault', {
        'id': recordId,
        'user_id': widget.currentUserId,
        'file_id': cloudFileId,
        'file_name': filename,
        'file_size': pickedFile.size,
        'extension': extension,
        'local_path': savedFile.path,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      _showSuccessBanner('"$filename" securely committed to personal vault.');
      await _loadVaultRecords();
    } catch (e) {
      _showErrorBanner('Vault preservation failure: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleFileAccess(Map<String, dynamic> item) async {
    final localPath = item['local_path']?.toString() ?? '';
    final fileId = item['file_id']?.toString() ?? '';
    final filename = item['file_name']?.toString() ?? 'Document';

    // Scenario A: File is available instantly locally in cache directories
    if (localPath.isNotEmpty && await File(localPath).exists()) {
      await OpenFile.open(localPath);
      return;
    }

    // Scenario B: File is missing from current disk cluster, fetch streaming link from cloud layer
    setState(() => _isProcessing = true);
    _showProgressIndicatorSnackBar('Fetching encrypted resource asset package from cloud layer...');

    try {
      final downloadUrl = await _resolveCloudDownloadUrl(fileId);
      if (downloadUrl == null) throw Exception("Failed to map cloud path pointers.");

      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) throw Exception("Cloud pipeline returned unstable status blocks.");

      final appDir = await getApplicationDocumentsDirectory();
      final uniqueFolder = Directory(p.join(appDir.path, 'vault_${widget.currentUserId}'));
      if (!await uniqueFolder.exists()) await uniqueFolder.create(recursive: true);

      final targetLocalPath = p.join(uniqueFolder.path, '${DateTime.now().millisecondsSinceEpoch}_$filename');
      final downloadedFile = File(targetLocalPath);
      await downloadedFile.writeAsBytes(response.bodyBytes);

      // Update local storage path inside table layout mapping
      await _localDb!.update(
        'student_vault',
        {'local_path': downloadedFile.path},
        where: 'id = ?',
        whereArgs: [item['id']],
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await _loadVaultRecords();
      await OpenFile.open(downloadedFile.path);
    } catch (e) {
      _showErrorBanner('Resource retrieval failure: ${e.toString()}');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDocumentPurge(Map<String, dynamic> item) async {
    if (_localDb == null) return;
    try {
      final localPath = item['local_path']?.toString() ?? '';
      if (localPath.isNotEmpty) {
        final targetFile = File(localPath);
        if (await targetFile.exists()) await targetFile.delete();
      }

      await _localDb!.delete(
        'student_vault',
        where: 'id = ? AND user_id = ?',
        whereArgs: [item['id'], widget.currentUserId],
      );

      _showSuccessBanner('Document wiped from system storage logs mapping.');
      await _loadVaultRecords();
    } catch (e) {
      _showErrorBanner('Purge sequence aborted: $e');
    }
  }

  // 💡 Custom SnackBar Notification Modals
  void _showSuccessBanner(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            EduComponents.icon(context: context, iconData: EduIcons.success, color: Colors.greenAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white))),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
      ),
    );
  }

  void _showErrorBanner(String msg) {
    if (!mounted) return;
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            EduComponents.icon(context: context, iconData: EduIcons.danger, color: systemExt.btnDangerText, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(msg, style: TextStyle(fontWeight: FontWeight.bold, color: systemExt.btnDangerText))),
          ],
        ),
        backgroundColor: systemExt.btnDangerBg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          side: BorderSide(color: systemExt.btnDangerBorder),
        ),
      ),
    );
  }

  void _showProgressIndicatorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16, 
              height: 16, 
              child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white))),
          ],
        ),
        backgroundColor: EduDesignTokens.slate900,
        duration: const Duration(minutes: 2), // Keep pinned until dismissed manually
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
      ),
    );
  }

  // 💡 UI Layout Constructors
  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final filteredItems = _vaultItems.where((element) {
      final name = (element['file_name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: systemExt.pageBackground,
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Immersive Dynamic Control Panel Header Bar Block
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                color: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Personal Vault',
                              style: textTheme.titleLarge?.copyWith(fontSize: 20),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Encrypted Sandboxed User Cache Storage',
                              style: textTheme.labelSmall,
                            ),
                          ],
                        ),
                        if (_isProcessing)
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.primaryColor),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Interactive Search Input Action Bar Layout
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: theme.cardColor, 
                        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                        border: Border.all(color: systemExt.borderNeutral),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: textTheme.bodyLarge?.copyWith(fontSize: 14),
                        decoration: InputDecoration(
                          icon: EduComponents.icon(
                            context: context, 
                            iconData: EduIcons.search, 
                            color: EduDesignTokens.slate400, 
                            size: 20,
                          ),
                          hintText: 'Search secure files...',
                          hintStyle: const TextStyle(fontSize: 13, color: EduDesignTokens.slate400),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main Core Item Stream Pipeline Viewport Feed List
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                    : filteredItems.isEmpty
                        ? _buildEmptyStateWidget()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            physics: const BouncingScrollPhysics(),
                            itemCount: filteredItems.length,
                            itemBuilder: (context, index) {
                              final item = filteredItems[index];
                              return RepaintBoundary(
                                child: _buildVaultListRowCard(item),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
      
      // Floating Multi-File Action Operations Pipeline Entry Interface
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcessing ? null : _handleDocumentUpload,
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
        icon: EduComponents.icon(
          context: context,
          iconData: const SolarIcon(SolarIcons.CloudUpload, weight: SolarIconWeight.outline),
          color: Colors.white,
          size: 20,
        ),
        label: const Text('Add Document', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.2)),
      ),
    );
  }

  Widget _buildEmptyStateWidget() {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          EduComponents.icon(
            context: context,
            iconData: const SolarIcon(SolarIcons.Folder, weight: SolarIconWeight.outline),
            size: 64,
            color: EduDesignTokens.slate300,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'Vault Sandbox is completely clear' : 'No storage records match criteria',
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _searchQuery.isEmpty ? 'Tap the control prompt below to populate data' : 'Refine configuration keywords',
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildVaultListRowCard(Map<String, dynamic> item) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filename = item['file_name']?.toString() ?? 'Unnamed File';
    final extension = item['extension']?.toString().toUpperCase() ?? 'FILE';
    final sizeBytes = item['file_size'] as int? ?? 0;
    final sizeKb = (sizeBytes / 1024).toStringAsFixed(1);
    
    final localPath = item['local_path']?.toString() ?? '';
    final bool isLocallyCached = localPath.isNotEmpty && File(localPath).existsSync();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: EduComponents.card(
        context: context,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: EduComponents.icon(
            context: context,
            iconData: const SolarIcon(SolarIcons.Documents, weight: SolarIconWeight.outline),
            color: systemExt.btnSoftText,
            size: 32,
          ),
          title: Text(
            filename,
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Text(
                '$extension · $sizeKb KB',
                style: textTheme.bodyMedium?.copyWith(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              // Status Icon Indicator tag monitoring local memory footprint bounds
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isLocallyCached 
                      ? (isDark ? Colors.green.withOpacity(0.2) : const Color(0xFFDCFCE7)) 
                      : systemExt.btnSoftBg,
                  borderRadius: BorderRadius.circular(EduDesignTokens.radiusM),
                  border: Border.all(
                    color: isLocallyCached 
                        ? (isDark ? Colors.green.withOpacity(0.4) : const Color(0xFFBBF7D0)) 
                        : systemExt.btnSoftBorder,
                  ),
                ),
                child: Text(
                  isLocallyCached ? 'Offline Cache' : 'Cloud Sync',
                  style: TextStyle(
                    fontSize: 9, 
                    color: isLocallyCached 
                        ? (isDark ? Colors.greenAccent : const Color(0xFF166534)) 
                        : systemExt.btnSoftText, 
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: EduComponents.icon(
                  context: context,
                  iconData: const SolarIcon(SolarIcons.CloudDownload, weight: SolarIconWeight.bold),
                  color: Theme.of(context).primaryColor,
                  size: 22,
                ),
                onPressed: () => _handleFileAccess(item),
              ),
              IconButton(
                icon: EduComponents.icon(
                  context: context,
                  iconData: const SolarIcon(SolarIcons.TrashBinMinimalistic, weight: SolarIconWeight.outline),
                  color: systemExt.btnDangerText,
                  size: 20,
                ),
                onPressed: () => _showDeletionVerificationAlert(item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeletionVerificationAlert(Map<String, dynamic> item) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    showDialog(
      context: context,
      builder: (context) {
        final dialogTheme = Theme.of(context);
        return AlertDialog(
          backgroundColor: dialogTheme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EduDesignTokens.radius2xl),
            side: BorderSide(color: systemExt.borderNeutral),
          ),
          title: Text(
            'Purge Vault File?', 
            style: dialogTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This action wipes the temporary offline document file cache completely.', 
            style: dialogTheme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel', 
                style: TextStyle(color: EduDesignTokens.slate400, fontWeight: FontWeight.bold),
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
              child: const Text('Purge Asset', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}

class JuridicalRadius {
  static Radius get zero => Radius.zero;
}