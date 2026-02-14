import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';



void main() {
  runApp(const DXFViewerApp());
}

class DXFViewerApp extends StatelessWidget {
  const DXFViewerApp({Key? key}) : super(key: key);

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
      home: const DXFViewerHome(),
    );
  }
}

class DXFViewerHome extends StatefulWidget {
  const DXFViewerHome({Key? key}) : super(key: key);

  @override
  State<DXFViewerHome> createState() => _DXFViewerHomeState();
}

class _DXFViewerHomeState extends State<DXFViewerHome> {
  DXFData? _dxfData;
  String? _filename;
  bool _isDragging = false;
  bool _layersPanelCollapsed = false;
  Color _backgroundColor = const Color(0xFF2b2b2b);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_filename ?? 'DXF Viewer'),
        backgroundColor: const Color(0xFF2b2b2b),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFile,
            tooltip: 'Open DXF File',
          ),
        ],
      ),
      body: DropTarget(
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
        child: Row(
          children: [
            // Main canvas area
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
                                'Drag & Drop DXF file here',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'or use the folder icon above',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        )
                      : DXFCanvas(
                          dxfData: _dxfData!,
                          backgroundColor: _backgroundColor,
                          onBackgroundColorChanged: (color) {
                            setState(() => _backgroundColor = color);
                          },
                          onReset: _resetView,
                        ),
                ),
              ),
            ),
            // Layer panel with collapse button
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
                          // Layers header with collapse button
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Layers',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
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
        ),
      ),
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

  Future<void> _loadFile(String filepath) async {
    try {
      print('Loading DXF file: $filepath');
      final parser = DXFParser();
      final data = await parser.parse(filepath);

      print('Parsed ${data.entities.length} entities');
      print('Found ${data.layers.length} layers: ${data.layers.keys.toList()}');
      print('Bounds: ${data.bounds}');

      setState(() {
        _dxfData = data;
        _filename = filepath.split(Platform.pathSeparator).last;
      });
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
  final Color color;

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
  Future<DXFData> parse(String filepath) async {
    try {
      final file = File(filepath);
      final lines = await file.readAsLines();

      final entities = <DXFEntity>[];
      final layers = <String, DXFLayer>{};

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

      // Parse entities - start right after ENTITIES line
      int i = entitiesStart + 1;
      Map<String, dynamic>? currentEntity;

      print('DEBUG: Starting entity parsing at line $i');
      print('DEBUG: First few lines: ${lines.sublist(i, math.min(i + 10, lines.length))}');

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
                print('WARNING: Failed to add entity ${currentEntity['type']}: $e');
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
              };
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
                        color: Colors.white,
                      );
                    }
                    break;
                  case 10: // X coordinate (or first X for polyline vertex)
                    if (currentEntity['type'] == 'LWPOLYLINE' || 
                        currentEntity['type'] == 'POLYLINE' ||
                        currentEntity['type'] == 'HATCH') {
                      // Add to vertices list
                      currentEntity['last_x'] = double.tryParse(value) ?? 0.0;
                    } else {
                      currentEntity['x'] = double.tryParse(value) ?? 0.0;
                    }
                    break;
                  case 20: // Y coordinate (or first Y for polyline vertex)
                    if (currentEntity['type'] == 'LWPOLYLINE' || 
                        currentEntity['type'] == 'POLYLINE' ||
                        currentEntity['type'] == 'HATCH') {
                      // Complete the vertex and add it
                      if (currentEntity.containsKey('last_x')) {
                        final vertices = currentEntity['vertices'] as List<Map<String, double>>;
                        vertices.add({
                          'x': currentEntity['last_x'] as double,
                          'y': double.tryParse(value) ?? 0.0,
                        });
                        currentEntity.remove('last_x');
                      }
                    } else {
                      currentEntity['y'] = double.tryParse(value) ?? 0.0;
                    }
                    break;
                  case 11: // X2 coordinate / major axis endpoint X
                    currentEntity['x2'] = double.tryParse(value) ?? 0.0;
                    break;
                  case 21: // Y2 coordinate / major axis endpoint Y
                    currentEntity['y2'] = double.tryParse(value) ?? 0.0;
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
                  case 62: // Color
                    currentEntity['color'] = _aciToColor(int.tryParse(value) ?? 7);
                    break;
                  case 70: // Flags (closed polyline, etc)
                    currentEntity['flags'] = int.tryParse(value) ?? 0;
                    break;
                  case 90: // Vertex count
                    currentEntity['vertex_count'] = int.tryParse(value) ?? 0;
                    break;
                  case 1: // Text value
                    currentEntity['text'] = value;
                    break;
                  case 7: // Text style
                    currentEntity['text_style'] = value;
                    break;
                }
              } catch (e) {
                print('WARNING: Failed to parse code $codeNum with value "$value": $e');
              }
            }
          }

          i += 2;
        } catch (e) {
          print('WARNING: Error parsing line $i: $e');
          i += 2;
        }
      }

      if (currentEntity != null) {
        try {
          _addEntity(currentEntity, entities, layers);
        } catch (e) {
          print('WARNING: Failed to add final entity: $e');
        }
      }

      // Calculate bounds
      final bounds = _calculateBounds(entities);

      print('Successfully parsed ${entities.length} entities from ${layers.length} layers');

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
          entities.add(DXFEntity(
            type: type,
            layer: layer,
            color: color,
            data: data,
          ));
        }
      } else if (type == 'SOLID' &&
          data.containsKey('vertices')) {
        final vertices = data['vertices'] as List<Map<String, double>>;
        if (vertices.length >= 3) {
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
          entities.add(DXFEntity(
            type: type,
            layer: layer,
            color: color,
            data: data,
          ));
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
      }
    } catch (e) {
      print('WARNING: Failed to add entity: $e');
      print('Entity data: $data');
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
      return const Rect.fromLTRB(0, 0, 100, 100);
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final entity in entities) {
      try {
        final data = entity.data;

        if (entity.type == 'LINE') {
          minX = math.min(minX, math.min(data['x'], data['x2']));
          maxX = math.max(maxX, math.max(data['x'], data['x2']));
          minY = math.min(minY, math.min(data['y'], data['y2']));
          maxY = math.max(maxY, math.max(data['y'], data['y2']));
        } else if (entity.type == 'CIRCLE' || entity.type == 'ARC') {
          final r = data['radius'];
          minX = math.min(minX, data['x'] - r);
          maxX = math.max(maxX, data['x'] + r);
          minY = math.min(minY, data['y'] - r);
          maxY = math.max(maxY, data['y'] + r);
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
        } else if (entity.type == 'ELLIPSE') {
          // Approximate ellipse bounds
          final cx = data['x'];
          final cy = data['y'];
          final majorX = data['x2'];
          final majorY = data['y2'];
          final majorRadius = math.sqrt(majorX * majorX + majorY * majorY);
          minX = math.min(minX, cx - majorRadius);
          maxX = math.max(maxX, cx + majorRadius);
          minY = math.min(minY, cy - majorRadius);
          maxY = math.max(maxY, cy + majorRadius);
        }
      } catch (e) {
        print('WARNING: Error calculating bounds for entity ${entity.type}: $e');
      }
    }

    // Fallback if no valid bounds found
    if (minX == double.infinity || maxX == double.negativeInfinity) {
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
  final Function(Color) onBackgroundColorChanged;
  final VoidCallback onReset;

  const DXFCanvas({
    Key? key,
    required this.dxfData,
    required this.backgroundColor,
    required this.onBackgroundColorChanged,
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
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _fitView(Size size) {
    setState(() {
      _offset = Offset.zero;
      _scale = 1.0;
    });
  }

  void _showBackgroundColorPicker() {
    final colors = [
      const Color(0xFF000000), // Black
      const Color(0xFF1a1a1a), // Very Dark Gray
      const Color(0xFF2b2b2b), // Dark Gray (default)
      const Color(0xFF404040), // Medium Dark Gray
      const Color(0xFF1e3a4f), // Dark Blue
      const Color(0xFF2d4a5c), // Medium Dark Blue
      const Color(0xFF4a90c4), // Light Blue
      const Color(0xFF808080), // Medium Gray
      const Color(0xFFc0c0c0), // Light Gray
      const Color(0xFFffffff), // White
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Canvas
            Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  setState(() {
                    // Zoom with mouse wheel
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
                      // Handle zoom
                      _scale = (_scale * details.scale).clamp(0.1, 10.0);

                      // Handle pan
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
                    ),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            ),
            // Control Buttons
            Positioned(
              top: 16,
              left: 16,
              child: Row(
                children: [
                  // Reset Button
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
                  // Fit View Button
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
                  // Background Color Picker
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

  DXFPainter({
    required this.dxfData,
    required this.offset,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = dxfData.bounds;
    final dxfWidth = bounds.width;
    final dxfHeight = bounds.height;

    if (dxfWidth == 0 || dxfHeight == 0) return;

    // Calculate base scale to fit
    final scaleX = (size.width * 0.9) / dxfWidth;
    final scaleY = (size.height * 0.9) / dxfHeight;
    final baseScale = math.min(scaleX, scaleY);

    // Apply zoom
    final totalScale = baseScale * scale;

    // Calculate center
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final dxfCenterX = (bounds.left + bounds.right) / 2;
    final dxfCenterY = (bounds.top + bounds.bottom) / 2;

    // Render entities
    for (final entity in dxfData.entities) {
      final layer = dxfData.layers[entity.layer];
      if (layer == null || !layer.visible) continue;

      final paint = Paint()
        ..color = entity.color
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      final data = entity.data;

      if (entity.type == 'LINE') {
        final x1 = (data['x'] - dxfCenterX) * totalScale + centerX + offset.dx;
        final y1 =
            -(data['y'] - dxfCenterY) * totalScale + centerY + offset.dy;
        final x2 = (data['x2'] - dxfCenterX) * totalScale + centerX + offset.dx;
        final y2 =
            -(data['y2'] - dxfCenterY) * totalScale + centerY + offset.dy;

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
        final sweepAngle =
            -(data['start_angle'] - data['end_angle']) * math.pi / 180;

        final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
        canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      } else if (entity.type == 'LWPOLYLINE' || entity.type == 'POLYLINE') {
        try {
          final vertices = data['vertices'] as List<Map<String, double>>;
          if (vertices.length < 2) continue;

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

          // Check if closed
          final flags = data['flags'] as int? ?? 0;
          if (flags & 1 == 1) {
            path.close();
          }

          canvas.drawPath(path, paint);
        } catch (e) {
          print('WARNING: Error rendering polyline: $e');
        }
      } else if (entity.type == 'HATCH') {
        try {
          final vertices = data['vertices'] as List<Map<String, double>>;
          if (vertices.isEmpty) continue;

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
          print('WARNING: Error rendering hatch: $e');
        }
      } else if (entity.type == 'SOLID') {
        try {
          final vertices = data['vertices'] as List<Map<String, double>>;
          if (vertices.length < 3) continue;

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
          print('WARNING: Error rendering solid: $e');
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
      }
    }
  }

  @override
  bool shouldRepaint(DXFPainter oldDelegate) {
    return oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.dxfData != dxfData;
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
  @override
  Widget build(BuildContext context) {
    final sortedLayers = widget.dxfData.layers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView.builder(
      itemCount: sortedLayers.length,
      itemBuilder: (context, index) {
        final entry = sortedLayers[index];
        final layerName = entry.key;
        final layer = entry.value;

        return ListTile(
          dense: true,
          leading: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: layer.color,
              border: Border.all(color: Colors.grey.shade700),
              borderRadius: BorderRadius.circular(2),
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
    );
  }
}