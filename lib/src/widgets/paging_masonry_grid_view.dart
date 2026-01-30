import 'dart:developer' as developer;

import 'package:fl_paging/src/datasource/data_source.dart';
import 'package:fl_paging/src/widgets/builder.dart';
import 'package:fl_paging/src/widgets/default/empty_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;

import 'base_widget.dart';
import 'default/load_more_widget.dart';
import 'default/paging_default_loading.dart';
import 'paging_state.dart';

/// A paging grid view widget that supports dynamic item heights using masonry layout.
///
/// Unlike [PagingGridView] which requires fixed aspect ratios, [PagingMasonryGridView]
/// allows items to have varying heights based on their content.
///
/// This widget uses a custom masonry layout algorithm without external dependencies.
/// Items are distributed across columns using round-robin distribution.
///
/// Example:
/// ```dart
/// PagingMasonryGridView<MyItem>(
///   crossAxisCount: 2,
///   mainAxisSpacing: 8.0,
///   crossAxisSpacing: 8.0,
///   itemBuilder: (context, item, index) => MyItemWidget(item),
///   pageDataSource: myDataSource,
/// )
/// ```
class PagingMasonryGridView<T> extends BaseWidget<T> {
  static const ROUTE_NAME = 'MasonryGridView';

  final widgets.EdgeInsets? padding;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final bool isEnablePullToRefresh;

  PagingMasonryGridView({
    Key? key,
    this.padding,
    required this.crossAxisCount,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.isEnablePullToRefresh = true,
    required ValueIndexWidgetBuilder<T> itemBuilder,
    WidgetBuilder? emptyBuilder,
    WidgetBuilder? loadingBuilder,
    ErrorBuilder? errorBuilder,
    WidgetBuilder? loadmoreBuilder,
    ScrollViewKeyboardDismissBehavior keyboardDismissBehavior =
        ScrollViewKeyboardDismissBehavior.manual,
    required DataSource<T> pageDataSource,
  })  : assert(crossAxisCount > 0, 'crossAxisCount must be greater than 0'),
        super(
          itemBuilder: itemBuilder,
          emptyBuilder: emptyBuilder,
          loadingBuilder: loadingBuilder,
          errorBuilder: errorBuilder,
          loadmoreBuilder: loadmoreBuilder,
          keyboardDismissBehavior: keyboardDismissBehavior,
          pageDataSource: pageDataSource,
          key: key,
        );

  @override
  MasonryGridViewState<T> createState() => MasonryGridViewState<T>();
}

class MasonryGridViewState<T> extends State<PagingMasonryGridView<T>> {
  static const TAG = 'MasonryGridView';

  PagingState<T> _pagingState = PagingState.loading();
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  void retry() => _loadPage(isRefresh: false);

  void refresh() => _loadPage(isRefresh: true);

  Future<void> _loadPage({bool isRefresh = false}) async {
    developer.log('_loadPage [isRefresh]: [$isRefresh]', name: TAG);

    if (isRefresh) {
      await _handleRefresh();
    } else {
      await _handleLoadMore();
    }
  }

  Future<void> _handleRefresh() async {
    try {
      final value = await widget.pageDataSource.loadPage(isRefresh: true);
      _updateState(PagingState(value, false, widget.pageDataSource.isEndList));
    } catch (error) {
      _updateState(PagingState.error(error));
    }
  }

  Future<void> _handleLoadMore() async {
    // Prevent multiple simultaneous load requests
    if (_isLoadingMore) return;

    if (_pagingState is PagingStateLoading<T>) {
      _isLoadingMore = true;
      try {
        final value = await widget.pageDataSource.loadPage();
        _updateState(
            PagingState(value, false, widget.pageDataSource.isEndList));
      } catch (error) {
        _updateState(PagingState.error(error));
      } finally {
        _isLoadingMore = false;
      }
    } else if (_pagingState is PagingStateError<T>) {
      _updateState(PagingState.loading());
      await _handleLoadMore();
    } else if (_pagingState is PagingStateData<T>) {
      _isLoadingMore = true;
      try {
        final value = await widget.pageDataSource.loadPage();
        final oldState = _pagingState as PagingStateData<T>;

        _updateState(value.isEmpty
            ? oldState.copyWith(
                isLoadMore: false,
                isEndList: true,
              ) as PagingState<T>
            : oldState.copyWith(
                isLoadMore: false,
                isEndList: widget.pageDataSource.isEndList,
                datas: oldState.datas..addAll(value),
              ) as PagingState<T>);
      } catch (error) {
        _updateState(PagingState.error(error));
      } finally {
        _isLoadingMore = false;
      }
    }
  }

