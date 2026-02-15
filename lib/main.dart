import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';



void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Force landscape orientation on mobile/tablet devices
  if (_isMobileOrTablet()) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  
  String? initialFilePath = args.isNotEmpty ? args[0] : null;
  runApp(DXFViewerApp(initialFile: initialFilePath));
}

// Helper function to detect mobile/tablet devices
bool _isMobileOrTablet() {
  if (kIsWeb) return false; // Web is not mobile
  
  // Check platform
  if (Platform.isAndroid || Platform.isIOS) {
    return true;
  }
  
  return false;
}

class DXFViewerApp extends StatefulWidget {
  final String? initialFile;
  
  const DXFViewerApp({super.key, this.initialFile});

  @override
  State<DXFViewerApp> createState() => _DXFViewerAppState();
}

class _DXFViewerAppState extends State<DXFViewerApp> {
  @override
  void initState() {
    super.initState();
    // Ensure orientation stays locked
    if (_isMobileOrTablet()) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void dispose() {
    // Reset orientation on app close (optional - uncomment if needed)
    // SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DXF Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1e1e1e),
        primaryColor: const Color(0xFF2b2b2b),
        cardColor: const Color(0xFF2b2b2b),
      ),
      home: DXFViewerHome(externalFile: widget.initialFile),
    );
  }
}

class DXFViewerHome extends StatefulWidget {
  final String? externalFile;
  const DXFViewerHome({super.key, this.externalFile});

  @override
  State<DXFViewerHome> createState() => _DXFViewerHomeState();
}

