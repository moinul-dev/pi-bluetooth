import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const PiBluetoothApp());
}

class PiBluetoothApp extends StatelessWidget {
  const PiBluetoothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'π-Bluetooth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B14),
        primaryColor: const Color(0xFF00E5FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final Strategy strategy = Strategy.P2P_CLUSTER;
  String userName = "Pi_User_${DateTime.now().millisecond}";
  String userStatus = "Available on π-Mesh";
  int avatarIndex = 0;

  // endpointId -> "name|status|avatarIndex"
  Map<String, String> discoveredDevices = {};
  Map<String, String> connectedDevices = {};
  bool isScanning = false;

  late AnimationController _radarController;

  final List<Color> avatarColors = [
    const Color(0xFF00E5FF),
    const Color(0xFFFF2A85),
    const Color(0xFF7C3AED),
    const Color(0xFF10B981),
    const Color(0xFFF59E0B),
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

  String get _encodedProfile => "$userName|$userStatus|$avatarIndex";

  Map<String, dynamic> _decodeProfile(String raw) {
    final parts = raw.split('|');
    return {
      'name': parts.isNotEmpty ? parts[0] : 'Unknown Peer',
      'status': parts.length > 1 ? parts[1] : 'Offline Mesh User',
      'avatar': parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0,
    };
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('username') ?? userName;
      userStatus = prefs.getString('userstatus') ?? userStatus;
      avatarIndex = prefs.getInt('avatarIndex') ?? 0;
    });
  }

