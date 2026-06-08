#!/usr/bin/env ruby
# Script to add ScaleCloudGo.xcframework to all targets in ScaleCloudApp.xcodeproj
# This fixes the "Unable to resolve module dependency: 'ScaleCloudGo'" error

require 'xcodeproj'

project_path = 'ScaleCloudApp.xcodeproj'
framework_path = '../ScaleCloudGo/prebuilt/ScaleCloudGo.xcframework'

project = Xcodeproj::Project.open(project_path)

# Find or create file reference for ScaleCloudGo.xcframework
file_ref = project.reference_for_path(framework_path)
unless file_ref
  file_ref = project.new_file(framework_path)
  file_ref.source_tree = 'SOURCE_ROOT'
end

# Add to all targets
project.targets.each do |target|
  puts "Processing target: #{target.name}"
  
  # Check if already linked
  already_linked = target.frameworks_build_phase.files.any? do |build_file|
    build_file.file_ref == file_ref
  end
  
  unless already_linked
    target.frameworks_build_phase.add_file_reference(file_ref)
    puts "  ✓ Added ScaleCloudGo.xcframework"
  else
    puts "  - Already linked"
  end
end

project.save

puts "\nDone! ScaleCloudGo.xcframework added to all targets."
