#!/usr/bin/env python3
"""
fix_pbxproj.py — Step 4: Wire ScaleCloudDeps prebuilt xcframeworks into ScaleCloudApp

What this script does:
1. Removes all SC00* packageProductDependencies lines from all targets
2. Removes the SC00PRC*BuildFile (Perception in Frameworks) PBXBuildFile line
3. Removes all SC00* XCSwiftPackageProductDependency definition blocks
4. Removes all SC00* XCRemoteSwiftPackageReference entries (packageReferences array + definition blocks)
5. Adds 8 PBXFileReference entries for ScaleCloudDeps xcframeworks
6. Adds 8 link-PBXBuildFile + 8 embed-PBXBuildFile entries for the main Nextcloud target
7. Adds the 8 embed build-file IDs to F76DA934 Embed Frameworks build phase
8. Adds the 8 link build-file IDs to the main Nextcloud Frameworks build phase (after ScaleCloudRenew)
9. Adds $(SRCROOT)/../ScaleCloudDeps/prebuilt to all FRAMEWORK_SEARCH_PATHS
"""

import re
import sys

PBXPROJ = "ScaleCloudApp.xcodeproj/project.pbxproj"

# ── IDs used for the 8 new xcframeworks ──────────────────────────────────────
DEPS = [
    ("Alamofire",       "SCDEP001F000001000AAAAA", "SCDEP001B000001000AAAAA", "SCDEP001E000001000AAAAA"),
    ("KeychainAccess",  "SCDEP001F000002000AAAAA", "SCDEP001B000002000AAAAA", "SCDEP001E000002000AAAAA"),
    ("Nuke",            "SCDEP001F000003000AAAAA", "SCDEP001B000003000AAAAA", "SCDEP001E000003000AAAAA"),
    ("SemanticVersion", "SCDEP001F000004000AAAAA", "SCDEP001B000004000AAAAA", "SCDEP001E000004000AAAAA"),
    ("Starscream",      "SCDEP001F000005000AAAAA", "SCDEP001B000005000AAAAA", "SCDEP001E000005000AAAAA"),
    ("SwiftyJSON",      "SCDEP001F000006000AAAAA", "SCDEP001B000006000AAAAA", "SCDEP001E000006000AAAAA"),
    ("SwiftyXMLParser", "SCDEP001F000007000AAAAA", "SCDEP001B000007000AAAAA", "SCDEP001E000007000AAAAA"),
    ("ZIPFoundation",   "SCDEP001F000008000AAAAA", "SCDEP001B000008000AAAAA", "SCDEP001E000008000AAAAA"),
]
# Column meaning: name, fileRef ID, link-buildfile ID, embed-buildfile ID

with open(PBXPROJ, "r") as f:
    content = f.read()

original_len = len(content.splitlines())
print(f"Original line count: {original_len}")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Remove SC00* packageProductDependencies lines (individual lines)
# Only removes lines that are SPM product dep refs — i.e. they end with */ comment
# but NOT SC00AA00[234]F (ScaleCloudSign/Renew link+embed build files we keep)
# The 4-tab lines to remove are inside packageProductDependencies arrays and
# XCSwiftPackageProductDependency reference lines inside target sections.
# We match only lines whose ID is NOT SC00AA00[1-9]F or SC00AA001F.
# ─────────────────────────────────────────────────────────────────────────────
sc00_pdep_pattern = re.compile(
    r'^\t{4}SC00(?!AA00[0-9A-F]F|AA001F)[^\n]+\n',
    re.MULTILINE
)
content, n = re.subn(sc00_pdep_pattern, '', content)
print(f"Step 1: removed {n} SC00* packageProductDependencies lines")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Remove SC00PRC* Perception entries:
#   a) PBXBuildFile definition line (2-tab)
#   b) In-phase reference line inside Frameworks build phase (4-tab)
# ─────────────────────────────────────────────────────────────────────────────
prc_buildfile_pattern = re.compile(
    r'^\t\tSC00PRC000000001000AAAAA /\* Perception in Frameworks \*/ = \{[^\n]+\};\n',
    re.MULTILINE
)
content, n = re.subn(prc_buildfile_pattern, '', content)
print(f"Step 2a: removed {n} Perception PBXBuildFile definition line")

