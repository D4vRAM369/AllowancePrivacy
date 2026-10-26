import 'package:budget_simple/pages/about_page.dart';
import 'package:budget_simple/pages/main_page_layout.dart';
import 'package:budget_simple/pages/transactions_history_page.dart';
import 'package:budget_simple/struct/database_global.dart';
import 'package:budget_simple/struct/functions.dart';
import 'package:flutter/material.dart';

class TopHeaderButtons extends StatelessWidget {
  const TopHeaderButtons({required this.large, super.key});
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Transform.translate(
          offset: const Offset(20, 0),
          child: IconButton(
            tooltip:
                amountsHidden.value ? 'Mostrar importes' : 'Ocultar importes',
            onPressed: () => amountsHidden.value = !amountsHidden.value,
            icon: Icon(amountsHidden.value
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            padding:
                large ? const EdgeInsets.all(20) : const EdgeInsets.all(15),
          ),
        ),
        getIsFullScreen(context)
            ? const SizedBox.shrink()
            : Transform.translate(
                offset: const Offset(10, 0),
                child: IconButton(
                  onPressed: () {
                    pushRoute(context, const TransactionsHistoryPage());
                  },
                  icon: const Icon(Icons.receipt),
                  padding: large
                      ? const EdgeInsets.all(20)
                      : const EdgeInsets.all(15),
                ),
              ),
        IconButton(
          onPressed: () {
            pushRoute(context, const AboutPage());
          },
          icon: const Icon(Icons.settings),
          padding: large ? const EdgeInsets.all(20) : const EdgeInsets.all(15),
        ),
      ],
    );
  }
}
