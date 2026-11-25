import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/database/database.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/loading_button.dart';
import 'package:interstellar/src/widgets/password_editor.dart';
import 'package:interstellar/src/widgets/text_editor.dart';
import 'package:provider/provider.dart';

@RoutePage()
class LoginConfirmScreen extends StatefulWidget {
  const new(this.software, this.server, {super.key});

  final ServerSoftware software;
  final String server;

  @override
  State<LoginConfirmScreen> createState() => _LoginConfirmScreenState();
}

class _LoginConfirmScreenState extends State<LoginConfirmScreen> {
  final _usernameEmailTextController = TextEditingController();
  final _passwordTextController = TextEditingController();
  final _totpTokenTextController = TextEditingController();
  // Reddit only: the client ID of the user's own installed Reddit app.
  final _redditClientIdTextController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l(context).addAccount)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  widget.server,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  widget.software.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (widget.software == ServerSoftware.lemmy ||
              widget.software == ServerSoftware.piefed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AutofillGroup(
                child: Column(
                  spacing: 12,
                  children: [
                    TextEditor(
                      _usernameEmailTextController,
                      label: l(context).usernameOrEmail,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() {}),
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                    ),
                    PasswordEditor(
                      _passwordTextController,
                      onChanged: (_) => setState(() {}),
                      maxLength: widget.software == ServerSoftware.lemmy
                          ? 60
                          : 128,
                    ),
                    if (widget.software == ServerSoftware.lemmy) ...[
                      TextEditor(
                        _totpTokenTextController,
                        label: l(context).totpToken,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (widget.software == ServerSoftware.reddit)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                spacing: 12,
                children: [
                  TextEditor(
                    _redditClientIdTextController,
                    label: 'Reddit app client ID',
                    onChanged: (_) => setState(() {}),
                  ),
                  const Text(
                    'Create an installed app at reddit.com/prefs/apps and '
                    'paste its client ID here. Set its redirect URI to '
                    'interstellar://auth on mobile, or '
                    'http://localhost:46837 on desktop.',
                  ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Reddit blocks unauthenticated traffic, so there is no
              // guest mode for it.
              if (widget.software != ServerSoftware.reddit)
                OutlinedButton(
                  onPressed: () {
                    final account = '@${widget.server}';
                    context.read<AppController>().setAccount(
                      account,
                      const Account(handle: '', isPushRegistered: false),
                      switchNow: true,
                    );

                    context.router.pop(true);
                  },
                  child: Text(l(context).guest),
                ),
              if (widget.software != ServerSoftware.reddit)
                const SizedBox(width: 12),
              LoadingFilledButton(
                label: Text(l(context).login),
                onPressed:
                    (widget.software == ServerSoftware.lemmy &&
                        (_usernameEmailTextController.text.isEmpty ||
                            _passwordTextController.text.isEmpty))
                    ? null
                    : (widget.software == ServerSoftware.reddit &&
                          _redditClientIdTextController.text.isEmpty)
                    ? null
                    : () async {
                        await context.read<AppController>().login(
                          software: widget.software,
                          server: widget.server,
                          username: _usernameEmailTextController.text,
                          password: _passwordTextController.text,
                          totp: _totpTokenTextController.text,
                          oauthClientId:
                              widget.software == ServerSoftware.reddit
                              ? _redditClientIdTextController.text
                              : null,
                          context: context,
                        );

                        if (!context.mounted) return;

                        context.router.pop(true);
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
