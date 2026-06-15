import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  bool _isProcessing = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String? _localVaultDirectory;

  // 💡 Telegram Gateway Credentials (Used exclusively for direct file downloads)
  static const String _botToken = "7705422769:AAE9Litq4FezGMrTYRzHuyi8SYUMgcxckkI";

  @override
  void initState() {
    super.initState();
    _initializeSandboxEnvironment().then((_) => _loadVaultRecords());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 💡 Deterministic Sandbox Initialization
  Future<void> _initializeSandboxEnvironment() async {
    final appDir = await getApplicationDocumentsDirectory();
    final uniqueFolder = Directory(p.join(appDir.path, 'vault_${widget.currentUserId}'));
    if (!await uniqueFolder.exists()) {
      await uniqueFolder.create(recursive: true);
    }
    _localVaultDirectory = uniqueFolder.path;
  }

  // 💡 Fetch metadata from the centralized API Gateway
  Future<void> _loadVaultRecords() async {
    try {
      final token = await AuthService.getAuthToken();
      final url = Uri.parse('https://flutter-app-development-mu.vercel.app/api/vault/records?token=$token');
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final List<dynamic> records = json.decode(response.body);
        if (mounted) {
          setState(() {
            _vaultItems = records.cast<Map<String, dynamic>>();
            // Sort by latest created_at locally
            _vaultItems.sort((a, b) {
              final dateA = DateTime.tryParse(a['created_at'].toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
              final dateB = DateTime.tryParse(b['created_at'].toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
              return dateB.compareTo(dateA);
            });
            _isLoading = false;
          });
        }
      } else {
        String errorDetail = "API Gateway returned ${response.statusCode}";
        try {
          final decoded = json.decode(response.body);
          errorDetail = decoded['detail']?.toString() ?? errorDetail;
        } catch (_) {}
        throw Exception(errorDetail);
      }
    } catch (e) {
      debugPrint("❌ Failed to query centralized vault metadata: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 💡 Directly resolve file paths for Telegram streaming downloads
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

  // 💡 File Lifecycle Controllers: Upload securely via Vercel Backend Proxy
  Future<void> _handleDocumentUpload() async {
    if (_isProcessing) return;

    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus != null && currentFocus.hasFocus) {
      currentFocus.unfocus();
      await Future.delayed(const Duration(milliseconds: 400));
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future.delayed(const Duration(milliseconds: 100)); 
    }

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

      final token = await AuthService.getAuthToken();
      final url = Uri.parse('https://flutter-app-development-mu.vercel.app/api/vault/upload');
      
      var request = http.MultipartRequest("POST", url)
        ..fields['token'] = token ?? ''
        ..files.add(await http.MultipartFile.fromPath('file', originalFile.path, filename: filename));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final decoded = json.decode(responseData);
        if (decoded['success'] == true) {
          final recordId = decoded['record']['id'];
          if (_localVaultDirectory != null) {
            final localSavedPath = p.join(_localVaultDirectory!, '${recordId}_$filename');
            await originalFile.copy(localSavedPath);
          }
          
          _showSuccessBanner('"$filename" securely committed to personal vault.');
          await _loadVaultRecords();
        }
      } else {
        String errorDetail = "API Gateway Rejected Payload (${response.statusCode})";
        try {
          final decoded = json.decode(responseData);
          errorDetail = decoded['detail']?.toString() ?? errorDetail;
        } catch (_) {}
        throw Exception(errorDetail);
      }
    } on PlatformException catch (pe) {
      if (pe.code == 'unknown_activity') {
        _showErrorBanner('No compatible File Manager found. Please install a file explorer app (e.g., Google Files) to pick attachments.');
      } else {
        _showErrorBanner('Native Picker Error: ${pe.message}');
      }
    } catch (e) {
      _showErrorBanner('Vault preservation failure: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // 💡 File Lifecycle Controllers: Context-Aware Sharing (Local File vs Cloud Link)
  Future<void> _handleFileShare(Map<String, dynamic> item, bool isLocallyCached) async {
    final fileId = item['file_id']?.toString() ?? '';
    final filename = item['file_name']?.toString() ?? 'Document';
    final recordId = item['id']?.toString() ?? '';

    if (isLocallyCached && _localVaultDirectory != null) {
      final expectedPath = p.join(_localVaultDirectory!, '${recordId}_$filename');
      if (await File(expectedPath).exists()) {
        await Share.shareXFiles(
          [XFile(expectedPath)], 
          text: 'Shared from EduPortal Vault: $filename'
        );
        return;
      }
    }

    setState(() => _isProcessing = true);
    _showProgressIndicatorSnackBar('Preparing secure cloud link...');

    try {
      final downloadUrl = await _resolveCloudDownloadUrl(fileId);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (downloadUrl != null) {
        await Share.share('Secure Document Link ($filename):\n$downloadUrl');
      } else {
        throw Exception("Cloud URL resolution pipeline failed.");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showErrorBanner('Sharing failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // 💡 File Lifecycle Controllers: Accessing and fetching files
  Future<void> _handleFileAccess(Map<String, dynamic> item) async {
    final fileId = item['file_id']?.toString() ?? '';
    final filename = item['file_name']?.toString() ?? 'Document';
    final recordId = item['id']?.toString() ?? '';

    if (_localVaultDirectory == null) return;
    
    final targetLocalPath = p.join(_localVaultDirectory!, '${recordId}_$filename');

    if (await File(targetLocalPath).exists()) {
      await OpenFile.open(targetLocalPath);
      return;
    }

    setState(() => _isProcessing = true);
    _showProgressIndicatorSnackBar('Fetching encrypted resource asset package from cloud layer...');

    try {
      final downloadUrl = await _resolveCloudDownloadUrl(fileId);
      if (downloadUrl == null) throw Exception("Failed to map cloud path pointers.");

      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) throw Exception("Cloud pipeline returned unstable status blocks.");

      final downloadedFile = File(targetLocalPath);
      await downloadedFile.writeAsBytes(response.bodyBytes);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (mounted) setState(() {}); 
      
      await OpenFile.open(downloadedFile.path);
    } catch (e) {
      _showErrorBanner('Resource retrieval failure: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // 💡 File Lifecycle Controllers: Complete Deletion
  Future<void> _handleDocumentPurge(Map<String, dynamic> item) async {
    try {
      final recordId = item['id']?.toString() ?? '';
      final filename = item['file_name']?.toString() ?? '';

      await Supabase.instance.client
          .from('student_vault')
          .delete()
          .eq('id', recordId);

      if (_localVaultDirectory != null) {
        final targetLocalPath = p.join(_localVaultDirectory!, '${recordId}_$filename');
        final targetFile = File(targetLocalPath);
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      }

      _showSuccessBanner('Document wiped securely from cloud and system storage.');
      await _loadVaultRecords();
    } catch (e) {
      _showErrorBanner('Purge sequence aborted: $e');
    }
  }

  // 💡 Utility: Format exact date string matching the reference UI
  String _formatDateString(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'Unknown Date';
    try {
      final date = DateTime.parse(isoString).toLocal();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      
      int hour = date.hour;
      final minute = date.minute.toString().padLeft(2, '0');
      final ampm = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      final hourStr = hour.toString().padLeft(2, '0');

      return '$day-$month-$year $hourStr:$minute $ampm';
    } catch (e) {
      return 'Unknown Date';
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
        duration: const Duration(minutes: 2), 
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
                        if (_isProcessing || _isLoading)
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
                child: RefreshIndicator(
                  onRefresh: _loadVaultRecords,
                  color: theme.primaryColor,
                  backgroundColor: theme.cardColor,
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                      : filteredItems.isEmpty
                          ? SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              child: Container(
                                height: MediaQuery.of(context).size.height * 0.5,
                                alignment: Alignment.center,
                                child: _buildEmptyStateWidget(),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                return RepaintBoundary(
                                  child: _buildVaultListRowCard(item),
                                );
                              },
                            ),
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

  // 💡 UPDATED: Fully Refactored Card Layout mapping to reference UI styles
  Widget _buildVaultListRowCard(Map<String, dynamic> item) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final recordId = item['id']?.toString() ?? '';
    final filename = item['file_name']?.toString() ?? 'Unnamed File';
    final extension = item['extension']?.toString().toUpperCase() ?? 'FILE';
    final sizeBytes = item['file_size'] as int? ?? 0;
    final sizeKb = (sizeBytes / 1024).toStringAsFixed(1);
    final formattedDate = _formatDateString(item['created_at']?.toString());
    
    bool isLocallyCached = false;
    if (_localVaultDirectory != null) {
      final expectedPath = p.join(_localVaultDirectory!, '${recordId}_$filename');
      isLocallyCached = File(expectedPath).existsSync();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: EduComponents.card(
        context: context,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Top Section: Icon, Title, and Metadata ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: systemExt.btnSoftBg,
                      borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                    ),
                    child: EduComponents.icon(
                      context: context,
                      iconData: const SolarIcon(SolarIcons.Documents, weight: SolarIconWeight.outline),
                      color: systemExt.btnSoftText,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          filename,
                          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$formattedDate • $extension • $sizeKb KB',
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 11, 
                            color: EduDesignTokens.slate400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Compact Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isLocallyCached 
                          ? (isDark ? Colors.green.withOpacity(0.15) : const Color(0xFFDCFCE7)) 
                          : systemExt.btnSoftBg,
                      borderRadius: BorderRadius.circular(EduDesignTokens.radiusM),
                      border: Border.all(
                        color: isLocallyCached 
                            ? (isDark ? Colors.green.withOpacity(0.3) : const Color(0xFFBBF7D0)) 
                            : systemExt.btnSoftBorder,
                      ),
                    ),
                    child: EduComponents.icon(
                      context: context,
                      iconData: isLocallyCached 
                          ? const SolarIcon(SolarIcons.CheckCircle, weight: SolarIconWeight.bold)
                          : const SolarIcon(SolarIcons.Cloud, weight: SolarIconWeight.bold),
                      color: isLocallyCached 
                          ? (isDark ? Colors.greenAccent : const Color(0xFF166534)) 
                          : EduDesignTokens.slate400,
                      size: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // --- Bottom Section: Structured Action Buttons ---
              Row(
                children: [
                  // Share Button (Outlined/Soft Style)
                  Expanded(
                    flex: 1,
                    child: _buildActionBtn(
                      context,
                      iconData: const SolarIcon(SolarIcons.Share, weight: SolarIconWeight.bold),
                      label: 'Share',
                      isPrimary: false,
                      onPressed: () => _handleFileShare(item, isLocallyCached),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Download/View Button (Solid Primary Style)
                  Expanded(
                    flex: 1,
                    child: _buildActionBtn(
                      context,
                      iconData: isLocallyCached 
                          ? const SolarIcon(SolarIcons.Eye, weight: SolarIconWeight.bold)
                          : const SolarIcon(SolarIcons.CloudDownload, weight: SolarIconWeight.bold),
                      label: isLocallyCached ? 'View' : 'Download',
                      isPrimary: true,
                      onPressed: () => _handleFileAccess(item),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // More Options Menu (Delete)
                  _buildMoreOptionsMenu(context, item),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 💡 UI Helpers for the new clean Card buttons
  Widget _buildActionBtn(BuildContext context, {
    required dynamic iconData, 
    required String label, 
    required bool isPrimary, 
    required VoidCallback onPressed
  }) {
    final theme = Theme.of(context);
    final systemExt = theme.extension<EduPortalThemeExtension>()!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isPrimary ? theme.primaryColor : systemExt.btnSoftBg,
            borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
            border: Border.all(
              color: isPrimary ? theme.primaryColor : systemExt.btnSoftBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EduComponents.icon(
                context: context, 
                iconData: iconData, 
                size: 16, 
                color: isPrimary ? Colors.white : systemExt.btnSoftText
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isPrimary ? Colors.white : systemExt.btnSoftText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMoreOptionsMenu(BuildContext context, Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final systemExt = theme.extension<EduPortalThemeExtension>()!;

    return PopupMenuButton<String>(
      offset: const Offset(0, 45),
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        side: BorderSide(color: systemExt.borderNeutral),
      ),
      onSelected: (value) {
        if (value == 'delete') {
          _showDeletionVerificationAlert(item);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              EduComponents.icon(
                context: context, 
                iconData: const SolarIcon(SolarIcons.TrashBinMinimalistic, weight: SolarIconWeight.outline), 
                size: 18, 
                color: systemExt.btnDangerText
              ),
              const SizedBox(width: 12),
              Text(
                'Delete Document', 
                style: TextStyle(color: systemExt.btnDangerText, fontWeight: FontWeight.bold, fontSize: 13)
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: systemExt.btnSoftBg,
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          border: Border.all(color: systemExt.btnSoftBorder),
        ),
        child: EduComponents.icon(
          context: context,
          iconData: Icons.more_horiz_rounded,
          size: 18,
          color: systemExt.btnSoftText,
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
            'This action permanently wipes the document from both your personal cloud vault and offline cache.', 
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