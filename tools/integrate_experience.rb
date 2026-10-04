#!/usr/bin/env ruby
# Incremental integration: preserves the existing project, settings and user changes.
require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'Venture.xcodeproj'))
app = project.targets.find { |t| t.name == 'Venture' }
tests = project.targets.find { |t| t.name == 'VentureTests' }
ui = project.targets.find { |t| t.name == 'VentureUITests' } || project.new_target(:ui_test_bundle, 'VentureUITests', :ios, '18.0')
ui.add_dependency(app) unless ui.dependencies.any? { |d| d.target == app }
ui.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.venture.brain-drift.uitests'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['TEST_TARGET_NAME'] = 'Venture'
  config.build_settings['SWIFT_VERSION'] = '5.0'
end
def reference(project, path)
  absolute = File.expand_path(path, project.path.dirname.to_s)
  project.files.find { |f| f.real_path.to_s == absolute } || project.main_group.new_file(path, 'SOURCE_ROOT')
end
def add_to(phase, file)
  phase.add_file_reference(file, true) unless phase.files_references.include?(file)
end
Dir.glob(File.join(root, 'Venture/**/*.swift')).each do |path|
  add_to(app.source_build_phase, reference(project, path.delete_prefix(root + '/')))
end
%w[Venture/Services/Companion/VentureSpeechService.swift Venture/Services/Companion/VentureCallingService.swift Venture/Services/Sensors/MediaPipeIrisTracker.swift].each do |path|
  add_to(app.source_build_phase, reference(project, path)) if File.exist?(File.join(root, path))
end
%w[Venture/Resources/KokoroModels Venture/Resources/Models/face_landmarker.task Venture/Resources/Models/LocalLLM/gemma-4-E2B-it-Q4_0.gguf Venture/Resources/ahh-example.wav Venture/Resources/ahh-example-attribution.txt].each do |path|
  next unless File.exist?(File.join(root, path))
  file = reference(project, path)
  file.last_known_file_type = 'folder' if File.directory?(File.join(root, path))
  add_to(app.resources_build_phase, file)
end
Dir.glob(File.join(root, 'VentureTests/*Tests.swift')).each do |path|
  add_to(tests.source_build_phase, reference(project, path.delete_prefix(root + '/')))
end
Dir.glob(File.join(root, 'VentureUITests/*.swift')).each do |path|
  add_to(ui.source_build_phase, reference(project, path.delete_prefix(root + '/')))
end
objects = Xcodeproj::Project::Object
package = project.root_object.package_references.find { |p| p.isa == 'XCLocalSwiftPackageReference' && p.relative_path == 'Vendor/KokoroCoreML' }
unless package
  package = project.new(objects::XCLocalSwiftPackageReference)
  package.relative_path = 'Vendor/KokoroCoreML'
  project.root_object.package_references << package
end
product = app.package_product_dependencies.find { |p| p.product_name == 'KokoroCoreML' }
unless product
  product = project.new(objects::XCSwiftPackageProductDependency)
  product.package = package
  product.product_name = 'KokoroCoreML'
  app.package_product_dependencies << product
  file = project.new(objects::PBXBuildFile)
  file.product_ref = product
  app.frameworks_build_phase.files << file
end
unless tests.package_product_dependencies.any? { |p| p.product_name == 'KokoroCoreML' }
  test_product = project.new(objects::XCSwiftPackageProductDependency)
  test_product.package = package
  test_product.product_name = 'KokoroCoreML'
  tests.package_product_dependencies << test_product
  file = project.new(objects::PBXBuildFile)
  file.product_ref = test_product
  tests.frameworks_build_phase.files << file
end
%w[Vision Common].each do |component|
  path = "Vendor/MediaPipe/#{component}/frameworks/MediaPipeTasks#{component}.xcframework"
  add_to(app.frameworks_build_phase, reference(project, path)) if File.exist?(File.join(root, path))
end
%w[Accelerate AudioToolbox CoreMedia AssetsLibrary CoreFoundation CoreGraphics CoreImage QuartzCore AVFoundation CoreVideo].each do |name|
  file = project.files.find { |f| f.path == "System/Library/Frameworks/#{name}.framework" } || project.frameworks_group.new_file("System/Library/Frameworks/#{name}.framework", 'SDKROOT')
  add_to(app.frameworks_build_phase, file)
end
project.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0' }
project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
    next unless target == app
    config.build_settings['OTHER_LDFLAGS[sdk=iphonesimulator*]'] = '$(inherited) -lc++ -ObjC -force_load "$(SRCROOT)/Vendor/MediaPipe/Common/frameworks/graph_libraries/libMediaPipeTasksCommon_simulator_graph.a"'
    config.build_settings['OTHER_LDFLAGS[sdk=iphoneos*]'] = '$(inherited) -lc++ -ObjC -force_load "$(SRCROOT)/Vendor/MediaPipe/Common/frameworks/graph_libraries/libMediaPipeTasksCommon_device_graph.a"'
  end
end
project.save
scheme_path = File.join(root, 'Venture.xcodeproj/xcshareddata/xcschemes/Venture.xcscheme')
scheme = Xcodeproj::XCScheme.new(scheme_path)
unless scheme.test_action.testables.any? { |t| t.buildable_references.any? { |r| r.target_uuid == ui.uuid } }
  scheme.add_test_target(ui)
  scheme.save_as(File.join(root, 'Venture.xcodeproj'), 'Venture', true)
end
puts 'Experience sources, Kokoro, MediaPipe and resources integrated.'
