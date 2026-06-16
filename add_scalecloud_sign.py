#!/usr/bin/env python3
"""
Add ScaleCloudRenew.xcframework file reference and link it to all targets.
This integrates the signing framework into ScaleCloudApp.
"""

import re
import uuid

def generate_uuid():
    """Generate a UUID in Xcode format (24 hex characters)."""
    return uuid.uuid4().hex[:24].upper()

def add_framework_to_project(pbxproj_path):
    with open(pbxproj_path, 'r') as f:
        content = f.read()
    
    # Check if ScaleCloudRenew.xcframework already exists
    if 'ScaleCloudRenew.xcframework' in content:
        print("ScaleCloudRenew.xcframework reference already exists in project")
        return content
    
    # Generate UUIDs for the file reference and build file
    file_ref_uuid = generate_uuid()
    
    # Add file reference for ScaleCloudRenew.xcframework
    # Find the PBXFileReference section
    file_ref_section_match = re.search(r'(/\* Begin PBXFileReference section \*/.*?/\* End PBXFileReference section \*/)', content, re.DOTALL)
    if not file_ref_section_match:
        print("ERROR: Could not find PBXFileReference section")
        return content
    
    file_ref_entry = f'\t\t{file_ref_uuid} /* ScaleCloudRenew.xcframework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = ScaleCloudRenew.xcframework; path = ../ScaleCloudRenew/prebuilt/ScaleCloudRenew.xcframework; sourceTree = SOURCE_ROOT; }};\n'
    
    # Insert before the "End PBXFileReference" comment
    content = content.replace('/* End PBXFileReference section */', file_ref_entry + '/* End PBXFileReference section */')
    
    print(f"✓ Added PBXFileReference for ScaleCloudRenew.xcframework ({file_ref_uuid})")
    
    # Now add ScaleCloudRenew.xcframework to each PBXFrameworksBuildPhase
    # Find all PBXFrameworksBuildPhase sections
    frameworks_phases = re.finditer(r'([A-F0-9]{24}) /\* Frameworks \*/ = \{\s*isa = PBXFrameworksBuildPhase;.*?files = \((.*?)\);', content, re.DOTALL)
    
    added_count = 0
    for match in frameworks_phases:
        phase_uuid = match.group(1)
        files_content = match.group(2)
        
        # Generate a new build file UUID for this phase
        build_file_uuid = generate_uuid()
        
        # Create the build file entry
        build_file_entry = f'\t\t{build_file_uuid} /* ScaleCloudRenew.xcframework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* ScaleCloudRenew.xcframework */; }};\n'
        
        # Add to PBXBuildFile section
        content = content.replace('/* End PBXBuildFile section */', build_file_entry + '/* End PBXBuildFile section */')
        
        # Add reference to this frameworks phase
        # Find the files array for this specific phase
        phase_pattern = f'{phase_uuid} /\\* Frameworks \\*/ = {{\\s*isa = PBXFrameworksBuildPhase;.*?files = \\((.*?)\\);'
        phase_match = re.search(phase_pattern, content, re.DOTALL)
        if phase_match:
            old_files = phase_match.group(1)
            new_files = old_files.rstrip() + f'\n\t\t\t\t{build_file_uuid} /* ScaleCloudRenew.xcframework in Frameworks */,'
            content = content.replace(f'files = ({old_files})', f'files = ({new_files})', 1)
            added_count += 1
    
    print(f"✓ Added ScaleCloudRenew.xcframework to {added_count} PBXFrameworksBuildPhase sections")
    
    return content

if __name__ == '__main__':
    pbxproj_path = 'ScaleCloudApp.xcodeproj/project.pbxproj'
    
    print("Adding ScaleCloudRenew.xcframework to ScaleCloudApp.xcodeproj...")
    modified_content = add_framework_to_project(pbxproj_path)
    
    # Write back
    with open(pbxproj_path, 'w') as f:
        f.write(modified_content)
    
    print("\n✓ Done! ScaleCloudRenew.xcframework has been added to all targets.")
