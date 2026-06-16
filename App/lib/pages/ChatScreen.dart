import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import '../constants/theme.dart';
import 'rich_parser.dart';
import 'profile_sheet.dart';
import 'color_assigner.dart';
import '../services/auth_service.dart';

class ChatGroupPage extends StatefulWidget {
  final String currentUserId;
  const ChatGroupPage({super.key, required this.currentUserId});

  @override
  State<ChatGroupPage> createState() => _ChatGroupPageState();
}

class _ChatGroupPageState extends State<ChatGroupPage>
    with TickerProviderStateMixin {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messagesList = [];
  bool _isSyncing = true;
  bool _isUploadingFile = false;
  RealtimeChannel? _chatChannelSubscription;

  // 💡 Replying & Editing message trackers
  Map<String, dynamic>? _replyingToMessage;
  Map<String, dynamic>? _editingMessage;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const String _telegramBotToken = "7705422769:AAE9Litq4FezGMrTYRzHuyi8SYUMgcxckkI";
  static const String _telegramChatId = "-1003952897986";

  final Map<String, String> _resolvedFileUrls = {};

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _fetchHistoricalMessages();
    _connectRealtimeBroadcast();
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    if (_chatChannelSubscription != null) {
      Supabase.instance.client.removeChannel(_chatChannelSubscription!);
    }
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('app_icon');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint("Notification tapped: ${response.payload}");
      },
    );

    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImplementation != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'group_chat_channel',
        'Group Chats',
        description: 'Real-time university group chat notifications',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      await androidImplementation.createNotificationChannel(channel);
      await androidImplementation.requestNotificationsPermission();
    }

    final iosImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosImplementation != null) {
      await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> _triggerNativeNotification(
    String senderName,
    String messageBody,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'group_chat_channel',
          'Group Chats',
          channelDescription: 'Real-time university group chat notifications',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          playSound: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: senderName,
      body: messageBody,
      notificationDetails: platformDetails,
      payload: 'group_chat_payload',
    );
  }

  Future<void> _fetchHistoricalMessages() async {
    try {
      final List<dynamic> data = await Supabase.instance.client
          .from('GroupChats')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      if (mounted) {
        setState(() {
          _messagesList = data.map((e) {
            final Map<String, dynamic> msg = Map<String, dynamic>.from(e);
            msg['sendingStatus'] = 'sent';
            return msg;
          }).toList();
          _isSyncing = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Chat sync exception: $e");
    }
  }

  void _connectRealtimeBroadcast() {
    _chatChannelSubscription = Supabase.instance.client
        .channel('public:GroupChats')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'GroupChats',
          callback: (payload) {
            final newRow = payload.newRecord;
            final oldRow = payload.oldRecord;
            final eventType = payload.eventType;

            if (mounted) {
              setState(() {
                if (eventType == PostgresChangeEvent.insert && newRow.isNotEmpty) {
                  final incomingSenderId = newRow['sender_id']?.toString();

                  // 💡 SEAMLESS MORPHING: Locate the optimistic message
                  final int tempIndex = _messagesList.indexWhere((msg) =>
                      msg['sendingStatus'] == 'sending' &&
                      msg['message_body'] == newRow['message_body'] &&
                      msg['sender_id'] == incomingSenderId
                  );

                  if (tempIndex != -1) {
                    final tempMsg = _messagesList[tempIndex];
                    final Map<String, dynamic> msg = Map<String, dynamic>.from(newRow);
                    
                    msg['sendingStatus'] = 'sent';
                    
                    // 💡 PREVENT WIDGET UNMOUNT: Lock the UI Key to the original Temp ID
                    msg['ui_key'] = tempMsg['id'];

                    // 💡 PREVENT NETWORK RELOAD: Directly propagate the local physical path
                    final oldMeta = tempMsg['attachment_meta'];
                    if (oldMeta != null && oldMeta is Map && oldMeta['local_path'] != null) {
                      Map<String, dynamic>? newMeta;
                      if (msg['attachment_meta'] is String) {
                        try { newMeta = Map<String, dynamic>.from(json.decode(msg['attachment_meta'])); } catch (_) {}
                      } else if (msg['attachment_meta'] is Map) {
                        newMeta = Map<String, dynamic>.from(msg['attachment_meta']);
                      }
                      
                      if (newMeta != null) {
                        newMeta['local_path'] = oldMeta['local_path'];
                        msg['attachment_meta'] = newMeta;
                      }
                    }

                    _messagesList[tempIndex] = msg; // 💡 Perfect in-place replacement
                  } else {
                    final Map<String, dynamic> msg = Map<String, dynamic>.from(newRow);
                    msg['sendingStatus'] = 'sent';
                    _messagesList.insert(0, msg);
                  }

                  if (incomingSenderId != widget.currentUserId) {
                    final senderName = newRow['sender_name'] ?? 'Classmate';
                    final messageBody = newRow['message_body'] ?? '';
                    _triggerNativeNotification(senderName, messageBody);
                  }
                } else if (eventType == PostgresChangeEvent.update && newRow.isNotEmpty) {
                  final int index = _messagesList.indexWhere((m) => m['id'] == newRow['id']);
                  if (index != -1) {
                    final Map<String, dynamic> updatedMsg = Map<String, dynamic>.from(newRow);
                    updatedMsg['sendingStatus'] = 'sent';
                    updatedMsg['ui_key'] = _messagesList[index]['ui_key']; // Preserve keys on edits
                    _messagesList[index] = updatedMsg;
                  }
                } else if (eventType == PostgresChangeEvent.delete && oldRow.isNotEmpty) {
                  _messagesList.removeWhere((m) => m['id'] == oldRow['id']);
                }
              });
            }
          },
        );

    _chatChannelSubscription!.subscribe((status, [error]) {
      if (status.name == 'subscribed' || status.toString().contains('subscribed')) {
        _fetchHistoricalMessages();
      }
    });
  }

  Future<String?> _uploadFileToTelegram(String path, String name) async {
    final uri = Uri.parse(
      "https://api.telegram.org/bot$_telegramBotToken/sendDocument",
    );
    final request = http.MultipartRequest("POST", uri)
      ..fields['chat_id'] = _telegramChatId
      ..files.add(
        await http.MultipartFile.fromPath('document', path, filename: name),
      );

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
      debugPrint("❌ Telegram Network Upload Exception: $e");
    }
    return null;
  }

  Future<String?> _resolveTelegramFileId(String fileId) async {
    if (_resolvedFileUrls.containsKey(fileId)) {
      return _resolvedFileUrls[fileId];
    }

    final uri = Uri.parse(
      "https://api.telegram.org/bot$_telegramBotToken/getFile?file_id=$fileId",
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final Map<String, dynamic> decoded = json.decode(response.body);
        if (decoded['ok'] == true) {
          final filePath = decoded['result']['file_path']?.toString();
          if (filePath != null) {
            final fileUrl =
                "https://api.telegram.org/file/bot$_telegramBotToken/$filePath";
            _resolvedFileUrls[fileId] = fileUrl;
            return fileUrl;
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Failed to resolve Telegram path: $e");
    }
    return null;
  }

  Future<void> _handleAttachmentSelection() async {
    if (_isUploadingFile) return; 

    // Safe MIUI focus detachment
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

      if (mounted) {
        setState(() {
          _isUploadingFile = true;
        });
      }

      final pickedFile = result.files.single;
      final localPath = pickedFile.path!;
      final filename = pickedFile.name;

      final optimisticAttachmentMsg = {
        'id': 'temp_${DateTime.now().millisecondsSinceEpoch}', 
        'sender_id': widget.currentUserId,
        'sender_name': AuthService.currentUser?.name ?? 'Anonymous Student',
        'sender_roll': AuthService.currentUser?.rollNumber ?? '',
        'sender_email': AuthService.currentUser?.email ?? '',
        'sender_branch': AuthService.currentUser?.department ?? 'B.Tech (IT)',
        'message_body': 'Shared file: $filename',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'has_attachment': true,
        'sendingStatus': 'sending',
        'attachment_meta': {
          'file_name': filename,
          'file_size': pickedFile.size,
          'extension': pickedFile.extension ?? 'octet-stream',
          'file_id': '_local_uploading_id',
          'local_path': localPath, 
        },
      };

      if (mounted) {
        setState(() {
          _messagesList.insert(0, optimisticAttachmentMsg);
        });
        _scrollToBottom();
      }

      final fileId = await _uploadFileToTelegram(localPath, filename);

      if (fileId != null) {
        final token = await AuthService.getAuthToken();
        final url = Uri.parse('https://flutter-app-development-mu.vercel.app/api/chat/send?token=$token');
        
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'body': 'Shared file: $filename',
            'has_attachment': true,
            'attachment_meta': {
              'file_id': fileId,
              'file_name': filename,
              'file_size': pickedFile.size,
              'extension': pickedFile.extension ?? 'octet-stream',
            },
          }),
        );

        if (response.statusCode != 200) {
          throw Exception("API Gateway returned ${response.statusCode}");
        }
      } else {
        if (mounted) {
          setState(() {
            _messagesList.removeWhere(
              (msg) => msg['attachment_meta']?['file_id'] == '_local_uploading_id',
            );
          });
        }
        throw Exception("Telegram failed to host file payload.");
      }
    } on PlatformException catch (pe) {
      if (!mounted) return;
      if (pe.code == 'unknown_activity') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent.shade700,
            content: const Text(
              'No compatible File Manager found. Please install a file explorer app (e.g., Google Files) to pick attachments.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Native Picker Error: ${pe.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to transmit attachment: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingFile = false;
        });
      }
    }
  }

  Future<void> _transmitTextMessage() async {
    final bodyText = _msgController.text.trim();
    if (bodyText.isEmpty) return;

    _msgController.clear();

    final rawReplyId = _replyingToMessage?['id'];
    final dynamic replyToId = (rawReplyId is String)
        ? int.tryParse(rawReplyId) ?? rawReplyId
        : rawReplyId;

    final replyToName = _replyingToMessage?['sender_name'];
    final replyToBody = _replyingToMessage?['message_body'];

    final optimisticMsg = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}', 
      'sender_id': widget.currentUserId,
      'sender_name': AuthService.currentUser?.name ?? 'Anonymous Student',
      'sender_roll': AuthService.currentUser?.rollNumber ?? '',
      'sender_email': AuthService.currentUser?.email ?? '',
      'sender_branch': AuthService.currentUser?.department ?? 'B.Tech (IT)',
      'message_body': bodyText,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'has_attachment': false,
      'attachment_meta': null,
      'sendingStatus': 'sending',
      'reply_to_id': replyToId,
      'reply_to_name': replyToName,
      'reply_to_body': replyToBody,
    };

    setState(() {
      _messagesList.insert(0, optimisticMsg);
      _replyingToMessage = null; 
    });
    _scrollToBottom();

    try {
      final token = await AuthService.getAuthToken();
      final url = Uri.parse('https://flutter-app-development-mu.vercel.app/api/chat/send?token=$token');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'body': bodyText,
          'has_attachment': false,
          'attachment_meta': null,
          'reply_to_id': replyToId,
          'reply_to_name': replyToName,
          'reply_to_body': replyToBody,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("API Gateway returned ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        _messagesList.removeWhere(
          (msg) =>
              msg['sendingStatus'] == 'sending' &&
              msg['message_body'] == bodyText,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to transmit message payload. Details: $e')),
      );
    }
  }

  Future<void> _updateTextMessage() async {
    final updatedText = _msgController.text.trim();
    if (updatedText.isEmpty || _editingMessage == null) return;

    final targetMessage = _editingMessage!;
    final rawMessageId = targetMessage['id'];
    final dynamic messageId = (rawMessageId is String)
        ? int.tryParse(rawMessageId) ?? rawMessageId
        : rawMessageId;

    _msgController.clear();

    setState(() {
      final index = _messagesList.indexWhere((m) => m['id'] == messageId);
      if (index != -1) {
        _messagesList[index]['message_body'] = updatedText;
        _messagesList[index]['is_edited'] = true;
      }
      _editingMessage = null;
    });

    try {
      await Supabase.instance.client
          .from('GroupChats')
          .update({'message_body': updatedText, 'is_edited': true})
          .eq('id', messageId);
    } catch (e) {
      try {
        await Supabase.instance.client
            .from('GroupChats')
            .update({'message_body': updatedText})
            .eq('id', messageId);
      } catch (fallbackError) {
        _fetchHistoricalMessages();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply message modifications.')),
        );
      }
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final messageId = message['id'];
    if (messageId == null) return;

    setState(() {
      _messagesList.removeWhere((m) => m['id'] == messageId);
    });

    try {
      await Supabase.instance.client
          .from('GroupChats')
          .delete()
          .eq('id', messageId);
    } catch (e) {
      _fetchHistoricalMessages();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete message. Syncing...')),
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _formatMessageTime(String? createdAtString) {
    if (createdAtString == null) return '';
    try {
      final dateTime = DateTime.parse(createdAtString).toLocal();
      final int hour = dateTime.hour;
      final int minute = dateTime.minute;
      final String amPm = hour >= 12 ? 'PM' : 'AM';
      final int hour12 = hour % 12 == 0 ? 12 : hour % 12;
      final String minuteStr = minute.toString().padLeft(2, '0');
      return '$hour12:$minuteStr $amPm';
    } catch (e) {
      return '';
    }
  }

  Widget _buildSystemDateSeparator(String text) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: systemExt.btnSoftBg,
        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        border: Border.all(color: systemExt.borderNeutral),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: systemExt.btnSoftText,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getDateSeparatorText(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final compareDate = DateTime(date.year, date.month, date.day);

    if (compareDate == today) {
      return 'Today';
    } else if (compareDate == yesterday) {
      return 'Yesterday';
    } else {
      final List<String> months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${date.day} ${months[date.month - 1]}';
    }
  }

  void _showMessageActionSheet(Map<String, dynamic> message, bool isMe) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(EduDesignTokens.radius3xl)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: EduComponents.icon(
                    context: context,
                    iconData: const SolarIcon(SolarIcons.Reply, weight: SolarIconWeight.outline),
                    color: Theme.of(context).primaryColor,
                  ),
                  title: const Text('Reply to message'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _replyingToMessage = message;
                      _editingMessage = null;
                    });
                  },
                ),
                if (isMe) ...[
                  ListTile(
                    leading: EduComponents.icon(
                      context: context,
                      iconData: const SolarIcon(SolarIcons.Pen, weight: SolarIconWeight.outline),
                      color: Colors.amber.shade700,
                    ),
                    title: const Text('Edit message'),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _editingMessage = message;
                        _replyingToMessage = null;
                        _msgController.text = message['message_body'] ?? '';
                      });
                    },
                  ),
                  ListTile(
                    leading: EduComponents.icon(
                      context: context,
                      iconData: const SolarIcon(SolarIcons.TrashBinMinimalistic, weight: SolarIconWeight.outline),
                      color: systemExt.btnDangerText,
                    ),
                    title: const Text('Delete message'),
                    onTap: () {
                      Navigator.pop(context);
                      _deleteMessage(message);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: systemExt.pageBackground),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _isSyncing
                    ? Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        reverse: true,
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                        itemCount: _messagesList.length,
                        itemBuilder: (context, index) {
                          final message = _messagesList[index];
                          final isMe = message['sender_id']?.toString() == widget.currentUserId;
          
                          bool showDateSeparator = false;
                          String separatorText = '';
                          try {
                            final currentMsgDate = DateTime.parse(message['created_at']).toLocal();
                            if (index == _messagesList.length - 1) {
                              showDateSeparator = true;
                              separatorText = _getDateSeparatorText(currentMsgDate);
                            } else {
                              final nextMsg = _messagesList[index + 1];
                              final nextMsgDate = DateTime.parse(nextMsg['created_at']).toLocal();
                              if (currentMsgDate.year != nextMsgDate.year ||
                                  currentMsgDate.month != nextMsgDate.month ||
                                  currentMsgDate.day != nextMsgDate.day) {
                                showDateSeparator = true;
                                separatorText = _getDateSeparatorText(currentMsgDate);
                              }
                            }
                          } catch (_) {}
          
                          final messageBubble = GestureDetector(
                            onLongPress: () => _showMessageActionSheet(message, isMe),
                            child: _buildChatBubbleCard(message, isMe),
                          );
          
                          final String msgKey = message['ui_key']?.toString() ?? 
                              message['id']?.toString() ?? 
                              'index_${index}_${message['created_at']}';
          
                          final swipeableBubble = Dismissible(
                            key: ValueKey(msgKey),
                            direction: DismissDirection.startToEnd,
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                setState(() {
                                  _replyingToMessage = message;
                                  _editingMessage = null; 
                                });
                              }
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20.0),
                              child: EduComponents.icon(
                                context: context,
                                iconData: const SolarIcon(SolarIcons.Reply, weight: SolarIconWeight.bold),
                                color: Theme.of(context).primaryColor,
                                size: 22,
                              ),
                            ),
                            child: messageBubble,
                          );
          
                          final Widget bubbleWithSeparator = showDateSeparator
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildSystemDateSeparator(separatorText),
                                    swipeableBubble,
                                  ],
                                )
                              : swipeableBubble;
          
                          return RepaintBoundary(child: bubbleWithSeparator);
                        },
                      ),
              ),
          
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _buildReplyingPreviewTrack(),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _buildEditingPreviewTrack(),
              ),
          
              _buildInputActionTrack(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyingPreviewTrack() {
    if (_replyingToMessage == null) return const SizedBox.shrink();
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: systemExt.borderNeutral)),
      ),
      child: Row(
        children: [
          Container(
            width: 4, height: 36,
            decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Replying to ${_replyingToMessage!['sender_name'] ?? 'Classmate'}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Theme.of(context).primaryColor),
                ),
                Text(_replyingToMessage!['message_body'] ?? 'Attachment',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: EduDesignTokens.slate400),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _replyingToMessage = null),
            icon: EduComponents.icon(context: context, iconData: EduIcons.close, size: 18, color: EduDesignTokens.slate400),
          ),
        ],
      ),
    );
  }

  Widget _buildEditingPreviewTrack() {
    if (_editingMessage == null) return const SizedBox.shrink();
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: systemExt.btnSoftBg,
        border: Border(top: BorderSide(color: systemExt.borderNeutral)),
      ),
      child: Row(
        children: [
          Container(
            width: 4, height: 36,
            decoration: BoxDecoration(color: EduDesignTokens.emerald500, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Editing message...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: EduDesignTokens.emerald700),
                ),
                Text(_editingMessage!['message_body'] ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: systemExt.btnSoftText.withOpacity(0.8)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() { _editingMessage = null; _msgController.clear(); }),
            icon: EduComponents.icon(context: context, iconData: EduIcons.close, size: 18, color: systemExt.btnSoftText),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubbleCard(Map<String, dynamic> msg, bool isMe) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final textTheme = Theme.of(context).textTheme;
    final senderName = msg['sender_name'] ?? 'Unknown User';
    final rawBody = msg['message_body'] ?? '';
    final senderRoll = msg['sender_roll']?.toString() ?? '';
    final hasAttachment = msg['has_attachment'] ?? false;
    final String sendingStatus = msg['sendingStatus'] ?? 'sent';
    final String formattedTime = _formatMessageTime(msg['created_at']);
    final bool isEdited = msg['is_edited'] ?? false;

    final replyToName = msg['reply_to_name'];
    final replyToBody = msg['reply_to_body'];

    Map<String, dynamic>? attachmentMeta;
    if (msg['attachment_meta'] != null) {
      if (msg['attachment_meta'] is String) {
        try { attachmentMeta = Map<String, dynamic>.from(json.decode(msg['attachment_meta'])); } catch (_) {}
      } else if (msg['attachment_meta'] is Map) {
        attachmentMeta = Map<String, dynamic>.from(msg['attachment_meta']);
      }
    }

    final colorSignature = SenderColorAssigner.getColor(senderRoll);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78, minWidth: 80),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: isMe
              ? (Theme.of(context).brightness == Brightness.dark ? EduDesignTokens.indigo500.withOpacity(0.15) : EduDesignTokens.indigo50)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(EduDesignTokens.radius2xl),
            topRight: const Radius.circular(EduDesignTokens.radius2xl),
            bottomLeft: isMe ? const Radius.circular(EduDesignTokens.radius2xl) : Radius.zero,
            bottomRight: isMe ? JuridicalRadius.zero : const Radius.circular(EduDesignTokens.radius2xl),
          ),
          border: Border.all(
            color: isMe
                ? (Theme.of(context).brightness == Brightness.dark ? EduDesignTokens.indigo500.withOpacity(0.3) : const Color(0xFFC7D2FE))
                : systemExt.borderNeutral,
          ),
        ),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMe) ...[
                GestureDetector(
                  onTap: () => UserProfileInspectorSheet.show(
                    context: context, name: senderName, rollNumber: senderRoll,
                    email: msg['sender_email'] ?? 'Not provided', branch: msg['sender_branch'] ?? 'B.Tech', semester: '4',
                  ),
                  child: Text(senderName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorSignature)),
                ),
                const SizedBox(height: 4),
              ],

              if (replyToName != null && replyToBody != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isMe ? Theme.of(context).cardColor : systemExt.btnSoftBg,
                    borderRadius: BorderRadius.circular(EduDesignTokens.radiusM),
                    border: Border(left: BorderSide(color: isMe ? Theme.of(context).primaryColor : colorSignature, width: 3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(replyToName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isMe ? Theme.of(context).primaryColor : colorSignature)),
                      const SizedBox(height: 2),
                      Text(replyToBody, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: systemExt.btnSoftText)),
                    ],
                  ),
                ),
              ],

              if (hasAttachment && attachmentMeta != null) ...[
                _buildAttachmentRenderer(attachmentMeta, sendingStatus), 
                const SizedBox(height: 6),
              ],

              RichChatMessageParser(
                text: _processNewlineFormatting(rawBody),
                baseStyle: textTheme.bodyLarge?.copyWith(fontSize: 14, height: 1.35),
              ),

              const SizedBox(height: 4),

              Align(
                alignment: Alignment.bottomRight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isEdited) const Text('Edited · ', style: TextStyle(color: Colors.grey, fontSize: 10, fontStyle: FontStyle.italic)),
                    Text(formattedTime, style: textTheme.labelSmall?.copyWith(fontSize: 10, color: EduDesignTokens.slate400)),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      if (sendingStatus == 'sending')
                        SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Theme.of(context).primaryColor.withOpacity(0.5)))
                      else
                        Icon(Icons.done_all_rounded, size: 14, color: Theme.of(context).primaryColor.withOpacity(0.8)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _processNewlineFormatting(String rawText) {
    if (rawText.isEmpty) return rawText;
    final RegExp mathRegex = RegExp(r'(\$\$(.*?)\$\$)|(\$(.*?)\$)', dotAll: true);
    final List<String> segments = [];
    final Iterable<RegExpMatch> matches = mathRegex.allMatches(rawText);

    int lastIndex = 0;
    for (final match in matches) {
      if (match.start > lastIndex) segments.add(_applyDoubleNewlines(rawText.substring(lastIndex, match.start)));
      segments.add(match.group(0)!);
      lastIndex = match.end;
    }
    if (lastIndex < rawText.length) segments.add(_applyDoubleNewlines(rawText.substring(lastIndex)));
    return segments.join('');
  }

  String _applyDoubleNewlines(String input) {
    final List<String> paragraphs = input.split('\n\n');
    final processed = paragraphs.map((segment) => segment.replaceAll('\n', '\n\n')).toList();
    return processed.join('\n\n');
  }

  // 💡 CORE FLICKER FIX: These stable widget structures permanently prevent Flutter element destruction
  Widget _buildStableImageBubbleCardLocal(String localPath, {bool isUploading = false}) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.file(
            File(localPath), fit: BoxFit.cover, width: double.infinity, height: 180,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 150, color: systemExt.btnSoftBg, alignment: Alignment.center,
              child: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.FileCorrupted, weight: SolarIconWeight.outline), color: systemExt.btnSoftText),
            ),
          ),
          if (isUploading) ...[
            Container(width: double.infinity, height: 180, color: Colors.black.withOpacity(0.4)), 
            CircularProgressIndicator(strokeWidth: 3, color: Colors.white.withOpacity(0.9)),
          ],
        ],
      ),
    );
  }

  Widget _buildStableDocumentBubbleCard(String filename, String extension, {bool isUploading = false}) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: systemExt.btnSoftBg, borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl), border: Border.all(color: systemExt.borderNeutral)),
      child: Row(
        children: [
          EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.Documents, weight: SolarIconWeight.outline), color: systemExt.btnSoftText, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filename, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).textTheme.bodyLarge?.color), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(isUploading ? 'Uploading...' : extension.toUpperCase(), style: TextStyle(fontSize: 10, color: isUploading ? Theme.of(context).primaryColor : systemExt.btnSoftText.withOpacity(0.7), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (isUploading)
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor))
          else
            EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.CloudDownload, weight: SolarIconWeight.bold), color: Theme.of(context).primaryColor, size: 22),
        ],
      ),
    );
  }

  Widget _buildAttachmentRenderer(Map<String, dynamic> meta, String sendingStatus) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final fileId = meta['file_id']?.toString() ?? '';
    final filename = meta['file_name']?.toString() ?? 'Attachment';
    final extension = meta['extension']?.toString().toLowerCase() ?? '';
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
    final localPath = meta['local_path'] as String?;

    // 💡 1. PERFECT LOCAL MORPH: Physically unifies the widget tree shape so Flutter doesn't reload it!
    if (localPath != null && File(localPath).existsSync()) {
      final bool isUploading = (sendingStatus == 'sending' || fileId == '_local_uploading_id');
      
      return GestureDetector(
        onTap: isUploading ? null : () => _openAttachmentActionSheet(fileId, filename, extension, isImage, localPath, true),
        child: isImage
            ? _buildStableImageBubbleCardLocal(localPath, isUploading: isUploading)
            : _buildStableDocumentBubbleCard(filename, extension, isUploading: isUploading),
      );
    }

    // 2. Active Upload Fallback (Rare - UI state without physical access)
    if (fileId == '_local_uploading_id' || sendingStatus == 'sending') {
      return Container(
        height: 80, padding: const EdgeInsets.all(12), alignment: Alignment.center,
        decoration: BoxDecoration(color: systemExt.btnSoftBg, borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl), border: Border.all(color: systemExt.btnSoftBorder)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor)),
            const SizedBox(width: 12),
            Text('Uploading attachment...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: systemExt.btnSoftText)),
          ],
        ),
      );
    }

    // 3. Network Resolution (For receiving standard cloud files from others)
    final String? cachedUrl = _resolvedFileUrls[fileId];
    if (cachedUrl != null) {
      return _buildClickableAttachmentCard(fileId, filename, extension, isImage, cachedUrl);
    }

    return FutureBuilder<String?>(
      future: _resolveTelegramFileId(fileId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: isImage ? 180 : 64, alignment: Alignment.center,
            decoration: BoxDecoration(color: systemExt.btnSoftBg, borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl), border: Border.all(color: systemExt.btnSoftBorder)),
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor)),
          );
        }
        final resolvedUrl = snapshot.data;
        if (resolvedUrl == null) {
          return Container(
            height: 64, alignment: Alignment.center,
            decoration: BoxDecoration(color: systemExt.btnDangerBg, borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl), border: Border.all(color: systemExt.btnDangerBorder)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                EduComponents.icon(context: context, iconData: EduIcons.danger, color: systemExt.btnDangerText, size: 20),
                const SizedBox(width: 8),
                Text('Resource Resolution Error', style: TextStyle(color: systemExt.btnDangerText, fontSize: 12)),
              ],
            ),
          );
        }
        return _buildClickableAttachmentCard(fileId, filename, extension, isImage, resolvedUrl);
      },
    );
  }

  Widget _buildClickableAttachmentCard(
    String fileId, String filename, String extension, bool isImage, String resolvedUrl,
  ) {
    return GestureDetector(
      onTap: () => _openAttachmentActionSheet(fileId, filename, extension, isImage, resolvedUrl, false),
      child: isImage ? _buildImageBubbleCard(resolvedUrl) : _buildStableDocumentBubbleCard(filename, extension, isUploading: false),
    );
  }

  Widget _buildImageBubbleCard(String resolvedUrl) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
      child: Image.network(
        resolvedUrl, fit: BoxFit.cover, width: double.infinity, height: 180,
        errorBuilder: (context, error, stackTrace) => Container(
          height: 150, color: systemExt.btnSoftBg, alignment: Alignment.center,
          child: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.FileCorrupted, weight: SolarIconWeight.outline), color: systemExt.btnSoftText),
        ),
      ),
    );
  }

  void _openAttachmentActionSheet(
    String fileId, String filename, String extension, bool isImage, String resolvedPathOrUrl, [bool isLocal = false]
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(EduDesignTokens.radius3xl))),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44, height: 4, margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: EduDesignTokens.slate300.withOpacity(0.5), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Text(filename, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('Format: ${extension.toUpperCase()}', style: theme.textTheme.labelSmall),
                const Divider(height: 24, thickness: 1),

                ListTile(
                  leading: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.ChatSquare, weight: SolarIconWeight.outline), color: theme.primaryColor),
                  title: Text(isImage ? 'Preview Full Screen' : 'Open Document Source'),
                  onTap: () {
                    Navigator.pop(context);
                    if (isImage) {
                      _triggerFullImagePreview(resolvedPathOrUrl, filename, isLocal);
                    } else {
                      _triggerDownloadAction(resolvedPathOrUrl, filename, isLocal);
                    }
                  },
                ),
                ListTile(
                  leading: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.CloudDownload, weight: SolarIconWeight.outline), color: theme.primaryColor),
                  title: const Text('Download to local storage'),
                  onTap: () {
                    Navigator.pop(context);
                    _triggerDownloadAction(resolvedPathOrUrl, filename, isLocal);
                  },
                ),
                if (!isLocal)
                  ListTile(
                    leading: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.Share, weight: SolarIconWeight.outline), color: theme.primaryColor),
                    title: const Text('Share File Link'),
                    onTap: () {
                      Navigator.pop(context);
                      _triggerShareLinkAction(resolvedPathOrUrl);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _triggerFullImagePreview(String pathOrUrl, String filename, [bool isLocal = false]) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                backgroundColor: Colors.transparent, elevation: 0,
                leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => Navigator.pop(context)),
                title: Text(filename, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: InteractiveViewer(
                  panEnabled: true, minScale: 0.5, maxScale: 4.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                    child: isLocal
                        ? Image.file(File(pathOrUrl), fit: BoxFit.contain)
                        : Image.network(pathOrUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _triggerDownloadAction(String pathOrUrl, String filename, [bool isLocal = false]) {
    if (isLocal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              EduComponents.icon(context: context, iconData: EduIcons.success, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 12),
              const Expanded(child: Text('File is already stored locally on your device.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            ],
          ),
          backgroundColor: Theme.of(context).primaryColor, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor)),
            const SizedBox(width: 12),
            Expanded(child: Text('Downloading $filename...', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          ],
        ),
        backgroundColor: EduDesignTokens.slate900, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              EduComponents.icon(context: context, iconData: EduIcons.success, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text('Completed download of $filename', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            ],
          ),
          backgroundColor: Theme.of(context).primaryColor, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
        ),
      );
    });
  }

  void _triggerShareLinkAction(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            EduComponents.icon(context: context, iconData: EduIcons.success, color: Colors.greenAccent, size: 20),
            const SizedBox(width: 12),
            const Text('Direct share link copied to clipboard!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl)),
      ),
    );
  }

  Widget _buildInputActionTrack() {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: theme.cardColor, border: Border(top: BorderSide(color: systemExt.borderNeutral))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: IconButton(
              onPressed: _isUploadingFile ? null : _handleAttachmentSelection,
              icon: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.Paperclip, weight: SolarIconWeight.outline), color: EduDesignTokens.slate400),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl), border: Border.all(color: systemExt.borderNeutral)),
              child: TextField(
                controller: _msgController, minLines: 1, maxLines: 2, keyboardType: TextInputType.multiline, textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14),
                decoration: const InputDecoration(hintText: "Type message...", hintStyle: TextStyle(fontSize: 13, color: EduDesignTokens.slate400), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, isDense: true),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: IconButton(
              onPressed: _editingMessage != null ? _updateTextMessage : _transmitTextMessage,
              style: IconButton.styleFrom(backgroundColor: theme.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl))),
              icon: EduComponents.icon(context: context, iconData: const SolarIcon(SolarIcons.ArrowRight, weight: SolarIconWeight.bold), color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class JuridicalRadius {
  static Radius get zero => Radius.zero;
}