  Future<void> _saveProfile(
      String newName, String newStatus, int newAvatar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newName);
    await prefs.setString('userstatus', newStatus);
    await prefs.setInt('avatarIndex', newAvatar);
    setState(() {
      userName = newName;
      userStatus = newStatus;
      avatarIndex = newAvatar;
    });
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();
  }

  void _startAdvertisingAndDiscovery() async {
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
                  discoveredDevices[id] ?? "Unknown Peer|Connected|0";
            });
          }
        },
        onDisconnected: (id) {
          setState(() {
            connectedDevices.remove(id);
          });
        },
      );

      await Nearby().startDiscovery(
        _encodedProfile,
        strategy,
        onEndpointFound: (id, rawInfo, serviceId) {
          setState(() {
            discoveredDevices[id] = rawInfo;
          });
        },
        onEndpointLost: (id) {
          setState(() {
            discoveredDevices.remove(id);
          });
        },
      );
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  void _stopAll() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    setState(() {
      isScanning = false;
      discoveredDevices.clear();
    });
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES) {
          String message = utf8.decode(payload.bytes!);
          ChatStorage.addMessage(endpointId, message, false);
        }
      },
    );
    setState(() {
      discoveredDevices[id] = info.endpointName;
    });
  }

  void _connectToDevice(String id, String rawProfile) {
    final profile = _decodeProfile(rawProfile);
    Nearby().requestConnection(
      _encodedProfile,
      id,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          setState(() {
            connectedDevices[id] = rawProfile;
          });
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                endpointId: id,
                peerName: profile['name'],
                peerStatus: profile['status'],
                avatarColor: avatarColors[profile['avatar'] % avatarColors.length],
                avatarIcon: avatarIcons[profile['avatar'] % avatarIcons.length],
              ),
            ),
          );
        }
      },
      onDisconnected: (id) {
        setState(() {
          connectedDevices.remove(id);
        });
      },
    );
  }

  void _editProfileDialog() {
    TextEditingController nameCtrl = TextEditingController(text: userName);
    TextEditingController statusCtrl = TextEditingController(text: userStatus);
    int selectedAvatar = avatarIndex;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text("Edit π-Profile",
              style: TextStyle(color: Color(0xFF00E5FF))),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(avatarColors.length, (idx) {
                    bool isSelected = selectedAvatar == idx;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedAvatar = idx),
                      child: CircleAvatar(
                        radius: isSelected ? 24 : 20,
                        backgroundColor: avatarColors[idx],
                        child: Icon(avatarIcons[idx],
                            color: Colors.black, size: isSelected ? 24 : 20),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: "Display Name",
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: statusCtrl,
                  decoration: InputDecoration(
                    labelText: "Status / Bio",
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  _saveProfile(
                      nameCtrl.text.trim(),
                      statusCtrl.text.trim().isEmpty
                          ? "Available on π-Mesh"
                          : statusCtrl.text.trim(),
                      selectedAvatar);
                }
                Navigator.pop(context);
              },
              child: const Text("Save Profile"),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRadarPulse() {
    return SizedBox(
      height: 120,
      width: 120,
      child: AnimatedBuilder(
        animation: _radarController,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (isScanning) ...[
                Container(
                  width: 120 * _radarController.value,
                  height: 120 * _radarController.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00E5FF)
                          .withOpacity(1 - _radarController.value),
                      width: 2.5,
                    ),
                  ),
                ),
                Container(
                  width: 80 * _radarController.value,
                  height: 80 * _radarController.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00E5FF)
                        .withOpacity(0.2 * (1 - _radarController.value)),
                  ),
                ),
              ],
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF3B82F6)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.4),
                      blurRadius: 15,
                    )
                  ],
                ),
                child: const Center(
                  child: Text(
                    "π",
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text("π-Bluetooth",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: Color(0xFF00E5FF))),
            SizedBox(width: 6),
            Icon(Icons.bluetooth_connected, color: Color(0xFF00E5FF), size: 20),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: _editProfileDialog,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: avatarColors[avatarIndex % avatarColors.length],
                child: Icon(avatarIcons[avatarIndex % avatarIcons.length],
                    color: Colors.black, size: 20),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Top Radar & Profile Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                _buildRadarPulse(),
                const SizedBox(height: 10),
                Text(userName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text(userStatus,
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 13)),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isScanning ? Colors.redAccent : const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: isScanning ? _stopAll : _startAdvertisingAndDiscovery,
                  icon: Icon(isScanning ? Icons.stop_circle : Icons.radar),
                  label: Text(
                    isScanning ? "Stop Radar" : "Scan Nearby Peers",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("NEARBY MESH USERS",
                    style: TextStyle(
                        color: Colors.white54,
                        letterSpacing: 1.2,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                Text("Offline P2P",
                    style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12)),
              ],
            ),
          ),

          Expanded(
            child: discoveredDevices.isEmpty
                ? const Center(
                    child: Text(
                      "No peers detected yet.\nTurn on Bluetooth & tap 'Scan Nearby Peers' on both devices.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, height: 1.5),
                    ),
                  )
                : ListView.builder(
                    itemCount: discoveredDevices.length,
                    itemBuilder: (context, index) {
                      String id = discoveredDevices.keys.elementAt(index);
                      String rawProfile = discoveredDevices[id]!;
                      final profile = _decodeProfile(rawProfile);
                      bool isConnected = connectedDevices.containsKey(id);
                      Color peerColor = avatarColors[
                          profile['avatar'] % avatarColors.length];
                      IconData peerIcon =
                          avatarIcons[profile['avatar'] % avatarIcons.length];

                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isConnected
                                ? Colors.greenAccent.withOpacity(0.5)
                                : Colors.transparent,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: peerColor,
                                child: Icon(peerIcon, color: Colors.black),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: isConnected
                                        ? Colors.greenAccent
                                        : Colors.amber,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0xFF1E293B),
                                        width: 2),
                                  ),
                                ),
                              )
                            ],
                          ),
                          title: Text(profile['name'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Text(
                            profile['status'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 13),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isConnected
                                  ? Colors.greenAccent.withOpacity(0.15)
                                  : const Color(0xFF00E5FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isConnected ? "Chat" : "Connect",
                              style: TextStyle(
                                  color: isConnected
                                      ? Colors.greenAccent
                                      : const Color(0xFF00E5FF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                          onTap: () {
                            if (isConnected) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    endpointId: id,
                                    peerName: profile['name'],
                                    peerStatus: profile['status'],
                                    avatarColor: peerColor,
                                    avatarIcon: peerIcon,
                                  ),
                                ),
                              );
                            } else {
                              _connectToDevice(id, rawProfile);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isMe;
  final String time;
  ChatMessage({required this.text, required this.isMe, required this.time});
}

class ChatStorage {
  static final Map<String, List<ChatMessage>> _chats = {};
  static final ValueNotifier<int> updateNotifier = ValueNotifier(0);

  static List<ChatMessage> getMessages(String endpointId) {
    return _chats[endpointId] ?? [];
  }

  static void addMessage(String endpointId, String text, bool isMe) {
    _chats.putIfAbsent(endpointId, () => []);
    final now = TimeOfDay.now();
    final timeStr = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    _chats[endpointId]!.add(ChatMessage(text: text, isMe: isMe, time: timeStr));
    updateNotifier.value++;
  }
}

class ChatScreen extends StatefulWidget {
  final String endpointId;
  final String peerName;
  final String peerStatus;
  final Color avatarColor;
  final IconData avatarIcon;

  const ChatScreen({
    super.key,
    required this.endpointId,
    required this.peerName,
    required this.peerStatus,
    required this.avatarColor,
    required this.avatarIcon,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();

  void _sendMessage() {
    String text = _msgController.text.trim();
    if (text.isEmpty) return;

    Nearby().sendBytesPayload(
        widget.endpointId, Uint8List.fromList(utf8.encode(text)));
    ChatStorage.addMessage(widget.endpointId, text, true);
    _msgController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: widget.avatarColor,
              child: Icon(widget.avatarIcon, color: Colors.black, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peerName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(widget.peerStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.greenAccent)),
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
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: msg.isMe
                              ? const LinearGradient(
                                  colors: [Color(0xFF00838F), Color(0xFF0284C7)],
                                )
                              : null,
                          color: msg.isMe ? null : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(msg.isMe ? 16 : 2),
                            bottomRight: Radius.circular(msg.isMe ? 2 : 16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(msg.text,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15)),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(msg.time,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 10)),
                                if (msg.isMe) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.done_all,
                                      size: 13, color: Color(0xFF00E5FF)),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: "Message via π-Mesh...",
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 23,
                  backgroundColor: const Color(0xFF00E5FF),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.black),
                    onPressed: _sendMessage,
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
