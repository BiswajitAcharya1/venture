require "xcodeproj"
require "fileutils"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "Venture.xcodeproj")
FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2650"
project.root_object.attributes["LastUpgradeCheck"] = "2650"

target = project.new_target(:application, "Venture", :ios, "17.0")
target.product_name = "Venture"

test_target = project.new_target(:unit_test_bundle, "VentureTests", :ios, "17.0")
test_target.add_dependency(target)

group = project.main_group.new_group("Venture", "Venture")
swift_files = Dir.glob(File.join(root, "Venture", "**", "*.swift")).sort
swift_files.each do |path|
  reference = group.new_file(path.delete_prefix(File.join(root, "Venture") + "/"))
  target.source_build_phase.add_file_reference(reference)
end

tests_group = project.main_group.new_group("VentureTests", "VentureTests")
Dir.glob(File.join(root, "VentureTests", "**", "*.swift")).sort.each do |path|
  reference = tests_group.new_file(path.delete_prefix(File.join(root, "VentureTests") + "/"))
  test_target.source_build_phase.add_file_reference(reference)
end

assets_path = File.join(root, "Venture", "Resources", "Assets.xcassets")
if File.exist?(assets_path)
  assets = group.new_file("Resources/Assets.xcassets")
  target.resources_build_phase.add_file_reference(assets)
end

privacy_manifest_path = File.join(root, "Venture", "Resources", "PrivacyInfo.xcprivacy")
if File.exist?(privacy_manifest_path)
  privacy_manifest = group.new_file("Resources/PrivacyInfo.xcprivacy")
  target.resources_build_phase.add_file_reference(privacy_manifest)
end

Dir.glob(File.join(root, "Venture", "Resources", "Models", "**", "*.{mlpackage,mlmodel,gguf,txt,md}")).sort.each do |path|
  next if path.include?(".mlpackage/")
  reference = group.new_file(path.delete_prefix(File.join(root, "Venture") + "/"))
  target.resources_build_phase.add_file_reference(reference)
end

llama_framework_path = File.join(root, "Vendor", "LlamaRuntime", "build-apple", "llama.xcframework")
if File.exist?(llama_framework_path)
  frameworks_group = project.main_group["Frameworks"] || project.main_group.new_group("Frameworks")
  llama_framework = frameworks_group.new_file(llama_framework_path.delete_prefix(root + "/"))
  target.frameworks_build_phase.add_file_reference(llama_framework)
  embed_phase = target.new_copy_files_build_phase("Embed Frameworks")
  embed_phase.symbol_dst_subfolder_spec = :frameworks
  embedded = embed_phase.add_file_reference(llama_framework, true)
  embedded.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
end

entitlements_path = File.join(root, "Venture", "Resources", "Venture.entitlements")

project.build_configurations.each do |configuration|
  configuration.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
end

target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES"] = "NO"
  settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = "AccentColor"
  settings["CODE_SIGN_ENTITLEMENTS"] = entitlements_path.delete_prefix(root + "/")
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["CURRENT_PROJECT_VERSION"] = "1"
  settings["DEVELOPMENT_TEAM"] = "K9QT25YK23"
  settings["ENABLE_PREVIEWS"] = "YES"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["INFOPLIST_FILE"] = "Venture/Resources/Info.plist"
  settings["INFOPLIST_KEY_NSFaceIDUsageDescription"] = "Venture uses Face ID to protect your private cognitive metrics."
  settings["INFOPLIST_KEY_NSHealthShareUsageDescription"] = "Venture reads recovery signals such as sleep and HRV to compare them with your personal baseline."
  settings["INFOPLIST_KEY_NSHealthUpdateUsageDescription"] = "Venture does not write health data."
  settings["INFOPLIST_KEY_NSMicrophoneUsageDescription"] = "Venture briefly uses the microphone to extract voice metrics, then deletes the recording."
  settings["INFOPLIST_KEY_NSSpeechRecognitionUsageDescription"] = "Venture recognizes a short reading prompt on device to measure speech timing and highlight your progress."
  settings["INFOPLIST_KEY_NSCameraUsageDescription"] = "Venture briefly uses the camera to extract eye metrics, then deletes the video."
  settings["INFOPLIST_KEY_VentureFamilyControlsEnabled"] = "NO"
  settings["INFOPLIST_KEY_VentureAuthBaseURL"] = ""
  settings["INFOPLIST_KEY_VentureEmailVerifierBaseURL"] = ""
  settings["INFOPLIST_KEY_VentureEmailVerifierProvider"] = "reacher"
  settings["INFOPLIST_KEY_VentureSupabaseURL"] = "$(VENTURE_SUPABASE_URL)"
  settings["INFOPLIST_KEY_VentureSupabaseAnonKey"] = "$(VENTURE_SUPABASE_ANON_KEY)"
  settings["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
  settings["INFOPLIST_KEY_UIApplicationSceneManifest_Generation"] = "YES"
  settings["MARKETING_VERSION"] = "0.1.0"
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.venture.brain-drift"
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
  settings["SWIFT_EMIT_LOC_STRINGS"] = "YES"
  settings["SWIFT_VERSION"] = "5.0"
  settings["VENTURE_SUPABASE_URL"] = ""
  settings["VENTURE_SUPABASE_ANON_KEY"] = ""
  settings["VENTURE_AUTH_BASE_URL"] = ""
  settings["VENTURE_EMAIL_VERIFIER_BASE_URL"] = ""
  settings["VENTURE_EMAIL_VERIFIER_PROVIDER"] = "reacher"
  settings["TARGETED_DEVICE_FAMILY"] = "1"
end


test_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["DEVELOPMENT_TEAM"] = "K9QT25YK23"
  settings["GENERATE_INFOPLIST_FILE"] = "YES"
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.venture.brain-drift.tests"
  settings["SWIFT_VERSION"] = "5.0"
  settings["TARGETED_DEVICE_FAMILY"] = "1"
  settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/Venture.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Venture"
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(test_target)
scheme.set_launch_target(target)
scheme.save_as(project_path, "Venture", true)

project.save
