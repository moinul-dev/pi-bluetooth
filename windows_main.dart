import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WinChatStorage.loadFromDisk();
  runApp(const PiBluetoothWindowsApp());
}

class PiBluetoothWindowsApp extends StatelessWidget {
  const PiBluetoothWindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'π-Bluetooth Desktop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B141A),
        primaryColor: const Color(0xFF00E5FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F2C34),
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1F2C34),
          selectedItemColor: Color(0xFF00E5FF),
          unselectedItemColor: Color(0xFF8696A0),
        ),
      ),
      home: const DesktopWhatsAppLayout(),
    );
  }
}

class DesktopWhatsAppLayout extends StatefulWidget {
  const DesktopWhatsAppLayout({super.key});

  @override
  State<DesktopWhatsAppLayout> createState() => _DesktopWhatsAppLayoutState();
}

class _DesktopWhatsAppLayoutState extends State<DesktopWhatsAppLayout>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;
  String? _activePeerId;

  String userName = "Moinul (PC)";
  String userAbout = "π-Bluetooth Windows Desktop";
  int avatarIndex = 0;

  List<ScanResult> scanResults = [];
  final Map<String, BluetoothDevice> _connectedDevices = {};
  bool isScanning = false;
  StreamSubscription? _scanSubscription;

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
    Icons.laptop_windows,
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
  }

  @override
  void dispose() {
    _radarController.dispose();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('win_username') ?? userName;
      userAbout = prefs.getString('win_userabout') ?? userAbout;
      avatarIndex = prefs.getInt('win_avatarIndex') ?? 0;
    });
  }

  Future<void> _saveProfile(
      String newName, String newAbout, int newAvatar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('win_username', newName);
    await prefs.setString('win_userabout', newAbout);
    await prefs.setInt('win_avatarIndex', newAvatar);
    setState(() {
      userName = newName;
      userAbout = newAbout;
      avatarIndex = newAvatar;
    });
  }

  void _toggleRadar() async {
    if (isScanning) {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      setState(() => isScanning = false);
    } else {
      setState(() {
        scanResults.clear();
        isScanning = true;
      });

      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
        _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
          setState(() {
            scanResults = results;
          });
          for (var r in results) {
            final id = r.device.remoteId.toString();
            final name = r.device.platformName.isNotEmpty
                ? r.device.platformName
                : "Bluetooth Peer (${id.substring(0, 5)})";
            WinChatStorage.registerPeer(id, "$name|Signal: ${r.rssi} dBm|0");
          }
        });
      } catch (e) {
        debugPrint("Windows Scan Error: $e");
      }

      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && isScanning) {
          setState(() => isScanning = false);
        }
      });
    }
  }

  void _openChatWithDevice(BluetoothDevice? device, String id, String name,
      String about, bool isWide) async {
    WinChatStorage.registerPeer(id, "$name|$about|0");

    if (device != null && !_connectedDevices.containsKey(id)) {
      try {
        await device.connect();
        setState(() => _connectedDevices[id] = device);
      } catch (e) {
        debugPrint("Connect error: $e");
      }
    }

    if (isWide) {
      setState(() {
        _activePeerId = id;
        _selectedTab = 0;
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopChatConversation(
            peerId: id,
            peerName: name,
            peerAbout: about,
            isOnline: _connectedDevices.containsKey(id),
            device: device,
          ),
        ),
      );
    }
  }

  Map<String, String> _parsePeer(String raw) {
    final parts = raw.split('|');
    return {
      'name': parts.isNotEmpty ? parts[0] : 'Unknown Peer',
      'about': parts.length > 1 ? parts[1] : 'Offline Bluetooth Device',
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width >= 750;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text("π",
                  style: TextStyle(
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.bold,
                      fontSize: 20)),
            ),
            const SizedBox(width: 10),
            const Text("π-Bluetooth Desktop",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isScanning ? Icons.radar : Icons.bluetooth_searching,
              color: isScanning ? const Color(0xFF00E5FF) : Colors.white70,
            ),
            tooltip: isScanning ? "Stop Radar" : "Scan Devices",
            onPressed: _toggleRadar,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: "Profile Settings",
            onPressed: () => setState(() => _selectedTab = 3),
          ),
        ],
      ),
      body: isWide
          ? Row(
              children: [
                SizedBox(
                  width: 360,
                  child: Column(
                    children: [
                      Expanded(child: _buildTabContent(true)),
                      _buildNavBar(),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFF222E35)),
                Expanded(
                  child: _activePeerId == null
                      ? _buildEmptyDesktopView()
                      : _buildRightChatPane(_activePeerId!),
                ),
              ],
            )
          : _buildTabContent(false),
      bottomNavigationBar: isWide ? null : _buildNavBar(),
    );
  }

  Widget _buildNavBar() {
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

  Widget _buildTabContent(bool isWide) {
    switch (_selectedTab) {
      case 0:
        return _buildChatsTab(isWide);
      case 1:
        return _buildRadarTab(isWide);
      case 2:
        return _buildStatusTab();
      case 3:
        return _buildProfileTab();
      default:
        return _buildChatsTab(isWide);
    }
  }

  // TAB 1: CHATS LIST
  Widget _buildChatsTab(bool isWide) {
    return ValueListenableBuilder<int>(
      valueListenable: WinChatStorage.updateNotifier,
      builder: (context, _, __) {
        final peerIds = WinChatStorage.savedPeers.keys.toList();

        if (peerIds.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.forum_outlined,
                      size: 60, color: Colors.white.withOpacity(0.15)),
                  const SizedBox(height: 16),
                  const Text("No Desktop Chats Yet",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    "Turn ON Windows Bluetooth and click Radar to scan nearby devices.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8696A0)),
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
                    label: const Text("Scan Nearby Devices",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: peerIds.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 74, color: Color(0xFF222E35)),
          itemBuilder: (context, idx) {
            final id = peerIds[idx];
            final info = _parsePeer(WinChatStorage.savedPeers[id]!);
            final messages = WinChatStorage.getMessages(id);
            final lastMsg = messages.isNotEmpty ? messages.last : null;
            final isConnected = _connectedDevices.containsKey(id);
            final isSelected = _activePeerId == id;

            return Container(
              color: isSelected ? const Color(0xFF2A3942) : Colors.transparent,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: avatarColors[idx % avatarColors.length],
                  child: const Icon(Icons.bluetooth, color: Colors.black),
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(info['name']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    Text(
                      lastMsg?.time ?? (isConnected ? "Connected" : "Saved"),
                      style: TextStyle(
                          fontSize: 11,
                          color: isConnected
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFF8696A0)),
                    ),
                  ],
                ),
                subtitle: Row(
                  children: [
                    if (lastMsg != null && lastMsg.isMe) ...[
                      const Icon(Icons.done_all,
                          size: 15, color: Color(0xFF00E5FF)),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        lastMsg != null
                            ? (lastMsg.imagePath != null
                                ? "📷 Photo"
                                : lastMsg.text ?? "")
                            : info['about']!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF8696A0), fontSize: 13),
                      ),
                    ),
                  ],
                ),
                onTap: () => _openChatWithDevice(
                    _connectedDevices[id], id, info['name']!, info['about']!, isWide),
              ),
            );
          },
        );
      },
    );
  }

  // TAB 2: ANIMATED RADAR TAB
  Widget _buildRadarTab(bool isWide) {
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
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: Color(0xFF00E5FF),
                          child: Text("π",
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black)),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
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
                    isScanning ? "Stop Radar" : "Scan Windows Bluetooth",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: scanResults.isEmpty
              ? const Center(
                  child: Text(
                    "Make sure Bluetooth is ON in Windows Settings.\nClick 'Scan Windows Bluetooth' to find nearby devices.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF8696A0)),
                  ),
                )
              : ListView.builder(
                  itemCount: scanResults.length,
                  itemBuilder: (context, idx) {
                    final r = scanResults[idx];
                    final id = r.device.remoteId.toString();
                    final name = r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : "Device (${id.substring(0, 6)})";
                    final about = "RSSI: ${r.rssi} dBm";

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            avatarColors[idx % avatarColors.length],
                        child: const Icon(Icons.devices, color: Colors.black),
                      ),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(about,
                          style: const TextStyle(color: Color(0xFF8696A0))),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () =>
                            _openChatWithDevice(r.device, id, name, about, isWide),
                        child: const Text("Chat"),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // TAB 3: STATUS TAB
  Widget _buildStatusTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 25,
            backgroundColor: avatarColors[avatarIndex % avatarColors.length],
            child: Icon(avatarIcons[avatarIndex % avatarIcons.length],
                color: Colors.black),
          ),
          title: const Text("My Status",
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(userAbout,
              style: const TextStyle(color: Color(0xFF8696A0))),
          onTap: () => setState(() => _selectedTab = 3),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text("NEARBY DISCOVERED NODES",
              style: TextStyle(
                  color: Color(0xFF8696A0),
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        if (scanResults.isEmpty)
          const Text("No active nearby nodes scanned yet.",
              style: TextStyle(color: Color(0xFF8696A0))),
        ...scanResults.map((r) {
          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.device.remoteId.toString();
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF00E5FF), width: 2),
              ),
              child: const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFF1F2C34),
                child: Icon(Icons.bluetooth, color: Color(0xFF00E5FF)),
              ),
            ),
            title: Text(name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Signal Strength: ${r.rssi} dBm",
                style: const TextStyle(color: Color(0xFF8696A0))),
          );
        }),
      ],
    );
  }

  // TAB 4: PROFILE SETTINGS
  Widget _buildProfileTab() {
    final nameCtrl = TextEditingController(text: userName);
    final aboutCtrl = TextEditingController(text: userAbout);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 44,
            backgroundColor: avatarColors[avatarIndex % avatarColors.length],
            child: Icon(avatarIcons[avatarIndex % avatarIcons.length],
                color: Colors.black, size: 42),
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
            labelText: "Desktop Display Name",
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
                const SnackBar(content: Text("Desktop Profile Saved!")),
              );
            }
          },
          child: const Text("Save Profile",
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildEmptyDesktopView() {
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
            const Text("π-Bluetooth for Windows",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300)),
            const SizedBox(height: 10),
            const Text(
              "Select a nearby Bluetooth peer from the left panel to start chatting\nand sharing images completely offline.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8696A0), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightChatPane(String peerId) {
    final raw = WinChatStorage.savedPeers[peerId] ?? "Peer|Offline|0";
    final info = _parsePeer(raw);
    return DesktopChatConversation(
      key: ValueKey(peerId),
      peerId: peerId,
      peerName: info['name']!,
      peerAbout: info['about']!,
      isOnline: _connectedDevices.containsKey(peerId),
      device: _connectedDevices[peerId],
      embedded: true,
    );
  }
}

