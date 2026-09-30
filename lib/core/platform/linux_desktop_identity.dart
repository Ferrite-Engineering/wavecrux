// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_linux_integration/crux_linux_integration.dart';

/// Every file kind WaveCrux opens, as a Linux desktop has to be told about it.
///
/// This is the Linux half of the document types the macOS bundle registers,
/// and it is two halves itself: the `MimeType=` line of the `.desktop` entry
/// decides which application a file manager offers, and the installed
/// `shared-mime-info` package is what lets the file be typed as ours in the
/// first place. Without the second, a `.vcd` is typed as something else and
/// the entry's claim resolves to nothing.
///
/// None of these formats is one a desktop already maps, so each is declared,
/// named after the format rather than after us where the format is someone
/// else's — VCD is IEEE 1364, FST and the GTKWave save file and the LXT/LXT2
/// dumps are GTKWave's, GHW is GHDL's. The session and the pack are ours and
/// say so, and the suite design manifest carries the name all four products
/// use, matching its macOS UTI `app.edacrux.project`.
///
/// Each declares a parent type where there is an honest one, so a desktop
/// that has never heard of ours still treats the file sensibly: the text
/// formats open in an editor and are searched as text, the pack unzips.
///
/// `linux_desktop_identity_test.dart` holds this list against the macOS
/// document types through `checkLinuxMimeCoverage`, so an extension
/// registered on one platform and not the other fails rather than quietly
/// opening on one and not the other.
final List<LinuxMimeType> kWaveCruxLinuxFileTypes = <LinuxMimeType>[
  LinuxMimeType.declared(
    name: 'application/x-edacrux-project',
    comment: 'EDACrux design manifest',
    extensions: const ['crux-project'],
    subClassOf: 'application/x-yaml',
  ),
  // `.vcd` is globbed to a Video CD playlist (`application/x-cdlink`) by a
  // stock database. Outranking that would retype every `.vcd` on the machine,
  // including the ones that really are playlists, so the glob sits below the
  // default weight and the waveform is recognised by its own header instead:
  // a VCD begins with one of these keywords, after an optional comment
  // preamble. The match is priority 90 — above 80, where the specification
  // has a content match decide over a glob — so a real waveform is ours and a
  // real playlist stays theirs.
  LinuxMimeType.declared(
    name: 'application/x-vcd-waveform',
    comment: 'Value change dump waveform',
    extensions: const ['vcd'],
    subClassOf: 'text/plain',
    globWeight: 40,
    magic: LinuxMimeMagic(
      priority: 90,
      matches: const [
        LinuxMimeMagicMatch(value: r'$date', offsetEnd: 256),
        LinuxMimeMagicMatch(value: r'$version', offsetEnd: 256),
        LinuxMimeMagicMatch(value: r'$timescale', offsetEnd: 256),
        LinuxMimeMagicMatch(value: r'$comment', offsetEnd: 256),
      ],
    ),
  ),
  LinuxMimeType.declared(
    name: 'application/x-fst-waveform',
    comment: 'Fast signal trace waveform',
    extensions: const ['fst'],
  ),
  LinuxMimeType.declared(
    name: 'application/x-ghw-waveform',
    comment: 'GHDL waveform',
    extensions: const ['ghw'],
  ),
  LinuxMimeType.declared(
    name: 'application/x-gtkwave-savefile',
    comment: 'GTKWave save file',
    extensions: const ['gtkw'],
    subClassOf: 'text/plain',
  ),
  LinuxMimeType.declared(
    name: 'application/x-lxt-waveform',
    comment: 'LXT legacy waveform',
    extensions: const ['lxt'],
  ),
  LinuxMimeType.declared(
    name: 'application/x-lxt2-waveform',
    comment: 'LXT2 legacy waveform',
    extensions: const ['lxt2'],
  ),
  LinuxMimeType.declared(
    name: 'application/x-wavecrux-session',
    comment: 'WaveCrux session',
    extensions: const ['wavecrux'],
    subClassOf: 'application/json',
  ),
  LinuxMimeType.declared(
    name: 'application/x-wavecrux-pack',
    comment: 'WaveCrux annotated waveform pack',
    extensions: const ['wavecruxpack'],
    subClassOf: 'application/zip',
  ),
];

/// The open-core build's freedesktop identity, installed as a host
/// `.desktop` entry when it runs from an AppImage.
///
/// [LinuxDesktopApp.appId] and [LinuxDesktopApp.execName] must equal
/// `APPLICATION_ID` and `BINARY_NAME` in `linux/CMakeLists.txt`: the GTK
/// runner sets the window's app id from the former, and a `.desktop` entry
/// whose `StartupWMClass` differs is not matched to the window. `bootstrap`
/// takes the identity as a parameter so the Pro overlay passes its own, with
/// the same [kWaveCruxLinuxFileTypes]: both tiers open the same files.
final LinuxDesktopApp kWaveCruxLinuxDesktopApp = LinuxDesktopApp(
  appId: 'com.ferriteengineering.wavecrux',
  name: 'WaveCrux',
  comment: 'Waveform viewer for HDL simulation traces (VCD, FST, GHW)',
  execName: 'wavecrux',
  fileTypes: kWaveCruxLinuxFileTypes,
);
