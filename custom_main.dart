import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ChatStorage.loadFromDisk();
  runApp(const PiBluetoothWhatsApp());
}

class PiBluetoothWhatsApp extends StatelessWidget {
  const PiBluetoothWhatsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'π-Bluetooth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B141A), // WhatsApp Dark BG
        primaryColor: const Color(0xFF00E5FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F2C34), // WhatsApp Dark AppBar
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1F2C34),
          selectedItemColor: Color(0xFF00E5FF),
          unselectedItemColor: Color(0xFF8696A0),
        ),
      ),
      home: const MainWhatsAppLayout(),
    );
  }
}

class MainWhatsAppLayout extends StatefulWidget {
  const MainWhatsAppLayout({super.key});

  @override
  State<MainWhatsAppLayout> createState() => _MainWhatsAppLayoutState();
}

class _MainWhatsAppLayoutState extends State<MainWhatsAppLayout>
    with SingleTickerProviderStateMixin {
  final Strategy strategy = Strategy.P2P_CLUSTER;
  int _selectedTab = 0;
  String? _activeChatPeerId;

  String userName = "Moinul";
  String userAbout = "Hey there! I am using π-Bluetooth Offline.";
  int avatarIndex = 0;

  Map<String, String> discoveredDevices = {};
  Map<String, String> connectedDevices = {};
  final Map<int, String> _tempFilePaths = {};
  bool isScanning = false;

  late AnimationController _radarController;

  final List<Color> avatarColors = [
    const Color(0xFF00E5FF),
    const Color(0xFF00A884),
    const Color(0xFF7C3AED),
    const Color(0xFFF59E0B),
    const Color(0xFFEC4899),
  ];

  final List<IconData> avatarIcons = [
    Icons.bolt,
    Icons.person,
    Icons.rocket_launch,
    Icons.headphones,
    Icons.code,
  ];

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadProfile();
    _requestPermissions();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  String get _encodedProfile => "$userName|$userAbout|$avatarIndex";

  Map<String, dynamic> _decodeProfile(String raw) {
    final parts = raw.split('|');
    return {
      'name': parts.isNotEmpty ? parts[0] : 'Pi User',
      'about': parts.length > 1 ? parts[1] : 'Offline Mesh User',
      'avatar': parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0,
    };
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('username') ?? userName;
      userAbout = prefs.getString('userabout') ?? userAbout;
      avatarIndex = prefs.getInt('avatarIndex') ?? 0;
    });
  }

  Future<void> _saveProfile(
      String newName, String newAbout, int newAvatar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newName);
    await prefs.setString('userabout', newAbout);
    await prefs.setInt('avatarIndex', newAvatar);
    setState(() {
      userName = newName;
      userAbout = newAbout;
      avatarIndex = newAvatar;
    });
  }

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.bluetooth,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
        Permission.nearbyWifiDevices,
        Permission.photos,
        Permission.storage,
      ].request();
    } catch (_) {}
  }

  void _toggleRadar() async {
    if (isScanning) {
      try {
        await Nearby().stopAdvertising();
        await Nearby().stopDiscovery();
      } catch (_) {}
      setState(() {
        isScanning = false;
      });
    } else {
      setState(() => isScanning = true);
      try {
        await Nearby().startAdvertising(
          _encodedProfile,
          strategy,
          onConnectionInitiated: _onConnectionInitiated,
          onConnectionResult: (id, status) {
            if (status == Status.CONNECTED) {
              setState(() {
                connectedDevices[id] =
                    discoveredDevices[id] ?? "Peer|Connected|0";
              });
              ChatStorage.registerPeer(
                  id, discoveredDevices[id] ?? "Peer|Connected|0");
            }
          },
          onDisconnected: (id) {
            setState(() => connectedDevices.remove(id));
          },
        );

        await Nearby().startDiscovery(
          _encodedProfile,
          strategy,
          onEndpointFound: (id, rawInfo, serviceId) {
            setState(() => discoveredDevices[id] = rawInfo);
            ChatStorage.registerPeer(id, rawInfo);
          },
          onEndpointLost: (id) {
            setState(() => discoveredDevices.remove(id));
          },
        );
      } catch (e) {
        debugPrint("Radar Error: $e");
      }
    }
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES) {
          String message = utf8.decode(payload.bytes!);
          ChatStorage.addMessage(endpointId, text: message, isMe: false);
        } else if (payload.type == PayloadType.FILE && payload.uri != null) {
          _tempFilePaths[payload.id] = payload.uri!;
        }
      },
      onPayloadTransferUpdate: (endpointId, update) async {
        if (update.status == PayloadStatus.SUCCESS &&
            _tempFilePaths.containsKey(update.id)) {
          String tempUri = _tempFilePaths.remove(update.id)!;
          final dir = await getApplicationDocumentsDirectory();
          final savedPath =
              "${dir.path}/pi_img_${DateTime.now().millisecondsSinceEpoch}.jpg";
          await Nearby().copyFileAndDeleteOriginal(tempUri, savedPath);
          ChatStorage.addMessage(endpointId, imagePath: savedPath, isMe: false);
        }
      },
    );
    setState(() => discoveredDevices[id] = info.endpointName);
    ChatStorage.registerPeer(id, info.endpointName);
  }

  void _connectAndOpenChat(String id, String rawProfile, bool isWideScreen) {
    ChatStorage.registerPeer(id, rawProfile);
    if (!connectedDevices.containsKey(id)) {
      try {
        Nearby().requestConnection(
          _encodedProfile,
          id,
          onConnectionInitiated: _onConnectionInitiated,
          onConnectionResult: (id, status) {
            if (status == Status.CONNECTED) {
              setState(() => connectedDevices[id] = rawProfile);
            }
          },
          onDisconnected: (id) {
            setState(() => connectedDevices.remove(id));
          },
        );
      } catch (_) {}
    }

    if (isWideScreen) {
      setState(() {
        _activeChatPeerId = id;
        _selectedTab = 0;
      });
    } else {
      final profile = _decodeProfile(rawProfile);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatConversationView(
            endpointId: id,
            peerName: profile['name'],
            peerAbout: profile['about'],
            isOnline: connectedDevices.containsKey(id),
            avatarColor: avatarColors[profile['avatar'] % avatarColors.length],
            avatarIcon: avatarIcons[profile['avatar'] % avatarIcons.length],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWideScreen = MediaQuery.of(context).size.width >= 750;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text("π",
                  style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                      fontSize: 20)),
            ),
            const SizedBox(width: 10),
            const Text("π-Bluetooth",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.white)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isScanning ? Icons.radar : Icons.bluetooth_searching,
              color: isScanning ? const Color(0xFF00E5FF) : Colors.white70,
            ),
            tooltip: isScanning ? "Stop Radar" : "Start Radar",
            onPressed: _toggleRadar,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onPressed: () => setState(() => _selectedTab = 3),
          ),
        ],
      ),
      body: isWideScreen
          ? Row(
              children: [
                SizedBox(
                  width: 360,
                  child: Column(
                    children: [
                      Expanded(child: _buildCurrentTab(true)),
                      _buildBottomNav(),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFF222E35)),
                Expanded(
                  child: _activeChatPeerId == null
                      ? _buildDesktopEmptyState()
                      : _buildEmbeddedChat(_activeChatPeerId!),
                ),
              ],
            )
          : _buildCurrentTab(false),
      bottomNavigationBar: isWideScreen ? null : _buildBottomNav(),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              onPressed: () {
                setState(() => _selectedTab = 1);
                if (!isScanning) _toggleRadar();
              },
              child: const Icon(Icons.chat_rounded),
            )
          : null,
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedTab,
      type: BottomNavigationBarType.fixed,
      onTap: (idx) => setState(() => _selectedTab = idx),
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_rounded), label: "Chats"),
        BottomNavigationBarItem(icon: Icon(Icons.radar), label: "Radar"),
        BottomNavigationBarItem(
            icon: Icon(Icons.donut_large_rounded), label: "Status"),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded), label: "Profile"),
      ],
    );
  }

  Widget _buildCurrentTab(bool isWideScreen) {
    switch (_selectedTab) {
      case 0:
        return _buildChatsListTab(isWideScreen);
      case 1:
        return _buildRadarTab(isWideScreen);
      case 2:
        return _buildStatusTab();
      case 3:
        return _buildProfileTab();
      default:
        return _buildChatsListTab(isWideScreen);
    }
  }

  // TAB 1: WHATSAPP CHATS LIST
  Widget _buildChatsListTab(bool isWideScreen) {
    return ValueListenableBuilder<int>(
      valueListenable: ChatStorage.updateNotifier,
      builder: (context, _, __) {
        final allPeerIds = <String>{
          ...ChatStorage.savedPeers.keys,
          ...discoveredDevices.keys,
        }.toList();

        if (allPeerIds.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.forum_outlined,
                      size: 64, color: Colors.white.withOpacity(0.15)),
                  const SizedBox(height: 16),
                  const Text("No Offline Chats Yet",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    "Tap the Radar icon at the top or the message button below to find nearby π-Bluetooth users without internet.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8696A0), height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: () {
                      setState(() => _selectedTab = 1);
                      if (!isScanning) _toggleRadar();
                    },
                    icon: const Icon(Icons.radar),
                    label: const Text("Find Nearby Users",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: allPeerIds.length,
          separatorBuilder: (_, __) => const Divider(
              height: 1, indent: 76, color: Color(0xFF222E35)),
          itemBuilder: (context, index) {
            final id = allPeerIds[index];
            final rawProfile = discoveredDevices[id] ??
                ChatStorage.savedPeers[id] ??
                "Pi User|Offline|0";
            final profile = _decodeProfile(rawProfile);
            final messages = ChatStorage.getMessages(id);
            final lastMsg = messages.isNotEmpty ? messages.last : null;
            final isOnline = connectedDevices.containsKey(id) ||
                discoveredDevices.containsKey(id);

            Color pColor =
                avatarColors[profile['avatar'] % avatarColors.length];
            IconData pIcon =
                avatarIcons[profile['avatar'] % avatarIcons.length];

            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: pColor,
                    child: Icon(pIcon, color: Colors.black, size: 26),
                  ),
                  if (isOnline)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E5FF),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF0B141A), width: 2.5),
                        ),
                      ),
                    ),
                ],
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(profile['name'],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    lastMsg?.time ?? (isOnline ? "Nearby" : "Offline"),
                    style: TextStyle(
                        fontSize: 12,
                        color: isOnline
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFF8696A0)),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (lastMsg != null && lastMsg.isMe) ...[
                      const Icon(Icons.done_all,
                          size: 16, color: Color(0xFF00E5FF)),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        lastMsg != null
                            ? (lastMsg.imagePath != null
                                ? "📷 Photo"
                                : lastMsg.text ?? "")
                            : profile['about'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF8696A0), fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              onTap: () => _connectAndOpenChat(id, rawProfile, isWideScreen),
            );
          },
        );
      },
    );
  }

  // TAB 2: ANIMATED RADAR SCANNER
  Widget _buildRadarTab(bool isWideScreen) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: const Color(0xFF1F2C34),
          child: Column(
            children: [
              SizedBox(
                height: 110,
                width: 110,
                child: AnimatedBuilder(
                  animation: _radarController,
                  builder: (context, _) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isScanning)
                          Container(
                            width: 110 * _radarController.value,
                            height: 110 * _radarController.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF00E5FF)
                                    .withOpacity(1 - _radarController.value),
                                width: 2,
                              ),
                            ),
                          ),
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFF00E5FF),
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : "π",
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isScanning ? Colors.redAccent : const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: _toggleRadar,
                icon: Icon(isScanning ? Icons.stop : Icons.radar),
                label: Text(
                    isScanning ? "Stop Scanning" : "Scan Nearby Devices",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: discoveredDevices.isEmpty
              ? const Center(
                  child: Text(
                    "Turn ON Bluetooth & Location on both devices\nand start scanning to see nearby peers.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8696A0)),
                  ),
                )
              : ListView.builder(
                  itemCount: discoveredDevices.length,
                  itemBuilder: (context, idx) {
                    final id = discoveredDevices.keys.elementAt(idx);
                    final raw = discoveredDevices[id]!;
                    final p = _decodeProfile(raw);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            avatarColors[p['avatar'] % avatarColors.length],
                        child: Icon(
                            avatarIcons[p['avatar'] % avatarIcons.length],
                            color: Colors.black),
                      ),
                      title: Text(p['name'],
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(p['about'],
                          style: const TextStyle(color: Color(0xFF8696A0))),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () =>
                            _connectAndOpenChat(id, raw, isWideScreen),
                        child: const Text("Message"),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // TAB 3: WHATSAPP STATUS TAB
  Widget _buildStatusTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: avatarColors[avatarIndex % avatarColors.length],
                child: Icon(avatarIcons[avatarIndex % avatarIcons.length],
                    color: Colors.black),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: const Color(0xFF00E5FF),
                  child: const Icon(Icons.add, size: 14, color: Colors.black),
                ),
              )
            ],
          ),
          title: const Text("My Status",
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(userAbout,
              style: const TextStyle(color: Color(0xFF8696A0))),
          onTap: () => setState(() => _selectedTab = 3),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text("RECENT MESH UPDATES",
              style: TextStyle(
                  color: Color(0xFF8696A0),
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        if (discoveredDevices.isEmpty)
          const Text("Scan nearby devices to see their live status.",
              style: TextStyle(color: Color(0xFF8696A0))),
        ...discoveredDevices.values.map((raw) {
          final p = _decodeProfile(raw);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF00E5FF), width: 2),
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor:
                    avatarColors[p['avatar'] % avatarColors.length],
                child: Icon(avatarIcons[p['avatar'] % avatarIcons.length],
                    color: Colors.black),
              ),
            ),
            title: Text(p['name'],
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(p['about'],
                style: const TextStyle(color: Color(0xFF8696A0))),
          );
        }),
      ],
    );
  }

  // TAB 4: PROFILE & SETTINGS TAB
  Widget _buildProfileTab() {
    final nameCtrl = TextEditingController(text: userName);
    final aboutCtrl = TextEditingController(text: userAbout);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 46,
            backgroundColor: avatarColors[avatarIndex % avatarColors.length],
            child: Icon(avatarIcons[avatarIndex % avatarIcons.length],
                color: Colors.black, size: 44),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(avatarColors.length, (idx) {
            return GestureDetector(
              onTap: () => _saveProfile(userName, userAbout, idx),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: CircleAvatar(
                  radius: avatarIndex == idx ? 20 : 16,
                  backgroundColor: avatarColors[idx],
                  child: Icon(avatarIcons[idx], color: Colors.black, size: 18),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: "Your Name",
            prefixIcon: const Icon(Icons.person, color: Color(0xFF00E5FF)),
            filled: true,
            fillColor: const Color(0xFF1F2C34),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: aboutCtrl,
          decoration: InputDecoration(
            labelText: "About / Status",
            prefixIcon:
                const Icon(Icons.info_outline, color: Color(0xFF00E5FF)),
            filled: true,
            fillColor: const Color(0xFF1F2C34),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            if (nameCtrl.text.trim().isNotEmpty) {
              _saveProfile(
                  nameCtrl.text.trim(), aboutCtrl.text.trim(), avatarIndex);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Profile Saved!")),
              );
            }
          },
          child: const Text("Save Changes",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        )
      ],
    );
  }

  Widget _buildDesktopEmptyState() {
    return Container(
      color: const Color(0xFF222E35),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00E5FF).withOpacity(0.1),
              ),
              child: const Text("π",
                  style: TextStyle(
                      fontSize: 60,
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            const Text("π-Bluetooth for Windows & Android",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300)),
            const SizedBox(height: 10),
            const Text(
              "Send and receive messages and photos completely offline\nusing Bluetooth & Local Peer-to-Peer Mesh.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8696A0), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbeddedChat(String peerId) {
    final raw = discoveredDevices[peerId] ??
        ChatStorage.savedPeers[peerId] ??
        "Pi User|Offline|0";
    final profile = _decodeProfile(raw);
    return ChatConversationView(
      key: ValueKey(peerId),
      endpointId: peerId,
      peerName: profile['name'],
      peerAbout: profile['about'],
      isOnline: connectedDevices.containsKey(peerId),
      avatarColor: avatarColors[profile['avatar'] % avatarColors.length],
      avatarIcon: avatarIcons[profile['avatar'] % avatarIcons.length],
      embedded: true,
    );
  }
}

// LOCAL PERSISTENT STORAGE FOR CHATS
class ChatMessage {
  final String? text;
  final String? imagePath;
  final bool isMe;
  final String time;

  ChatMessage(
      {this.text, this.imagePath, required this.isMe, required this.time});

  Map<String, dynamic> toJson() => {
        'text': text,
        'imagePath': imagePath,
        'isMe': isMe,
        'time': time,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'],
        imagePath: json['imagePath'],
        isMe: json['isMe'] ?? true,
        time: json['time'] ?? '',
      );
}

class ChatStorage {
  static final Map<String, List<ChatMessage>> _chats = {};
  static final Map<String, String> savedPeers = {};
  static final ValueNotifier<int> updateNotifier = ValueNotifier(0);

  static Future<void> loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final peersStr = prefs.getString('saved_peers');
    if (peersStr != null) {
      savedPeers.addAll(Map<String, String>.from(jsonDecode(peersStr)));
    }
    final chatsStr = prefs.getString('saved_chats');
    if (chatsStr != null) {
      final decoded = Map<String, dynamic>.from(jsonDecode(chatsStr));
      decoded.forEach((key, list) {
        _chats[key] = (list as List)
            .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
    }
  }

  static Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_peers', jsonEncode(savedPeers));
    final encodedChats = _chats.map(
        (key, list) => MapEntry(key, list.map((m) => m.toJson()).toList()));
    await prefs.setString('saved_chats', jsonEncode(encodedChats));
  }

  static void registerPeer(String id, String rawProfile) {
    savedPeers[id] = rawProfile;
    _saveToDisk();
    updateNotifier.value++;
  }

  static List<ChatMessage> getMessages(String endpointId) =>
      _chats[endpointId] ?? [];

  static void addMessage(String endpointId,
      {String? text, String? imagePath, required bool isMe}) {
    _chats.putIfAbsent(endpointId, () => []);
    final now = TimeOfDay.now();
    final timeStr = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    _chats[endpointId]!.add(ChatMessage(
        text: text, imagePath: imagePath, isMe: isMe, time: timeStr));
    _saveToDisk();
    updateNotifier.value++;
  }
}

// WHATSAPP CHAT SCREEN
class ChatConversationView extends StatefulWidget {
  final String endpointId;
  final String peerName;
  final String peerAbout;
  final bool isOnline;
  final Color avatarColor;
  final IconData avatarIcon;
  final bool embedded;

  const ChatConversationView({
    super.key,
    required this.endpointId,
    required this.peerName,
    required this.peerAbout,
    required this.isOnline,
    required this.avatarColor,
    required this.avatarIcon,
    this.embedded = false,
  });

  @override
  State<ChatConversationView> createState() => _ChatConversationViewState();
}

class _ChatConversationViewState extends State<ChatConversationView> {
  final TextEditingController _msgController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  void _sendMessage() {
    String text = _msgController.text.trim();
    if (text.isEmpty) return;

    try {
      Nearby().sendBytesPayload(
          widget.endpointId, Uint8List.fromList(utf8.encode(text)));
    } catch (_) {}

    ChatStorage.addMessage(widget.endpointId, text: text, isMe: true);
    _msgController.clear();
  }

  Future<void> _sendGalleryImage() async {
    final XFile? file =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (file == null) return;

    try {
      await Nearby().sendFilePayload(widget.endpointId, file.path);
    } catch (_) {}

    ChatStorage.addMessage(widget.endpointId,
        imagePath: file.path, isMe: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: widget.avatarColor,
              child: Icon(widget.avatarIcon, color: Colors.black, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peerName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    widget.isOnline ? "online • π-Mesh" : widget.peerAbout,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: widget.isOnline
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFF8696A0)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: ChatStorage.updateNotifier,
              builder: (context, _, __) {
                final messages = ChatStorage.getMessages(widget.endpointId);
                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return Align(
                      alignment: msg.isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.72),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: msg.isMe
                              ? const Color(0xFF005C4B) // WhatsApp Sent Bubble
                              : const Color(0xFF1F2C34), // WhatsApp Recv Bubble
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: Radius.circular(msg.isMe ? 12 : 0),
                            bottomRight: Radius.circular(msg.isMe ? 0 : 12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (msg.imagePath != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(msg.imagePath!),
                                    width: 220,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            if (msg.text != null)
                              Text(msg.text!,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 15)),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(msg.time,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 10)),
                                if (msg.isMe) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.done_all,
                                      size: 14, color: Color(0xFF00E5FF)),
                                ]
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // WhatsApp Bottom Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2C34),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        const Icon(Icons.emoji_emotions_outlined,
                            color: Color(0xFF8696A0)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _msgController,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: const InputDecoration(
                              hintText: "Message",
                              hintStyle: TextStyle(color: Color(0xFF8696A0)),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.photo_camera_rounded,
                              color: Color(0xFF8696A0)),
                          onPressed: _sendGalleryImage,
                          tooltip: "Send Photo",
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF00E5FF),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.black),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
