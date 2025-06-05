import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FileCollectorApp());
}

class FileCollectorApp extends StatefulWidget {
  @override
  _FileCollectorAppState createState() => _FileCollectorAppState();
}

class _FileCollectorAppState extends State<FileCollectorApp> {
  // ← your hardcoded default start directory:
  final Directory defaultDir = Directory(r'E:\src\social_learning');

  List<FileNode> roots = [];

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  void _loadRoot() async {
    if (await defaultDir.exists()) {
      final ents = defaultDir.listSync();
      setState(() {
        roots = ents.map((e) => FileNode(entity: e)).toList();
      });
    } else {
      // Fallback or error message if directory missing
      setState(() {
        roots = [];
      });
    }
  }

  List<_NodeEntry> _visibleNodes() {
    final list = <_NodeEntry>[];
    void traverse(FileNode node, int depth) {
      list.add(_NodeEntry(node: node, depth: depth));
      if (node.isExpanded && node.children != null) {
        for (var c in node.children!) traverse(c, depth + 1);
      }
    }

    for (var r in roots) traverse(r, 0);
    return list;
  }

  Future<void> _toggleNode(FileNode node) async {
    if (node.entity is Directory) {
      if (!node.isExpanded && node.children == null) {
        node.isLoading = true;
        setState(() {});
        final children = (node.entity as Directory).listSync();
        node.children =
            children.map((e) => FileNode(entity: e)).toList();
        node.isLoading = false;
      }
      node.isExpanded = !node.isExpanded;
      setState(() {});
    }
  }

  Future<void> _onFileTap(FileNode node) async {
    if (node.entity is File) {
      final txt = await (node.entity as File).readAsString();
      await Clipboard.setData(ClipboardData(text: txt));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied "${p.basename(node.entity.path)}"')),
      );
    }
  }

  Future<void> _downloadSelected() async {
    final sels = <File>[];
    void collect(FileNode n) {
      if (n.entity is File && n.isSelected) sels.add(n.entity as File);
      if (n.children != null) for (var c in n.children!) collect(c);
    }

    for (var r in roots) collect(r);

    if (sels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No files checked.')),
      );
      return;
    }

    final buf = StringBuffer();
    for (var f in sels) {
      buf.writeln(await f.readAsString());
      buf.writeln('\n');
    }

    // getDownloadsDirectory works on Windows as of path_provider ≥2.0.14
    final downloadsDir = await getDownloadsDirectory() ??
        Directory('${Platform.environment['USERPROFILE']}\\Downloads');
    final outFile = File(
      '${downloadsDir.path}\\collected_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    await outFile.writeAsString(buf.toString());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved to "${outFile.path}"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _visibleNodes();
    return MaterialApp(
      title: 'File Collector',
      home: Scaffold(
        appBar: AppBar(title: Text('File Collector')),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: nodes.length,
                itemBuilder: (ctx, i) {
                  final entry = nodes[i];
                  final node = entry.node;
                  final indent = entry.depth * 16.0;
                  final isDir = node.entity is Directory;
                  return Padding(
                    padding: EdgeInsets.only(left: indent),
                    child: Row(
                      children: [
                        // expand/collapse icon for directories
                        if (isDir)
                          InkWell(
                            onTap: () => _toggleNode(node),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                node.isExpanded ? Icons.remove : Icons.add,
                                size: 16,
                              ),
                            ),
                          )
                        else
                          SizedBox(width: 32),
                        // checkbox for files only
                        if (!isDir)
                          Checkbox(
                            value: node.isSelected,
                            onChanged: (v) {
                              node.isSelected = v ?? false;
                              setState(() {});
                            },
                          ),
                        // file/folder name
                        Expanded(
                          child: InkWell(
                            onTap: () => _onFileTap(node),
                            child: Text(
                              p.basename(node.entity.path),
                              style: TextStyle(
                                color:
                                isDir ? Colors.black87 : Colors.blueAccent,
                                decoration:
                                isDir ? null : TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.all(12),
              child: ElevatedButton.icon(
                icon: Icon(Icons.download),
                label: Text('Download Selected'),
                onPressed: _downloadSelected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds each file/directory in the tree.
class FileNode {
  final FileSystemEntity entity;
  bool isExpanded = false;
  bool isLoading = false;
  bool isSelected = false; // only meaningful for files
  List<FileNode>? children;

  FileNode({required this.entity});
}

/// Pair of node + its depth in the tree for rendering.
class _NodeEntry {
  final FileNode node;
  final int depth;
  _NodeEntry({required this.node, required this.depth});
}