class _DXFViewerHomeState extends State<DXFViewerHome> {
  DXFData? _dxfData;
  String? _filename;
  bool _isDragging = false;
  bool _layersPanelCollapsed = false;
  bool _showFills = false; // NEW: Toggle for filled entities (default OFF)
  double _fillOpacity = 0.3; // NEW: Adjustable fill opacity
  bool _invertColors = false; // NEW: Invert colors for visibility
  Color _backgroundColor = const Color(0xFF2b2b2b);
  List<String> _sampleFiles = []; // Available sample files
  bool _samplesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableSamples(); // Load sample file list
    if (widget.externalFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadFile(widget.externalFile!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_filename ?? 'DXF Viewer'),
        backgroundColor: const Color(0xFF2b2b2b),
        actions: [
          // Sample files dropdown (dynamic from assets)
          if (_samplesLoaded && _sampleFiles.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.folder_special),
              tooltip: 'Load Sample File',
              onSelected: _loadSampleFile,
              itemBuilder: (context) => _sampleFiles.asMap().entries.map((entry) {
                final index = entry.key;
                final filename = entry.value;
                return PopupMenuItem<String>(
                  value: filename,
                  child: Row(
                    children: [
                      const Icon(Icons.description, size: 20),
                      const SizedBox(width: 12),
                      Text('Sample ${index + 1}'),
                    ],
                  ),
                );
              }).toList(),
            ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFile,
            tooltip: 'Open DXF File',
          ),
        ],
      ),
      body: _isDesktop()
          ? DropTarget(
              onDragEntered: (details) {
                setState(() => _isDragging = true);
              },
              onDragExited: (details) {
                setState(() => _isDragging = false);
              },
              onDragDone: (details) {
                setState(() => _isDragging = false);
                if (details.files.isNotEmpty) {
                  final file = details.files.first;
                  if (file.path.toLowerCase().endsWith('.dxf')) {
                    _loadFile(file.path);
                  } else {
                    _showError('Please drop a .dxf file');
                  }
                }
              },
              child: _buildMainContent(),
            )
          : _buildMainContent(),
    );
  }

  // Helper method to check if running on desktop
  bool _isDesktop() {
    if (kIsWeb) return true; // Web supports drag & drop
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  Widget _buildMainContent() {
    return Row(
      children: [
        Expanded(
          child: MouseRegion(
            cursor: _isDragging ? SystemMouseCursors.copy : SystemMouseCursors.basic,
            child: Container(
              color: _isDragging
                  ? const Color(0xFF3c3c3c)
                  : _backgroundColor,
              child: _dxfData == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.file_download_outlined,
                            size: 64,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isDesktop() 
                                ? 'Drag & Drop DXF file here'
                                : 'Tap the folder icon to open a DXF file',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_isDesktop()) ...[
                            const SizedBox(height: 8),
                            Text(
                              'or use the folder icon above',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : DXFCanvas(
                      dxfData: _dxfData!,
                      backgroundColor: _backgroundColor,
                      showFills: _showFills,
                      fillOpacity: _fillOpacity,
                      invertColors: _invertColors,
                      onBackgroundColorChanged: (color) {
                        setState(() {
                          _backgroundColor = color;
                          // Auto-invert if background and drawing colors are similar
                          if (_dxfData != null) {
                            _autoDetectColorInversion(color);
                          }
                        });
                      },
                      onShowFillsChanged: (show) {
                        setState(() => _showFills = show);
                      },
                      onFillOpacityChanged: (opacity) {
                        setState(() => _fillOpacity = opacity);
                      },
                      onInvertColorsChanged: (invert) {
                        setState(() => _invertColors = invert);
                      },
                      onReset: _resetView,
                    ),
            ),
          ),
        ),
        if (_dxfData != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _layersPanelCollapsed ? 40 : 250,
            decoration: BoxDecoration(
              color: const Color(0xFF3c3c3c),
              border: Border(
                left: BorderSide(color: Colors.grey.shade800),
              ),
            ),
            child: _layersPanelCollapsed
                ? Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () {
                        setState(() => _layersPanelCollapsed = false);
                      },
                      tooltip: 'Show Layers',
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Layers',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: () {
                                setState(() => _layersPanelCollapsed = true);
                              },
                              tooltip: 'Hide Layers',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              iconSize: 20,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: LayerPanel(
                          dxfData: _dxfData!,
                          onLayerToggle: (layerName, visible) {
                            setState(() {
                              _dxfData!.layers[layerName]!.visible = visible;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }

  Future<void> _openFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['dxf'],
    );

    if (result != null && result.files.single.path != null) {
      _loadFile(result.files.single.path!);
    }
  }

  // Load list of available sample files from assets
  Future<void> _loadAvailableSamples() async {
    try {
      // Load the AssetManifest to discover all sample files
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      
      // Filter for .dxf files in the samples folder
      final samples = manifestMap.keys
          .where((String key) => key.startsWith('samples/') && key.endsWith('.dxf'))
          .map((String key) => key.split('/').last) // Get filename only
          .toList();
      
      setState(() {
        _sampleFiles = samples;
        _samplesLoaded = true;
      });
      
      // print('Found ${samples.length} sample files: $samples');
    } catch (e) {
      // print('Error loading sample files: $e');
      setState(() {
        _samplesLoaded = true; // Mark as loaded even if empty
      });
    }
  }

  Future<void> _loadSampleFile(String sampleFileName) async {
    try {
      // Load the asset as bytes
      final ByteData data = await rootBundle.load('samples/$sampleFileName');
      
      // Get temporary directory
      final Directory tempDir = await getTemporaryDirectory();
      final String tempPath = '${tempDir.path}/$sampleFileName';
      
      // Write bytes to temporary file
      final File tempFile = File(tempPath);
      await tempFile.writeAsBytes(data.buffer.asUint8List());
      
      // Load the temporary file
      await _loadFile(tempPath);
      
      setState(() {
        _filename = sampleFileName; // Set the display name
      });
    } catch (e) {
      // print('Error loading sample file: $e');
      _showError('Failed to load sample file: $e');
    }
  }

  Future<void> _loadFile(String filepath) async {
    try {
      // print('Loading DXF file: $filepath');
      final parser = DXFParser();
      final data = await parser.parse(filepath);

      // print('Parsed ${data.entities.length} entities');
      // print('Found ${data.layers.length} layers: ${data.layers.keys.toList()}');
      // print('Bounds: ${data.bounds}');

      setState(() {
        _dxfData = data;
        _filename = filepath.split(Platform.pathSeparator).last;
      });
      
      // Auto-detect if color inversion is needed
      _autoDetectColorInversion(_backgroundColor);
    } catch (e, stackTrace) {
      print('Error loading DXF: $e');
      print('Stack trace: $stackTrace');
      _showError('Failed to load DXF file: $e');
    }
  }

  void _resetView() {
    setState(() {
      _dxfData = null;
      _filename = null;
      _layersPanelCollapsed = false;
    });
  }

  void _autoDetectColorInversion(Color backgroundColor) {
    if (_dxfData == null) return;
    
    // Get background luminance
    final bgLum = backgroundColor.computeLuminance();
    
    // Check if most entities have similar luminance to background
    int similarCount = 0;
    int totalCount = 0;
    
    for (final entity in _dxfData!.entities) {
      final entityLum = entity.color.computeLuminance();
      final lumDiff = (bgLum - entityLum).abs();
      
      // If luminance difference is less than 0.3, they're too similar
      if (lumDiff < 0.3) {
        similarCount++;
      }
      totalCount++;
      
      // Sample first 100 entities for performance
      if (totalCount >= 100) break;
    }
    
    // If more than 50% of entities have similar luminance, auto-invert
    if (totalCount > 0 && similarCount / totalCount > 0.5) {
      setState(() {
        _invertColors = true;
      });
      // print('AUTO-INVERT: Enabled color inversion (${similarCount}/${totalCount} entities similar to background)');
    } else {
      setState(() {
        _invertColors = false;
      });
      // print('AUTO-INVERT: Disabled color inversion (only ${similarCount}/${totalCount} entities similar to background)');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }
}

// DXF Data Models
class DXFEntity {
  final String type;
  final String layer;
  final Color color;
  final Map<String, dynamic> data;

  DXFEntity({
    required this.type,
    required this.layer,
    required this.color,
    required this.data,
  });
}

class DXFLayer {
  final String name;
  bool visible;
  Color color; // Changed from final to allow color updates

  DXFLayer({
    required this.name,
    this.visible = true,
    required this.color,
  });
}

class DXFData {
  final List<DXFEntity> entities;
  final Map<String, DXFLayer> layers;
  final Rect bounds;

  DXFData({
    required this.entities,
    required this.layers,
    required this.bounds,
  });
}

// DXF Parser
class DXFParser {
  // Predefined color palette for layers
  final List<Color> _layerColorPalette = [
    const Color(0xFFFF0000), // Red
    const Color(0xFF00FF00), // Green
    const Color(0xFF0000FF), // Blue
    const Color(0xFFFFFF00), // Yellow
    const Color(0xFF00FFFF), // Cyan
    const Color(0xFFFF00FF), // Magenta
    const Color(0xFFFF8000), // Orange
    const Color(0xFF8000FF), // Purple
    const Color(0xFF00FF80), // Spring Green
    const Color(0xFF0080FF), // Sky Blue
    const Color(0xFFFF0080), // Pink
    const Color(0xFF80FF00), // Lime
    const Color(0xFFFFFFFF), // White
    const Color(0xFFC0C0C0), // Light Gray
    const Color(0xFF808080), // Gray
    const Color(0xFF804000), // Brown
  ];

  Color _getLayerColor(int index) {
    return _layerColorPalette[index % _layerColorPalette.length];
  }

  Future<DXFData> parse(String filepath) async {
    try {
      final file = File(filepath);
      final lines = await file.readAsLines();

      final entities = <DXFEntity>[];
      final layers = <String, DXFLayer>{};
      int layerIndex = 0; // Track layer count for color assignment

      // Find ENTITIES section
      int entitiesStart = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].trim() == 'ENTITIES') {
          entitiesStart = i;
          break;
        }
      }

      if (entitiesStart == -1) {
        print('WARNING: No ENTITIES section found in DXF file');
        return DXFData(
          entities: [],
          layers: {},
          bounds: const Rect.fromLTRB(0, 0, 100, 100),
        );
      }

      // Parse entities
      int i = entitiesStart + 1;
      Map<String, dynamic>? currentEntity;

      // print('DEBUG: Starting entity parsing at line $i');

      while (i < lines.length - 1) {
        try {
          final code = lines[i].trim();
          final value = i + 1 < lines.length ? lines[i + 1].trim() : '';

          if (code == 'ENDSEC') break;

          if (code == '0') {
            if (currentEntity != null) {
              try {
                _addEntity(currentEntity, entities, layers);
              } catch (e) {
                // print('WARNING: Failed to add entity ${currentEntity['type']}: $e');
              }
            }

            if (['LINE', 'CIRCLE', 'ARC', 'LWPOLYLINE', 'POLYLINE', 'SPLINE', 
                 'ELLIPSE', 'TEXT', 'MTEXT', 'HATCH', 'INSERT', 'SOLID', 'POINT'].contains(value)) {
              currentEntity = {
                'type': value,
                'layer': '0',
                'color': Colors.white,
                'vertices': <Map<String, double>>[],
                'points': <Map<String, double>>[],
                'hatch_reading_vertices': false, // For HATCH: are we past the header?
                'hatch_vertices_to_read': 0, // For HATCH: how many vertices to read
              };
              // if (entities.length < 5) {
              //   print('DEBUG: Started parsing ${value} entity #${entities.length} at line $i');
              // }
            } else {
              currentEntity = null;
            }
          } else if (currentEntity != null) {
            final codeNum = int.tryParse(code);
            if (codeNum != null) {
              try {
                switch (codeNum) {
                  case 8: // Layer name
                    currentEntity['layer'] = value;
                    if (!layers.containsKey(value)) {
                      layers[value] = DXFLayer(
                        name: value,
                        color: _getLayerColor(layerIndex),
                      );
                      layerIndex++;
                    }
                    break;
                    
                  case 10: // First corner X (or polyline vertex X)
                    if (currentEntity['type'] == 'SOLID') {
                      currentEntity['x1'] = double.tryParse(value) ?? 0.0;
                    } else if (currentEntity['type'] == 'HATCH') {
                      // For HATCH, only read vertices if we're in vertex reading mode
                      if (currentEntity['hatch_reading_vertices'] == true) {
                        final verticesRead = (currentEntity['vertices'] as List).length;
                        final toRead = currentEntity['hatch_vertices_to_read'] as int;
                        
                        if (verticesRead < toRead) {
                          final x = double.tryParse(value) ?? 0.0;
                          currentEntity['last_x'] = x;
                          // final hatchNum = entities.where((e) => e.type == 'HATCH').length;
                          // if (hatchNum < 3 && verticesRead < 5) {
                          //   print('DEBUG HATCH #$hatchNum: Reading vertex #${verticesRead + 1}/$toRead, X=$x');
                          // }
                        }
                      }
                      // Ignore 10/20 pairs before code 93
                    } else if (currentEntity['type'] == 'LWPOLYLINE' || 
                        currentEntity['type'] == 'POLYLINE' ||
                        currentEntity['type'] == 'SPLINE') {
                      final x = double.tryParse(value) ?? 0.0;
                      currentEntity['last_x'] = x;
                      
                      // if (currentEntity['type'] == 'SPLINE') {
                      //   final splineNum = entities.where((e) => e.type == 'SPLINE').length;
                      //   final pointsRead = (currentEntity['points'] as List).length;
                      //   if (splineNum < 3 && pointsRead < 5) {
                      //     print('DEBUG SPLINE #$splineNum: Reading point #${pointsRead + 1}, X=$x');
                      //   }
                      // }
                    } else {
                      currentEntity['x'] = double.tryParse(value) ?? 0.0;
                    }
                    break;
                    
                  case 20: // First corner Y (or polyline vertex Y)
                    if (currentEntity['type'] == 'SOLID') {
                      currentEntity['y1'] = double.tryParse(value) ?? 0.0;
                    } else if (currentEntity['type'] == 'HATCH') {
                      if (currentEntity.containsKey('last_x') && 
                          currentEntity['hatch_reading_vertices'] == true) {
                        final vertices = currentEntity['vertices'] as List<Map<String, double>>;
                        final toRead = currentEntity['hatch_vertices_to_read'] as int;
                        
                        if (vertices.length < toRead) {
                          final y = double.tryParse(value) ?? 0.0;
                          vertices.add({
                            'x': currentEntity['last_x'] as double,
                            'y': y,
                          });
                          // final hatchNum = entities.where((e) => e.type == 'HATCH').length;
                          // if (hatchNum < 3 && vertices.length <= 5) {
                          //   print('DEBUG HATCH #$hatchNum: Added vertex #${vertices.length}: x=${currentEntity['last_x']}, y=$y');
                          // }
                          currentEntity.remove('last_x');
                        }
                      }
                    } else if (currentEntity['type'] == 'LWPOLYLINE' || 
                        currentEntity['type'] == 'POLYLINE' ||
                        currentEntity['type'] == 'SPLINE') {
                      if (currentEntity.containsKey('last_x')) {
                        final points = currentEntity['type'] == 'SPLINE' 
                            ? currentEntity['points'] as List<Map<String, double>>
                            : currentEntity['vertices'] as List<Map<String, double>>;
                        final y = double.tryParse(value) ?? 0.0;
                        points.add({
                          'x': currentEntity['last_x'] as double,
                          'y': y,
                        });
                        
                        // if (currentEntity['type'] == 'SPLINE') {
                        //   final splineNum = entities.where((e) => e.type == 'SPLINE').length;
                        //   if (splineNum < 3 && points.length <= 5) {
                        //     print('DEBUG SPLINE #$splineNum: Added point #${points.length}: x=${currentEntity['last_x']}, y=$y');
                        //   }
                        // }
                        
                        currentEntity.remove('last_x');
                      }
                    } else {
                      currentEntity['y'] = double.tryParse(value) ?? 0.0;
                    }
                    break;
                    
                  case 11: // Second corner X (or major axis endpoint X)
                    if (currentEntity['type'] == 'SOLID') {
                      currentEntity['x2'] = double.tryParse(value) ?? 0.0;
                    } else {
                      currentEntity['x2'] = double.tryParse(value) ?? 0.0;
                    }
                    break;
                    
                  case 21: // Second corner Y (or major axis endpoint Y)
                    if (currentEntity['type'] == 'SOLID') {
                      currentEntity['y2'] = double.tryParse(value) ?? 0.0;
                    } else {
                      currentEntity['y2'] = double.tryParse(value) ?? 0.0;
                    }
                    break;
                    
                  case 12: // Third corner X
                    currentEntity['x3'] = double.tryParse(value) ?? 0.0;
                    break;
                    
                  case 22: // Third corner Y
                    currentEntity['y3'] = double.tryParse(value) ?? 0.0;
                    break;
                    
                  case 13: // Fourth corner X
                    currentEntity['x4'] = double.tryParse(value) ?? 0.0;
                    break;
                    
                  case 23: // Fourth corner Y
                    currentEntity['y4'] = double.tryParse(value) ?? 0.0;
                    break;
                    
                  case 40: // Radius / minor to major ratio
                    currentEntity['radius'] = double.tryParse(value) ?? 0.0;
                    break;
                  case 41: // Start parameter / ratio
                    currentEntity['start_param'] = double.tryParse(value) ?? 0.0;
                    break;
                  case 42: // End parameter / bulge
                    currentEntity['end_param'] = double.tryParse(value) ?? 0.0;
                    break;
                  case 50: // Start angle
                    currentEntity['start_angle'] = double.tryParse(value) ?? 0.0;
                    break;
                  case 51: // End angle
                    currentEntity['end_angle'] = double.tryParse(value) ?? 0.0;
                    break;
                  case 62: // Color (ACI)
                    currentEntity['color'] = _aciToColor(int.tryParse(value) ?? 7);
                    break;
                  case 420: // RGB color (24-bit)
                  case 421: // RGB color (24-bit)  
                    final rgb = int.tryParse(value) ?? 16777215;
                    currentEntity['color'] = Color(0xFF000000 | rgb);
                    break;
                  case 70: // Flags (closed polyline, etc)
                    currentEntity['flags'] = int.tryParse(value) ?? 0;
                    break;
                  case 90: // Vertex count
                    currentEntity['vertex_count'] = int.tryParse(value) ?? 0;
                    break;
                  case 93: // HATCH: Number of boundary path edges/vertices
                    if (currentEntity['type'] == 'HATCH') {
                      final count = int.tryParse(value) ?? 0;
                      currentEntity['hatch_vertices_to_read'] = count;
                      currentEntity['hatch_reading_vertices'] = true;
                      // final hatchNum = entities.where((e) => e.type == 'HATCH').length;
                      // if (hatchNum < 3) {
                      //   print('DEBUG HATCH #$hatchNum: Code 93 says $count vertices to read (line $i)');
                      // }
                    }
                    break;
                  case 1: // Text value
                    currentEntity['text'] = value;
                    break;
                  case 7: // Text style
                    currentEntity['text_style'] = value;
                    break;
                }
              } catch (e) {
                // print('WARNING: Failed to parse code $codeNum with value "$value": $e');
              }
            }
          }

          i += 2;
        } catch (e) {
          // print('WARNING: Error parsing line $i: $e');
          i += 2;
        }
      }

      if (currentEntity != null) {
        try {
          _addEntity(currentEntity, entities, layers);
        } catch (e) {
          // print('WARNING: Failed to add final entity: $e');
        }
      }

      // Calculate bounds
      final bounds = _calculateBounds(entities);

      // print('Successfully parsed ${entities.length} entities from ${layers.length} layers');
      // print('Final bounds: $bounds');
      
      // Print entity type breakdown
      // final entityCounts = <String, int>{};
      // for (final entity in entities) {
      //   entityCounts[entity.type] = (entityCounts[entity.type] ?? 0) + 1;
      // }
      // print('Entity breakdown: $entityCounts');
      
      // Print layer breakdown
      // print('\n=== LAYER STATUS ===');
      // for (final layer in layers.values) {
      //   final layerEntities = entities.where((e) => e.layer == layer.name).length;
      //   print('Layer "${layer.name}": ${layer.visible ? "VISIBLE" : "HIDDEN"}, $layerEntities entities');
      // }
      
      // Check if any entities have valid coordinates
      // int entitiesWithCoords = 0;
      // for (final entity in entities) {
      //   if (entity.type == 'HATCH' || entity.type == 'LWPOLYLINE') {
      //     final vertices = entity.data['vertices'] as List<Map<String, double>>?;
      //     if (vertices != null && vertices.isNotEmpty) {
      //       entitiesWithCoords++;
      //       if (entitiesWithCoords == 1) {
      //         print('\n=== FIRST ENTITY WITH COORDS ===');
      //         print('Type: ${entity.type}');
      //         print('Layer: ${entity.layer}');
      //         print('Vertices: ${vertices.length}');
      //         print('First vertex: ${vertices.first}');
      //         print('Last vertex: ${vertices.last}');
      //       }
      //     }
      //   }
      // }
      // print('Total entities with coordinates: $entitiesWithCoords');
      // print('==================\n');

      return DXFData(
        entities: entities,
        layers: layers,
        bounds: bounds,
      );
    } catch (e, stackTrace) {
      print('ERROR: Fatal error parsing DXF file: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  void _addEntity(
    Map<String, dynamic> data,
    List<DXFEntity> entities,
    Map<String, DXFLayer> layers,
  ) {
    try {
      final type = data['type'] as String;
      final layer = data['layer'] as String;
      final color = data['color'] as Color? ?? Colors.white;

      if (type == 'LINE' &&
          data.containsKey('x') &&
          data.containsKey('y') &&
          data.containsKey('x2') &&
          data.containsKey('y2')) {
        entities.add(DXFEntity(
          type: type,
          layer: layer,
          color: color,
          data: data,
        ));
      } else if (type == 'CIRCLE' &&
          data.containsKey('x') &&
          data.containsKey('y') &&
          data.containsKey('radius')) {
        entities.add(DXFEntity(
          type: type,
          layer: layer,
          color: color,
          data: data,
        ));
      } else if (type == 'ARC' &&
          data.containsKey('x') &&
          data.containsKey('y') &&
          data.containsKey('radius') &&
          data.containsKey('start_angle') &&
          data.containsKey('end_angle')) {
        entities.add(DXFEntity(
          type: type,
          layer: layer,
          color: color,
          data: data,
        ));
      } else if ((type == 'LWPOLYLINE' || type == 'POLYLINE') &&
          data.containsKey('vertices')) {
        final vertices = data['vertices'] as List<Map<String, double>>;
        if (vertices.length >= 2) {
          // if (entities.length < 5) {  // Debug first few entities
          //   print('DEBUG: Adding $type entity #${entities.length}');
          //   print('  Layer: $layer');
          //   print('  Vertices: ${vertices.length}');
          //   if (vertices.isNotEmpty) {
          //     print('  First vertex: ${vertices.first}');
          //     print('  Last vertex: ${vertices.last}');
          //   }
          // }
          entities.add(DXFEntity(
            type: type,
            layer: layer,
            color: color,
            data: data,
          ));
        } else {
          // if (entities.length < 5) {
          //   print('WARNING: Skipping $type #${entities.length} - only ${vertices.length} vertices (need >=2)');
          // }
        }
      } else if (type == 'SPLINE' && data.containsKey('points')) {
        final points = data['points'] as List<Map<String, double>>;
        if (points.length >= 2) {
          // if (entities.length < 5) {
          //   print('DEBUG: Adding SPLINE entity #${entities.length}');
          //   print('  Layer: $layer');
          //   print('  Control points: ${points.length}');
          //   if (points.isNotEmpty) {
          //     print('  First point: ${points.first}');
          //     print('  Last point: ${points.last}');
          //   }
          // }
          entities.add(DXFEntity(
            type: type,
            layer: layer,
            color: color,
            data: data,
          ));
        } else {
          // if (entities.length < 5) {
          //   print('WARNING: Skipping SPLINE #${entities.length} - only ${points.length} points (need >=2)');
          // }
        }
      } else if (type == 'SOLID') {
        if (data.containsKey('x1') && data.containsKey('y1') &&
            data.containsKey('x2') && data.containsKey('y2') &&
            data.containsKey('x3') && data.containsKey('y3')) {
          // Convert SOLID corners to vertices
          final vertices = <Map<String, double>>[
            {'x': data['x1'], 'y': data['y1']},
            {'x': data['x2'], 'y': data['y2']},
            {'x': data['x3'], 'y': data['y3']},
          ];
          if (data.containsKey('x4') && data.containsKey('y4')) {
            vertices.add({'x': data['x4'], 'y': data['y4']});
          }
          data['vertices'] = vertices;
          
          entities.add(DXFEntity(
            type: type,
            layer: layer,
            color: color,
            data: data,
          ));
        }
      } else if (type == 'HATCH' &&
          data.containsKey('vertices')) {
        final vertices = data['vertices'] as List<Map<String, double>>;
        if (vertices.isNotEmpty) {
          // if (entities.length < 5) {  // Debug first few entities
          //   print('DEBUG: Adding HATCH entity #${entities.length}');
          //   print('  Layer: $layer');
          //   print('  Color: $color');
          //   print('  Vertices: ${vertices.length}');
          //   if (vertices.isNotEmpty) {
          //     print('  First vertex: ${vertices.first}');
          //     print('  Last vertex: ${vertices.last}');
          //   }
          // }
          entities.add(DXFEntity(
            type: type,
            layer: layer,
            color: color,
            data: data,
          ));
        } else {
          // if (entities.length < 5) {
          //   print('WARNING: Skipping HATCH #${entities.length} - no vertices (vertices list empty)');
          // }
        }
      } else if (type == 'ELLIPSE' &&
          data.containsKey('x') &&
          data.containsKey('y') &&
          data.containsKey('x2') &&
          data.containsKey('y2')) {
        entities.add(DXFEntity(
          type: type,
          layer: layer,
          color: color,
          data: data,
        ));
      } else if (type == 'POINT' &&
          data.containsKey('x') &&
          data.containsKey('y')) {
        entities.add(DXFEntity(
          type: type,
          layer: layer,
          color: color,
          data: data,
        ));
      }
    } catch (e) {
      // print('WARNING: Failed to add entity: $e');
      // print('Entity data: $data');
    }
  }

  Color _aciToColor(int aci) {
    const aciColors = {
      1: Color(0xFFFF0000), // Red
      2: Color(0xFFFFFF00), // Yellow
      3: Color(0xFF00FF00), // Green
      4: Color(0xFF00FFFF), // Cyan
      5: Color(0xFF0000FF), // Blue
      6: Color(0xFFFF00FF), // Magenta
      7: Color(0xFFFFFFFF), // White
      8: Color(0xFF808080), // Gray
      9: Color(0xFFC0C0C0), // Light Gray
    };
    return aciColors[aci] ?? Colors.white;
  }

  Rect _calculateBounds(List<DXFEntity> entities) {
    if (entities.isEmpty) {
      // print('WARNING: No entities for bounds calculation');
      return const Rect.fromLTRB(0, 0, 100, 100);
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    
    int boundedCount = 0;

    for (final entity in entities) {
      try {
        final data = entity.data;

        if (entity.type == 'LINE') {
          minX = math.min(minX, math.min(data['x'], data['x2']));
          maxX = math.max(maxX, math.max(data['x'], data['x2']));
          minY = math.min(minY, math.min(data['y'], data['y2']));
          maxY = math.max(maxY, math.max(data['y'], data['y2']));
          boundedCount++;
        } else if (entity.type == 'CIRCLE' || entity.type == 'ARC') {
          final r = data['radius'];
          minX = math.min(minX, data['x'] - r);
          maxX = math.max(maxX, data['x'] + r);
          minY = math.min(minY, data['y'] - r);
          maxY = math.max(maxY, data['y'] + r);
          boundedCount++;
        } else if (entity.type == 'LWPOLYLINE' || 
                   entity.type == 'POLYLINE' || 
                   entity.type == 'HATCH' ||
                   entity.type == 'SOLID') {
          final vertices = data['vertices'] as List<Map<String, double>>;
          for (final vertex in vertices) {
            final x = vertex['x']!;
            final y = vertex['y']!;
            minX = math.min(minX, x);
            maxX = math.max(maxX, x);
            minY = math.min(minY, y);
            maxY = math.max(maxY, y);
          }
          if (vertices.isNotEmpty) boundedCount++;
        } else if (entity.type == 'SPLINE') {
          final points = data['points'] as List<Map<String, double>>? ?? [];
          for (final point in points) {
            final x = point['x']!;
            final y = point['y']!;
            minX = math.min(minX, x);
            maxX = math.max(maxX, x);
            minY = math.min(minY, y);
            maxY = math.max(maxY, y);
          }
          if (points.isNotEmpty) boundedCount++;
        } else if (entity.type == 'ELLIPSE') {
          final cx = data['x'];
          final cy = data['y'];
          final majorX = data['x2'];
          final majorY = data['y2'];
          final majorRadius = math.sqrt(majorX * majorX + majorY * majorY);
          minX = math.min(minX, cx - majorRadius);
          maxX = math.max(maxX, cx + majorRadius);
          minY = math.min(minY, cy - majorRadius);
          maxY = math.max(maxY, cy + majorRadius);
          boundedCount++;
        } else if (entity.type == 'POINT') {
          minX = math.min(minX, data['x']);
          maxX = math.max(maxX, data['x']);
          minY = math.min(minY, data['y']);
          maxY = math.max(maxY, data['y']);
          boundedCount++;
        }
      } catch (e) {
        // print('WARNING: Error calculating bounds for entity ${entity.type}: $e');
      }
    }
    
    // print('Bounded $boundedCount/${entities.length} entities');
    // print('Raw bounds: minX=$minX, minY=$minY, maxX=$maxX, maxY=$maxY');

    if (minX == double.infinity || maxX == double.negativeInfinity) {
      // print('ERROR: Invalid bounds, using default');
      return const Rect.fromLTRB(0, 0, 100, 100);
    }

    // Add 10% padding
    final width = maxX - minX;
    final height = maxY - minY;
    final paddingX = width * 0.1;
    final paddingY = height * 0.1;

    return Rect.fromLTRB(
      minX - paddingX,
      minY - paddingY,
      maxX + paddingX,
      maxY + paddingY,
    );
  }
}

// Canvas Widget
class DXFCanvas extends StatefulWidget {
  final DXFData dxfData;
  final Color backgroundColor;
  final bool showFills;
  final double fillOpacity;
  final bool invertColors;
  final Function(Color) onBackgroundColorChanged;
  final Function(bool) onShowFillsChanged;
  final Function(double) onFillOpacityChanged;
  final Function(bool) onInvertColorsChanged;
  final VoidCallback onReset;

  const DXFCanvas({
    Key? key,
    required this.dxfData,
    required this.backgroundColor,
    required this.showFills,
    required this.fillOpacity,
    required this.invertColors,
    required this.onBackgroundColorChanged,
    required this.onShowFillsChanged,
    required this.onFillOpacityChanged,
    required this.onInvertColorsChanged,
    required this.onReset,
  }) : super(key: key);

  @override
  State<DXFCanvas> createState() => _DXFCanvasState();
}

class _DXFCanvasState extends State<DXFCanvas> {
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  Offset? _lastFocalPoint;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoFitView();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _autoFitView() {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final size = renderBox.size;
      _fitView(size);
    }
  }

  void _fitView(Size size) {
    setState(() {
      final bounds = widget.dxfData.bounds;
      final dxfWidth = bounds.width;
      final dxfHeight = bounds.height;

      if (dxfWidth == 0 || dxfHeight == 0) {
        _offset = Offset.zero;
        _scale = 1.0;
        return;
      }

      _scale = 1.0;
      _offset = Offset.zero;
      
      // print('Fit view: canvas=${size.width}x${size.height}, bounds=${dxfWidth}x${dxfHeight}');
    });
  }

  void _showBackgroundColorPicker() {
    final colors = [
      const Color(0xFF000000),
      const Color(0xFF1a1a1a),
      const Color(0xFF2b2b2b),
      const Color(0xFF404040),
      const Color(0xFF1e3a4f),
      const Color(0xFF2d4a5c),
      const Color(0xFF4a90c4),
      const Color(0xFF808080),
      const Color(0xFFc0c0c0),
      const Color(0xFFffffff),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2b2b2b),
        title: Text(
          'Select Background Color',
          style: TextStyle(color: Colors.grey.shade300),
        ),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            return InkWell(
              onTap: () {
                widget.onBackgroundColorChanged(color);
                Navigator.pop(context);
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(
                    color: widget.backgroundColor == color
                        ? Colors.blue
                        : Colors.grey.shade600,
                    width: widget.backgroundColor == color ? 3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showFillSettings() {
    // Create local copies of current values
    bool localShowFills = widget.showFills;
    bool localInvertColors = widget.invertColors;
    double localFillOpacity = widget.fillOpacity;
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2b2b2b),
          title: Text(
            'Display Settings',
            style: TextStyle(color: Colors.grey.shade300),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                title: const Text('Show Fills'),
                subtitle: const Text('Toggle HATCH/SOLID entities'),
                value: localShowFills,
                onChanged: (value) {
                  setDialogState(() {
                    localShowFills = value;
                  });
                  widget.onShowFillsChanged(value);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Invert Colors'),
                subtitle: const Text('Better visibility for light colors'),
                value: localInvertColors,
                onChanged: (value) {
                  setDialogState(() {
                    localInvertColors = value;
                  });
                  widget.onInvertColorsChanged(value);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Fill Opacity: ${(localFillOpacity * 100).toInt()}%',
                style: TextStyle(color: Colors.grey.shade300),
              ),
              Slider(
                value: localFillOpacity,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label: '${(localFillOpacity * 100).toInt()}%',
                onChanged: (value) {
                  setDialogState(() {
                    localFillOpacity = value;
                  });
                  widget.onFillOpacityChanged(value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  setState(() {
                    final delta = event.scrollDelta.dy;
                    final zoomFactor = delta > 0 ? 0.9 : 1.1;
                    _scale = (_scale * zoomFactor).clamp(0.1, 10.0);
                  });
                }
              },
              child: KeyboardListener(
                focusNode: _focusNode,
                onKeyEvent: (event) {
                  if (event is KeyDownEvent) {
                    setState(() {
                      if (event.logicalKey.keyLabel == '+' || 
                          event.logicalKey.keyLabel == '=') {
                        _scale = (_scale * 1.1).clamp(0.1, 10.0);
                      } else if (event.logicalKey.keyLabel == '-') {
                        _scale = (_scale * 0.9).clamp(0.1, 10.0);
                      }
                    });
                  }
                },
                child: GestureDetector(
                  onScaleStart: (details) {
                    _lastFocalPoint = details.focalPoint;
                    _focusNode.requestFocus();
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      _scale = (_scale * details.scale).clamp(0.1, 10.0);

                      if (_lastFocalPoint != null) {
                        _offset += details.focalPoint - _lastFocalPoint!;
                      }
                      _lastFocalPoint = details.focalPoint;
                    });
                  },
                  onScaleEnd: (details) {
                    _lastFocalPoint = null;
                  },
                  child: CustomPaint(
                    painter: DXFPainter(
                      dxfData: widget.dxfData,
                      offset: _offset,
                      scale: _scale,
                      showFills: widget.showFills,
                      fillOpacity: widget.fillOpacity,
                      invertColors: widget.invertColors,
                    ),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Row(
                children: [
                  // DEBUG BUTTON REMOVED FOR PRODUCTION
                  // Material(
                  //   elevation: 4,
                  //   borderRadius: BorderRadius.circular(4),
                  //   color: const Color(0xFF3c3c3c),
                  //   child: InkWell(
                  //     onTap: () {
                  //       // Force show fills for debugging
                  //       widget.onShowFillsChanged(true);
                  //       print('DEBUG: Forced fills ON');
                  //     },
                  //     borderRadius: BorderRadius.circular(4),
                  //     child: Padding(
                  //       padding: const EdgeInsets.symmetric(
                  //         horizontal: 12,
                  //         vertical: 8,
                  //       ),
                  //       child: Row(
                  //         mainAxisSize: MainAxisSize.min,
                  //         children: [
                  //           Icon(Icons.bug_report, size: 18, color: Colors.orange),
                  //           const SizedBox(width: 6),
                  //           Text(
                  //             'DEBUG',
                  //             style: TextStyle(
                  //               color: Colors.orange,
                  //               fontSize: 12,
                  //               fontWeight: FontWeight.bold,
                  //             ),
                  //           ),
                  //         ],
                  //       ),
                  //     ),
                  //   ),
                  // ),
                  // const SizedBox(width: 8),
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(4),
                    color: const Color(0xFF3c3c3c),
                    child: InkWell(
                      onTap: widget.onReset,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close, size: 20, color: Colors.grey.shade300),
                            const SizedBox(width: 8),
                            Text(
                              'Reset',
                              style: TextStyle(
                                color: Colors.grey.shade300,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(4),
                    color: const Color(0xFF3c3c3c),
                    child: InkWell(
                      onTap: () => _fitView(constraints.biggest),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fit_screen, size: 20, color: Colors.grey.shade300),
                            const SizedBox(width: 8),
                            Text(
                              'Fit View',
                              style: TextStyle(
                                color: Colors.grey.shade300,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(4),
                    color: const Color(0xFF3c3c3c),
                    child: InkWell(
                      onTap: _showBackgroundColorPicker,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: widget.backgroundColor,
                                border: Border.all(color: Colors.grey.shade600),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.palette, size: 20, color: Colors.grey.shade300),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(4),
                    color: const Color(0xFF3c3c3c),
                    child: InkWell(
                      onTap: _showFillSettings,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.showFills ? Icons.format_color_fill : Icons.format_color_reset,
                              size: 20,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Fills',
                              style: TextStyle(
                                color: Colors.grey.shade300,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// Custom Painter
class DXFPainter extends CustomPainter {
  final DXFData dxfData;
  final Offset offset;
  final double scale;
  final bool showFills;
  final double fillOpacity;
  final bool invertColors;

  DXFPainter({
    required this.dxfData,
    required this.offset,
    required this.scale,
    required this.showFills,
    required this.fillOpacity,
    required this.invertColors,
  });

  Color _processColor(Color original) {
    if (!invertColors) return original;
    
    // Invert RGB but keep alpha
    return Color.fromARGB(
      original.alpha,
      255 - original.red,
      255 - original.green,
      255 - original.blue,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = dxfData.bounds;
    final dxfWidth = bounds.width;
    final dxfHeight = bounds.height;

    // print('=== PAINT DEBUG ===');
    // print('Canvas size: ${size.width} x ${size.height}');
    // print('DXF bounds: $bounds');
    // print('DXF size: $dxfWidth x $dxfHeight');
    // print('Total entities: ${dxfData.entities.length}');
    // print('Total layers: ${dxfData.layers.length}');
    
    // Count visible entities
    // int visibleCount = 0;
    // for (final entity in dxfData.entities) {
    //   final layer = dxfData.layers[entity.layer];
    //   if (layer != null && layer.visible) visibleCount++;
    // }
    // print('Visible entities: $visibleCount');

    if (dxfWidth == 0 || dxfHeight == 0) {
      // print('ERROR: Invalid DXF dimensions, cannot render');
      // Draw error indicator
      final paint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(Rect.fromLTWH(10, 10, size.width - 20, size.height - 20), paint);
      canvas.drawLine(Offset(10, 10), Offset(size.width - 10, size.height - 10), paint);
      canvas.drawLine(Offset(size.width - 10, 10), Offset(10, size.height - 10), paint);
      return;
    }

    // Calculate base scale to fit
    final scaleX = (size.width * 0.9) / dxfWidth;
    final scaleY = (size.height * 0.9) / dxfHeight;
    final baseScale = math.min(scaleX, scaleY);
    final totalScale = baseScale * scale;
    
    // print('Scale: base=$baseScale, user=$scale, total=$totalScale');

    // Calculate center
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final dxfCenterX = (bounds.left + bounds.right) / 2;
    final dxfCenterY = (bounds.top + bounds.bottom) / 2;
    
    // print('Centers: canvas=($centerX, $centerY), dxf=($dxfCenterX, $dxfCenterY)');
    // print('==================');

    // CRITICAL FIX: Render in two passes
    // Pass 1: Filled entities (background) - only if showFills is true
    if (showFills) {
      for (final entity in dxfData.entities) {
        final layer = dxfData.layers[entity.layer];
        if (layer == null || !layer.visible) continue;
        
        if (entity.type == 'HATCH' || entity.type == 'SOLID') {
          _renderEntity(canvas, entity, layer, totalScale, centerX, centerY, dxfCenterX, dxfCenterY, true);
        }
      }
    }
    
    // Pass 2: Outline entities (foreground)
    for (final entity in dxfData.entities) {
      final layer = dxfData.layers[entity.layer];
      if (layer == null || !layer.visible) continue;
      
      if (entity.type != 'HATCH' && entity.type != 'SOLID') {
        _renderEntity(canvas, entity, layer, totalScale, centerX, centerY, dxfCenterX, dxfCenterY, false);
      }
    }
  }

  void _renderEntity(Canvas canvas, DXFEntity entity, DXFLayer layer, double totalScale,
      double centerX, double centerY, double dxfCenterX, double dxfCenterY, bool isFillPass) {
    // Use layer color if available, otherwise use entity color
    final isFilledEntity = entity.type == 'HATCH' || entity.type == 'SOLID';
    
    // Apply color inversion if enabled
    Color baseColor = invertColors ? _processColor(layer.color) : layer.color;
    
    final renderColor = (isFilledEntity && isFillPass)
        ? baseColor.withOpacity(fillOpacity)  // Adjustable opacity for fills
        : baseColor;
    
    final paint = Paint()
      ..color = renderColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final data = entity.data;

    if (entity.type == 'LINE') {
      final x1 = (data['x'] - dxfCenterX) * totalScale + centerX + offset.dx;
      final y1 = -(data['y'] - dxfCenterY) * totalScale + centerY + offset.dy;
      final x2 = (data['x2'] - dxfCenterX) * totalScale + centerX + offset.dx;
      final y2 = -(data['y2'] - dxfCenterY) * totalScale + centerY + offset.dy;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    } else if (entity.type == 'CIRCLE') {
      final cx = (data['x'] - dxfCenterX) * totalScale + centerX + offset.dx;
      final cy = -(data['y'] - dxfCenterY) * totalScale + centerY + offset.dy;
      final r = data['radius'] * totalScale;
      canvas.drawCircle(Offset(cx, cy), r, paint);
    } else if (entity.type == 'ARC') {
      final cx = (data['x'] - dxfCenterX) * totalScale + centerX + offset.dx;
      final cy = -(data['y'] - dxfCenterY) * totalScale + centerY + offset.dy;
      final r = data['radius'] * totalScale;
      final startAngle = -data['end_angle'] * math.pi / 180;
      final sweepAngle = -(data['start_angle'] - data['end_angle']) * math.pi / 180;
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
    } else if (entity.type == 'LWPOLYLINE' || entity.type == 'POLYLINE') {
      try {
        final vertices = data['vertices'] as List<Map<String, double>>;
        if (vertices.length < 2) return;

        final path = Path();
        final firstVertex = vertices[0];
        final x = (firstVertex['x']! - dxfCenterX) * totalScale + centerX + offset.dx;
        final y = -(firstVertex['y']! - dxfCenterY) * totalScale + centerY + offset.dy;
        path.moveTo(x, y);

        for (int i = 1; i < vertices.length; i++) {
          final vertex = vertices[i];
          final vx = (vertex['x']! - dxfCenterX) * totalScale + centerX + offset.dx;
          final vy = -(vertex['y']! - dxfCenterY) * totalScale + centerY + offset.dy;
          path.lineTo(vx, vy);
        }

        final flags = data['flags'] as int? ?? 0;
        if (flags & 1 == 1) path.close();
        canvas.drawPath(path, paint);
      } catch (e) {
        // print('WARNING: Error rendering polyline: $e');
      }
    } else if (entity.type == 'SPLINE') {
      try {
        final points = data['points'] as List<Map<String, double>>? ?? [];
        if (points.length < 2) return;

        final path = Path();
        final firstPoint = points[0];
        final x = (firstPoint['x']! - dxfCenterX) * totalScale + centerX + offset.dx;
        final y = -(firstPoint['y']! - dxfCenterY) * totalScale + centerY + offset.dy;
        path.moveTo(x, y);

        // Draw SPLINE as connected line segments through control points
        for (int i = 1; i < points.length; i++) {
          final point = points[i];
          final px = (point['x']! - dxfCenterX) * totalScale + centerX + offset.dx;
          final py = -(point['y']! - dxfCenterY) * totalScale + centerY + offset.dy;
          path.lineTo(px, py);
        }

        canvas.drawPath(path, paint);
      } catch (e) {
        // print('WARNING: Error rendering SPLINE: $e');
      }
    } else if ((entity.type == 'HATCH' || entity.type == 'SOLID') && isFillPass) {
      try {
        final vertices = data['vertices'] as List<Map<String, double>>;
        if (vertices.isEmpty) return;

        final path = Path();
        final firstVertex = vertices[0];
        final x = (firstVertex['x']! - dxfCenterX) * totalScale + centerX + offset.dx;
        final y = -(firstVertex['y']! - dxfCenterY) * totalScale + centerY + offset.dy;
        path.moveTo(x, y);

        for (int i = 1; i < vertices.length; i++) {
          final vertex = vertices[i];
          final vx = (vertex['x']! - dxfCenterX) * totalScale + centerX + offset.dx;
          final vy = -(vertex['y']! - dxfCenterY) * totalScale + centerY + offset.dy;
          path.lineTo(vx, vy);
        }

        path.close();
        paint.style = PaintingStyle.fill;
        canvas.drawPath(path, paint);
      } catch (e) {
        // print('WARNING: Error rendering ${entity.type}: $e');
      }
    } else if (entity.type == 'ELLIPSE') {
      final cx = (data['x'] - dxfCenterX) * totalScale + centerX + offset.dx;
      final cy = -(data['y'] - dxfCenterY) * totalScale + centerY + offset.dy;
      final majorX = data['x2'] * totalScale;
      final majorY = -data['y2'] * totalScale;
      final majorRadius = math.sqrt(majorX * majorX + majorY * majorY);
      final minorRadius = majorRadius * (data['radius'] ?? 1.0);
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: majorRadius * 2,
        height: minorRadius * 2,
      );
      canvas.drawOval(rect, paint);
    } else if (entity.type == 'POINT') {
      final x = (data['x'] - dxfCenterX) * totalScale + centerX + offset.dx;
      final y = -(data['y'] - dxfCenterY) * totalScale + centerY + offset.dy;
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 2.0, paint);
    }
  }

  @override
  bool shouldRepaint(DXFPainter oldDelegate) {
    return oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.dxfData != dxfData ||
        oldDelegate.showFills != showFills ||
        oldDelegate.fillOpacity != fillOpacity ||
        oldDelegate.invertColors != invertColors;
  }
}

// Layer Panel Widget
class LayerPanel extends StatefulWidget {
  final DXFData dxfData;
  final Function(String, bool) onLayerToggle;

  const LayerPanel({
    Key? key,
    required this.dxfData,
    required this.onLayerToggle,
  }) : super(key: key);

  @override
  State<LayerPanel> createState() => _LayerPanelState();
}

class _LayerPanelState extends State<LayerPanel> {
  bool _allLayersVisible = true;

  void _toggleAllLayers(bool? value) {
    if (value == null) return;
    
    setState(() {
      _allLayersVisible = value;
      // Update all layers
      for (final layerName in widget.dxfData.layers.keys) {
        widget.dxfData.layers[layerName]!.visible = value;
        widget.onLayerToggle(layerName, value);
      }
    });
  }

  void _updateAllLayersState() {
    // Check if all layers are visible
    final allVisible = widget.dxfData.layers.values.every((layer) => layer.visible);
    final anyVisible = widget.dxfData.layers.values.any((layer) => layer.visible);
    
    if (allVisible) {
      _allLayersVisible = true;
    } else if (!anyVisible) {
      _allLayersVisible = false;
    }
  }

  void _showLayerColorPicker(String layerName, DXFLayer layer) {
    final colors = [
      const Color(0xFFFF0000), // Red
      const Color(0xFFFFFF00), // Yellow
      const Color(0xFF00FF00), // Green
      const Color(0xFF00FFFF), // Cyan
      const Color(0xFF0000FF), // Blue
      const Color(0xFFFF00FF), // Magenta
      const Color(0xFFFFFFFF), // White
      const Color(0xFF808080), // Gray
      const Color(0xFFC0C0C0), // Light Gray
      const Color(0xFFFF8000), // Orange
      const Color(0xFF8000FF), // Purple
      const Color(0xFF00FF80), // Spring Green
      const Color(0xFF0080FF), // Sky Blue
      const Color(0xFFFF0080), // Pink
      const Color(0xFF80FF00), // Lime
      const Color(0xFF000000), // Black
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2b2b2b),
        title: Text(
          'Select Color for "$layerName"',
          style: TextStyle(color: Colors.grey.shade300, fontSize: 14),
        ),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            return InkWell(
              onTap: () {
                setState(() {
                  layer.color = color;
                });
                Navigator.pop(context);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(
                    color: layer.color == color
                        ? Colors.blue
                        : Colors.grey.shade600,
                    width: layer.color == color ? 3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _updateAllLayersState();
    
    final sortedLayers = widget.dxfData.layers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      children: [
        // All Layers toggle at the top
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2b2b2b),
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade800),
            ),
          ),
          child: CheckboxListTile(
            dense: true,
            title: Text(
              'All Layers',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade300,
              ),
            ),
            value: _allLayersVisible,
            onChanged: _toggleAllLayers,
            controlAffinity: ListTileControlAffinity.trailing,
          ),
        ),
        // Individual layers list
        Expanded(
          child: ListView.builder(
            itemCount: sortedLayers.length,
            itemBuilder: (context, index) {
              final entry = sortedLayers[index];
              final layerName = entry.key;
              final layer = entry.value;

              return ListTile(
                dense: true,
                leading: InkWell(
                  onTap: () => _showLayerColorPicker(layerName, layer),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: layer.color,
                      border: Border.all(color: Colors.grey.shade700),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                title: Text(
                  layerName,
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: Checkbox(
                  value: layer.visible,
                  onChanged: (value) {
                    widget.onLayerToggle(layerName, value ?? true);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}