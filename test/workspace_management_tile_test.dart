import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/models/workspace.dart';
import 'package:key_ring/utils/theme_config.dart';
import 'package:key_ring/widgets/workspace_management_tile.dart';

Workspace _workspace({
  String id = 'ws-1',
  String name = '工作',
  String? icon = '💼',
  SyncPolicy policy = SyncPolicy.mobileOnly,
}) {
  return Workspace(id: id, name: name, icon: icon, syncPolicy: policy);
}

Widget _harness(
  Workspace workspace, {
  double? width,
  double textScale = 1.0,
  int itemCount = 3,
  bool isProtected = false,
  int index = 0,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  required VoidCallback onConfigureAccess,
}) {
  final Widget tile = WorkspaceManagementTile(
    key: ValueKey<String>(workspace.id),
    workspace: workspace,
    itemCount: itemCount,
    isProtected: isProtected,
    index: index,
    onEdit: onEdit,
    onDelete: onDelete,
    onConfigureAccess: onConfigureAccess,
  );
  final Widget sized = width == null
      ? tile
      : SizedBox(width: width, child: tile);
  return MaterialApp(
    theme: ThemeConfig.appTheme,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: Center(child: sized)),
  );
}

void main() {
  testWidgets(
    'wide layout shows icon, name, badge, count and separated actions',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          _workspace(),
          width: 800,
          onEdit: () {},
          onDelete: () {},
          onConfigureAccess: () {},
        ),
      );

      expect(find.text('💼'), findsOneWidget);
      expect(find.text('工作'), findsOneWidget);
      expect(find.text('仅移动端'), findsOneWidget);
      expect(find.text('3 项'), findsOneWidget);

      expect(find.byTooltip('访问验证'), findsOneWidget);
      expect(find.byTooltip('编辑'), findsOneWidget);
      expect(find.byTooltip('删除'), findsOneWidget);
      expect(find.byTooltip('拖动排序'), findsOneWidget);
      expect(find.byTooltip('更多'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide actions are aligned 44x44 slots without overlap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        _workspace(),
        width: 800,
        onEdit: () {},
        onDelete: () {},
        onConfigureAccess: () {},
      ),
    );

    final Rect access = tester.getRect(find.byTooltip('访问验证'));
    final Rect edit = tester.getRect(find.byTooltip('编辑'));
    final Rect del = tester.getRect(find.byTooltip('删除'));
    final Rect drag = tester.getRect(find.byTooltip('拖动排序'));

    expect(access.width, closeTo(44, 0.1));
    expect(access.height, closeTo(44, 0.1));
    expect(drag.width, closeTo(44, 0.1));

    // 顺序排列且互不重叠。
    expect(edit.left, greaterThanOrEqualTo(access.right));
    expect(del.left, greaterThanOrEqualTo(edit.right));
    expect(drag.left, greaterThanOrEqualTo(del.right));

    // 右侧动作行垂直对齐（同一水平中线）。
    final double centerY = access.center.dy;
    expect(edit.center.dy, closeTo(centerY, 0.1));
    expect(del.center.dy, closeTo(centerY, 0.1));
    expect(drag.center.dy, closeTo(centerY, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide action callbacks fire independently', (tester) async {
    int edits = 0;
    int deletes = 0;
    int accesses = 0;
    await tester.pumpWidget(
      _harness(
        _workspace(),
        width: 800,
        onEdit: () => edits++,
        onDelete: () => deletes++,
        onConfigureAccess: () => accesses++,
      ),
    );

    await tester.tap(find.byTooltip('访问验证'));
    expect(accesses, 1);
    expect(edits, 0);
    expect(deletes, 0);

    await tester.tap(find.byTooltip('编辑'));
    expect(edits, 1);
    expect(deletes, 0);

    await tester.tap(find.byTooltip('删除'));
    expect(deletes, 1);
  });

  testWidgets('access icon reflects protection state', (tester) async {
    await tester.pumpWidget(
      _harness(
        _workspace(),
        width: 800,
        isProtected: true,
        onEdit: () {},
        onDelete: () {},
        onConfigureAccess: () {},
      ),
    );
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsNothing);
  });

  testWidgets(
    'narrow layout keeps access + drag, merges edit/delete into menu',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      int edits = 0;
      int deletes = 0;
      await tester.pumpWidget(
        _harness(
          _workspace(name: '这是一个名字特别长特别长的工作区用于窄屏验证'),
          isProtected: true,
          onEdit: () => edits++,
          onDelete: () => deletes++,
          onConfigureAccess: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('访问验证'), findsOneWidget);
      expect(find.byTooltip('拖动排序'), findsOneWidget);
      expect(find.byTooltip('更多'), findsOneWidget);
      expect(find.byTooltip('编辑'), findsNothing);
      expect(find.byTooltip('删除'), findsNothing);

      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(deletes, 0);
    },
  );

  testWidgets('narrow layout with large text does not overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(
        _workspace(name: '超大字体下的长工作区名称验证不溢出行为'),
        itemCount: 128,
        isProtected: true,
        textScale: 1.5,
        onEdit: () {},
        onDelete: () {},
        onConfigureAccess: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('128 项'), findsOneWidget);
  });

  testWidgets('provides one drag handle per tile under ReorderableListView', (
    tester,
  ) async {
    final List<Workspace> workspaces = <Workspace>[
      _workspace(id: 'ws-a'),
      _workspace(id: 'ws-b', name: '个人', icon: null, policy: SyncPolicy.full),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeConfig.appTheme,
        home: Scaffold(
          body: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: workspaces.length,
            onReorderItem: (int oldIndex, int newIndex) {},
            itemBuilder: (BuildContext context, int index) =>
                WorkspaceManagementTile(
                  key: ValueKey<String>(workspaces[index].id),
                  workspace: workspaces[index],
                  itemCount: index,
                  isProtected: false,
                  index: index,
                  onEdit: () {},
                  onDelete: () {},
                  onConfigureAccess: () {},
                ),
          ),
        ),
      ),
    );

    expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
    expect(find.text('全设备同步'), findsOneWidget);
    expect(find.text('仅移动端'), findsOneWidget);
    // 未设置图标时回退默认工作区图标。
    expect(find.text(Workspace.defaultIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
