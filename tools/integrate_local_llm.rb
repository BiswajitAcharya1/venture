require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "Venture.xcodeproj")
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |candidate| candidate.name == "Venture" }
abort "Venture target not found" unless target
test_target = project.targets.find { |candidate| candidate.name == "VentureTests" }
abort "VentureTests target not found" unless test_target

venture_group = project.main_group.children.find { |child| child.display_name == "Venture" }
abort "Venture group not found" unless venture_group

def ensure_file(group, path)
  group.files.find { |file| file.path == path } || group.new_file(path)
end

def ensure_build_file(phase, reference)
  phase.files.find { |build_file| build_file.file_ref == reference } ||
    phase.add_file_reference(reference, true)
end

project.files
  .select { |file| file.path&.match?(/TinyLlama|tinyllama|SmolLM2/) }
  .each(&:remove_from_project)

source = ensure_file(venture_group, "Services/Companion/BundledLlamaEngine.swift")
ensure_build_file(target.source_build_phase, source)

tests_group = project.main_group.children.find { |child| child.display_name == "VentureTests" }
abort "VentureTests group not found" unless tests_group
test_source = ensure_file(tests_group, "BundledLlamaEngineTests.swift")
ensure_build_file(test_target.source_build_phase, test_source)

model_paths = [
  "Resources/Models/LocalLLM/lfm2_5_230m_q4_k_m.gguf",
  "Resources/Models/LocalLLM/LFM2.5-LICENSE.txt",
  "Resources/Models/LocalLLM/LFM2.5-MODEL-CARD.md",
  "Resources/Models/ParkinsonVoiceScreen.mlmodel",
  "Resources/Models/ParkinsonVoiceScreen-LICENSE.txt",
  "Resources/Models/NightSignal-LICENSE.txt"
]
model_paths.each do |path|
  reference = ensure_file(venture_group, path)
  reference.last_known_file_type = "file" if File.extname(path) == ".gguf"
  ensure_build_file(target.resources_build_phase, reference)
end

frameworks_group = project.main_group.children.find { |child| child.display_name == "Frameworks" }
frameworks_group ||= project.main_group.new_group("Frameworks")
framework_path = "Vendor/LlamaRuntime/build-apple/llama.xcframework"
framework = ensure_file(frameworks_group, framework_path)
framework.last_known_file_type = "wrapper.xcframework"
ensure_build_file(target.frameworks_build_phase, framework)

embed_phase = target.copy_files_build_phases.find { |phase| phase.name == "Embed Frameworks" }
embed_phase ||= target.new_copy_files_build_phase("Embed Frameworks")
embed_phase.symbol_dst_subfolder_spec = :frameworks
embedded = ensure_build_file(embed_phase, framework)
embedded.settings = {
  "ATTRIBUTES" => [
    "CodeSignOnCopy",
    "RemoveHeadersOnCopy"
  ]
}

project.save
puts "Integrated bundled llama.cpp runtime and LFM2.5 model."
