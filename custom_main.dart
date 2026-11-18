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
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        primaryColor: const Color(0xFF00E5FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111827),
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

class _HomeScreenState extends State<HomeScreen> {
  final Strategy strategy = Strategy.P2P_CLUSTER;
  String userName = "Pi_User_${DateTime.now().millisecond}";
  Map<String, String> discoveredDevices = {}; // endpointId -> userName
  Map<String, String> connectedDevices = {}; // endpointId -> userName
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _requestPermissions();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString('username') ?? userName;
    });
  }

  Future<void> _saveUserName(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newName);
    setState(() {
      userName = newName;
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
      // 1. Make this device visible to others
      await Nearby().startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            setState(() {
              connectedDevices[id] = discoveredDevices[id] ?? "Unknown Peer";
            });
          }
        },
        onDisconnected: (id) {
          setState(() {
            connectedDevices.remove(id);
          });
        },
      );

      // 2. Search for nearby devices
      await Nearby().startDiscovery(
        userName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          setState(() {
            discoveredDevices[id] = name;
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
    // Auto-accept connections for seamless mesh experience
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

  void _connectToDevice(String id, String name) {
    Nearby().requestConnection(
      userName,
      id,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          setState(() {
            connectedDevices[id] = name;
          });
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(endpointId: id, peerName: name),
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

  void _editNameDialog() {
    TextEditingController controller = TextEditingController(text: userName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text("Set Your Display Name"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Enter your name"),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _saveUserName(controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text("Save", style: TextStyle(color: Color(0xFF00E5FF))),
          )
        ],
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
            SizedBox(width: 8),
            Icon(Icons.bluetooth_connected, color: Color(0xFF00E5FF), size: 20),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editNameDialog,
            tooltip: "Edit Name",
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF111827),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Your ID: $userName",
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(
                      isScanning ? "Radar Active: Searching..." : "Radar Offline",
                      style: TextStyle(
                        color: isScanning ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isScanning ? Colors.redAccent : const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: isScanning ? _stopAll : _startAdvertisingAndDiscovery,
                  icon: Icon(isScanning ? Icons.stop : Icons.radar),
                  label: Text(isScanning ? "Stop" : "Scan"),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("NEARBY DEVICES",
                  style: TextStyle(
                      color: Colors.white54,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            child: discoveredDevices.isEmpty
                ? const Center(
                    child: Text(
                      "No nearby π-Bluetooth users found.\nTap 'Scan' on both phones.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    itemCount: discoveredDevices.length,
                    itemBuilder: (context, index) {
                      String id = discoveredDevices.keys.elementAt(index);
                      String name = discoveredDevices[id]!;
                      bool isConnected = connectedDevices.containsKey(id);

                      return Card(
                        color: const Color(0xFF1F2937),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF00E5FF),
                            child: Text("π",
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20)),
                          ),
                          title: Text(name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            isConnected ? "Connected • Tap to Chat" : "Tap to Connect",
                            style: TextStyle(
                                color: isConnected
                                    ? Colors.greenAccent
                                    : Colors.white60),
                          ),
                          trailing: const Icon(Icons.chat_bubble_outline,
                              color: Color(0xFF00E5FF)),
                          onTap: () {
                            if (isConnected) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ChatScreen(endpointId: id, peerName: name),
                                ),
                              );
                            } else {
                              _connectToDevice(id, name);
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

// Simple In-Memory & Local Message Manager
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

  const ChatScreen(
      {super.key, required this.endpointId, required this.peerName});

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerName, style: const TextStyle(fontSize: 18)),
            const Text("Offline Bluetooth Mesh",
                style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
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
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return Align(
                      alignment: msg.isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: msg.isMe
                              ? const Color(0xFF00838F)
                              : const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(msg.text,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(msg.time,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10)),
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
            color: const Color(0xFF111827),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: "Type offline message...",
                      filled: true,
                      fillColor: const Color(0xFF1F2937),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF00E5FF),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black),
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