  void _updateState(PagingState<T> newState) {
    if (mounted) {
      setState(() => _pagingState = newState);
    }
  }

  void _onScrollEnd(bool isEndList, bool isLoadMore) {
    if (isEndList || isLoadMore || _isLoadingMore) return;
    if (_pagingState is! PagingStateData) return;

    _loadPage();
    _updateState((_pagingState as PagingStateData<T>).copyWith(
      isLoadMore: true,
    ) as PagingState<T>);
  }

  @override
  Widget build(BuildContext context) {
    return _pagingState.when(
      (datas, isLoadMore, isEndList) =>
          _buildDataState(datas, isLoadMore, isEndList),
      loading: () =>
          widget.loadingBuilder?.call(context) ?? PagingDefaultLoading(),
      error: (error) =>
          widget.errorBuilder?.call(context, error) ?? ErrorWidget(error),
    );
  }

  Widget _buildDataState(List<T> datas, bool isLoadMore, bool isEndList) {
    if (datas.isEmpty) {
      return widget.emptyBuilder?.call(context) ?? EmptyWidget();
    }

    final body = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.pixels ==
                notification.metrics.maxScrollExtent) {
          _onScrollEnd(isEndList, isLoadMore);
        }
        return false;
      },
      child: CustomScrollView(
        keyboardDismissBehavior: widget.keyboardDismissBehavior,
        slivers: [
          widgets.SliverPadding(
            padding: widget.padding ?? EdgeInsets.zero,
            sliver: _MasonryGridSliver<T>(
              crossAxisCount: widget.crossAxisCount,
              mainAxisSpacing: widget.mainAxisSpacing,
              crossAxisSpacing: widget.crossAxisSpacing,
              items: datas,
              itemBuilder: widget.itemBuilder,
            ),
          ),
          if (!isEndList)
            SliverToBoxAdapter(
              child: widget.loadmoreBuilder?.call(context) ??
                  widget.loadingBuilder?.call(context) ??
                  LoadMoreWidget(),
            ),
        ],
      ),
    );

    return widget.isEnablePullToRefresh
        ? RefreshIndicator(
            onRefresh: () => _loadPage(isRefresh: true),
            child: body,
          )
        : body;
  }
}

/// Custom sliver widget that implements masonry grid layout
class _MasonryGridSliver<T> extends StatelessWidget {
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final List<T> items;
  final ValueIndexWidgetBuilder<T> itemBuilder;

  const _MasonryGridSliver({
    required this.crossAxisCount,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.items,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = _calculateColumnWidth(constraints.crossAxisExtent);
        final columns = _distributeItemsToColumns(context);

        return SliverToBoxAdapter(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildColumns(columns, columnWidth),
          ),
        );
      },
    );
  }

  double _calculateColumnWidth(double totalWidth) {
    final totalSpacing = crossAxisSpacing * (crossAxisCount - 1);
    return (totalWidth - totalSpacing) / crossAxisCount;
  }

  List<List<Widget>> _distributeItemsToColumns(BuildContext context) {
    final columns = List.generate(
      crossAxisCount,
      (_) => <Widget>[],
      growable: false,
    );

    for (int i = 0; i < items.length; i++) {
      columns[i % crossAxisCount].add(
        Padding(
          padding: EdgeInsets.only(bottom: mainAxisSpacing),
          child: itemBuilder(context, items[i], i),
        ),
      );
    }

    return columns;
  }

  List<Widget> _buildColumns(List<List<Widget>> columns, double columnWidth) {
    final children = <Widget>[];

    for (int i = 0; i < crossAxisCount; i++) {
      children
        ..add(
          SizedBox(
            width: columnWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: columns[i],
            ),
          ),
        )
        ..add(
          i < crossAxisCount - 1
              ? SizedBox(width: crossAxisSpacing)
              : const SizedBox.shrink(),
        );
    }

    return children;
  }
}
