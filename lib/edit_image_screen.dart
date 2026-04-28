import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';

class EditImageScreen extends StatefulWidget {
  final Uint8List imageData;

  const EditImageScreen({super.key, required this.imageData});

  @override
  State<EditImageScreen> createState() => _EditImageScreenState();
}

class _EditImageScreenState extends State<EditImageScreen> {
  final _cropController = CropController();
  int _rotationTurns = 0;

  double _brightness = 0.0;
  double _contrast = 0.0;
  double _saturation = 0.0;

  // We need the image dimensions to fix the NaN layout error
  double? _imageWidth;
  double? _imageHeight;

  @override
  void initState() {
    super.initState();
    _loadImageDimensions();
  }

  Future<void> _loadImageDimensions() async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(widget.imageData);
    final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(buffer);
    setState(() {
      _imageWidth = descriptor.width.toDouble();
      _imageHeight = descriptor.height.toDouble();
    });
  }

  List<double> _calculateColorMatrix() {
    double s = _saturation + 1;
    const double lumR = 0.2126;
    const double lumG = 0.7152;
    const double lumB = 0.0722;
    double sr = (1 - s) * lumR;
    double sg = (1 - s) * lumG;
    double sb = (1 - s) * lumB;

    List<double> matrix = [
      sr + s, sg,     sb,     0, 0,
      sr,     sg + s, sb,     0, 0,
      sr,     sg,     sb + s, 0, 0,
      0,      0,      0,      1, 0,
    ];

    double c = _contrast + 1;
    double offset = 128 * (1 - c);
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 4; j++) {
        matrix[i * 5 + j] *= c;
      }
      matrix[i * 5 + 4] += offset;
    }

    double b = _brightness * 255;
    matrix[4] += b;
    matrix[9] += b;
    matrix[14] += b;

    return matrix;
  }

  Future<Uint8List> _applyFilterToBytes(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final ui.Image image = frameInfo.image;

    final bool isVertical = _rotationTurns % 2 != 0;
    final double targetWidth = isVertical ? image.height.toDouble() : image.width.toDouble();
    final double targetHeight = isVertical ? image.width.toDouble() : image.height.toDouble();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    canvas.translate(targetWidth / 2, targetHeight / 2);
    canvas.rotate(_rotationTurns * math.pi / 2);
    canvas.translate(-image.width / 2, -image.height / 2);

    final Paint paint = Paint()
      ..colorFilter = ui.ColorFilter.matrix(_calculateColorMatrix());

    canvas.drawImage(image, Offset.zero, paint);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image filteredImage = await picture.toImage(targetWidth.toInt(), targetHeight.toInt());
    final ByteData? byteData = await filteredImage.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Edit Image'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_right),
            onPressed: () => setState(() => _rotationTurns++),
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => _cropController.crop(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _imageWidth == null
                ? const Center(child: CircularProgressIndicator())
                : Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: RotatedBox(
                    quarterTurns: _rotationTurns,
                    child: SizedBox(
                      // Setting explicit dimensions prevents the NaN error
                      width: _imageWidth,
                      height: _imageHeight,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(_calculateColorMatrix()),
                        child: Crop(
                          image: widget.imageData,
                          controller: _cropController,
                          onCropped: (result) async {
                            if (result is CropSuccess) {
                              final finalImage = await _applyFilterToBytes(result.croppedImage);
                              if (mounted) Navigator.pop(context, finalImage);
                            } else if (result is CropFailure) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cropping failed')),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: [
                _buildSlider('Brightness', _brightness, -1, 1, (v) => setState(() => _brightness = v)),
                _buildSlider('Contrast', _contrast, -1, 1, (v) => setState(() => _contrast = v)),
                _buildSlider('Saturation', _saturation, -1, 1, (v) => setState(() => _saturation = v)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
      ],
    );
  }
}