import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/sos.dart';
import '../services/storage_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  // Native SMS MethodChannel
  static const _smsChannel = MethodChannel('com.resqlink.sms');

  final MapController _mapController = MapController();
  List<SOS> _sosList = [];
  SOS? _selectedSOS;

  bool _isCaching = false;
  double _cacheProgress = 0.0;
  bool _cacheComplete = false;

  late AnimationController _radarController;

  // Default base coordinates (Mandya base station)
  final LatLng _myLocation = const LatLng(12.5118, 76.8851);

  // SMS Portal State
  String? _selectedTemplate;
  final TextEditingController _customMsgController = TextEditingController();
  bool _sendingSMS = false;

  // Pre-defined emergency message templates
  static const String _customOption = '✏️ Custom Message...';
  static const List<String> _smsTemplates = [
    '🚨 CRITICAL: Evacuation required at current location. Please dispatch rescue team immediately.',
    '🚑 MEDICAL: Stranded individuals require urgent medical aid. Send medical team to our GPS coordinates.',
    '🌾 SUPPLIES: Clean drinking water and food packages needed. People are without resources.',
    '⛺ SHELTER: Safe zone established. We need tents, bedding and warmth supplies.',
    '⚡ POWER: No electricity access. Battery backup and charging units needed.',
    '🟢 RESOLVED: Situation stabilized. All individuals safe. Rescue acknowledged.',
    _customOption,
  ];

  // Visual styling mapping for distress needs
  final Map<String, Map<String, dynamic>> _needsTheme = {
    'Medical Aid': {
      'icon': Icons.medical_services_rounded,
      'color': Colors.redAccent,
    },
    'Drinking Water': {
      'icon': Icons.water_drop_rounded,
      'color': Colors.blue,
    },
    'Emergency Food': {
      'icon': Icons.restaurant_rounded,
      'color': Colors.orange,
    },
    'Warm Shelter': {
      'icon': Icons.home_rounded,
      'color': Colors.brown,
    },
    'Rescue/Extraction': {
      'icon': Icons.directions_boat_rounded,
      'color': Colors.teal,
    },
    'Other Emergency': {
      'icon': Icons.warning_rounded,
      'color': Colors.deepOrange,
    },
  };

  @override
  void initState() {
    super.initState();
    _loadSOSSignals();
    _selectedTemplate = _smsTemplates[0];

    // Set up pulsating base station radar animation
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    _mapController.dispose();
    _customMsgController.dispose();
    super.dispose();
  }

  void _loadSOSSignals() {
    setState(() {
      _sosList = StorageService.getAllSOS();
    });
  }

  void _simulatePreCaching() async {
    setState(() {
      _isCaching = true;
      _cacheProgress = 0.0;
      _cacheComplete = false;
    });

    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() {
        _cacheProgress = i / 10.0;
      });
    }

    setState(() {
      _isCaching = false;
      _cacheComplete = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline Sector Map pre-cached successfully! (24.5 MB saved)'),
          backgroundColor: Color(0xFF6D8B74),
        ),
      );
    }
  }

  LatLng _parseCoords(String locationStr) {
    try {
      final parts = locationStr.split(',');
      final latStr = parts[0].replaceAll('Lat:', '').trim();
      final lngStr = parts[1].replaceAll('Lng:', '').trim();
      return LatLng(double.parse(latStr), double.parse(lngStr));
    } catch (_) {
      // Return a predictable offset based on hash to avoid overlapping
      final seed = locationStr.hashCode;
      final random = Random(seed);
      return LatLng(
        _myLocation.latitude + (random.nextDouble() - 0.5) * 0.015,
        _myLocation.longitude + (random.nextDouble() - 0.5) * 0.015,
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
      case 'RESOLVED':
        return Colors.green;
      case 'RELAY_ACCEPTED':
      case 'DISPATCHED':
        return Colors.orange;
      case 'CREATED':
      case 'RELAY_PENDING':
      default:
        return Colors.red;
    }
  }

  void _selectAndCenterSOS(SOS sos) {
    setState(() {
      _selectedSOS = sos;
    });
    final pos = _parseCoords(sos.location);
    _mapController.move(pos, 14.5);
  }

  // --- SMS Portal Logic ---

  Future<void> _triggerSMS(String message) async {
    if (message.trim().isEmpty) return;
    setState(() => _sendingSMS = true);
    try {
      await _smsChannel.invokeMethod('sendSMS', {
        'number': '7996710095',
        'message': message.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📱 SMS app opened — tap Send to dispatch the alert!'),
            backgroundColor: Color(0xFF5F7161),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SMS launch failed: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingSMS = false);
    }
  }

  void _showSMSPortal() {
    setState(() {
      _selectedTemplate = _smsTemplates[0];
      _customMsgController.clear();
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSMSPortalSheet(),
    );
  }

  Widget _buildSMSPortalSheet() {
    return StatefulBuilder(
      builder: (context, setSheetState) {
        final bool isCustom = _selectedTemplate == _customOption;
        final String effectiveMessage = isCustom
            ? _customMsgController.text
            : (_selectedTemplate ?? '');

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF5F7161), Color(0xFF3D5040)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.sms_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Emergency SMS Portal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Send a pre-defined emergency alert via SMS',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Recipient display
                      const Text(
                        'RECIPIENT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5F7161).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF5F7161).withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF5F7161).withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.phone_rounded,
                                color: Color(0xFF5F7161),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '+91 7996710095',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF3D5040),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  'Emergency Response Command',
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // ── Template dropdown
                      const Text(
                        'MESSAGE TEMPLATE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200, width: 1.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedTemplate,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF5F7161)),
                            style: const TextStyle(color: Colors.black87, fontSize: 13),
                            items: _smsTemplates.map((template) {
                              return DropdownMenuItem<String>(
                                value: template,
                                child: Text(
                                  template,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setSheetState(() => _selectedTemplate = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Message preview or custom text input
                      if (!isCustom) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'MESSAGE PREVIEW',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _selectedTemplate ?? '',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: _customMsgController,
                          maxLines: 4,
                          onChanged: (_) => setSheetState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Type your emergency message here...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFF5F7161), width: 2),
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ── Send button
                      SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: effectiveMessage.trim().isEmpty || _sendingSMS
                              ? null
                              : () async {
                                  Navigator.pop(context);
                                  await _triggerSMS(effectiveMessage);
                                },
                          icon: _sendingSMS
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 22),
                          label: Text(
                            _sendingSMS ? 'OPENING SMS...' : 'Send via SMS',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5F7161),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 2,
                            shadowColor: const Color(0xFF5F7161).withOpacity(0.4),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                      const Text(
                        'This will open your default SMS app pre-filled with the message above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      // My Location Marker (Pulsating Radar Beacon)
      Marker(
        point: _myLocation,
        width: 80,
        height: 80,
        child: AnimatedBuilder(
          animation: _radarController,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 80 * _radarController.value,
                  height: 80 * _radarController.value,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(1.0 - _radarController.value),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 40 * _radarController.value,
                  height: 40 * _radarController.value,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue.withOpacity(0.5), width: 1.5),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      )
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.radio_button_checked, size: 8, color: Colors.white),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ];

    // Add SOS Markers
    for (final sos in _sosList) {
      final pos = _parseCoords(sos.location);
      final color = _getStatusColor(sos.status);
      final isSelected = _selectedSOS?.id == sos.id;
      final needData = _needsTheme[sos.need] ?? {
        'icon': Icons.warning_amber_rounded,
        'color': color,
      };
      final IconData needIcon = needData['icon'];

      markers.add(
        Marker(
          point: pos,
          width: 50,
          height: 60,
          child: GestureDetector(
            onTap: () => _selectAndCenterSOS(sos),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color: color,
                  size: isSelected ? 52 : 42,
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                Positioned(
                  top: isSelected ? 8 : 6,
                  child: Icon(
                    needIcon,
                    color: Colors.white,
                    size: isSelected ? 20 : 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tactical Mesh Map',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'P2P Mesh Overlay Network',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // SMS Portal launch button
          IconButton(
            icon: const Icon(Icons.sms_rounded),
            onPressed: _showSMSPortal,
            tooltip: 'Emergency SMS Portal',
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            onPressed: () {
              _loadSOSSignals();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Telemetry indicators synchronized from local database'),
                  backgroundColor: Color(0xFF6D8B74),
                ),
              );
            },
            tooltip: 'Reload Telemetry',
          )
        ],
      ),
      body: Stack(
        children: [
          // 1. The Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.resqlink.mesh',
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _myLocation,
                    color: Colors.blue.withOpacity(0.06),
                    borderColor: Colors.blue.withOpacity(0.3),
                    borderStrokeWidth: 2,
                    useRadiusInMeter: true,
                    radius: 1000,
                  ),
                  CircleMarker(
                    point: _myLocation,
                    color: Colors.transparent,
                    borderColor: Colors.blue.withOpacity(0.15),
                    borderStrokeWidth: 1.5,
                    useRadiusInMeter: true,
                    radius: 2000,
                  ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  if (_selectedSOS != null)
                    Polyline(
                      points: [
                        _myLocation,
                        _parseCoords(_selectedSOS!.location),
                      ],
                      color: _getStatusColor(_selectedSOS!.status).withOpacity(0.8),
                      strokeWidth: 3.5,
                      isDotted: true,
                    ),
                ],
              ),
              MarkerLayer(markers: markers),
            ],
          ),

          // 2. Offline Status Banner
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2022).withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, color: Colors.amber, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'OFFLINE TACTICAL MAP',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _cacheComplete ? 'Mandya Sector Active (Cached)' : 'Local mesh telemetry mode active',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!_isCaching && !_cacheComplete)
                    ElevatedButton.icon(
                      onPressed: _simulatePreCaching,
                      icon: const Icon(Icons.cloud_download_rounded, size: 14),
                      label: const Text('CACHE SECTOR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                  else if (_isCaching)
                    SizedBox(
                      width: 80,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: _cacheProgress,
                              minHeight: 4,
                              backgroundColor: Colors.grey.shade800,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'DOWNLOADING...',
                            style: TextStyle(color: Colors.blueAccent, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )
                  else
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF6D8B74), size: 16),
                        SizedBox(width: 4),
                        Text(
                          'READY',
                          style: TextStyle(color: Color(0xFF6D8B74), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // 3. Draggable Scrollable Sheet
          DraggableScrollableSheet(
            initialChildSize: 0.28,
            minChildSize: 0.15,
            maxChildSize: 0.70,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 15,
                      spreadRadius: 2,
                      offset: const Offset(0, -5),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.list_alt_rounded, color: Color(0xFF5F7161), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Mesh Signals Index (${_sosList.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF5F7161),
                                ),
                              ),
                            ],
                          ),
                          // Quick SMS shortcut in the bottom panel header
                          GestureDetector(
                            onTap: _showSMSPortal,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF5F7161).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF5F7161).withOpacity(0.25),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.sms_rounded, color: Color(0xFF5F7161), size: 13),
                                  SizedBox(width: 5),
                                  Text(
                                    'Send SMS',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF5F7161),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1, thickness: 1),
                    Expanded(
                      child: _sosList.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.radar, size: 44, color: Colors.grey.shade400),
                                    const SizedBox(height: 10),
                                    Text(
                                      'No active mesh signals detected.\nTelemetry registry is clean.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              itemCount: _sosList.length,
                              itemBuilder: (context, index) {
                                final sos = _sosList[index];
                                final isSelected = _selectedSOS?.id == sos.id;
                                final color = _getStatusColor(sos.status);
                                final needData = _needsTheme[sos.need] ?? {
                                  'icon': Icons.warning_rounded,
                                  'color': color,
                                };
                                final IconData icon = needData['icon'];
                                final Color iconColor = needData['color'];

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: isSelected ? 3 : 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: isSelected ? color : Colors.grey.shade200,
                                      width: isSelected ? 2.0 : 1.0,
                                    ),
                                  ),
                                  color: isSelected ? color.withOpacity(0.04) : Colors.white,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? color.withOpacity(0.12) : Colors.grey.shade50,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(icon, color: isSelected ? color : iconColor, size: 22),
                                    ),
                                    title: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          sos.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            sos.status.replaceAll('_', ' '),
                                            style: TextStyle(
                                              color: color,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 6),
                                        Text(
                                          'Distress need: ${sos.need} • ${sos.people} Stranded',
                                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Coords: ${sos.location}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(
                                        Icons.gps_fixed_rounded,
                                        color: isSelected ? color : Colors.grey,
                                      ),
                                      onPressed: () => _selectAndCenterSOS(sos),
                                      tooltip: 'Center on Map',
                                    ),
                                    onTap: () => _selectAndCenterSOS(sos),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
