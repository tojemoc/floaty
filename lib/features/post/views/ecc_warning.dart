import 'package:flutter/material.dart';
import 'package:floaty/settings.dart';
import 'package:go_router/go_router.dart';

class EccWarning extends StatefulWidget {
  const EccWarning(this.postId, {super.key, this.discoverable});

  final String postId;
  final bool? discoverable;

  @override
  State<EccWarning> createState() => _EccWarningState();
}

class _EccWarningState extends State<EccWarning> {
  bool seen = false;
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hey friendly warning!',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            widget.discoverable == true
                ? Text(
                    'You are watching video from an undiscoverable channel. Floaty will NEVER show any content from this channel in your Discord RPC.',
                    style: Theme.of(context).textTheme.bodyLarge)
                : Text(
                    'I see you are apart of the ECC Squad! To protect unreleased content from being leaked, Floaty will NEVER show any content from the ECC Squad channel in your Discord RPC. Your Discord RPC is still enabled and will show other content just not anything from the ECC squad.',
                    style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                settings.setBool('eccsquadwarningseen', true);
                context.pushReplacement('/post/${widget.postId}');
              },
              child: const Text('Acknowledge Warning & Return'),
            ),
          ],
        ),
      ),
    );
  }
}
