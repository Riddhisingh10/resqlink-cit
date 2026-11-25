import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'storage_service.dart';
import '../models/sos.dart';

enum MeshConnectionStatus { disconnected, advertising, discovering, connected }

class MeshStatusInfo {
  final MeshConnectionStatus status;
  final int connectedCount;
  final int discoveredCount;

  MeshStatusInfo({
    required this.status,
    required this.connectedCount,
    required this.discoveredCount,
  });
}

class WifiService {
  static final WifiService instance = WifiService._internal();
  WifiService._internal();

  static const String serviceId = "com.resqlink.mesh";
  static const Strategy strategy = Strategy.P2P_CLUSTER;

  // Active connections: endpointId -> PeerDetails
  final Map<String, PeerDetails> connectedPeers = {};

  // Discovered endpoints: endpointId -> name
  final Map<String, String> discoveredEndpoints = {};

  // Status notifier for UI
  final ValueNotifier<MeshStatusInfo> connectionStatus =
      ValueNotifier<MeshStatusInfo>(MeshStatusInfo(
    status: MeshConnectionStatus.disconnected,
    connectedCount: 0,
    discoveredCount: 0,
  ));

  // Callback when local storage is updated by sync
  VoidCallback? onSyncCompleted;

  bool _isAdvertising = false;
  bool _isDiscovering = false;

  bool get isAdvertising => _isAdvertising;
  bool get isDiscovering => _isDiscovering;

  // Start both advertising and discovery for ad-hoc mesh behavior
  Future<bool> startMesh() async {
    if (!Platform.isAndroid) {
      debugPrint('Nearby Connections is Android-only. Mesh connection is skipped on this platform.');
      return false;
    }
    await stopMesh();

    bool advStarted = await _startAdvertising();
    bool discStarted = await _startDiscovery();
    _updateStatus();

    return advStarted || discStarted;
  }

  Future<void> stopMesh() async {
    if (!Platform.isAndroid) return;
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();
    _isAdvertising = false;
    _isDiscovering = false;
    connectedPeers.clear();
    discoveredEndpoints.clear();
    _updateStatus();
  }

  void _updateStatus() {
    MeshConnectionStatus status;
    if (connectedPeers.isNotEmpty) {
      status = MeshConnectionStatus.connected;
    } else if (_isAdvertising && _isDiscovering) {
      status = MeshConnectionStatus.connected;
    } else if (_isAdvertising) {
      status = MeshConnectionStatus.advertising;
    } else if (_isDiscovering) {
      status = MeshConnectionStatus.discovering;
    } else {
      status = MeshConnectionStatus.disconnected;
    }

    connectionStatus.value = MeshStatusInfo(
      status: status,
      connectedCount: connectedPeers.length,
      discoveredCount: discoveredEndpoints.length,
    );
  }

  // Advertising
  Future<bool> _startAdvertising() async {
    try {
      final myName =
          "${StorageService.getDeviceName()} (${StorageService.getRole()})";
      bool running = await Nearby().startAdvertising(
        myName,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: (id, status) => _onConnectionResult(id, status),
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
      );
      _isAdvertising = running;
      print('Advertising status: $running');
      return running;
    } catch (e) {
      print('Advertising failed to start: $e');
      _isAdvertising = false;
      return false;
    }
  }

  // Discovery
  Future<bool> _startDiscovery() async {
    try {
      bool running = await Nearby().startDiscovery(
        StorageService.getDeviceName(),
        strategy,
        onEndpointFound: (id, name, serviceId) {
          print('Endpoint found: $id ($name)');
          discoveredEndpoints[id] = name;
          _updateStatus(); // Notify UI of new discovered node in range
          // Auto-connect to build the mesh
          _requestConnection(id, name);
        },
        onEndpointLost: (id) {
          print('Endpoint lost: $id');
          discoveredEndpoints.remove(id);
          _updateStatus(); // Notify UI that node left range
        },
        serviceId: serviceId,
      );
      _isDiscovering = running;
      print('Discovery status: $running');
      return running;
    } catch (e) {
      print('Discovery failed to start: $e');
      _isDiscovering = false;
      return false;
    }
  }