prc_phase_pattern = re.compile(
    r'^\t{4}SC00PRC000000001000AAAAA /\* Perception in Frameworks \*/,\n',
    re.MULTILINE
)
content, n = re.subn(prc_phase_pattern, '', content)
print(f"Step 2b: removed {n} Perception in-phase reference line")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Remove all SC00* XCSwiftPackageProductDependency blocks (5-line blocks)
# ─────────────────────────────────────────────────────────────────────────────
sc00_sppd_pattern = re.compile(
    r'^\t\tSC00[A-Za-z0-9]+ /\*[^\n]+\*/ = \{\n'
    r'\t\t\tisa = XCSwiftPackageProductDependency;\n'
    r'\t\t\tpackage = [^\n]+\n'
    r'\t\t\tproductName = [^\n]+\n'
    r'\t\t\};\n',
    re.MULTILINE
)
content, n = re.subn(sc00_sppd_pattern, '', content)
print(f"Step 3: removed {n} SC00* XCSwiftPackageProductDependency blocks")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: Remove SC00* XCRemoteSwiftPackageReference array entries
# ─────────────────────────────────────────────────────────────────────────────
# These entries use 4-tab indent inside packageReferences array
sc00_pkgref_array_pattern = re.compile(
    r'^[ \t]+SC00[^\n]+ /\* XCRemoteSwiftPackageReference[^\n]+\*/,\n',
    re.MULTILINE
)
content, n = re.subn(sc00_pkgref_array_pattern, '', content)
print(f"Step 4a: removed {n} SC00* packageReferences array entries")

# Remove the XCRemoteSwiftPackageReference definition blocks (8-line blocks)
# requirement block has 2 inner lines: kind + minimumVersion
sc00_pkgref_def_pattern = re.compile(
    r'^\t\tSC00[A-Za-z0-9]+ /\* XCRemoteSwiftPackageReference[^\n]+\*/ = \{\n'
    r'\t\t\tisa = XCRemoteSwiftPackageReference;\n'
    r'\t\t\trepositoryURL = [^\n]+\n'
    r'\t\t\trequirement = \{\n'
    r'\t\t\t\t[^\n]+\n'
    r'\t\t\t\t[^\n]+\n'
    r'\t\t\t\};\n'
    r'\t\t\};\n',
    re.MULTILINE
)
content, n = re.subn(sc00_pkgref_def_pattern, '', content)
print(f"Step 4b: removed {n} SC00* XCRemoteSwiftPackageReference definition blocks")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: Add 8 PBXFileReference entries before "/* End PBXFileReference section */"
# ─────────────────────────────────────────────────────────────────────────────
new_filerefs = ""
for name, fref_id, link_id, embed_id in DEPS:
    new_filerefs += (
        f'\t\t{fref_id} /* {name}.xcframework */ = '
        f'{{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; '
        f'name = {name}.xcframework; '
        f'path = ../ScaleCloudDeps/prebuilt/{name}.xcframework; '
        f'sourceTree = SOURCE_ROOT; }};\n'
    )

content = content.replace(
    '/* End PBXFileReference section */',
    new_filerefs + '/* End PBXFileReference section */'
)
print(f"Step 5: added 8 PBXFileReference entries")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6: Add 8 link + 8 embed PBXBuildFile entries before "/* End PBXBuildFile section */"
# Anchor on the full PBXBuildFile definition line (2-tab), which is unique.
# ─────────────────────────────────────────────────────────────────────────────
anchor = '\t\tSC00AA002F000001000AAAAA /* ScaleCloudSign in Frameworks */ = {isa = PBXBuildFile;'
new_buildfiles = ""
for name, fref_id, link_id, embed_id in DEPS:
    new_buildfiles += (
        f'\t\t{link_id} /* {name}.xcframework in Frameworks */ = '
        f'{{isa = PBXBuildFile; fileRef = {fref_id} /* {name}.xcframework */; }};\n'
    )
    new_buildfiles += (
        f'\t\t{embed_id} /* {name}.xcframework in Embed Frameworks */ = '
        f'{{isa = PBXBuildFile; fileRef = {fref_id} /* {name}.xcframework */; '
        f'settings = {{ATTRIBUTES = (CodeSignOnCopy, ); }}; }};\n'
    )

assert anchor in content, "ERROR Step 6: anchor not found"
content = content.replace(anchor, new_buildfiles + anchor)
print(f"Step 6: added 16 PBXBuildFile entries (8 link + 8 embed)")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7: Add embed build-file IDs to F76DA934 Embed Frameworks build phase
# Anchor on the full closing of the files list, which contains ScaleCloudSign
# and ScaleCloudRenew embed entries followed by );
# ─────────────────────────────────────────────────────────────────────────────
embed_anchor = (
    '\t\t\t\tSC00AA003F000001000AAAAA /* ScaleCloudSign in Embed Frameworks */,\n'
    '\t\t\t\tSC00AA004F000001000AAAAA /* ScaleCloudRenew.xcframework in Embed Frameworks */,\n'
    '\t\t\t);'
)
new_embed_entries = ""
for name, fref_id, link_id, embed_id in DEPS:
    new_embed_entries += f'\t\t\t\t{embed_id} /* {name}.xcframework in Embed Frameworks */,\n'

