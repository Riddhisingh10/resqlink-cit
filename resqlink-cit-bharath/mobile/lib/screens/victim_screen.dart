import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../models/sos.dart';
import '../services/storage_service.dart';
import '../services/wifi_service.dart';
import '../services/sync_bridge_service.dart';

class VictimScreen extends StatefulWidget {
  const VictimScreen({Key? key}) : super(key: key);

  @override
  State<VictimScreen> createState() => _VictimScreenState();
}

class _VictimScreenState extends State<VictimScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _landmarkController = TextEditingController();
  int _peopleCount = 1;
  List<SOS> _myRequests = [];

  // Need grid items for toggle selection
  final List<Map<String, dynamic>> _needsGrid = [
    {
      'name': 'Medical Aid',
      'icon': Icons.medical_services_rounded,
      'color': Colors.redAccent,
    },
    {
      'name': 'Drinking Water',
      'icon': Icons.water_drop_rounded,
      'color': Colors.blue,
    },
    {
      'name': 'Emergency Food',
      'icon': Icons.restaurant_rounded,
      'color': Colors.orange,
    },
    {
      'name': 'Warm Shelter',
      'icon': Icons.home_rounded,
      'color': Colors.brown,
    },
    {
      'name': 'Rescue/Extraction',
      'icon': Icons.directions_boat_rounded,
      'color': Colors.teal,
    },
    {
      'name': 'Other Emergency',
      'icon': Icons.warning_rounded,
      'color': Colors.deepOrange,
    },
  ];

  final List<String> _selectedItems = [];
  bool _detectingLocation = false;
  bool _sendingInstantSOS = false;

  Timer? _syncTimer;
  List<dynamic> _cachedBroadcasts = [];

  @override
  void initState() {
    super.initState();
    // Prefill name if available
    final name = StorageService.getUsername();
    _nameController.text = name.isEmpty ? "Citizen" : name;
    _locationController.text = "Lat: 12.5118, Lng: 76.8851";
    _loadRequests();
    _loadBroadcasts();
    _startPolling();
    WifiService.instance.onSyncCompleted = () {
      if (mounted) {
        _loadRequests();
      }
    };
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _nameController.dispose();
    _locationController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  void _loadBroadcasts() {
    setState(() {
      _cachedBroadcasts = StorageService.getCachedBroadcasts();
    });
  }

  void _startPolling() {
    _syncTimer = Timer.periodic(const Duration(seconds: 7), (timer) async {
      final isOnline = await SyncBridgeService.isServerOnline();
      if (isOnline) {
        await SyncBridgeService.syncUnsyncedSignals();
        await SyncBridgeService.updateDispatchesFromServer();
        await SyncBridgeService.pullBroadcasts();
        
        if (mounted) {
          _loadRequests();
          _loadBroadcasts();
        }
      }
    });
  }

  void _loadRequests() {
    setState(() {
      _myRequests = StorageService.getAllSOS();
      final myIds = StorageService.getMySosIds();

      // Sort: mine first, then newest first
      _myRequests.sort((a, b) {
        final aIsMine = myIds.contains(a.id);
        final bIsMine = myIds.contains(b.id);

        if (aIsMine && !bIsMine) {
          return -1; // a goes first
        } else if (!aIsMine && bIsMine) {
          return 1;  // b goes first
        } else {
          return b.timestamp.compareTo(a.timestamp); // newest first
        }
      });
    });
  }

  void _sendInstantSOS() async {
    setState(() {
      _sendingInstantSOS = true;
    });

    try {
      String locationStr = "Lat: 12.5118, Lng: 76.8851"; // Default fallback

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 4),
          );
          locationStr =
              "Lat: ${position.latitude.toStringAsFixed(5)}, Lng: ${position.longitude.toStringAsFixed(5)}";
        }
      }

      final name = StorageService.getUsername();
      final finalName = name.isEmpty ? "Citizen" : name;

      final instantSOS = SOS(
        id: "SOS-INST-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}",
        name: finalName,
        need: 'CRITICAL RESCUE HELP NEEDED',
        people: 1,
        location: locationStr,
        status: 'RELAY_PENDING',
        relayDecision: 'PENDING',
        commandDecision: 'PENDING',
        eta: '',
        timestamp: DateTime.now(),
        lastUpdated: DateTime.now(),
        safetyChecklist: ['Urgent Extraction Required'],
        synced: false,
      );

      await StorageService.saveSOS(instantSOS);
      await StorageService.addMySosId(instantSOS.id);
      WifiService.instance.syncAllData();
      _loadRequests();

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
                SizedBox(width: 8),
                Text('SOS Broadcasted'),
              ],
            ),
            content: Text(
              'Your emergency alert has been sent to the mesh network!\n\n'
              '📍 Coordinates: $locationStr\n'
              '📡 Status: Broadcasting to nearby rescue nodes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to trigger instant SOS: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingInstantSOS = false;
        });
      }
    }
  }

  void _submitSOS() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one immediate need category.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final gpsCoords = _locationController.text.trim();
    final details = _landmarkController.text.trim();
    final combinedLocation = details.isNotEmpty ? "$gpsCoords ($details)" : gpsCoords;
    
    // Primary need is the first selected item
    final primaryNeed = _selectedItems.first;

    final newSOS = SOS(
      id: "SOS-${const Uuid().v4().substring(0, 8).toUpperCase()}",
      name: _nameController.text.trim(),
      need: primaryNeed,
      people: _peopleCount,
      location: combinedLocation,
      status: 'RELAY_PENDING',
      relayDecision: 'PENDING',
      commandDecision: 'PENDING',
      eta: '',
      timestamp: DateTime.now(),
      lastUpdated: DateTime.now(),
      safetyChecklist: List<String>.from(_selectedItems),
      synced: false,
    );

    await StorageService.saveSOS(newSOS);
    await StorageService.addMySosId(newSOS.id);

    // Clear and reset form fields (keep name prefilled)
    _locationController.text = "Lat: 12.5118, Lng: 76.8851";
    _landmarkController.clear();
    setState(() {
      _peopleCount = 1;
      _selectedItems.clear();
    });

    _loadRequests();

    // Broadcast the new SOS immediately over the mesh network
    WifiService.instance.syncAllData();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🚨 SOS Alert ${newSOS.id} Broad-casted Offline!'),
        backgroundColor: const Color(0xFF5F7161),
      ),
    );
  }

  void _detectLiveLocation() async {
    setState(() {
      _detectingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Location services are disabled. Please enable GPS.')),
        );
        setState(() {
          _detectingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
          setState(() {
            _detectingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Location permissions are permanently denied.')),
        );
        setState(() {
          _detectingLocation = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      setState(() {
        _locationController.text =
            "Lat: ${position.latitude.toStringAsFixed(5)}, Lng: ${position.longitude.toStringAsFixed(5)}";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('GPS Coordinates detected automatically!'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error detecting location: $e')),
      );
    } finally {
      setState(() {
        _detectingLocation = false;
      });
    }
  }

  Widget _buildFlashingAlerts() {
    if (_cachedBroadcasts.isEmpty) return const SizedBox.shrink();

    return Column(
      children: _cachedBroadcasts.map((alert) {
        final severity = alert['severity'] ?? 'info';
        final message = alert['message'] ?? '';
        final zone = alert['targetZone'] ?? 'All Sectors';

        Color alertColor = Colors.blue;
        IconData icon = Icons.info_outline;
        if (severity == 'critical') {
          alertColor = Colors.red;
          icon = Icons.gavel_rounded;
        } else if (severity == 'warning') {
          alertColor = Colors.amber;
          icon = Icons.warning_amber_rounded;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: alertColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: alertColor.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: alertColor.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: alertColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: alertColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HQ EMERGENCY ALERT • ZONE $zone',
                      style: TextStyle(
                        color: alertColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInstantSOSButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Quick Emergency Action',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _sendingInstantSOS ? null : _sendInstantSOS,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _sendingInstantSOS
                      ? [Colors.grey.shade400, Colors.grey.shade600]
                      : [const Color(0xFFD32F2F), const Color(0xFFC62828)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD32F2F).withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _sendingInstantSOS
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(
                            Icons.bolt,
                            size: 28,
                            color: Colors.white,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _sendingInstantSOS ? 'BROADCASTING...' : 'TRIGGER INSTANT SOS',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'One-touch automatic GPS lock & immediate network broadcast',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeshStatusBanner() {
    return ValueListenableBuilder<MeshStatusInfo>(
      valueListenable: WifiService.instance.connectionStatus,
      builder: (context, info, child) {
        final status = info.status;
        Color bannerColor = Colors.grey;
        String statusText = "Mesh Offline";
        IconData icon = Icons.offline_bolt_outlined;
        bool isPulsing = false;

        if (status == MeshConnectionStatus.connected) {
          bannerColor = const Color(0xFF6D8B74);
          statusText =
              "Mesh Active: ${info.connectedCount} Peer(s) Connected • ${info.discoveredCount} Node(s) in Range";
          icon = Icons.insights;
          isPulsing = true;
        } else if (status == MeshConnectionStatus.advertising) {
          bannerColor = Colors.orangeAccent;
          statusText = "Broadcasting offline beacon (${info.discoveredCount} in range)...";
          icon = Icons.sensors;
          isPulsing = true;
        } else if (status == MeshConnectionStatus.discovering) {
          bannerColor = Colors.blueAccent;
          statusText = "Searching... (${info.discoveredCount} node(s) in range)";
          icon = Icons.online_prediction;
          isPulsing = true;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bannerColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: bannerColor.withOpacity(0.3), width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, color: bannerColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MESH SIGNAL STATUS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        color: Colors.grey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: bannerColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPulsing)
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: bannerColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: bannerColor.withOpacity(0.6),
                        blurRadius: 6,
                        spreadRadius: 2,
                      )
                    ]
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSOSForm() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200, width: 1.5),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.edit_document, color: Color(0xFF5F7161), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Detailed SOS Request',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5F7161),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 1),
              
              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Your Name / Identifier',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Please enter name'
                    : null,
              ),
              const SizedBox(height: 18),

              // GPS Location Card & Action
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.gps_fixed, color: Colors.blueAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GPS Coordinates',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _locationController.text,
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _detectingLocation
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : ElevatedButton.icon(
                            onPressed: _detectLiveLocation,
                            icon: const Icon(Icons.refresh, size: 14),
                            label: const Text('Lock GPS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Landmark / Details
              TextFormField(
                controller: _landmarkController,
                decoration: const InputDecoration(
                  labelText: 'Landmark / Floor / Specific Details',
                  prefixIcon: Icon(Icons.location_on),
                  hintText: 'e.g. 3rd Floor, Room 302, near blue gate',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
              ),
              const SizedBox(height: 20),

              // Need Categories Grid
              const Text(
                'Select Immediate Needs:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _needsGrid.length,
                itemBuilder: (context, index) {
                  final need = _needsGrid[index];
                  final String name = need['name'];
                  final IconData icon = need['icon'];
                  final Color color = need['color'];
                  final isSelected = _selectedItems.contains(name);

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedItems.remove(name);
                        } else {
                          _selectedItems.add(name);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withOpacity(0.12) : Colors.grey.shade50,
                        border: Border.all(
                          color: isSelected ? color : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Icon(icon, color: isSelected ? color : Colors.grey, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? color : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Stranded Count Row
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Stranded People Count',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        Text(
                          'Include yourself and others with you',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _peopleCount > 1
                              ? () => setState(() => _peopleCount--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        ),
                        Text(
                          '$_peopleCount',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _peopleCount++),
                          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Submit Button
              ElevatedButton(
                onPressed: _submitSOS,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_tethering, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'BROADCAST DISTRESS SIGNAL',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSOSStatusCard(SOS sos) {
    int currentStep = 0;
    if (sos.status == 'RELAY_ACCEPTED' || sos.status == 'COMMAND_PENDING') {
      currentStep = 1;
    } else if (sos.status == 'DISPATCHED') {
      currentStep = 2;
    } else if (sos.status == 'COMPLETED') {
      currentStep = 3;
    }

    Color statusBadgeColor = Colors.orangeAccent;
    if (sos.status == 'DISPATCHED') statusBadgeColor = Colors.green;
    if (sos.status == 'COMPLETED') statusBadgeColor = Colors.blue;

    final isMine = StorageService.isMySos(sos.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isMine ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isMine ? const Color(0xFF6D8B74) : Colors.grey.shade200,
          width: isMine ? 2.0 : 1.5,
        ),
      ),
      color: isMine ? const Color(0xFFF4F7F5) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      sos.id,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        color: isMine ? const Color(0xFF5F7161) : Colors.black87,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6D8B74).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF6D8B74).withOpacity(0.4)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.person, size: 10, color: Color(0xFF5F7161)),
                            SizedBox(width: 3),
                            Text(
                              'MY REQUEST',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5F7161),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBadgeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusBadgeColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    sos.status == 'RELAY_ACCEPTED'
                        ? 'MESH SYNCED'
                        : (sos.status == 'RELAY_PENDING'
                            ? 'MESH PENDING'
                            : sos.status.replaceAll('_', ' ')),
                    style: TextStyle(color: statusBadgeColor, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Text(
              'Primary Need: ${sos.need}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Name: ${sos.name}',
              style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text('People Stranded: ${sos.people}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 4),
            Text('Location: ${sos.location}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            
            if (sos.safetyChecklist.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: sos.safetyChecklist.map((item) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      item,
                      style: const TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),

            // Stepper Visual Progression
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStepIndicator('SOS Created', currentStep >= 0),
                _buildStepLine(currentStep >= 1),
                _buildStepIndicator('Mesh Synced', currentStep >= 1),
                _buildStepLine(currentStep >= 2),
                _buildStepIndicator('Rescue Sent', currentStep >= 2),
              ],
            ),

            if (sos.status == 'DISPATCHED' && sos.eta.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black87, fontSize: 13),
                          children: [
                            const TextSpan(text: 'Rescue Team En Route! ETA: '),
                            TextSpan(
                              text: sos.eta,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(String label, bool active) {
    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor:
              active ? const Color(0xFF6D8B74) : Colors.grey.shade200,
          child: Icon(
            active ? Icons.check : Icons.circle,
            size: active ? 14 : 6,
            color: active ? Colors.white : Colors.grey.shade400,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? const Color(0xFF5F7161) : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(bool active) {
    return Expanded(
      child: Container(
        height: 2,
        color: active ? const Color(0xFF6D8B74) : Colors.grey.shade200,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFlashingAlerts(),
          _buildMeshStatusBanner(),
          const SizedBox(height: 16),
          _buildInstantSOSButton(),
          const SizedBox(height: 16),
          _buildSOSForm(),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'SOS Status Signals',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5F7161)),
            ),
          ),
          const SizedBox(height: 10),

          _myRequests.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Center(
                    child: Text(
                      'No active distress signals created yet.\nYour SOS alerts will list here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _myRequests.length,
                  itemBuilder: (context, index) {
                    return _buildSOSStatusCard(_myRequests[index]);
                  },
                ),
        ],
      ),
    );
  }
}