  // Request Connection
  Future<void> _requestConnection(
      String endpointId, String endpointName) async {
    try {
      final myName =
          "${StorageService.getDeviceName()} (${StorageService.getRole()})";
      await Nearby().requestConnection(
        myName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: (id, status) => _onConnectionResult(id, status),
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      print('Connection request to $endpointName failed: $e');
    }
  }

  // Connection flow callbacks
  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    print('Connection initiated with $endpointId (${info.endpointName})');
    // Automatically accept incoming connection to keep the experience seamless
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (id, payload) =>
          _onPayloadReceived(endpointId, payload),
      onPayloadTransferUpdate: (id, payloadTransferUpdate) {},
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      print('Connected successfully to $endpointId');
      final name = discoveredEndpoints[endpointId] ?? 'Peer';
      connectedPeers[endpointId] = PeerDetails(id: endpointId, name: name);
      _updateStatus();

      // Perform handshake and sync instantly
      syncAllData();
    } else {
      print('Connection result failed: $status');
      connectedPeers.remove(endpointId);
      _updateStatus();
    }
  }

  void _onDisconnected(String endpointId) {
    print('Disconnected from $endpointId');
    connectedPeers.remove(endpointId);
    _updateStatus();
  }

  // Data transmission
  void syncAllData() {
    if (!Platform.isAndroid) return;
    if (connectedPeers.isEmpty) return;

    // Build the sync payload
    final localSOSList = StorageService.getAllSOS();
    final dataMap = {
      'type': 'SYNC',
      'role': StorageService.getRole(),
      'deviceName': StorageService.getDeviceName(),
      'sosList': localSOSList.map((sos) => sos.toMap()).toList(),
    };

    final jsonString = json.encode(dataMap);
    final bytes = Uint8List.fromList(utf8.encode(jsonString));

    for (var endpointId in connectedPeers.keys) {
      Nearby().sendBytesPayload(endpointId, bytes);
      print('Synced data to peer: $endpointId');
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    try {
      final jsonString = utf8.decode(payload.bytes!);
      final dataMap = json.decode(jsonString) as Map<String, dynamic>;

      if (dataMap['type'] == 'SYNC') {
        final peerRole = dataMap['role'] ?? 'Unknown';
        final peerName = dataMap['deviceName'] ?? 'Unknown';
        final sosListMaps = dataMap['sosList'] as List<dynamic>;

        print(
            'Received sync payload from $peerName ($peerRole) containing ${sosListMaps.length} items');

        bool hasChanges = false;

        for (var item in sosListMaps) {
          final incomingSOS = SOS.fromMap(Map<String, dynamic>.from(item));
          final existingSOS = StorageService.getSOS(incomingSOS.id);

          var updatedIncoming = incomingSOS;
          if (incomingSOS.relayDecision == 'PENDING' ||
              incomingSOS.status == 'RELAY_PENDING') {
            updatedIncoming = incomingSOS.copyWith(
              status: 'RELAY_ACCEPTED',
              relayDecision: 'APPROVED',
              lastUpdated: DateTime.now(),
            );
          }

          if (existingSOS == null) {
            // New message discovered
            StorageService.saveSOS(updatedIncoming);
            hasChanges = true;
          } else {
            // Deduplicate and choose the latest status based on lastUpdated
            if (updatedIncoming.lastUpdated.isAfter(existingSOS.lastUpdated)) {
              StorageService.saveSOS(updatedIncoming);
              hasChanges = true;
            }
          }
        }

        if (hasChanges) {
          print(
              'Local state updated from sync. Refreshing UI and cascading updates.');
          if (onSyncCompleted != null) {
            onSyncCompleted!();
          }
          // In a mesh, cascade updates to all other peers
          syncAllData();
        }
      }
    } catch (e) {
      print('Error parsing received payload: $e');
    }
  }
}

class PeerDetails {
  final String id;
  final String name;

  PeerDetails({required this.id, required this.name});
}
