import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for secure clipboard operations
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutty_solar_icons/flutty_solar_icons.dart';
import '../constants/theme.dart'; // Handles your solar icons and customized theme globally
import 'rich_parser.dart'; // Handles markdown & LaTeX formulas
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

  // 💡 Native Local Notifications plugin instance
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // 💡 Telegram Credentials
  static const String _telegramBotToken ="7705422769:AAE9Litq4FezGMrTYRzHuyi8SYUMgcxckkI";
  static const String _telegramChatId = "-1003952897986";

  // 💡 Local cache to store resolved Telegram File URLs (prevents continuous API rebuilding)
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
        AndroidInitializationSettings('@mipmap/ic_launcher');

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

    // 💡 FIXED: Configured initialize with the required named 'settings' parameter pattern
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint("Notification tapped: ${response.payload}");
      },
    );

    // Request Permissions & Setup channels dynamically for both Android & iOS
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
      debugPrint("🔔 Android Notification Channel registered successfully.");
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
      debugPrint("🔔 iOS Notification Permissions requested successfully.");
    }
  }

  Future<void> _triggerNativeNotification(
    String senderName,
    String messageBody,
  ) async {
    debugPrint(
      "🔔 Dispatching Notification - Sender: $senderName, Body: $messageBody",
    );

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

    // 💡 FIXED: Passed variables as NAMED parameters to avoid compiler crash with show() method in v20+
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
          event: PostgresChangeEvent
              .all, // Listen to INSERT, UPDATE, and DELETE actions
          schema: 'public',
          table: 'GroupChats',
          callback: (payload) {
            final newRow = payload.newRecord;
            final oldRow = payload.oldRecord;
            final eventType = payload.eventType;

            if (mounted) {
              setState(() {
                if (eventType == PostgresChangeEvent.insert &&
                    newRow.isNotEmpty) {
                  final incomingSenderId = newRow['sender_id']?.toString();

                  // Clear active matching optimistic preview bars
                  _messagesList.removeWhere(
                    (msg) =>
                        msg['sendingStatus'] == 'sending' &&
                        msg['message_body'] == newRow['message_body'] &&
                        msg['sender_id'] == incomingSenderId,
                  );

                  final Map<String, dynamic> msg = Map<String, dynamic>.from(
                    newRow,
                  );
                  msg['sendingStatus'] = 'sent';
                  _messagesList.insert(0, msg);

                  if (incomingSenderId != widget.currentUserId) {
                    final senderName = newRow['sender_name'] ?? 'Classmate';
                    final messageBody = newRow['message_body'] ?? '';
                    _triggerNativeNotification(senderName, messageBody);
                  }
                } else if (eventType == PostgresChangeEvent.update &&
                    newRow.isNotEmpty) {
                  final int index = _messagesList.indexWhere(
                    (m) => m['id'] == newRow['id'],
                  );
                  if (index != -1) {
                    final Map<String, dynamic> updatedMsg =
                        Map<String, dynamic>.from(newRow);
                    updatedMsg['sendingStatus'] = 'sent';
                    _messagesList[index] = updatedMsg;
                  }
                } else if (eventType == PostgresChangeEvent.delete &&
                    oldRow.isNotEmpty) {
                  _messagesList.removeWhere((m) => m['id'] == oldRow['id']);
                }
              });
            }
          },
        );

    _chatChannelSubscription!.subscribe((status, [error]) {
      if (status.name == 'subscribed' ||
          status.toString().contains('subscribed')) {
        debugPrint("⚡ Realtime Broadcast established successfully.");
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
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isUploadingFile = true;
      });

      final pickedFile = result.files.single;
      final localPath = pickedFile.path!;
      final filename = pickedFile.name;

      // ⚡ OPTIMISTIC UI: Instantly render placeholders
      final optimisticAttachmentMsg = {
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
        },
      };

      setState(() {
        _messagesList.insert(0, optimisticAttachmentMsg);
      });
      _scrollToBottom();

      final fileId = await _uploadFileToTelegram(localPath, filename);

      if (fileId != null) {
        await Supabase.instance.client.from('GroupChats').insert({
          'sender_id': widget.currentUserId,
          'sender_name': AuthService.currentUser?.name ?? 'Anonymous Student',
          'sender_roll': AuthService.currentUser?.rollNumber ?? '',
          'sender_email': AuthService.currentUser?.email ?? '',
          'sender_branch': AuthService.currentUser?.department ?? 'B.Tech (IT)',
          'message_body': 'Shared file: $filename',
          'has_attachment': true,
          'attachment_meta': {
            'file_id': fileId,
            'file_name': filename,
            'file_size': pickedFile.size,
            'extension': pickedFile.extension ?? 'octet-stream',
          },
        });
      } else {
        setState(() {
          _messagesList.removeWhere(
            (msg) =>
                msg['attachment_meta']?['file_id'] == '_local_uploading_id',
          );
        });
        throw Exception("Telegram failed to host file payload.");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to transmit attachment: ${e.toString()}'),
        ),
      );
    } finally {
      setState(() {
        _isUploadingFile = false;
      });
    }
  }

  Future<void> _transmitTextMessage() async {
    final bodyText = _msgController.text.trim();
    if (bodyText.isEmpty) return;

    _msgController.clear();

    // Safely parsing ID dynamically to ensure strict schema structural conformity
    final rawReplyId = _replyingToMessage?['id'];
    final dynamic replyToId = (rawReplyId is String)
        ? int.tryParse(rawReplyId) ?? rawReplyId
        : rawReplyId;

    final replyToName = _replyingToMessage?['sender_name'];
    final replyToBody = _replyingToMessage?['message_body'];

    final optimisticMsg = {
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
      _replyingToMessage = null; // Clean active selection
    });
    _scrollToBottom();

    try {
      // 💡 Attempt 1: Try inserting with current parsed ID format
      await Supabase.instance.client.from('GroupChats').insert({
        'sender_id': widget.currentUserId,
        'sender_name': AuthService.currentUser?.name ?? 'Anonymous Student',
        'sender_roll': AuthService.currentUser?.rollNumber ?? '',
        'sender_email': AuthService.currentUser?.email ?? '',
        'sender_branch': AuthService.currentUser?.department ?? 'B.Tech (IT)',
        'message_body': bodyText,
        'has_attachment': false,
        'attachment_meta': null,
        'reply_to_id': replyToId,
        'reply_to_name': replyToName,
        'reply_to_body': replyToBody,
      });
    } catch (e) {
      debugPrint(
        "First reply attempt failed: $e. Trying automatic type conversion fallback...",
      );
      try {
        // 💡 Attempt 2: Auto-convert datatype (e.g. if replyToId is int, send String; if String, send int)
        final alternativeReplyId = (replyToId is int)
            ? replyToId.toString()
            : (int.tryParse(replyToId.toString()) ?? replyToId);

        await Supabase.instance.client.from('GroupChats').insert({
          'sender_id': widget.currentUserId,
          'sender_name': AuthService.currentUser?.name ?? 'Anonymous Student',
          'sender_roll': AuthService.currentUser?.rollNumber ?? '',
          'sender_email': AuthService.currentUser?.email ?? '',
          'sender_branch': AuthService.currentUser?.department ?? 'B.Tech (IT)',
          'message_body': bodyText,
          'has_attachment': false,
          'attachment_meta': null,
          'reply_to_id': alternativeReplyId,
          'reply_to_name': replyToName,
          'reply_to_body': replyToBody,
        });
      } catch (fallbackError) {
        debugPrint(
          "Adaptive retry failed: $fallbackError. Sending standard fallback...",
        );
        try {
          // Attempt 3: If reply mapping completely fails, drop columns and send standard message safely
          await Supabase.instance.client.from('GroupChats').insert({
            'sender_id': widget.currentUserId,
            'sender_name': AuthService.currentUser?.name ?? 'Anonymous Student',
            'sender_roll': AuthService.currentUser?.rollNumber ?? '',
            'sender_email': AuthService.currentUser?.email ?? '',
            'sender_branch':
                AuthService.currentUser?.department ?? 'B.Tech (IT)',
            'message_body': bodyText,
            'has_attachment': false,
            'attachment_meta': null,
          });
        } catch (finalError) {
          setState(() {
            _messagesList.removeWhere(
              (msg) =>
                  msg['sendingStatus'] == 'sending' &&
                  msg['message_body'] == bodyText,
            );
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message transfer failure. Syncing backend...'),
            ),
          );
        }
      }
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
      // Safely catch tables lacking is_edited column definition mapping
      await Supabase.instance.client
          .from('GroupChats')
          .update({'message_body': updatedText, 'is_edited': true})
          .eq('id', messageId);
    } catch (e) {
      debugPrint(
        "is_edited column mapping failed, targeting message_body alone: $e",
      );
      try {
        await Supabase.instance.client
            .from('GroupChats')
            .update({'message_body': updatedText})
            .eq('id', messageId);
      } catch (fallbackError) {
        _fetchHistoricalMessages();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to apply message modifications.'),
          ),
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
      return '${date.day} ${months[date.month - 1]}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: systemExt.pageBackground),
        child: Column(
          children: [
            Expanded(
              child: _isSyncing
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).primaryColor,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      reverse: true,
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      itemCount: _messagesList.length,
                      itemBuilder: (context, index) {
                        final message = _messagesList[index];
                        final isMe =
                            message['sender_id']?.toString() ==
                            widget.currentUserId;

                        bool showDateSeparator = false;
                        String separatorText = '';
                        try {
                          final currentMsgDate = DateTime.parse(
                            message['created_at'],
                          ).toLocal();
                          if (index == _messagesList.length - 1) {
                            showDateSeparator = true;
                            separatorText = _getDateSeparatorText(
                              currentMsgDate,
                            );
                          } else {
                            final nextMsg = _messagesList[index + 1];
                            final nextMsgDate = DateTime.parse(
                              nextMsg['created_at'],
                            ).toLocal();
                            if (currentMsgDate.year != nextMsgDate.year ||
                                currentMsgDate.month != nextMsgDate.month ||
                                currentMsgDate.day != nextMsgDate.day) {
                              showDateSeparator = true;
                              separatorText = _getDateSeparatorText(
                                currentMsgDate,
                              );
                            }
                          }
                        } catch (_) {}

                        final messageBubble = GestureDetector(
                          onLongPress: () =>
                              _showMessageActionSheet(message, isMe),
                          child: _buildChatBubbleCard(message, isMe),
                        );

                        final swipeableBubble = Dismissible(
                          key: ValueKey(
                            message['id'] ??
                                'index_${index}_${message['created_at']}',
                          ),
                          direction: DismissDirection.startToEnd,
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.startToEnd) {
                              setState(() {
                                _replyingToMessage = message;
                                _editingMessage =
                                    null; // Reply overrides Edit mode
                              });
                            }
                            return false;
                          },
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 20.0),
                            child: EduComponents.icon(
                              context: context,
                              iconData: const SolarIcon(
                                SolarIcons.Reply,
                                weight: SolarIconWeight.bold,
                              ),
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

                        // High frame rate viewport isolation optimization
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

            // Message input bar
            _buildInputActionTrack(),
          ],
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
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${_replyingToMessage!['sender_name'] ?? 'Classmate'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                Text(
                  _replyingToMessage!['message_body'] ?? 'Attachment',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: EduDesignTokens.slate400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
            icon: EduComponents.icon(
              context: context,
              iconData: EduIcons.close,
              size: 18,
              color: EduDesignTokens.slate400,
            ),
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
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: EduDesignTokens.emerald500,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Editing message...',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: EduDesignTokens.emerald700,
                  ),
                ),
                Text(
                  _editingMessage!['message_body'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: systemExt.btnSoftText.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _editingMessage = null;
                _msgController.clear();
              });
            },
            icon: EduComponents.icon(
              context: context,
              iconData: EduIcons.close,
              size: 18,
              color: systemExt.btnSoftText,
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageActionSheet(Map<String, dynamic> message, bool isMe) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EduDesignTokens.radius3xl),
        ),
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
                    iconData: const SolarIcon(
                      SolarIcons.Reply,
                      weight: SolarIconWeight.outline,
                    ),
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
                      iconData: const SolarIcon(
                        SolarIcons.Pen,
                        weight: SolarIconWeight.outline,
                      ),
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
                      iconData: const SolarIcon(
                        SolarIcons.TrashBinMinimalistic,
                        weight: SolarIconWeight.outline,
                      ),
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
        try {
          attachmentMeta = Map<String, dynamic>.from(
            json.decode(msg['attachment_meta']),
          );
        } catch (_) {}
      } else if (msg['attachment_meta'] is Map) {
        attachmentMeta = Map<String, dynamic>.from(msg['attachment_meta']);
      }
    }

    final colorSignature = SenderColorAssigner.getColor(senderRoll);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        // 💡 OPTIMIZED: The constraints limit maximum width, but IntrinsicWidth below lets the bubble shrink-wrap tightly!
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
          minWidth: 80,
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: isMe
              ? (Theme.of(context).brightness == Brightness.dark
                    ? EduDesignTokens.indigo500.withOpacity(0.15)
                    : EduDesignTokens.indigo50)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(EduDesignTokens.radius2xl),
            topRight: const Radius.circular(EduDesignTokens.radius2xl),
            bottomLeft: isMe
                ? const Radius.circular(EduDesignTokens.radius2xl)
                : Radius.zero,
            bottomRight: isMe
                ? JuridicalRadius.zero
                : const Radius.circular(EduDesignTokens.radius2xl),
          ),
          border: Border.all(
            color: isMe
                ? (Theme.of(context).brightness == Brightness.dark
                      ? EduDesignTokens.indigo500.withOpacity(0.3)
                      : const Color(0xFFC7D2FE))
                : systemExt.borderNeutral,
          ),
        ),
        // 💡 FIXED: Wrapping in IntrinsicWidth forces the Column to layout tightly to the width of the text!
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMe) ...[
                GestureDetector(
                  onTap: () => UserProfileInspectorSheet.show(
                    context: context,
                    name: senderName,
                    rollNumber: senderRoll,
                    email: msg['sender_email'] ?? 'Not provided',
                    branch: msg['sender_branch'] ?? 'B.Tech',
                    semester: '4',
                  ),
                  child: Text(
                    senderName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorSignature,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],

              if (replyToName != null && replyToBody != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Theme.of(context).cardColor
                        : systemExt.btnSoftBg,
                    borderRadius: BorderRadius.circular(
                      EduDesignTokens.radiusM,
                    ),
                    border: Border(
                      left: BorderSide(
                        color: isMe
                            ? Theme.of(context).primaryColor
                            : colorSignature,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        replyToName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: isMe
                              ? Theme.of(context).primaryColor
                              : colorSignature,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        replyToBody,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: systemExt.btnSoftText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (hasAttachment && attachmentMeta != null) ...[
                _buildAttachmentRenderer(attachmentMeta),
                const SizedBox(height: 6),
              ],

              RichChatMessageParser(
                text: _processNewlineFormatting(rawBody),
                baseStyle: textTheme.bodyLarge?.copyWith(
                  fontSize: 14,
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 4),

              Align(
                alignment: Alignment.bottomRight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isEdited) ...[
                      const Text(
                        'Edited · ',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    Text(
                      formattedTime,
                      style: textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: EduDesignTokens.slate400,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      if (sendingStatus == 'sending')
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.5),
                          ),
                        )
                      else
                        Icon(
                          Icons.done_all_rounded,
                          size: 14,
                          color: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.8),
                        ),
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

    final RegExp mathRegex = RegExp(
      r'(\$\$(.*?)\$\$)|(\$(.*?)\$)',
      dotAll: true,
    );
    final List<String> segments = [];
    final Iterable<RegExpMatch> matches = mathRegex.allMatches(rawText);

    int lastIndex = 0;
    for (final match in matches) {
      if (match.start > lastIndex) {
        segments.add(
          _applyDoubleNewlines(rawText.substring(lastIndex, match.start)),
        );
      }
      segments.add(match.group(0)!);
      lastIndex = match.end;
    }
    if (lastIndex < rawText.length) {
      segments.add(_applyDoubleNewlines(rawText.substring(lastIndex)));
    }
    return segments.join('');
  }

  String _applyDoubleNewlines(String input) {
    final List<String> paragraphs = input.split('\n\n');
    final processed = paragraphs.map((segment) {
      return segment.replaceAll('\n', '\n\n');
    }).toList();
    return processed.join('\n\n');
  }

  Widget _buildAttachmentRenderer(Map<String, dynamic> meta) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final fileId = meta['file_id']?.toString() ?? '';
    final filename = meta['file_name']?.toString() ?? 'Attachment';
    final extension = meta['extension']?.toString().toLowerCase() ?? '';
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);

    if (fileId == '_local_uploading_id') {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          color: systemExt.btnSoftBg,
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          border: Border.all(color: systemExt.btnSoftBorder),
        ),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Uploading attachment to cloud...',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: systemExt.btnSoftText,
              ),
            ),
          ],
        ),
      );
    }

    final String? cachedUrl = _resolvedFileUrls[fileId];
    if (cachedUrl != null) {
      return _buildClickableAttachmentCard(
        fileId,
        filename,
        extension,
        isImage,
        cachedUrl,
      );
    }

    return FutureBuilder<String?>(
      future: _resolveTelegramFileId(fileId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: isImage ? 180 : 64,
            decoration: BoxDecoration(
              color: systemExt.btnSoftBg,
              borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
              border: Border.all(color: systemExt.btnSoftBorder),
            ),
            alignment: Alignment.center,
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).primaryColor,
              ),
            ),
          );
        }
        final resolvedUrl = snapshot.data;
        if (resolvedUrl == null) {
          return Container(
            height: 64,
            decoration: BoxDecoration(
              color: systemExt.btnDangerBg,
              borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
              border: Border.all(color: systemExt.btnDangerBorder),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                EduComponents.icon(
                  context: context,
                  iconData: EduIcons.danger,
                  color: systemExt.btnDangerText,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Resource Resolution Error',
                  style: TextStyle(
                    color: systemExt.btnDangerText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }
        return _buildClickableAttachmentCard(
          fileId,
          filename,
          extension,
          isImage,
          resolvedUrl,
        );
      },
    );
  }

  Widget _buildClickableAttachmentCard(
    String fileId,
    String filename,
    String extension,
    bool isImage,
    String resolvedUrl,
  ) {
    return GestureDetector(
      onTap: () => _openAttachmentActionSheet(
        fileId,
        filename,
        extension,
        isImage,
        resolvedUrl,
      ),
      child: isImage
          ? _buildImageBubbleCard(resolvedUrl)
          : _buildDocumentBubbleCard(filename, extension),
    );
  }

  Widget _buildImageBubbleCard(String resolvedUrl) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
      child: Image.network(
        resolvedUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: 180,
        errorBuilder: (context, error, stackTrace) => Container(
          height: 150,
          color: systemExt.btnSoftBg,
          alignment: Alignment.center,
          child: EduComponents.icon(
            context: context,
            iconData: const SolarIcon(
              SolarIcons.FileCorrupted,
              weight: SolarIconWeight.outline,
            ),
            color: systemExt.btnSoftText,
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentBubbleCard(String filename, String extension) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: systemExt.btnSoftBg,
        borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        border: Border.all(color: systemExt.btnSoftBorder),
      ),
      child: Row(
        children: [
          EduComponents.icon(
            context: context,
            iconData: const SolarIcon(
              SolarIcons.Documents,
              weight: SolarIconWeight.outline,
            ),
            color: systemExt.btnSoftText,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  extension.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: systemExt.btnSoftText.withOpacity(0.7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          EduComponents.icon(
            context: context,
            iconData: const SolarIcon(
              SolarIcons.CloudDownload,
              weight: SolarIconWeight.bold,
            ),
            color: Theme.of(context).primaryColor,
            size: 22,
          ),
        ],
      ),
    );
  }

  void _openAttachmentActionSheet(
    String fileId,
    String filename,
    String extension,
    bool isImage,
    String resolvedUrl,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EduDesignTokens.radius3xl),
        ),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final systemExt = theme.extension<EduPortalThemeExtension>()!;
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
                  filename,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Format: ${extension.toUpperCase()}',
                  style: theme.textTheme.labelSmall,
                ),
                const Divider(height: 24, thickness: 1),

                ListTile(
                  leading: EduComponents.icon(
                    context: context,
                    iconData: const SolarIcon(
                      SolarIcons.ChatSquare,
                      weight: SolarIconWeight.outline,
                    ),
                    color: theme.primaryColor,
                  ),
                  title: Text(
                    isImage ? 'Preview Full Screen' : 'Open Document Source',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    if (isImage) {
                      _triggerFullImagePreview(resolvedUrl, filename);
                    } else {
                      _triggerDownloadAction(resolvedUrl, filename);
                    }
                  },
                ),
                ListTile(
                  leading: EduComponents.icon(
                    context: context,
                    iconData: const SolarIcon(
                      SolarIcons.CloudDownload,
                      weight: SolarIconWeight.outline,
                    ),
                    color: theme.primaryColor,
                  ),
                  title: const Text('Download to local storage'),
                  onTap: () {
                    Navigator.pop(context);
                    _triggerDownloadAction(resolvedUrl, filename);
                  },
                ),
                ListTile(
                  leading: EduComponents.icon(
                    context: context,
                    iconData: const SolarIcon(
                      SolarIcons.Share,
                      weight: SolarIconWeight.outline,
                    ),
                    color: theme.primaryColor,
                  ),
                  title: const Text('Share File Link'),
                  onTap: () {
                    Navigator.pop(context);
                    _triggerShareLinkAction(resolvedUrl);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _triggerFullImagePreview(String url, String filename) {
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
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  filename,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      EduDesignTokens.radiusXl,
                    ),
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _triggerDownloadAction(String url, String filename) {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Downloading $filename...',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: EduDesignTokens.slate900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              EduComponents.icon(
                context: context,
                iconData: EduIcons.success,
                color: Colors.greenAccent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Completed download of $filename',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
          ),
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
            EduComponents.icon(
              context: context,
              iconData: EduIcons.success,
              color: Colors.greenAccent,
              size: 20,
            ),
            const SizedBox(width: 12),
            const Text(
              'Direct share link copied to clipboard!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
        ),
      ),
    );
  }

  Widget _buildInputActionTrack() {
    final systemExt = Theme.of(context).extension<EduPortalThemeExtension>()!;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: systemExt.borderNeutral)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: IconButton(
              onPressed: _isUploadingFile ? null : _handleAttachmentSelection,
              icon: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(
                  SolarIcons.Paperclip,
                  weight: SolarIconWeight.outline,
                ),
                color: EduDesignTokens.slate400,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                border: Border.all(color: systemExt.borderNeutral),
              ),
              child: TextField(
                controller: _msgController,
                minLines: 1,
                maxLines: 2,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Type message...",
                  hintStyle: const TextStyle(fontSize: 13, color: EduDesignTokens.slate400),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: IconButton(
              onPressed: _editingMessage != null
                  ? _updateTextMessage
                  : _transmitTextMessage,
              style: IconButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(EduDesignTokens.radiusXl),
                ),
              ),
              icon: EduComponents.icon(
                context: context,
                iconData: const SolarIcon(
                  SolarIcons.ArrowRight,
                  weight: SolarIconWeight.bold,
                ),
                color: Colors.white,
                size: 18,
              ),
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
