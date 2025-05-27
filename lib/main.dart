import 'dart:io';

import 'package:animated_tree_view/animated_tree_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Change this to your preferred startup folder
const String defaultPath = r"C:\";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'File Collector',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const FileCollectorPage(),
    );
  }
}

class FileCollectorPage extends StatefulWidget {
  const FileCollectorPage({super.key});
  @override
  State<FileCollectorPage> createState() => _FileCollectorPageState();
}

class _FileCollectorPageState extends State<FileCollectorPage> {
  /// The invisible root node; we'll show only its children
  late final TreeNode root = TreeNode.root();

  /// All file paths in the tree; used to detect files vs folders
  final Set<String> filePaths = {};

  /// Which files are checked for download
  final Set<String> _selectedFiles = {};

  /// Controller we get back once the TreeView is ready
  TreeViewController<TreeNode>? _controller;

  @override
  void initState() {
    super.initState();
    _loadFileTree();
  }

  /// Recursively builds TreeNode children under [path]
  Future<List<TreeNode>> _buildNodes(String path) async {
    final List<TreeNode> list = [];
    try {
      final dir = Directory(path);
      final entities = dir.listSync();
      entities.sort((a, b) {
        // directories first, then alphabetic
        if (a is Directory && b is File) return -1;
        if (a is File && b is Directory) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      for (final e in entities) {
        final key = e.path;
        if (e is Directory) {
          final node = TreeNode(key: key);
          final children = await _buildNodes(key);
          if (children.isNotEmpty) node.addAll(children);
          list.add(node);
        } else if (e is File) {
          list.add(TreeNode(key: key));
          filePaths.add(key);
        }
      }
    } catch (_) {
      // ignore unreadable folders
    }
    return list;
  }

  Future<void> _loadFileTree() async {
    final children = await _buildNodes(defaultPath);
    setState(() {
      root
        ..children.clear()
        ..addAll(children);
    });
  }

  /// Called when you tap any node
  void _onItemTap(TreeNode node) async {
    final key = node.key;
    // If it’s a file → copy to clipboard
    if (filePaths.contains(key)) {
      try {
        final text = await File(key).readAsString();
        await Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied "${p.basename(key)}" to clipboard')),
        );
      } catch (_) {}
    } else {
      // Directory → toggle expand/collapse
      if (_controller != null) {
        if (node.isExpanded) {
          _controller!.collapseNode(node);
        } else {
          _controller!.expandNode(node);
        }
      }
    }
  }

  /// Renders each node: folder icon vs file+checkbox
  Widget _nodeBuilder(BuildContext context, TreeNode node) {
    final key = node.key;
    final isFile = filePaths.contains(key);
    final checked = _selectedFiles.contains(key);
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Row(
        children: [
          if (isFile)
            Checkbox(
              value: checked,
              onChanged: (v) {
                setState(() {
                  if (v == true)
                    _selectedFiles.add(key);
                  else
                    _selectedFiles.remove(key);
                });
              },
            )
          else
            const SizedBox(width: 40),
          Icon(
            isFile ? Icons.insert_drive_file : Icons.folder,
            size: 18,
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(p.basename(key))),
        ],
      ),
    );
  }

  /// Concatenate all checked files and write to Downloads/collected.txt
  Future<void> _downloadSelected() async {
    final buffer = StringBuffer();
    for (final path in _selectedFiles) {
      try {
        buffer.writeln(await File(path).readAsString());
        buffer.writeln('\n');
      } catch (_) {}
    }
    Directory? dl = await getDownloadsDirectory();
    final downloadsPath = dl?.path ??
        (Platform.environment['USERPROFILE']! + r'\Downloads');
    final outFile = File(p.join(downloadsPath, 'collected.txt'));
    await outFile.writeAsString(buffer.toString());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved to ${outFile.path}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('File Collector')),
      body: root.children.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TreeView.simple(
        tree: root,
        showRootNode: false,
        // ± expander indicator :contentReference[oaicite:1]{index=1}
        expansionIndicatorBuilder: (ctx, node) =>
            PlusMinusIndicator(tree: node),
        // square-joint connector lines :contentReference[oaicite:2]{index=2}
        indentation: const Indentation(style: IndentStyle.squareJoint),
        onTreeReady: (ctr) => _controller = ctr,
        onItemTap: _onItemTap,
        builder: _nodeBuilder,
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Download selected files',
        onPressed: _downloadSelected,
        child: const Icon(Icons.download),
      ),
    );
  }
}