assert embed_anchor in content, "ERROR Step 7: anchor not found in Embed Frameworks phase"
content = content.replace(
    embed_anchor,
    '\t\t\t\tSC00AA003F000001000AAAAA /* ScaleCloudSign in Embed Frameworks */,\n'
    '\t\t\t\tSC00AA004F000001000AAAAA /* ScaleCloudRenew.xcframework in Embed Frameworks */,\n'
    + new_embed_entries
    + '\t\t\t);'
)
print(f"Step 7: added 8 entries to Embed Frameworks build phase")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 8: Add link build-file IDs to main Nextcloud Frameworks build phase
# Insert after the ScaleCloudRenew Frameworks entry in the main target's Frameworks phase
# The main target has: 292D7BEE3E7B47E09C8D3D61 /* ScaleCloudRenew.xcframework in Frameworks */,
# ─────────────────────────────────────────────────────────────────────────────
# The main Nextcloud Frameworks phase ends with ScaleCloudRenew on same line as );
# e.g.: \t\t\t\t292D7BEE...Frameworks */,);
link_anchor = '\t\t\t\t292D7BEE3E7B47E09C8D3D61 /* ScaleCloudRenew.xcframework in Frameworks */,);'
new_link_entries = ""
for name, fref_id, link_id, embed_id in DEPS:
    new_link_entries += f'\t\t\t\t{link_id} /* {name}.xcframework in Frameworks */,\n'

assert link_anchor in content, "ERROR Step 8: anchor not found in Frameworks phase"
content = content.replace(
    link_anchor,
    '\t\t\t\t292D7BEE3E7B47E09C8D3D61 /* ScaleCloudRenew.xcframework in Frameworks */,\n'
    + new_link_entries
    + '\t\t\t);'
)
print(f"Step 8: added 8 link entries to main Nextcloud Frameworks build phase")

# ─────────────────────────────────────────────────────────────────────────────
# STEP 9: Add ScaleCloudDeps/prebuilt to all FRAMEWORK_SEARCH_PATHS
# ─────────────────────────────────────────────────────────────────────────────
old_fsp = '$(SRCROOT)/../ScaleCloudKit/prebuilt $(SRCROOT)/../ScaleCloudGo/prebuilt $(SRCROOT)/../ScaleCloudSign/prebuilt $(SRCROOT)/../ScaleCloudRenew/prebuilt"'
new_fsp = '$(SRCROOT)/../ScaleCloudKit/prebuilt $(SRCROOT)/../ScaleCloudGo/prebuilt $(SRCROOT)/../ScaleCloudSign/prebuilt $(SRCROOT)/../ScaleCloudRenew/prebuilt $(SRCROOT)/../ScaleCloudDeps/prebuilt"'
content, n = re.subn(re.escape(old_fsp), new_fsp, content)
print(f"Step 9: updated {n} FRAMEWORK_SEARCH_PATHS entries")

# ─────────────────────────────────────────────────────────────────────────────
# Write output
# ─────────────────────────────────────────────────────────────────────────────
with open(PBXPROJ, "w") as f:
    f.write(content)

new_len = len(content.splitlines())
print(f"Done. New line count: {new_len} (delta: {new_len - original_len:+d})")

# ─────────────────────────────────────────────────────────────────────────────
# Sanity checks
# ─────────────────────────────────────────────────────────────────────────────
remaining_sc00 = len(re.findall(r'SC00(?!AA00[123]F|AA001F)', content))
print(f"\nSanity: remaining SC00* references (excluding SC00AA keep): {remaining_sc00}")
for name, fref_id, link_id, embed_id in DEPS:
    assert fref_id in content, f"MISSING fileRef: {fref_id} ({name})"
    assert link_id in content, f"MISSING link buildfile: {link_id} ({name})"
    assert embed_id in content, f"MISSING embed buildfile: {embed_id} ({name})"
print("Sanity: all 8 xcframework IDs present ✓")
assert "ScaleCloudDeps/prebuilt" in content, "MISSING ScaleCloudDeps in FRAMEWORK_SEARCH_PATHS"
print("Sanity: ScaleCloudDeps/prebuilt in FRAMEWORK_SEARCH_PATHS ✓")