// LOCAL DISK STORAGE
class WinChatMessage {
  final String? text;
  final String? imagePath;
  final bool isMe;
  final String time;

  WinChatMessage(
      {this.text, this.imagePath, required this.isMe, required this.time});

  Map<String, dynamic> toJson() => {
        'text': text,
        'imagePath': imagePath,
        'isMe': isMe,
        'time': time,
      };

  factory WinChatMessage.fromJson(Map<String, dynamic> json) => WinChatMessage(
        text: json['text'],
        imagePath: json['imagePath'],
        isMe: json['isMe'] ?? true,
        time: json['time'] ?? '',
      );
}

class WinChatStorage {
  static final Map<String, List<WinChatMessage>> _chats = {};
  static final Map<String, String> savedPeers = {};
  static final ValueNotifier<int> updateNotifier = ValueNotifier(0);

  static Future<void> loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final peersStr = prefs.getString('win_saved_peers');
    if (peersStr != null) {
      savedPeers.addAll(Map<String, String>.from(jsonDecode(peersStr)));
    }
    final chatsStr = prefs.getString('win_saved_chats');
    if (chatsStr != null) {
      final decoded = Map<String, dynamic>.from(jsonDecode(chatsStr));
      decoded.forEach((key, list) {
        _chats[key] = (list as List)
            .map((e) => WinChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
    }
  }

  static Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('win_saved_peers', jsonEncode(savedPeers));
    final encoded = _chats.map(
        (key, list) => MapEntry(key, list.map((m) => m.toJson()).toList()));
    await prefs.setString('win_saved_chats', jsonEncode(encoded));
  }

  static void registerPeer(String id, String rawInfo) {
    savedPeers[id] = rawInfo;
    _saveToDisk();
    updateNotifier.value++;
  }

  static List<WinChatMessage> getMessages(String peerId) =>
      _chats[peerId] ?? [];

  static void addMessage(String peerId,
      {String? text, String? imagePath, required bool isMe}) {
    _chats.putIfAbsent(peerId, () => []);
    final now = TimeOfDay.now();
    final timeStr = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    _chats[peerId]!.add(WinChatMessage(
        text: text, imagePath: imagePath, isMe: isMe, time: timeStr));
    _saveToDisk();
    updateNotifier.value++;
  }
}

// WHATSAPP DESKTOP CHAT PANE
class DesktopChatConversation extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String peerAbout;
  final bool isOnline;
  final BluetoothDevice? device;
  final bool embedded;

