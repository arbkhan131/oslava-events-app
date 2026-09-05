import 'package:flutter/material.dart';

class WorkerMyWorkScreen extends StatelessWidget {
  const WorkerMyWorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Work'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Confirmed'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [
              _EmptyWorkState(label: 'No confirmed work yet'),
              _EmptyWorkState(label: 'No completed work yet'),
              _EmptyWorkState(label: 'No cancelled work yet'),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyWorkState extends StatelessWidget {
  const _EmptyWorkState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(label));
  }
}
