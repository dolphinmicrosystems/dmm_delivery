import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/business_profile.dart';
import '../../services/business_profile_store.dart';
import '../../theme/app_colors.dart';
import '../../util/app_log.dart';
import '../../widgets/surface_card.dart';
import 'save_setting.dart';

/// The business as drivers see it - logo and name in the app bar after they
/// sign in - and where it delivers: country and time zone.
class BusinessCard extends StatelessWidget {
  const BusinessCard({super.key, required this.store});

  final BusinessProfileStore store;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BusinessProfile>(
      stream: store.watch(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLog.owner.error('business profile stream failed', snapshot.error, snapshot.stackTrace);
        }
        final profile = snapshot.data ?? BusinessProfile.empty;
        final country = Country.byCode(profile.country) ?? Country.all.first;
        return SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  BusinessLogo(profile: profile, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Logo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        const Text(
                          'Your drivers see it at the top of the app once they sign in.',
                          style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => _pickLogo(context),
                              child: Text(profile.logo == null ? 'Add logo' : 'Change'),
                            ),
                            if (profile.logo != null)
                              TextButton(
                                onPressed: () => saveSetting(context, 'remove logo', store.removeLogo),
                                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                child: const Text('Remove'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _NameField(
                key: ValueKey(profile.name),
                initial: profile.name ?? '',
                onSave: (name) => saveSetting(context, 'business name', () => store.setName(name)),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: country.code,
                decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()),
                items: [for (final c in Country.all) DropdownMenuItem(value: c.code, child: Text(c.name))],
                onChanged: (code) {
                  final chosen = Country.byCode(code);
                  if (chosen == null || chosen.code == profile.country) return;
                  // A new country starts on its main time zone.
                  saveSetting(context, 'country', () => store.setPlace(chosen.code, chosen.timezones.first));
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(country.code),
                initialValue: profile.timezone,
                decoration: const InputDecoration(labelText: 'Time zone', border: OutlineInputBorder()),
                items: [
                  for (final zone in country.timezones)
                    DropdownMenuItem(value: zone, child: Text(Country.zoneLabel(zone))),
                ],
                onChanged: country.timezones.length < 2
                    ? null
                    : (zone) {
                        if (zone == null || zone == profile.timezone) return;
                        saveSetting(context, 'time zone', () => store.setPlace(country.code, zone));
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickLogo(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    try {
      await store.setLogo(await picked.readAsBytes());
      messenger.showSnackBar(const SnackBar(content: Text('Logo saved. Your drivers will see it.')));
    } on LogoException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error, stack) {
      AppLog.owner.error('logo save failed', error, stack);
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't save the logo. Try again.")));
    }
  }
}

/// The business name, saved when the owner is done typing (Done, or leaving
/// the field) rather than on every letter.
class _NameField extends StatefulWidget {
  const _NameField({super.key, required this.initial, required this.onSave});

  final String initial;
  final void Function(String name) onSave;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _controller = TextEditingController(text: widget.initial);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  void _save() {
    if (_controller.text.trim() != widget.initial) widget.onSave(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      maxLength: BusinessProfile.maxNameLength,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      decoration: const InputDecoration(
        labelText: 'Business name',
        hintText: 'e.g. Dunedin Milk & More',
        border: OutlineInputBorder(),
        counterText: '',
      ),
    );
  }
}

/// The business's logo, or its initial (or the Blue Dot "B") on brand blue.
class BusinessLogo extends StatelessWidget {
  const BusinessLogo({super.key, required this.profile, this.size = 32});

  final BusinessProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = profile.logo;
    final radius = BorderRadius.circular(size * 0.3);
    if (logo != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          width: size,
          height: size,
          color: Colors.white,
          child: Image.memory(logo, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      );
    }
    final name = profile.name ?? '';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.brand, borderRadius: radius),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? 'B' : name.characters.first.toUpperCase(),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.45),
      ),
    );
  }
}