  const DesktopChatConversation({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerAbout,
    required this.isOnline,
    this.device,
    this.embedded = false,
  });

  @override
  State<DesktopChatConversation> createState() =>
      _DesktopChatConversationState();
}

class _DesktopChatConversationState extends State<DesktopChatConversation> {
  final TextEditingController _msgController = TextEditingController();

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    if (widget.device != null) {
      try {
        final services = await widget.device!.discoverServices();
        for (var s in services) {
          for (var c in s.characteristics) {
            if (c.properties.write || c.properties.writeWithoutResponse) {
              await c.write(utf8.encode(text),
                  withoutResponse: c.properties.writeWithoutResponse);
              break;
            }
          }
        }
      } catch (_) {}
    }

    WinChatStorage.addMessage(widget.peerId, text: text, isMe: true);
    _msgController.clear();
  }

  Future<void> _pickPCImage() async {
    FilePickerResult? result =
        await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      WinChatStorage.addMessage(widget.peerId,
          imagePath: result.files.single.path!, isMe: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFF00E5FF),
              child: Icon(Icons.bluetooth, color: Colors.black, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peerName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    widget.isOnline ? "online • Bluetooth BLE" : widget.peerAbout,
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
              valueListenable: WinChatStorage.updateNotifier,
              builder: (context, _, __) {
                final messages = WinChatStorage.getMessages(widget.peerId);
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, idx) {
                    final msg = messages[idx];
                    return Align(
                      alignment: msg.isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: msg.isMe
                              ? const Color(0xFF005C4B)
                              : const Color(0xFF1F2C34),
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
                                    width: 240,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
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
                        const SizedBox(width: 14),
                        const Icon(Icons.emoji_emotions_outlined,
                            color: Color(0xFF8696A0)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _msgController,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: const InputDecoration(
                              hintText: "Type a message",
                              hintStyle: TextStyle(color: Color(0xFF8696A0)),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.image_rounded,
                              color: Color(0xFF8696A0)),
                          onPressed: _pickPCImage,
                          tooltip: "Attach Image from PC",
                        ),
                      ],
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
