#!/bin/zsh

# Source this after setting PROJECT_ROOT. Xcode can block when coordinating a
# project inside iCloud Documents; build a local, isolated source snapshot.
venture_build_root="$(mktemp -d "${TMPDIR:-/tmp}/venture-build.XXXXXX")"
readonly BUILD_ROOT="$venture_build_root"
unset venture_build_root
print "Source snapshot: $BUILD_ROOT"

rsync -a \
    --no-owner \
    --no-group \
    --no-perms \
    --exclude='.git' \
    --exclude='xcuserdata' \
    --exclude='*.xcuserstate' \
    --exclude='.DS_Store' \
    --exclude='.gitignore' \
    --exclude='README.md' \
    --exclude='docs' \
    --exclude='AppStore' \
    --exclude='supabase' \
    --exclude='DerivedData' \
    --exclude='build' \
    --exclude='.research' \
    --exclude='Venture/Resources/Models/LocalLLM/SmolLM2-*' \
    --exclude='Venture/Resources/Models/LocalLLM/smollm2-360m-instruct-q4_k_m.gguf' \
    --exclude='Vendor/LlamaRuntime/build-apple/llama.xcframework/macos-*' \
    --exclude='Vendor/LlamaRuntime/build-apple/llama.xcframework/tvos-*' \
    --exclude='Vendor/LlamaRuntime/build-apple/llama.xcframework/xros-*' \
    "$PROJECT_ROOT/" "$BUILD_ROOT/"
